#define BOUNDARY_NAME "producer_token_edges"
#include "boundary.h"

static volatile uint32_t stored_value;

static uint32_t csr_store_short(uint32_t poison)
{
    uint32_t result;
    asm volatile(
        "csrw mscratch, %2\n"
        "csrr t0, mscratch\n"
        "csrw mscratch, zero\n"
        "csrr a5, mscratch\n"
        "sw a5, 0(%1)\n"
        "lw %0, 0(%1)"
        : "=&r"(result)
        : "r"(&stored_value), "r"(poison)
        : "t0", "a5", "memory");
    return result;
}

static uint32_t csr_store_after_token_churn(uint32_t poison)
{
    uint32_t result;
    asm volatile(
        "csrw mscratch, %2\n"
        "csrr t0, mscratch\n"
        /* More independent destinations than the four producer slots. */
        "addi a1, %2, 1\n"
        "xori a2, %2, 0x55\n"
        "ori  a3, %2, 0x100\n"
        "andi a4, %2, 0x7ff\n"
        "add  a6, a1, a2\n"
        "xor  t1, a3, a4\n"
        "csrw mscratch, zero\n"
        "csrr a5, mscratch\n"
        "sw a5, 0(%1)\n"
        "lw %0, 0(%1)"
        : "=&r"(result)
        : "r"(&stored_value), "r"(poison)
        : "t0", "t1", "a1", "a2", "a3", "a4", "a5", "a6", "memory");
    return result;
}

static uint32_t csr_store_with_lsu_pressure(uint32_t poison, uint32_t *scratch)
{
    uint32_t result;
    asm volatile(
        "csrw mscratch, %3\n"
        "csrr t0, mscratch\n"
        "lw a1, 0(%2)\n"
        "lw a2, 4(%2)\n"
        "sw a1, 8(%2)\n"
        "sw a2, 12(%2)\n"
        "csrw mscratch, zero\n"
        "csrr a5, mscratch\n"
        "sw a5, 0(%1)\n"
        "lw %0, 0(%1)"
        : "=&r"(result)
        : "r"(&stored_value), "r"(scratch), "r"(poison)
        : "t0", "a1", "a2", "a5", "memory");
    return result;
}

int main(void)
{
    static uint32_t scratch[4] = {
        0x11111111u, 0x22222222u, 0, 0
    };
    static const uint32_t poison_values[] = {
        6u, 1u, 0xffffffffu, 0x80000000u,
        0x7fffffffu, 0xaaaaaaaau, 0x55555555u, 0x12345678u
    };

    for (uint32_t round = 0; round < 128; round++) {
        uint32_t poison = poison_values[round & 7u] ^ (round << 16);
        stored_value = 0xdeadbeefu;
        CHECK_EQ("csr_store_short", csr_store_short(poison), 0);
        stored_value = 0xdeadbeefu;
        CHECK_EQ("csr_store_token_churn",
                 csr_store_after_token_churn(poison), 0);
        stored_value = 0xdeadbeefu;
        CHECK_EQ("csr_store_lsu_pressure",
                 csr_store_with_lsu_pressure(poison, scratch), 0);
    }

    boundary_finish();
}
