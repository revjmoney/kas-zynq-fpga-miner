"""End-to-end bus tests against independently checked CPU vectors."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'orphan_kas'))
from reference import generate_matrix,kheavyhash
vectors=json.loads((ROOT/'orphan_kas'/'vectors.json').read_text())
out=['''`timescale 1ns/1ps
module tb_kas;
 reg clk=0,rstn=0,we=0,re=0;
 reg [15:0] addr=0;
 reg [31:0] wd=0;
 wire [31:0] rd;
 always #5 clk=~clk;
 kas_engine dut(.clk(clk),.rstn(rstn),.bus_addr(addr),.bus_wdata(wd),.bus_wstrb(4'hf),.bus_we(we),.bus_re(re),.bus_rdata(rd));
 task wr(input [9:0] idx,input [31:0] value); begin
 @(negedge clk); addr=16'h1000+idx*4; wd=value; we=1;
 @(negedge clk); we=0;
 @(negedge clk);
 end endtask
 task rd_check(input [9:0] idx,input [31:0] expected); begin
 @(negedge clk); addr=16'h1000+idx*4; re=1;
 @(negedge clk); re=0;
 repeat(2) @(negedge clk);
 if(rd !== expected) $fatal(1,"register read mismatch idx=%d got=%h expected=%h",idx,rd,expected);
 end endtask
 task wait_done; begin
 @(negedge clk); wait(!dut.busy); @(negedge clk);
 end endtask
 initial begin #25; rstn=1;
 rd_check(0,32'h4b415331);
 rd_check(17,32'd1);
''']
def wr(i,v):out.append(f"wr(10'd{i},32'h{v:08x});")
def value_words(base,data):
    for i in range(0,len(data),4):wr(base+i//4,int.from_bytes(data[i:i+4],'little'))
def u64(base,n): value_words(base,int(n).to_bytes(8,'little'))
for vi,v in enumerate(vectors):
    seed=bytes.fromhex(v['seed']); value_words(64,seed)
    for si in range(8):out.append(f"rd_check(10'd{64+si},32'h{int.from_bytes(seed[si*4:si*4+4],'little'):08x});")
    u64(72,v['timestamp'])
    for i,word in enumerate(v['matrix']):wr(512+i,word)
    for hi,h in enumerate(v['hashes']):
        nonce=int(v['start'])+hi
        u64(74,nonce);u64(76,nonce+len(v['hashes'])-1 if hi==0 else nonce)
        # Test equality boundary on the first nonce and exhaustion on the others.
        expected=int.from_bytes(bytes.fromhex(h),'little')
        target=expected if hi==0 else expected-1
        value_words(80,target.to_bytes(32,'little'))
        wr(1,1);out.append('wait_done;')
        out.append(f"if(dut.last_hash !== 256'h{expected:064x}) $fatal(1,\"hash mismatch vector {vi}/{hi}: %h\",dut.last_hash);")
        out.append(f"if(dut.last_nonce !== 64'h{nonce:016x} || dut.hashes !== 1) $fatal(1,\"nonce/count mismatch\");")
        out.append(f"if(dut.found !== 1'b{int(hi==0)} || dut.exhausted !== 1'b{int(hi!=0)}) $fatal(1,\"target mismatch\");")
        out.append(f'$display("PASS vector {vi}/{hi}");')
        for si in range(8):out.append(f"rd_check(10'd{9+si},32'h{int.from_bytes(bytes.fromhex(h)[si*4:si*4+4],'little'):08x});")
    # Search several consecutive nonces, impossible target so all must exhaust.
    u64(74,v['start']);u64(76,int(v['start'])+len(v['hashes'])-1)
    value_words(80,bytes(32));wr(1,1);out.append('wait_done;')
    out.append(f'if(dut.hashes !== {len(v["hashes"])} || !dut.exhausted) $fatal(1,"search range mismatch");')
    out.append('$display("PASS inclusive range search: %0d hashes in %0d clocks",dut.hashes,dut.cycles);')
# Exercise sustained overlap without wrapping the 64-bit nonce.
# Keep this job after the third vector's matrix upload.
end=0xffffffffffffffff
count=257
expected=int.from_bytes(kheavyhash(seed,int(v['timestamp']),end,generate_matrix(seed)),'little')
u64(74,end-count+1);u64(76,end);value_words(80,bytes(32));wr(1,1)
out.append('wait_done;')
out.append(f'if(dut.hashes!={count} || !dut.exhausted || dut.last_nonce!=64\'h{end:016x} || dut.last_hash!=256\'h{expected:064x}) $fatal(1,"long range mismatch");')
out.append('$display("PASS sustained search: %0d hashes in %0d clocks",dut.hashes,dut.cycles);')
u64(74,0);u64(76,0xffffffffffffffff);wr(1,1)
out.append('repeat(20) @(negedge clk);')
wr(1,2);out.append('if(dut.busy || !dut.stopped) $fatal(1,"stop failed");')
u64(74,2);u64(76,1);wr(1,1)
out.append('if(dut.busy || !dut.bad_config) $fatal(1,"invalid range accepted");')
wr(1,4);out.append('if(dut.hashes || dut.busy || dut.bad_config) $fatal(1,"clear failed");')
out.append('''$display("PASS stop, invalid range, clear; ALL TESTS PASSED");
 $finish; end
 initial begin #9000000; $fatal(1,"watchdog"); end
endmodule''')
(ROOT/'sim'/'tb_kas.v').write_text('\n'.join(out))
