#define BOUNDARY_NAME "trap_pipeline_edges"
#include "boundary.h"

#define MAX_TRAPS 8u

static volatile uint32_t trap_count;
static volatile uint32_t trap_epc[MAX_TRAPS];
static volatile uint32_t trap_cause[MAX_TRAPS];
static volatile uint32_t return_advance = 4;
static volatile uint32_t load_value = 0x12345678u;

__attribute__((naked)) static void pipeline_trap_handler(void)
{
    asm volatile(
        "la t0, trap_count\n"
        "lw t1, 0(t0)\n"
        "slli t2, t1, 2\n"
        "la t3, trap_epc\n"
        "add t3, t3, t2\n"
        "csrr t4, mepc\n"
        "sw t4, 0(t3)\n"
        "la t3, trap_cause\n"
        "add t3, t3, t2\n"
        "csrr t2, mcause\n"
        "sw t2, 0(t3)\n"
        "addi t1, t1, 1\n"
        "sw t1, 0(t0)\n"
        "la t0, return_advance\n"
        "lw t0, 0(t0)\n"
        "add t4, t4, t0\n"
        "csrw mepc, t4\n"
        "mret\n");
}

static void check_last_trap(const char *name, uint32_t expected_epc,
                            uint32_t expected_count)
{
    CHECK_EQ(name, trap_count, expected_count);
    CHECK_EQ("trap_mcause", trap_cause[expected_count - 1], 11);
    CHECK_EQ("trap_mepc", trap_epc[expected_count - 1], expected_epc);
}

int main(void)
{
    uint32_t expected_epc;
    uint32_t value;
    uint32_t marker;
    uint32_t handler = (uint32_t)(uintptr_t)pipeline_trap_handler;

    asm volatile("csrw mtvec, %0" :: "r"(handler));

    /* A taken branch must kill the fall-through ECALL and trap at the target. */
    asm volatile(
        "li t0, 1\n"
        "beq t0, t0, 2f\n"
        "ecall\n"
        "2: la %0, 3f\n"
        "3: ecall"
        : "=r"(expected_epc) :: "t0", "t1", "t2", "t3", "t4", "memory");
    check_last_trap("branch_ecall_count", expected_epc, 1);

    /* The load-use stall must retire before the following ECALL is accepted. */
    asm volatile(
        "lw t0, 0(%2)\n"
        "addi %1, t0, 1\n"
        "la %0, 1f\n"
        "1: ecall"
        : "=r"(expected_epc), "=r"(value)
        : "r"(&load_value)
        : "t0", "t1", "t2", "t3", "t4", "memory");
    CHECK_EQ("load_result_before_ecall", value, load_value + 1);
    check_last_trap("load_ecall_count", expected_epc, 2);

    /* A multicycle DIV result and its dependent instruction precede ECALL. */
    asm volatile(
        "li t0, 100\n"
        "li t1, 7\n"
        "div t2, t0, t1\n"
        "addi %1, t2, 1\n"
        "la %0, 1f\n"
        "1: ecall"
        : "=r"(expected_epc), "=r"(value)
        :: "t0", "t1", "t2", "t3", "t4", "memory");
    CHECK_EQ("div_result_before_ecall", value, 15);
    check_last_trap("div_ecall_count", expected_epc, 3);

    /* The instruction immediately following MRET must execute exactly once. */
    marker = 0;
    asm volatile(
        "la %0, 1f\n"
        "1: ecall\n"
        "addi %1, %1, 1"
        : "=r"(expected_epc), "+r"(marker)
        :: "t0", "t1", "t2", "t3", "t4", "memory");
    CHECK_EQ("mret_first_instruction", marker, 1);
    check_last_trap("mret_ecall_count", expected_epc, 4);

    /* The younger adjacent ECALL must be flushed when the first trap is taken. */
    return_advance = 8;
    marker = 0;
    asm volatile(
        "la %0, 1f\n"
        "1: ecall\n"
        "ecall\n"
        "addi %1, %1, 1"
        : "=r"(expected_epc), "+r"(marker)
        :: "t0", "t1", "t2", "t3", "t4", "memory");
    CHECK_EQ("younger_ecall_flushed", trap_count, 5);
    CHECK_EQ("post_flush_instruction", marker, 1);
    CHECK_EQ("younger_test_mepc", trap_epc[4], expected_epc);
    CHECK_EQ("younger_test_mcause", trap_cause[4], 11);

    boundary_finish();
}
