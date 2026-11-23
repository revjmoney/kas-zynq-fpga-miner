"""Protocol tests, including an actual local TCP fake-pool session."""
import json,socket,struct,sys,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'orphan_kas'))
from stratum import parse_job,target_for_diff,nonce_bounds,Session,DIFF_ONE
from reference import generate_matrix,kheavyhash

seed=bytes.fromhex('853a0bb20ce86f2666da260099e3ab24bb4df7c83a9630e3f519f29a41142ed2')
assert parse_job(['1',seed.hex()+'9abb1a6300000000'])==('1',seed,1662696346)
assert parse_job(['1',list(struct.unpack('<4Q',seed)),1662696346])==('1',seed,1662696346)
assert target_for_diff(1)==DIFF_ONE and target_for_diff(2)==DIFF_ONE//2
assert target_for_diff('0.0000000001')==(1<<256)-1
assert nonce_bounds('ab')[0]==0xab00000000000000
for bad in [0,-1,'NaN','Infinity']:
    try:target_for_diff(bad);raise AssertionError('accepted invalid difficulty')
    except ValueError:pass

class FakeEngine:
    def __init__(self):self.running=False;self.last=None;self.starts=0
    def stop(self):self.running=False
    def configure(self,seed,ts,start,end,target,matrix):
        self.seed,self.ts,self.start_nonce,self.end,self.target,self.matrix=seed,ts,start,end,target,matrix
    def start(self):
        self.starts+=1;self.running=True
        value=kheavyhash(self.seed,self.ts,self.start_nonce,self.matrix)
        self.last=dict(found=True,nonce=str(self.start_nonce),hash=value.hex(),verified=True)
    def r(self,i):return 0
    def result(self):return self.last
    def status(self):return {'hashes':'1','busy':False}
    def u64(self,i):return 1 if i==3 else self.end
    def words(self,i,data):self.start_nonce=struct.unpack('<Q',data)[0]

server=socket.socket();server.bind(('127.0.0.1',0));server.listen(1)
port=server.getsockname()[1];cancel=threading.Event();messages=[];errors=[];states=[]
def pool():
    try:
        c,_=server.accept();c.settimeout(5);f=c.makefile('rwb')
        def send(data):f.write((json.dumps(data)+'\n').encode());f.flush()
        a=json.loads(f.readline());b=json.loads(f.readline())
        assert a['method']=='mining.subscribe' and b['method']=='mining.authorize'
        assert b['params'][0]=='kaspa:'+'q'*61+'.test'
        send({'id':1,'result':[True,'EthereumStratum/1.0.0'],'error':None})
        send({'id':2,'result':True,'error':None})
        send({'method':'mining.set_extranonce','params':['ab']})
        send({'method':'mining.set_difficulty','params':[1e-10]})
        send({'method':'mining.notify','params':['7',list(struct.unpack('<4Q',seed)),1]})
        msg=json.loads(f.readline());messages.append(msg)
        assert msg['method']=='mining.submit' and msg['params'][1]=='7'
        assert msg['params'][2].startswith('ab') and len(msg['params'][2])==16
        send({'id':msg['id'],'result':True,'error':None})
        time.sleep(.15);cancel.set();f.close();c.close()
    except Exception as e:errors.append(e);cancel.set()
threading.Thread(target=pool,daemon=True).start()
session=Session(FakeEngine(),dict(wallet='kaspa:'+'q'*61,worker='test',pool=f'stratum+tcp://127.0.0.1:{port}',password='x'),cancel,lambda **kw:states.append(kw))
session.run();server.close()
assert not errors,errors
assert messages and session.stats['accepted']>=1
assert session.stats['submitted']>=1
assert not session.stats['connected']
print('PASS job decoding, difficulty, extranonce, wallet authorization, TCP submit and share acknowledgement')
