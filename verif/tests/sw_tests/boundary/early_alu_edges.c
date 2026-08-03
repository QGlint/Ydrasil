#define BOUNDARY_NAME "early_alu_edges"
#include "boundary.h"

static volatile uint32_t source[4] = {
    0x12345678u, 0x89abcdefu, 0x0f1e2d3cu, 0xcafebabeu
};
static volatile uint32_t sink[4];

int main(void)
{
    uint32_t r;

    asm volatile(
        "li t0, 0x7fffffff\naddi t1, t0, 1\n"
        "slt t2, t1, t0\nsltu t3, t1, t0\nsub %0, t2, t3"
        : "=&r"(r) : : "t0", "t1", "t2", "t3");
    CHECK_EQ("early_arith_signed_unsigned", r, 1u);

    asm volatile(
        "li t0, 0x5a5aa5a5\nli t4, 0x0f0ff0f0\n"
        "xor t1, t0, t4\nand t2, t1, t0\nor %0, t2, t4"
        : "=&r"(r) : : "t0", "t1", "t2", "t4");
    CHECK_EQ("early_logic_chain", r,
             ((0x5a5aa5a5u ^ 0x0f0ff0f0u) & 0x5a5aa5a5u) |
             0x0f0ff0f0u);

    asm volatile(
        "li t0, 0x80018100\nsrli t1, t0, 1\n"
        "srli t2, t1, 8\nsrli %0, t2, 16"
        : "=&r"(r) : : "t0", "t1", "t2");
    CHECK_EQ("early_srli_1_8_16", r, 0x80018100u >> 25);

    asm volatile(
        "li t0, 0xf1234567\nsrli t1, t0, 0\nsrli t2, t0, 1\n"
        "srli t3, t0, 2\nxor t4, t1, t2\nxor %0, t4, t3"
        : "=&r"(r) : : "t0", "t1", "t2", "t3", "t4");
    CHECK_EQ("srli_early_boundary_0_1_2", r,
             0xf1234567u ^ (0xf1234567u >> 1) ^ (0xf1234567u >> 2));

    asm volatile(
        "li t0, 0xf1234567\nsrli t1, t0, 7\nsrli t2, t0, 8\n"
        "srli t3, t0, 9\nxor t4, t1, t2\nxor %0, t4, t3"
        : "=&r"(r) : : "t0", "t1", "t2", "t3", "t4");
    CHECK_EQ("srli_early_boundary_7_8_9", r,
             (0xf1234567u >> 7) ^ (0xf1234567u >> 8) ^
             (0xf1234567u >> 9));

    asm volatile(
        "li t0, 0xf1234567\nsrli t1, t0, 15\nsrli t2, t0, 16\n"
        "srli t3, t0, 17\nxor t4, t1, t2\nxor %0, t4, t3"
        : "=&r"(r) : : "t0", "t1", "t2", "t3", "t4");
    CHECK_EQ("srli_early_boundary_15_16_17", r,
             (0xf1234567u >> 15) ^ (0xf1234567u >> 16) ^
             (0xf1234567u >> 17));

    /* These shifts are intentionally outside the early subset. */
    asm volatile(
        "li t0, 0x8000000c\nsrli t1, t0, 2\naddi t2, t1, 3\n"
        "srai t3, t0, 31\nslli t4, t3, 7\nxor %0, t2, t4"
        : "=&r"(r) : : "t0", "t1", "t2", "t3", "t4");
    CHECK_EQ("non_early_shift_no_stale_forward", r,
             ((0x8000000cu >> 2) + 3u) ^ 0xffffff80u);

    asm volatile("lui t0, 0x12345\naddi %0, t0, 0x678"
                 : "=&r"(r) : : "t0");
    CHECK_EQ("early_lui_to_addi", r, 0x12345678u);

    asm volatile(
        "auipc t0, 0\naddi t0, t0, 12\nauipc t1, 0\nsub %0, t0, t1"
        : "=&r"(r) : : "t0", "t1");
    CHECK_EQ("early_auipc_chain", r, 4u);

    asm volatile("addi t0, %1, 4\nlw %0, 0(t0)"
                 : "=&r"(r) : "r"(&source[0]) : "t0", "memory");
    CHECK_EQ("early_to_load_address", r, source[1]);

    asm volatile("addi t0, %1, 7\nsw t0, 0(%0)"
                 : : "r"(&sink[0]), "r"(0x10203040u)
                 : "t0", "memory");
    CHECK_EQ("early_to_store_data", sink[0], 0x10203047u);

    asm volatile(
        "addi t0, %0, 8\nli t1, 0x55667788\nsw t1, 0(t0)"
        : : "r"(&sink[0]) : "t0", "t1", "memory");
    CHECK_EQ("early_to_store_address", sink[2], 0x55667788u);

    asm volatile("addi t0, %1, 9\nadd %0, t0, t0"
                 : "=&r"(r) : "r"(0x100u) : "t0");
    CHECK_EQ("early_to_both_sources", r, 0x212u);

    /* These consumers are outside the early-forward whitelist. */
    asm volatile(
        "addi t0, %2, 7\nbeq t0, %3, 1f\nli %0, 0\nj 2f\n"
        "1: li %0, 1\n2:"
        : "=&r"(r) : "0"(0u), "r"(0x120u), "r"(0x127u) : "t0");
    CHECK_EQ("early_to_branch_waits", r, 1u);

    asm volatile("addi t0, %1, 3\nmul %0, t0, t0"
                 : "=&r"(r) : "r"(9u) : "t0");
    CHECK_EQ("early_to_mul_waits", r, 144u);

    asm volatile(
        "addi t0, %1, 5\ncsrw mscratch, t0\ncsrr %0, mscratch"
        : "=&r"(r) : "r"(0x13570000u) : "t0", "memory");
    CHECK_EQ("early_to_csr_waits", r, 0x13570005u);

    r = 0;
    asm volatile(
        "la t0, 2f\naddi t0, t0, 1\njalr zero, 0(t0)\n"
        "li %0, 0\nj 3f\n2: li %0, 1\n3:"
        : "+r"(r) : : "t0");
    CHECK_EQ("early_to_jalr_waits", r, 1u);

    asm volatile(
        "lw t0, 0(%1)\naddi t1, t0, 0x21\nxor %0, t1, t0"
        : "=&r"(r) : "r"(&source[2]) : "t0", "t1", "memory");
    CHECK_EQ("load_completion_to_early_chain", r,
             (source[2] + 0x21u) ^ source[2]);

    asm volatile(
        "li t0, 17\nli t1, 19\nmul t2, t0, t1\n"
        "addi t3, t2, 7\nsw t3, 0(%0)"
        : : "r"(&sink[1]) : "t0", "t1", "t2", "t3", "memory");
    CHECK_EQ("mul_completion_to_early_store", sink[1], 330u);

    asm volatile(
        "li t0, 1001\nli t1, 7\ndiv t2, t0, t1\n"
        "addi t3, t2, 5\nadd %0, t3, t3"
        : "=&r"(r) : : "t0", "t1", "t2", "t3");
    CHECK_EQ("div_completion_to_early_both", r, 296u);

    asm volatile(
        "csrw mscratch, %1\ncsrr t0, mscratch\n"
        "xori t1, t0, 0x55\nsw t1, 0(%0)"
        : : "r"(&sink[3]), "r"(0x2468ace0u)
        : "t0", "t1", "memory");
    CHECK_EQ("csr_completion_to_early_store", sink[3], 0x2468acb5u);

    asm volatile(
        "li t4, 0x11110000\naddi t0, t4, 1\n"
        "xori t0, t4, 0x22\nsrli t0, t0, 8\naddi t0, t0, 5\n"
        "sw t0, 0(%0)"
        : : "r"(&sink[0]) : "t0", "t4", "memory");
    CHECK_EQ("early_same_rd_youngest", sink[0],
             ((0x11110000u ^ 0x22u) >> 8) + 5u);

    asm volatile(
        "li t0, 7\nbeq t0, t0, 1f\naddi t0, t0, 99\n"
        "1: addi %0, t0, 1"
        : "=&r"(r) : : "t0");
    CHECK_EQ("flush_clears_wrong_path_early", r, 8u);

    asm volatile("addi x0, %0, 9\naddi %0, x0, 3" : "+r"(r));
    CHECK_EQ("early_never_tracks_x0", r, 3u);

    for (uint32_t round = 0; round < 128; round++) {
        uint32_t a = 0x01020304u ^ (round * 0x10201u);
        uint32_t b = (round << 3) | 1u;
        uint32_t expected = ((((a + b) ^ a) >> 8) & 0x00ffffffu) + 3u;
        asm volatile(
            "add t0, %1, %2\nxor t1, t0, %1\n"
            "srli t2, t1, 8\nand t3, t2, %3\naddi %0, t3, 3"
            : "=&r"(r)
            : "r"(a), "r"(b), "r"(0x00ffffffu)
            : "t0", "t1", "t2", "t3");
        CHECK_EQ("changing_early_chain", r, expected);
    }

    boundary_finish();
}
