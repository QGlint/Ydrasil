#define BOUNDARY_NAME "mmio_dtcm_order_edges"
#include "boundary.h"

#define SW0_REG ((volatile uint32_t *)0x80200000u)
#define SEG_REG ((volatile uint32_t *)0x80200020u)

static volatile uint32_t dtcm[4];

int main(void)
{
    uint32_t r;
    uint32_t mmio;

    asm volatile(
        "csrw mscratch, %3\ncsrr t0, mscratch\n"
        "sw t0, 0(%1)\n"
        "lw %0, 0(%2)"
        : "=&r"(mmio)
        : "r"(&dtcm[0]), "r"(SW0_REG), "r"(0x11223344u)
        : "t0", "memory");
    CHECK_EQ("waiting_dtcm_store_before_mmio_load", dtcm[0], 0x11223344u);
    CHECK_EQ("mmio_load_value", mmio, 0);

    asm volatile(
        "lw t0, 0(%2)\n"
        "csrw mscratch, %3\ncsrr t1, mscratch\n"
        "sw t1, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r)
        : "r"(&dtcm[1]), "r"(SW0_REG), "r"(0x55667788u)
        : "t0", "t1", "memory");
    CHECK_EQ("mmio_load_before_csr_store", r, 0x55667788u);

    asm volatile(
        "li t0, 0x13579\nsw t0, 0(%2)\n"
        "lw %0, 0(%1)"
        : "=&r"(r) : "r"(&dtcm[1]), "r"(SEG_REG)
        : "t0", "memory");
    CHECK_EQ("mmio_store_before_dtcm_load", r, 0x55667788u);

    asm volatile(
        "li t0, 0x2468a\nsw t0, 0(%1)\n"
        "li t1, 0x369cf\nsw t1, 0(%2)\n"
        "lw %0, 0(%2)"
        : "=&r"(r) : "r"(&dtcm[2]), "r"(SEG_REG)
        : "t0", "t1", "memory");
    CHECK_EQ("dtcm_store_before_mmio_store", dtcm[2], 0x2468au);
    CHECK_EQ("mmio_store_readback", r, 0x369cfu);

    asm volatile(
        "lw t0, 0(%2)\n"
        "li t1, 0x10203\nsw t1, 0(%2)\nlw %0, 0(%2)"
        : "=&r"(r) : "r"(&dtcm[0]), "r"(SEG_REG)
        : "t0", "t1", "memory");
    CHECK_EQ("mmio_load_then_mmio_store", r, 0x10203u);

    dtcm[3] = 0xabcdef01u;
    asm volatile("lw t0, 0(%2)\nlw %0, 0(%1)"
                 : "=&r"(r) : "r"(&dtcm[3]), "r"(SEG_REG)
                 : "t0", "memory");
    CHECK_EQ("mmio_load_then_dtcm_load", r, 0xabcdef01u);

    asm volatile(
        "li t0, 0x30405\nsw t0, 0(%1)\n"
        "li t1, 0x60708\nsw t1, 0(%0)"
        :: "r"(&dtcm[3]), "r"(SEG_REG)
        : "t0", "t1", "memory");
    CHECK_EQ("mmio_store_then_dtcm_store", dtcm[3], 0x60708u);

    for (uint32_t i = 0; i < 32; i++) {
        uint32_t value = 0x50000000u ^ (i * 0x10201u);
        uint32_t dtcm_read;
        uint32_t mmio_read;
        asm volatile(
            "sw %4, 0(%2)\nsw %4, 0(%3)\n"
            "lw %0, 0(%3)\nlw %1, 0(%2)"
            : "=&r"(mmio_read), "=&r"(dtcm_read)
            : "r"(&dtcm[i & 3u]), "r"(SEG_REG), "r"(value)
            : "memory");
        CHECK_EQ("dtcm_mmio_switch_dtcm", dtcm_read, value);
        CHECK_EQ("dtcm_mmio_switch_mmio", mmio_read, value);
    }
    boundary_finish();
}
