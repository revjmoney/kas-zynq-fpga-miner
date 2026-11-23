# OPRHAN KASPA PARALLEL FPGA + ZYNQ DRAM DMA PACKAGE
**Target Hardware:** Bitmain Antminer S9 Control Board (`xc7z010clg400-1`, disconnected hashboards)  
**Host OS:** Debian 13 (ARMv7 Cortex-A9)  
**Author:** Rev. J. Money

## Package Contents
- `rtl/` — Complete synthesizable Verilog RTL for 4 parallel kHeavyHash cores (`kas_top_parallel.v`), wide-BRAM parallel matrix multiplier (`matrix_mult_64x64_bram.v`), fixed Keccak-f[1600] (`keccak_f1600.v`), and 64-bit AXI4 HP0 DRAM DMA loader (`dram_job_dma.v`).
- `dts/oprhan-kas-s9.dts` — Linux Device Tree Overlay configuring `fpga_manager`, `/dev/uio0` (`0x43C00000` + `IRQ_F2P[0]` / GIC SPI 29), and `/dev/udmabuf0` (64 KB contiguous DMA buffer).
- `host/kas_dram_host.c` — Debian 13 C host driver with blocking UIO interrupt handling, `udmabuf0` physical address lookup, and reference Kaspa `xoshiro256**` matrix generator.
- `scripts/build_vivado_s9.tcl` — Automated Vivado batch script that builds the Zynq Block Design (`M_AXI_GP0`, `S_AXI_HP0`, `IRQ_F2P`, `100 MHz FCLK_CLK0`), runs synthesis/implementation, and outputs `oprhan_kas_4core.bin`.
- `scripts/deploy_s9_debian13.sh` — One-step Debian 13 deployment script to load kernel modules, apply the Device Tree Overlay, program the FPGA, and run the hardware verification test.
- `tb/tb_kas_top_parallel.v` — Self-checking Verilog testbench simulating both AXI-Lite control and AXI4 HP0 DRAM burst reads.
- `docs/ARCHITECTURE_AND_BRINGUP.md` — Full technical documentation, resource/timing breakdown, register map, and Debian 13 bring-up checklist.
