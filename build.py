"""Build KAS on F:, rejecting a bitstream with failed timing."""
import os,sys,tempfile,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
BUILD_TEMP=Path(os.environ.get('ORPHAN_BUILD_TEMP',str(Path(os.environ.get('TEMP',str(ROOT/'temp')))/'orphan-kas') if os.name=='nt' else str(ROOT/'temp')))
BUILD_TEMP.mkdir(parents=True,exist_ok=True)
os.environ['TEMP']=os.environ['TMP']=str(BUILD_TEMP)
tempfile.tempdir=str(BUILD_TEMP)
ARDZY=Path(os.environ.get('ARDZY_PC_APP',str(ROOT.parents[1]/'ardzy'/'pc_app')))
sys.path.insert(0,str(ARDZY))
sys.path.insert(0,str(ARDZY/'fpga'))
from fpga import flow
def log(msg,kind=''):
    print(str(msg),flush=True)
bit=flow.build(str(ROOT/'orphan_kas'),log=log)
report=flow.build_report(str(ROOT/'orphan_kas'))
if not report or not report.get('timing_ok'):
    raise SystemExit('BUILD REJECTED: timing failed. Do not deploy this bitstream.')
(ROOT/'build-report.json').write_text(json.dumps(report,indent=2))
from write_manifest import write
write(ROOT,bit)
print('BITSTREAM',bit,flush=True)
print('BUILD_METADATA',report,flush=True)
