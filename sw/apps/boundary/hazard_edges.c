#define BOUNDARY_NAME "hazard_edges"
#include "boundary.h"

static volatile uint32_t source = 0x12345678u;
static volatile uint32_t destination;
static volatile uintptr_t destination_address = (uintptr_t)&destination;
static volatile uint32_t wrong_path;

int main(void)
{
    uint32_t r;


    asm volatile(
        "li t0, 7\n"
        "addi t1, t0, 5\n"
        "sub %0, t1, t0"
        : "=r"(r) :: "t0", "t1");
    CHECK_EQ("alu_raw_rs1_rs2", r, 5);

    asm volatile(
        "lw t0, 0(%1)\n"
        "add %0, t0, t0"
        : "=r"(r) : "r"(&source) : "t0", "memory");
    CHECK_EQ("load_to_alu_both_sources", r, 0x2468acf0u);

    asm volatile(
        "lw t0, 0(%1)\n"
        "beq t0, %2, 1f\n"
        "li %0, 0\n"
        "j 2f\n"
        "1: li %0, 1\n"
        "2:"
        : "=&r"(r) : "r"(&source), "r"(0x12345678u) : "t0", "memory");
    CHECK_EQ("load_to_branch", r, 1);

    destination = 0;
    asm volatile(
        "lw t0, 0(%0)\n"
        "sw t0, 0(%1)"
        :: "r"(&source), "r"(&destination) : "t0", "memory");
    CHECK_EQ("load_to_store_data", destination, source);

    destination = 0;
    asm volatile(
        "lw t0, 0(%0)\n"
        "li t1, 0x55aa33cc\n"
        "sw t1, 0(t0)"
        :: "r"(&destination_address) : "t0", "t1", "memory");
    CHECK_EQ("load_to_store_address", destination, 0x55aa33ccu);

    asm volatile(
        "li t0, 6\n"
        "mul t0, t0, t0\n"
        "addi %0, t0, 1"
        : "=r"(r) :: "t0");
    CHECK_EQ("mul_to_alu", r, 37);

    asm volatile(
        "li t0, 100\n"
        "li t1, 7\n"
        "div t0, t0, t1\n"
        "add %0, t0, t1"
        : "=r"(r) :: "t0", "t1");
    CHECK_EQ("div_to_alu", r, 21);

    asm volatile(
        "li t0, 100\n"
        "li t1, 7\n"
        "div t0, t0, t1\n"
        "addi t0, zero, 9\n"
        "mv %0, t0"
        : "=r"(r) :: "t0", "t1");
    CHECK_EQ("div_waw", r, 9);

    wrong_path = 0;
    asm volatile(
        "li t0, 5\n"
        "beq t0, t0, 1f\n"
        "addi t0, zero, 99\n"
        "sw t0, 0(%1)\n"
        "1: mv %0, t0"
        : "=r"(r) : "r"(&wrong_path) : "t0", "memory");
    CHECK_EQ("flush_register_write", r, 5);
    CHECK_EQ("flush_store", wrong_path, 0);

    asm volatile(
        "la t0, 1f\n"
        "addi t0, t0, 1\n"
        "jalr zero, 0(t0)\n"
        "li %0, 0\n"
        ".align 2\n"
        "1: li %0, 1"
        : "=&r"(r) :: "t0");
    CHECK_EQ("alu_to_jalr_and_bit0_clear", r, 1);

    asm volatile(
        "li t0, 1\n"
        "beq t0, t0, 1f\n"
        "li %0, 0\n"
        "1: bne t0, zero, 2f\n"
        "li %0, 0\n"
        "2: li %0, 1"
        : "=&r"(r) :: "t0");
    CHECK_EQ("back_to_back_taken_branches", r, 1);

    boundary_finish();
}
