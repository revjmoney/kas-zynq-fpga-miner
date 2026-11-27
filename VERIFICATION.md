# Hardware verification

Test date: 2026-11-21. Hardware: S9 control board #2, XC7Z010 CLG400-1, Orphan Debian 13, 100 MHz FCLK0.

## First verified baseline

* Implementation timing: **112.68 MHz maximum**, PASS at 100 MHz, zero reported hold violations.
* Resources: **7,561 LUTs**, 6,745 flip-flops, one BRAM36 equivalent, one DSP.
* Independent cSHAKE tests: 8 passed against PyCryptodome.
* Upstream Kaspa fixtures: HeavyHash result and all 4,096 generated matrix entries match.
* RTL: 8 complete hash vectors, target equality/rejection, inclusive ranges near the u64 limit, repeated jobs, stop, clear, invalid ranges and two-cycle register readback passed.
* Hardware: 8 hash vectors and 3 exhaustion ranges passed through the deployed service.
* Hardware benchmark: **1,000,000 hashes in 1,383,000,000 FPGA clocks**, or **13.83 seconds / 72,306.58 H/s**.
* Final benchmark nonce: 999999. Serialized final hash: `55d9ca708ae4e4e5a1a413900de081fa13d111421ed909fa3f54a7c00301f31d`. ARM independently recomputed and verified it.
* Fan peripheral ID readback: `0x46414e31` (`FAN1`). Temperature is read live from the Zynq XADC.

This baseline serializes groups of matrix coefficients. Its measured throughput is substantially lower than the original archive's unverified four-core estimates. Further optimization must retain these correctness checks.

## Full-row matrix pipeline

* Final RTL simulation passed all eight hash vectors, all three inclusive nonce ranges, and stop, clear, and invalid-range checks.
* The ranges completed in 174 active clocks per hash. The routed core passed 100 MHz timing with a reported maximum of 103.31 MHz and zero hold violations. It uses 8,753 LUTs, 7,282 flip-flops, four BRAM36 equivalents and one DSP.
* On board #2, the deployed self-test passed eight hash vectors and three inclusive nonce ranges. The one-million-nonce benchmark completed in 174,000,000 FPGA clocks, or **1.74 seconds / 574,712.64 H/s** at 100 MHz. ARM verified the final hash, which matched the baseline exactly. The saved wallet and pool settings file matched its pre-deployment checksum.
* ARM matrix preparation measured 181.3 ms with Python and 2.25 ms with the native packed generator on board #2. The native output matched the independent Python matrix across 12 seeds.

## Overlapping nonce pipeline

* RTL tested eight hash vectors and inclusive, early-hit, u64-limit and 257-nonce ranges. The 257-nonce range took 26,257 cycles.
* Routing passed the 100 MHz clock constraint at a reported 129.13 MHz maximum, with zero hold violations. It uses 9,093 LUTs, 7,861 flip-flops, four BRAM36 equivalents and one DSP.
* Board #2 passed eight hash vectors and three inclusive nonce ranges. The million-nonce benchmark took **102,000,043 clocks**, or **980,391.74 H/s** at 100 MHz. ARM verified the hash at nonce 999999. The wallet and pool settings checksum matched.
* The board resumed the saved pool session and received live jobs at approximately 980.2 kH/s on the FPGA and 959.8 kH/s over wall time during the initial check. It reported zero accepted and zero rejected shares at that point.

## Pool and UI

* HTTP tests: wallet/pool persistence, pool account names, request validation, origin check and active-job settings guard passed.
* Local TCP fake-pool test: subscription, authorization, compact/large jobs, difficulty conversion, extranonce handling, submission and acknowledgement accounting passed.
* Live HeroMiners US East GPU/FPGA endpoint: subscription and wallet/worker authorization succeeded; live jobs were received and hashed. The pool assigned normalized difficulty 4.
* **No real accepted pool share has been observed.** At baseline peak throughput, difficulty 4 represents about 66 hours per share on average before job-setup overhead. Zero accepted/rejected shares is consistent with the measured rate.
* A proposed real-FPGA/local-fake-pool test was not completed because a live mining session was active. Its guard was corrected to skip active sessions without changing them. It is not counted as passed.
* The deployed live log records connection, subscription, authorization, difficulty, jobs, verified submissions, acknowledgements and errors.

The original user package is preserved in `Oprhan_KAS_S9_Complete_Package/`. No bootloader, NAND or boot-default change was needed for this project.
