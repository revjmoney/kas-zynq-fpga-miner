"""HTTP settings persistence and validation regression; no FPGA required."""
import http.server,json,sys,tempfile,threading,urllib.request,urllib.error
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'orphan_kas'))
import earnings,main,settings

with patch.object(earnings,'read_json',side_effect=[{'hashrate':330000},{'blockreward':1.94},{'price':.025}]):
    assert earnings.market()['network_hs']==330e15

with patch.object(earnings, 'read_json', side_effect=AssertionError('SOLO terms require no wallet request')):
    taz = earnings.pool_stats('test-wallet', 'pool.tazmining.ch', 7110)
    assert (taz['mode'], taz['minimum_kas'], taz['fee_percent']) == ('solo', 1, 0.5)
    assert 'balance_kas' not in taz and 'paid_week_kas' not in taz
    assert earnings.pool_stats('test-wallet', 'pool.tazmining.ch', 7100)['status'] == 'unsupported'
    assert earnings.Earnings.key({'wallet': 'test-wallet', 'pool': 'stratum+tcp://pool.tazmining.ch:7110'})[-1] == 7110
class Control:
    def __init__(self):
        self.lock=threading.Lock();self.active=False;self.cancel=threading.Event();self.state={'settings':settings.public()};self.commands=[]
    def snapshot(self):return self.state
    def submit(self,cmd):self.commands.append(cmd)
    def log(self,*args):pass
with tempfile.TemporaryDirectory(prefix='orphan-api-test-') as folder:
    settings.PATH=Path(folder)/'settings.local.json'
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),main.Handler);server.control=Control()
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url=f'http://127.0.0.1:{server.server_port}'
    def post(data,origin=None):
        headers={'Content-Type':'application/json'}
        if origin:headers['Origin']=origin
        r=urllib.request.Request(url+'/api/command',json.dumps(data).encode(),headers)
        try:
            with urllib.request.urlopen(r) as result:return result.status,json.load(result)
        except urllib.error.HTTPError as error:return error.code,json.load(error)
    wallet='kaspa:'+'q'*61
    cfg={'wallet':wallet,'wallets':[],'worker':'test','pool':'stratum+tcp://127.0.0.1:5555','password':'test-only'}
    assert post({'action':'settings','settings':cfg})[0]==202
    assert settings.load()['wallet']==wallet and settings.load()['password']=='test-only'
    assert settings.public()['password']=='test-only'   # LAN-only page shows the saved pool password (Rev's call)
    with patch.object(settings,'save',side_effect=OSError(5,'Input/output error')):
        status,reply=post({'action':'settings','settings':{**cfg,'worker':'replacement'}})
        assert status==503 and 'SD card' in reply['error']
        assert server.control.state['settings']['worker']=='test'
    assert post({'action':'settings','settings':{**cfg,'wallet':'not a wallet!'}})[0]==400
    assert post({'action':'settings','settings':{**cfg,'wallet':'revjmoney'}})[0]==202   # Mining-Dutch: pool account name
    assert post({'action':'settings','settings':cfg})[0]==202
    assert post({'action':'job','start':'10','end':'1'})[0]==400
    assert post({'action':'job','timestamp':str(1<<64)})[0]==400
    assert post({'action':'job','target':'1'*65})[0]==400
    assert post({'action':'selftest'},'http://unrelated.example')[0]==400
    assert post({'action':'selftest'})[0]==202
    server.control.active=True
    assert post({'action':'settings','settings':cfg})[0]==400
    server.control.active=False
    assert post({'action':'stop'})[0]==202 and server.control.cancel.is_set()
    with urllib.request.urlopen(url+'/') as result:
        page=result.read().decode();assert 'Wallet &amp; pool' in page and 'JMSCNC' in page
    server.shutdown();server.server_close()
print('PASS web API, wallet persistence, pool account names, input validation, active-job guard and origin check')
