#define BOUNDARY_NAME "system_illegal_edges"
#include "boundary.h"

static volatile uint32_t trap_seen;
static volatile uint32_t trap_cause;
static volatile uint32_t trap_epc;
static volatile uint32_t trap_tval;

__attribute__((naked)) static void illegal_handler(void)
{
    asm volatile(
        "csrr t0, mcause\n"
        "la t1, trap_cause\n"
        "sw t0, 0(t1)\n"
        "csrr t0, mepc\n"
        "la t1, trap_epc\n"
        "sw t0, 0(t1)\n"
        "csrr t0, mtval\n"
        "la t1, trap_tval\n"
        "sw t0, 0(t1)\n"
        "li t0, 1\n"
        "la t1, trap_seen\n"
        "sw t0, 0(t1)\n"
        "csrr t0, mepc\n"
        "addi t0, t0, 4\n"
        "csrw mepc, t0\n"
        "mret\n");
}

int main(void)
{
    uint32_t expected_epc;
    uint32_t handler = (uint32_t)(uintptr_t)illegal_handler;

    asm volatile("csrw mtvec, %0" :: "r"(handler));
    /* WFI is permitted to complete as a no-sleep instruction in M mode. */
    asm volatile("wfi" ::: "memory");
    CHECK_EQ("wfi_does_not_trap", trap_seen, 0);

    asm volatile("la %0, 1f\n1: .word 0x7b200073" : "=r"(expected_epc) ::
        "t0", "t1", "memory");

    CHECK_EQ("illegal_seen", trap_seen, 1);
    CHECK_EQ("illegal_cause", trap_cause, 2);
    CHECK_EQ("illegal_epc", trap_epc, expected_epc);
    CHECK_EQ("illegal_tval", trap_tval, 0x7b200073u);
    boundary_finish();
}
