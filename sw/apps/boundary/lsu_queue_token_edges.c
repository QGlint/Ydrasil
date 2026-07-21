#define BOUNDARY_NAME "lsu_queue_token_edges"
#include "boundary.h"

static volatile uint32_t source[4] = {11, 22, 33, 44};
static volatile uint32_t sink[4];
static volatile uint32_t ordered;

int main(void)
{
    for (uint32_t round = 0; round < 128; round++) {
        uint32_t csr_value = 0x10000000u ^ round;
        uint32_t mul_a = round + 3;
        uint32_t mul_b = round + 5;
        for (uint32_t i = 0; i < 4; i++) sink[i] = 0;

        asm volatile(
            "csrw mscratch, %4\n"
            "csrr a1, mscratch\n"
            "sw a1, 0(%0)\n"       /* head: waits for CSR */
            "lw a2, 0(%1)\n"       /* entry 1: load */
            "li a3, 0x334\n"
            "sw a3, 4(%0)\n"       /* entry 2: ready store */
            "mul a4, %2, %3\n"
            "sw a4, 8(%0)\n"       /* entry 3: waits for MUL */
            "sw a2, 12(%0)"        /* enqueue/dequeue overlap */
            :: "r"(&sink[0]), "r"(&source[round & 3]),
               "r"(mul_a), "r"(mul_b), "r"(csr_value)
            : "a1", "a2", "a3", "a4", "memory");

        CHECK_EQ("queue_head_csr", sink[0], csr_value);
        CHECK_EQ("queue_ready_store", sink[1], 0x334u);
        CHECK_EQ("queue_tail_mul", sink[2], mul_a * mul_b);
        CHECK_EQ("queue_load_store", sink[3], source[round & 3]);

        /* A waiting oldest store must not be bypassed by ready stores. */
        ordered = 0;
        asm volatile(
            "mul a1, %1, %2\n"
            "sw a1, 0(%0)\n"
            "li a2, 0x22\nsw a2, 0(%0)\n"
            "li a3, 0x33\nsw a3, 0(%0)\n"
            "li a4, 0x44\nsw a4, 0(%0)"
            :: "r"(&ordered), "r"(round + 7u), "r"(round + 11u)
            : "a1", "a2", "a3", "a4", "memory");
        CHECK_EQ("oldest_store_order", ordered, 0x44u);

        /* More than a queue depth forces head and tail through 3 -> 0. */
        for (uint32_t turn = 0; turn < 9; turn++) {
            uint32_t value = (round << 8) | turn;
            asm volatile("sw %1, 0(%0)\nlw t0, 0(%0)"
                         : : "r"(&sink[turn & 3u]), "r"(value)
                         : "t0", "memory");
            CHECK_EQ("queue_pointer_wrap", sink[turn & 3u], value);
        }
    }
    boundary_finish();
}
