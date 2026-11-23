// kas_dram_host.c - Debian 13 ARM Host Driver for 4-Core Parallel KAS + HP0 DRAM DMA
// Compile on S9 Debian 13: gcc -O3 -Wall kas_dram_host.c -o kas_dram_host
//
// Features:
//   - Maps /dev/uio0 (0x43C00000) for register control + blocking GIC interrupt wait
//   - Maps /dev/udmabuf0 for zero-copy 64-bit S_AXI_HP0 DRAM DMA bursts
//   - Includes reference Kaspa xoshiro256** matrix generator from pre_pow_hash

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

// AXI-Lite Word Offsets (base 0x43C00000)
#define REG_CTRL         0  // 0x000: bit0=en, bit1=rst, bit2=clr, bit3=dma_start
#define REG_STATUS       1  // 0x004: bit0=busy, bit1=found, bit2=exhaust, bit3=dma_busy, bit4=dma_done, bit5=dma_err
#define REG_DRAM_ADDR    2  // 0x008
#define REG_CORE_COUNT   3  // 0x00C
#define REG_CORE_ID      4  // 0x010 ("KAS4" = 0x4B415334)
#define REG_JOB_ID_LO    5  // 0x014
#define REG_JOB_ID_HI    6  // 0x018
#define REG_LANE_FOUND   7  // 0x01C
#define REG_LANE_EXHAUST 8  // 0x020
#define REG_WIN_LANE     9  // 0x024
#define REG_WIN_NONCE_LO 10 // 0x028
#define REG_WIN_NONCE_HI 11 // 0x02C
#define REG_WIN_HASH_0   12 // 0x030..0x04C
#define REG_TOT_HASH_LO  20 // 0x050
#define REG_TOT_HASH_HI  21 // 0x054

typedef struct __attribute__((packed, aligned(64))) {
    uint32_t target[8];       // Bytes    0..  31
    uint64_t nonce_start;     // Bytes   32..  39
    uint64_t nonce_end;       // Bytes   40..  47
    uint32_t block_rate[34];  // Bytes   48.. 183 (1088-bit padded block)
    uint64_t job_id;          // Bytes  184.. 191
    uint32_t matrix[512];     // Bytes  192..2239 (64x64 4-bit entries)
} kas_dram_job_t;

// Kaspa xoshiro256** PRNG used to generate the 64x64 rank-64 matrix per block template
static inline uint64_t rotl64(uint64_t x, int k) {
    return (x << k) | (x >> (64 - k));
}

static uint64_t xoshiro256ss_next(uint64_t s[4]) {
    const uint64_t result = rotl64(s[1] * 5, 7) * 9;
    const uint64_t t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = rotl64(s[3], 45);
    return result;
}

// Generates a packed 64x64 4-bit matrix (512 x uint32_t) from 32-byte pre_pow_hash
static void generate_kaspa_matrix(const uint8_t pre_pow_hash[32], uint32_t out_matrix[512]) {
    uint64_t state[4];
    memcpy(state, pre_pow_hash, 32);

    uint8_t mat[64][64];
    memset(mat, 0, sizeof(mat));

    for (int i = 0; i < 64; i++) {
        for (int j = 0; j < 64; j += 16) {
            uint64_t val = xoshiro256ss_next(state);
            for (int k = 0; k < 16; k++) {
                mat[i][j + k] = (val >> (4 * k)) & 0x0F;
            }
        }
    }

    // Pack into 512 x 32-bit little-endian words (8 nibbles per 32-bit word)
    for (int r = 0; r < 64; r++) {
        for (int w = 0; w < 8; w++) {
            uint32_t word = 0;
            for (int n = 0; n < 8; n++) {
                word |= ((uint32_t)(mat[r][w * 8 + n] & 0x0F)) << (4 * n);
            }
            out_matrix[r * 8 + w] = word;
        }
    }
}

static uint32_t read_phys_addr(const char *sysfs_path) {
    FILE *f = fopen(sysfs_path, "r");
    if (!f) return 0;
    unsigned long addr = 0;
    if (fscanf(f, "%lx", &addr) != 1) addr = 0;
    fclose(f);
    return (uint32_t)addr;
}

