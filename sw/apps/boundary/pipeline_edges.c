#define BOUNDARY_NAME "pipeline_edges"
#include "boundary.h"

static volatile uint32_t side_effect;

int main(void)
{
    uint32_t r;
    uintptr_t odd_target;

    asm volatile(
        "li %0, 1\n"
        "beq %0, %0, 1f\n"
        "sw %0, 0(%1)\n"
        "1: addi %0, %0, 2"
        : "=&r"(r) : "r"(&side_effect) : "memory");
    CHECK_EQ("taken_branch", r, 3);
    CHECK_EQ("flushed_store", side_effect, 0);

    asm volatile(
        "la %0, 1f\n"
        "ori %0, %0, 1\n"
        "jalr zero, 0(%0)\n"
        "sw %0, 0(%1)\n"
        ".align 2\n"
        "1:"
        : "=&r"(odd_target) : "r"(&side_effect) : "memory");
    CHECK_EQ("jalr_flush", side_effect, 0);

    asm volatile(
        "li %0, 1\n"
        "addi %0, %0, 2\n"
        "add %0, %0, %0"
        : "=&r"(r));
    CHECK_EQ("raw_chain", r, 6);
    boundary_finish();
}
