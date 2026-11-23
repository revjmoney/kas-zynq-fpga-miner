"""Independent crypto and upstream Kaspa fixture checks; emit RTL test vectors."""
import ast,json,sys,re,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path[:0]=[str(ROOT/'.deps'),str(ROOT.parent/'.deps'),str(ROOT/'orphan_kas')]
import reference as ref
from Crypto.Hash import cSHAKE256
for custom in (b'ProofOfWorkHash',b'HeavyHash'):
    for data in (b'', bytes(range(32)), bytes(range(80)),bytes(range(256))):
        assert ref.cshake(data,custom)==cSHAKE256.new(data=data,custom=custom).read(32)
print('PASS independent cSHAKE256 vectors (8)')
source=(ROOT/'sim'/'upstream_matrix.rs').read_text()
expected=bytes(ast.literal_eval(re.search(r'let expected_hash = Hash::from_bytes\((\[.*?\])\)',source,re.S)[1]))
matrix=ast.literal_eval(re.search(r'let test_matrix = Matrix\((\[.*?\])\);',source,re.S)[1])
test=source[source.index('let test_matrix'):]
# Upstream fixture input is extracted explicitly below, not inferred from the expected result.
match=re.search(r'let hash = Hash::from_bytes\((\[.*?\])\)',test,re.S)
if match:
    first=bytes(ast.literal_eval(match[1]))
else:
    raise RuntimeError('Inspect upstream fixture input syntax')
assert ref.heavy_hash(first,matrix)==expected
print('PASS upstream Kaspa heavy_hash fixture')
expected_matrix=ast.literal_eval(re.search(r'let expected_matrix = Matrix\((\[.*?\])\);',source,re.S)[1])
assert ref.generate_matrix(bytes([42])*32)==expected_matrix
print('PASS upstream Kaspa matrix generation fixture (4096 entries)')
vectors=[]
for seed,ts,start,count in [(bytes([42])*32,5435345234,432432432,1),
                           (bytes(range(32)),0xffffffffffffffff,0xfffffffffffffffd,3),
                           (bytes(range(160,192)),0,0,4)]:
    m=ref.generate_matrix(seed)
    hashes=[ref.kheavyhash(seed,ts,start+i,m).hex() for i in range(count)]
    vectors.append(dict(seed=seed.hex(),timestamp=str(ts),start=str(start),
                        hashes=hashes,matrix=ref.matrix_words(m)))
(ROOT/'orphan_kas'/'vectors.json').write_text(json.dumps(vectors,indent=2))
print('PASS matrix rank and end-to-end vector generation')