int main(int argc, char **argv) {
    int use_irq = (argc > 1 && strcmp(argv[1], "--irq") == 0);

    int uio_fd = open("/dev/uio0", O_RDWR | O_SYNC);
    if (uio_fd < 0) {
        perror("open /dev/uio0");
        return 1;
    }
    volatile uint32_t *regs = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, uio_fd, 0);
    if (regs == MAP_FAILED) {
        perror("mmap uio0");
        return 1;
    }

    uint32_t core_id = regs[REG_CORE_ID];
    uint32_t ncores  = regs[REG_CORE_COUNT];
    printf("FPGA Online: CORE_ID=0x%08X | Parallel Lanes=%u | Mode=%s\n",
           core_id, ncores, use_irq ? "GIC_IRQ" : "POLL");
    if (core_id != 0x4B415334) {
        fprintf(stderr, "ERROR: Expected CORE_ID 0x4B415334. Check bitstream load state.\n");
        return 1;
    }

    int dma_fd = open("/dev/udmabuf0", O_RDWR | O_SYNC);
    if (dma_fd < 0) {
        perror("open /dev/udmabuf0");
        return 1;
    }
    uint32_t phys_addr = read_phys_addr("/sys/class/u-dma-buf/udmabuf0/phys_addr");
    if (phys_addr == 0) {
        fprintf(stderr, "ERROR: Cannot read /sys/class/u-dma-buf/udmabuf0/phys_addr\n");
        return 1;
    }
    kas_dram_job_t *job = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, dma_fd, 0);
    if (job == MAP_FAILED) {
        perror("mmap udmabuf0");
        return 1;
    }

    // Build test job in contiguous DRAM
    memset(job, 0, sizeof(*job));
    for (int i = 0; i < 8; i++) job->target[i] = 0xFFFFFFFF;
    job->nonce_start = 1000;
    job->nonce_end   = 200000;
    job->job_id      = 0x0000000100000042ULL;

    uint8_t dummy_pre_pow[32];
    for (int i = 0; i < 32; i++) dummy_pre_pow[i] = (uint8_t)(0xA0 + i);
    generate_kaspa_matrix(dummy_pre_pow, job->matrix);

    for (int i = 0; i < 34; i++) job->block_rate[i] = 0x12345678u + i;

    __sync_synchronize();

    // Enable UIO interrupt before launching if --irq is specified
    if (use_irq) {
        uint32_t irq_en = 1;
        if (write(uio_fd, &irq_en, sizeof(irq_en)) != sizeof(irq_en)) {
            perror("write uio0 irq enable");
        }
    }

    // Trigger HP0 DMA load (bit 3) + Enable all 4 cores (bit 0)
    regs[REG_DRAM_ADDR] = phys_addr;
    regs[REG_CTRL]      = (1u << 3) | (1u << 0);

    uint32_t status = 0;
    if (use_irq) {
        uint32_t irq_count = 0;
        if (read(uio_fd, &irq_count, sizeof(irq_count)) == sizeof(irq_count)) {
            status = regs[REG_STATUS];
        }
    } else {
        while (1) {
            status = regs[REG_STATUS];
            if (status & ((1u << 1) | (1u << 2) | (1u << 5)))
                break;
            usleep(100);
        }
    }

    uint64_t total_hashes = ((uint64_t)regs[REG_TOT_HASH_HI] << 32) | regs[REG_TOT_HASH_LO];
    uint64_t win_nonce    = ((uint64_t)regs[REG_WIN_NONCE_HI] << 32) | regs[REG_WIN_NONCE_LO];

    printf("Done: STATUS=0x%02X | Total Hashes=%llu | Winning Lane=%u | Winning Nonce=%llu\n",
           status, (unsigned long long)total_hashes, regs[REG_WIN_LANE], (unsigned long long)win_nonce);

    // Clear latched status & disable cores
    regs[REG_CTRL] = (1u << 2);
    return 0;
}
