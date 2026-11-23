#!/usr/bin/env bash
# deploy_s9_debian13.sh - Load FPGA bitstream, Device Tree Overlay, and run test on S9 Debian 13
set -euo pipefail

BIN_FILE="oprhan_kas_4core.bin"
DTS_FILE="dts/oprhan-kas-s9.dts"
DTBO_FILE="oprhan-kas-s9.dtbo"

echo "[1/5] Checking kernel modules (fpga_mgr, uio_pdrv_genirq, u-dma-buf)..."
modprobe uio || true
modprobe uio_pdrv_genirq of_id="generic-uio" || true
modprobe u-dma-buf || echo "WARNING: u-dma-buf module not found; ensure it is built/installed."

echo "[2/5] Copying bitstream to /lib/firmware/..."
mkdir -p /lib/firmware
cp -f "$BIN_FILE" /lib/firmware/oprhan_kas_4core.bin

echo "[3/5] Compiling Device Tree Overlay..."
dtc -@ -I dts -O dtb -o "$DTBO_FILE" "$DTS_FILE"

echo "[4/5] Applying Device Tree Overlay (programs PL + creates /dev/uio0 & /dev/udmabuf0)..."
mkdir -p /sys/kernel/config/device-tree/overlays/oprhan_kas
if [ -f /sys/kernel/config/device-tree/overlays/oprhan_kas/dtbo ]; then
    rmdir /sys/kernel/config/device-tree/overlays/oprhan_kas
    mkdir -p /sys/kernel/config/device-tree/overlays/oprhan_kas
fi
cp "$DTBO_FILE" /sys/kernel/config/device-tree/overlays/oprhan_kas/dtbo
sleep 0.5

echo "[5/5] Verifying FPGA state & compiling host test..."
cat /sys/class/fpga_manager/fpga0/state
gcc -O3 -Wall host/kas_dram_host.c -o kas_dram_host
./kas_dram_host --irq
