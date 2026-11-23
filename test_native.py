"""Run on the ARM board after compiling matrix_native.so."""
import sys,time,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'orphan_kas'))
import matrix
from reference import generate_matrix,matrix_words
assert matrix.native is not None,'Compile matrix_native.so first'
python_seconds=native_seconds=0
for i in range(12):
    seed=bytes([42])*32 if i==0 else hashlib.sha256(('orphan-matrix-%d'%i).encode()).digest()
    start=time.perf_counter();expected=generate_matrix(seed);python_seconds+=time.perf_counter()-start
    start=time.perf_counter();got=matrix.generate_matrix(seed);native_seconds+=time.perf_counter()-start
    assert got==expected and matrix_words(got)==matrix_words(expected)
try:matrix.generate_matrix(bytes(32));raise AssertionError('zero seed accepted')
except ValueError:pass
print('PASS 12 native matrices / 49152 entries match independent Python reference')
print('Job preparation average: Python %.3f ms, native %.3f ms, %.1fx faster'%(python_seconds/12*1000,native_seconds/12*1000,python_seconds/native_seconds))
