"""Write portable source hashes: text is normalized to LF, bitstreams remain binary."""
import hashlib,json
from pathlib import Path
def write(root,bit):
    root=Path(root);bit=Path(bit)
    sources={p.name:hashlib.sha256(p.read_bytes().replace(b'\r\n',b'\n')).hexdigest()
             for p in (root/'orphan_kas').iterdir() if p.suffix in ('.v','.xdc') or p.name=='fpga.json'}
    (root/'build-manifest.json').write_text(json.dumps({'source_hash_format':'sha256-lf','bitstream':bit.name,
        'sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),'sources':sources},indent=2))
if __name__=='__main__':
    root=Path(__file__).resolve().parent
    write(root,root/'orphan_kas'/'orphan_kas.bit')
