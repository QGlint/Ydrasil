#define BOUNDARY_NAME "ebreak_trap_edges"
#include "boundary.h"

static volatile uint32_t seen, cause, epc;

__attribute__((naked)) static void handler(void)
{
    asm volatile(
        "csrr t0, mcause\nla t1, cause\nsw t0, 0(t1)\n"
        "csrr t0, mepc\nla t1, epc\nsw t0, 0(t1)\n"
        "li t1, 1\nla t2, seen\nsw t1, 0(t2)\n"
        "addi t0, t0, 4\ncsrw mepc, t0\nmret\n");
}

int main(void)
{
    uint32_t expected;
    uint32_t target = (uint32_t)(uintptr_t)handler;
    asm volatile("csrw mtvec, %0" :: "r"(target));
    asm volatile("la %0, 1f\n1: ebreak" : "=r"(expected) :: "t0", "t1", "t2", "memory");
    CHECK_EQ("seen", seen, 1);
    CHECK_EQ("mcause_breakpoint", cause, 3);
    CHECK_EQ("mepc_breakpoint", epc, expected);
    boundary_finish();
}
