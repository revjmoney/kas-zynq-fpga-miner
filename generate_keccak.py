"""Emit constant-wired Keccak round logic to keep synthesis simple."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent/'orphan_kas'))
from reference import RC, RHO
out = ['''// Keccak-f1600, 24 rounds. Constant lane wiring. Orphan KAS.
module kas_keccak(input wire clk, input wire rstn, input wire start,
 input wire [1599:0] state_in, output reg [1599:0] state_out=0,
 output reg done=0);
 reg [1599:0] a=0;
 reg [4:0] round=0;
 reg busy=0;
 wire [1599:0] next_a;
 reg [1599:0] b_pipe=0;
 reg phase=0;
 function [63:0] round_constant;
 input [4:0] r;
 begin case(r)''']
out += [f" 5'd{i}: round_constant=64'h{v:016x};" for i,v in enumerate(RC)]
out += [" default: round_constant=0; endcase end endfunction", "wire [63:0] rc=round_constant(round);"]
def lane(x,y): return f'a[{64*(x+5*y)} +: 64]'
for x in range(5):
    out.append(f"wire [63:0] c{x} = " + ' ^ '.join(lane(x,y) for y in range(5)) + ';')
    out.append(f"wire [63:0] d{x};")
for x in range(5):
    out.append(f'assign d{x}=c{(x+4)%5} ^ {{c{(x+1)%5}[62:0], c{(x+1)%5}[63]}};')
for x in range(5):
    for y in range(5):
        i=x+5*y; dest=y+5*((2*x+3*y)%5); n=RHO[x][y]
        out.append(f'wire [63:0] t{i}={lane(x,y)} ^ d{x};')
        value=f'{{t{i}[{63-n}:0], t{i}[63:{64-n}]}}' if n else f't{i}'
        out.append(f'wire [63:0] b{dest}={value};')
for y in range(5):
    for x in range(5):
        i=x+5*y
        out.append(f'assign next_a[{64*i} +: 64]=b_pipe[{64*i} +:64] ^ ((~b_pipe[{64*((x+1)%5+5*y)} +:64]) & b_pipe[{64*((x+2)%5+5*y)} +:64])' + (' ^ rc;' if i==0 else ';'))
for i in range(25):
    out.append(f'always @(posedge clk) if(busy && !phase) b_pipe[{i*64} +:64]<=b{i};')
out.append('''always @(posedge clk) begin
 done<=0;
 if(!rstn) begin busy<=0; round<=0; phase<=0; end
 else if(start && !busy) begin a<=state_in; round<=0; busy<=1; phase<=0; end
 else if(busy && !phase) phase<=1;
 else if(busy) begin
   phase<=0;
   a<=next_a;
   if(round==23) begin state_out<=next_a; done<=1; busy<=0; end
   else round<=round+1'b1;
 end
end
endmodule
''')
Path(__file__).with_name('orphan_kas').joinpath('kas_keccak.v').write_text('\n'.join(out))
