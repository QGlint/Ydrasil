#define BOUNDARY_NAME "hot_token_edges"
#include "boundary.h"

static volatile uint32_t data[24] __attribute__((aligned(64)));

int main(void)
{
    for (uint32_t i = 0; i < 24; i++) data[i] = 0x1000u + i;

    for (uint32_t round = 0; round < 128; round++) {
        uint32_t index = round & 7u;
        volatile uint32_t *a = &data[index];
        volatile uint32_t *alias = &data[index + 8]; /* Same hot-cache index. */
        uint32_t old;
        uint32_t expected = 0x80000000u ^ round;
        uint32_t observed;

        old = *a;                       /* Starts a fill. */
        *alias = old ^ 0x55aa55aau;     /* Invalidates the same index. */
        asm volatile(
            "csrw mscratch, %2\ncsrr t0, mscratch\n"
            "sw t0, 0(%1)\nlw %0, 0(%1)"
            : "=&r"(observed) : "r"(a), "r"(expected)
            : "t0", "memory");
        CHECK_EQ("csr_token_store", observed, expected);
        CHECK_EQ("hot_alias_store", *alias, old ^ 0x55aa55aau);
        CHECK_EQ("hot_refill_after_token_store", *a, expected);
    }
    boundary_finish();
}
