"""Local fake-pool acceptance through the deployed service and real FPGA.

Run on the S9 after loading orphan_kas. Does not contact a public pool.
Restores the board's wallet/pool configuration in a finally block.
"""
import json,socket,struct,sys,threading,time,urllib.request
sys.path.insert(0,'/opt/ardzy/projects/orphan_kas')
import settings
URL='http://127.0.0.1:8000'
def get():
    with urllib.request.urlopen(URL+'/api/status',timeout=3) as r:return json.load(r)
def post(data):
    req=urllib.request.Request(URL+'/api/command',json.dumps(data).encode(),{'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=3) as r:return json.load(r)
def idle():
    deadline=time.monotonic()+20
    while get()['mode']!='idle':
        if time.monotonic()>deadline:raise TimeoutError('service did not stop')
        time.sleep(.1)
if get()['mode']!='idle':raise SystemExit('A real mining session is active. Test skipped without changing it.')
original=settings.load();changed=False
server=socket.socket();server.bind(('127.0.0.1',0));server.listen(1);server.settimeout(20)
port=server.getsockname()[1];seen=[];errors=[]
def pool():
    try:
        c,_=server.accept();c.settimeout(10)
        with c,c.makefile('rwb') as f:
            def send(msg):f.write((json.dumps(msg)+'\n').encode());f.flush()
            subscribe=json.loads(f.readline());authorize=json.loads(f.readline())
            assert subscribe['method']=='mining.subscribe' and authorize['method']=='mining.authorize'
            send({'id':1,'result':[True,'EthereumStratum/1.0.0'],'error':None})
            send({'id':2,'result':True,'error':None})
            send({'method':'mining.set_extranonce','params':['ab']})
            send({'method':'mining.set_difficulty','params':[1e-10]})
            send({'method':'mining.notify','params':['1',list(struct.unpack('<4Q',bytes([42])*32)),5435345234]})
            while True:
                line=f.readline()
                if not line:break
                msg=json.loads(line)
                if msg.get('method')=='mining.submit':
                    assert msg['params'][2].startswith('ab')
                    assert len(msg['params'][2])==16
                    seen.append(msg['params'][2]);send({'id':msg['id'],'result':True,'error':None})
    except (ConnectionError,OSError):pass
    except Exception as exc:errors.append(str(exc))
try:
    idle();threading.Thread(target=pool,daemon=True).start()
    post({'action':'settings','settings':{'wallet':'kaspa:'+'q'*61,'wallets':[],'worker':'hardware-test','pool':f'stratum+tcp://127.0.0.1:{port}','password':'x'}})
    changed=True
    post({'action':'mine'});deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        state=get()
        if state.get('error'):raise RuntimeError(state['error'])
        if state['mining'].get('accepted',0)>=1:break
        time.sleep(.05)
    else:raise TimeoutError('No acknowledged local test share')
    assert seen and not errors,errors
    print('PASS real FPGA -> CPU verification -> Stratum submit -> local fake-pool acknowledgement',flush=True)
    print('Local test shares acknowledged:',state['mining']['accepted'],flush=True)
finally:
    if changed:
        post({'action':'stop'});idle();post({'action':'settings','settings':original})
    server.close()
