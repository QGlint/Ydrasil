#define BOUNDARY_NAME "writeback_pressure"
#include "boundary.h"

static volatile uint32_t data[16];

int main(void)
{
    for (uint32_t i = 0; i < 16; i++) data[i] = i + 3;
    for (uint32_t round = 0; round < BOUNDARY_STRESS_ROUNDS; round++) {
        uint32_t r0, r1, r2, r3;
        asm volatile(
            "lw %0, 0(%4)\n"
            "mul %1, %5, %6\n"
            "addi %2, %5, 17\n"
            "div %3, %6, %5\n"
            "add %0, %0, %1\n"
            "xor %2, %2, %3"
            : "=&r"(r0), "=&r"(r1), "=&r"(r2), "=&r"(r3)
            : "r"(&data[round & 15]), "r"(round + 1), "r"(round + 33)
            : "memory");
        CHECK_EQ("mixed_load_mul", r0, data[round & 15] + (round + 1) * (round + 33));
        CHECK_EQ("mixed_div_alu", r2, (round + 18) ^ ((round + 33) / (round + 1)));
    }
    boundary_finish();
}
