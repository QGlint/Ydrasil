#define BOUNDARY_NAME "csr_trap_edges"
#include "boundary.h"

static volatile uint32_t trap_seen;
static volatile uint32_t trap_mcause;
static volatile uint32_t trap_mepc;
static volatile uint32_t trap_mstatus;
static volatile uint32_t expected_mepc;

__attribute__((naked)) static void direct_trap_handler(void)
{
    asm volatile(
        "csrr t0, mcause\n"
        "la t1, trap_mcause\n"
        "sw t0, 0(t1)\n"
        "csrr t0, mepc\n"
        "la t1, trap_mepc\n"
        "sw t0, 0(t1)\n"
        "csrr t0, mstatus\n"
        "la t1, trap_mstatus\n"
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
    uint32_t r;
    uint32_t handler = (uint32_t)(uintptr_t)direct_trap_handler;

    asm volatile("csrw mtvec, %0\ncsrr %1, mtvec" : "+r"(handler), "=r"(r));
    CHECK_EQ("mtvec_rw", r, handler);
    asm volatile("csrw mcause, zero\ncsrrsi %0, mcause, 0" : "=r"(r));
    CHECK_EQ("csrrsi_zero", r, 0);
    asm volatile("csrrwi %0, mepc, 3" : "=r"(r));
    asm volatile("csrrci %0, mepc, 1" : "=r"(r));
    CHECK_EQ("csrrci_old", r, 3);
    asm volatile("csrr %0, mepc" : "=r"(r));
    CHECK_EQ("csrrci_new", r, 2);

    r = 1u << 7;
    asm volatile("csrsi mstatus, 8\ncsrc mstatus, %0" :: "r"(r));
    asm volatile("la %0, 1f\nla t0, expected_mepc\nsw %0, 0(t0)\n1: ecall"
                 : "=r"(r) :: "t0", "t1", "memory");
    CHECK_EQ("trap_seen", trap_seen, 1);
    CHECK_EQ("mcause_ecall_m", trap_mcause, 11);
    CHECK_EQ("mepc_ecall", trap_mepc, expected_mepc);
    CHECK_EQ("trap_mie", trap_mstatus & (1u << 3), 0);
    CHECK_EQ("trap_mpie", trap_mstatus & (1u << 7), 1u << 7);
    asm volatile("csrr %0, mstatus" : "=r"(r));
    CHECK_EQ("mret_mie", r & (1u << 3), 1u << 3);
    CHECK_EQ("mret_mpie", r & (1u << 7), 1u << 7);
    boundary_finish();
}
