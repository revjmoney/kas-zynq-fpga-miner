# Technical Architecture & Resource Analysis: Antminer S9 Control Board (XC7Z010)

## 1. Hardware Target Profile
- **Board:** Bitmain Antminer S9 Control Board (Zynq-7010 SoC, disconnected from hashboards)
- **FPGA / SoC Part:** `xc7z010clg400-1`
- **Processing System (PS):** Dual-core ARM Cortex-A9 running Debian 13 (Linux), DDR3 system DRAM, Gigabit Ethernet
- **Programmable Logic (PL) Budget:**
  - **17,600 LUTs** (6-input)
  - **35,200 Flip-Flops**
  - **80 DSP48E1 slices**
  - **60 Block RAMs** (36 Kb each = 2,160 Kb total, or 120 × 18 Kb BRAMs)

---

## 2. Bottleneck Elimination & Throughput Engineering

### A. Why the Original Core Was Serial-Bound
In the initial prototype (`matrix_mult_64x64.v`), the 64×64 matrix multiplication stepped through `row` (`0..63`) and `col_cnt` (`0..63`) one element per clock cycle, taking **4,096 clocks** just for the matrix step (~4,145 clocks total per hash).

### B. Parallel Wide-BRAM Matrix Engine (`~35×` Per-Core Speedup)
- Each `kas_core_lane` instantiates `matrix_ram_64x256.v` using **4× RAMB18E1** blocks configured in parallel to deliver an entire **256-bit matrix row (64 × 4-bit entries) in a single clock cycle**.
- `matrix_mult_64x64_bram.v` computes all 64 4-bit × 4-bit products and reduces them through a 3-stage adder tree every clock cycle.
- **New Latency per Hash:**
  - First Keccak-f[1600]: **24 clocks**
  - 64×64 Matrix Multiply: **65 clocks** (64 rows + 1 pipeline flush)
  - Second Keccak-f[1600]: **24 clocks**
  - FSM & Nonce Check Overhead: **3 clocks**
  - **Total:** **~116 clocks per hash** (~862 kH/s per core at 100 MHz).

### C. Parallel Scaling on XC7Z010 (`NUM_CORES = 4`)
| Resource | 1 Core | 4 Parallel Cores + DMA | XC7Z010 Limit | Utilization |
| :--- | :--- | :--- | :--- | :--- |
| **LUTs** | ~3,200 | ~13,600 | 17,600 | ~77% |
| **DSP48E1** | 16 | 64 | 80 | 80% |
| **BRAM36** | 2 | 8 | 60 | ~13% |
| **Aggregate Hashrate @ 100 MHz** | ~0.86 MH/s | **~3.45 MH/s** | — | **~143× vs original** |

*(Note: If Vivado reports routing congestion or minor negative slack at 100 MHz with 4 cores, lower `FCLK_CLK0` to `85 MHz` or set `NUM_CORES = 3` in `kas_top_parallel.v`.)*

---

## 3. Zero-Copy Zynq System DRAM DMA (`S_AXI_HP0`)
- Rather than writing 560+ registers over AXI-Lite (`M_AXI_GP0`) for every new Stratum block template, Debian 13 populates a contiguous **2,240-byte `kas_dram_job_t` struct** in DDR3 via `/dev/udmabuf0`.
- When ARM writes the physical DDR address to `0x008` and sets `CTRL.dma_load_start` (`bit 3`), `dram_job_dma.v` issues **35 AXI4 INCR bursts** (8 beats × 64 bits = 64 bytes per burst) over `S_AXI_HP0`.
- The entire 2,240-byte job loads in **~280 data beats (~2.8 µs at 100 MHz)** and broadcasts the matrix rows simultaneously into all 4 worker lanes' private Block RAMs.

---

## 4. Complete Register Map (`0x43C00000`, 4 KB Window)

| Byte Offset | Word Index | Register Name | Access | Bit / Field Definition |
| :--- | :--- | :--- | :--- | :--- |
| `0x000` | `0` | `CTRL` | R/W | `bit0`: enable_cores, `bit1`: soft_reset (pulse), `bit2`: clear_found (pulse), `bit3`: dma_load_start (pulse) |
| `0x004` | `1` | `STATUS` | R | `bit0`: any_busy, `bit1`: any_found, `bit2`: all_exhausted, `bit3`: dma_busy, `bit4`: dma_done, `bit5`: dma_err |
| `0x008` | `2` | `DRAM_ADDR` | R/W | 32-bit physical DDR address of `kas_dram_job_t` (must be 64-byte aligned) |
| `0x00C` | `3` | `CORE_COUNT` | R | Parameterized `NUM_CORES` (`4`) |
| `0x010` | `4` | `CORE_ID` | R | Constant `0x4B415334` (`"KAS4"`) |
| `0x014` | `5` | `JOB_ID_LO` | R | Active Job ID `[31:0]` |
| `0x018` | `6` | `JOB_ID_HI` | R | Active Job ID `[63:32]` |
| `0x01C` | `7` | `LANE_FOUND` | R | Bitmask `[3:0]` of lanes that found a valid hash `<= target` |
| `0x020` | `8` | `LANE_EXHAUST` | R | Bitmask `[3:0]` of lanes that completed their strided nonce range |
| `0x024` | `9` | `WIN_LANE` | R | Index (`0..3`) of the lowest-numbered winning core |
| `0x028` | `10` | `WIN_NONCE_LO` | R | Winning 64-bit nonce `[31:0]` |
| `0x02C` | `11` | `WIN_NONCE_HI` | R | Winning 64-bit nonce `[63:32]` |
| `0x030..0x04C` | `12..19` | `WIN_HASH_0..7` | R | Winning 256-bit kHeavyHash result (little-endian) |
| `0x050` | `20` | `TOT_HASH_LO` | R | Combined hashes evaluated across all 4 cores `[31:0]` |
| `0x054` | `21` | `TOT_HASH_HI` | R | Combined hashes evaluated across all 4 cores `[63:32]` |

---

## 5. Debian 13 Bring-Up & Safety Checklist (Disconnected Hashboards)
1. **Bitmain S9 Hashboard Headers:** With the 3 hashboard data cables unplugged, no PL pins are driven externally; all AXI and interrupt signals remain internal between the Zynq PS and PL.
2. **Load Bitstream Before Touching `/dev/uio0`:** Accessing `0x43C00000` while the PL is unconfigured or `FCLK_CLK0` is gated will cause an AXI bus timeout / kernel external abort. Always apply the Device Tree Overlay (or write `/sys/class/fpga_manager/fpga0/firmware`) first and verify `/sys/class/fpga_manager/fpga0/state` reads `operating`.
3. **Contiguous DRAM Coherency:** Using `u-dma-buf` (`/dev/udmabuf0`) with `O_SYNC` or `dma-coherent` ensures ARM CPU writes to `kas_dram_job_t` are visible in DDR3 before ringing `CTRL.dma_load_start`.
