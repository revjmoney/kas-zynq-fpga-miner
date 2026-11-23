"""Run on the board after copying a host/UI update; preserve live mining intent."""
import hashlib,json,os,subprocess,urllib.request,time
from pathlib import Path
ROOT=Path('/opt/ardzy/projects/orphan_kas')
def state():
    with urllib.request.urlopen('http://127.0.0.1:8000/api/status',timeout=3) as r:return json.load(r)
s=state();config=ROOT/'settings.local.json'
before=hashlib.sha256(config.read_bytes()).hexdigest() if config.exists() else None
if s.get('mode')=='mine':
    marker=ROOT/'resume.local.json';marker.write_text(json.dumps({'mining':True,'totals':s.get('mining',{})}));os.chmod(marker,0o600)
subprocess.run(['ardzy','restart'],check=True)
deadline=time.monotonic()+20
while time.monotonic()<deadline:
    try:
        current=state()
        if current.get('hardware') and (s.get('mode')!='mine' or current.get('mode')=='mine'):break
    except Exception:pass
    time.sleep(.2)
else:raise TimeoutError('Updated service did not become ready')
after=hashlib.sha256(config.read_bytes()).hexdigest() if config.exists() else None
assert before==after,'Wallet settings changed during update'
print('Updated service; wallet settings unchanged; mining '+('resumed' if s.get('mode')=='mine' else 'was idle'))
