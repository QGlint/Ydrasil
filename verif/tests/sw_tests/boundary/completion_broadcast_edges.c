#define BOUNDARY_NAME "completion_broadcast_edges"
#include "boundary.h"

static volatile uint32_t source[4] = {
    0x10203040u, 0x55667788u, 0x89abcdefu, 0x76543210u
};
static volatile uint32_t sink[8];
static volatile uintptr_t jump_target;
#define SEG_REG ((volatile uint32_t *)0x80200020u)

static void clear_sink(void)
{
    for (uint32_t i = 0; i < 8; i++) sink[i] = 0;
}

int main(void)
{
    uint32_t r;
    uint32_t marker;

    clear_sink();
    asm volatile(
        "addi t0, %1, 0x123\n"
        "sw t0, 0(%0)"
        :: "r"(&sink[0]), "r"(0x1000u) : "t0", "memory");
    CHECK_EQ("alu_broadcast_to_store_data", sink[0], 0x1123u);

    asm volatile(
        "csrw mscratch, %1\n"
        "csrr t0, mscratch\n"
        "sw t0, 0(%0)"
        :: "r"(&sink[1]), "r"(0x2468ace0u) : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_store_data", sink[1], 0x2468ace0u);

    asm volatile(
        "lw t0, 0(%1)\n"
        "sw t0, 0(%0)"
        :: "r"(&sink[2]), "r"(&source[0]) : "t0", "memory");
    CHECK_EQ("load_broadcast_to_store_data", sink[2], source[0]);

    asm volatile(
        "li t0, 0x1234\nli t1, 9\n"
        "mul t2, t0, t1\n"
        "sw t2, 0(%0)"
        :: "r"(&sink[3]) : "t0", "t1", "t2", "memory");
    CHECK_EQ("mul_broadcast_to_store_data", sink[3], 0xa3d4u);

    asm volatile(
        "li t0, 1000\nli t1, 7\n"
        "div t2, t0, t1\n"
        "sw t2, 0(%0)"
        :: "r"(&sink[4]) : "t0", "t1", "t2", "memory");
    CHECK_EQ("div_broadcast_to_store_data", sink[4], 142u);

    /* Store address is a blocking rs1 consumer and must see the new value. */
    asm volatile(
        "addi t0, %0, 20\n"
        "li t1, 0x31415\n"
        "sw t1, 0(t0)"
        :: "r"(&sink[0]) : "t0", "t1", "memory");
    CHECK_EQ("alu_broadcast_to_store_address", sink[5], 0x31415u);

    asm volatile(
        "csrw mscratch, %1\ncsrr t0, mscratch\naddi %0, t0, 7"
        : "=r"(r) : "r"(0x12340000u) : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_alu", r, 0x12340007u);

    asm volatile(
        "csrw mscratch, %0\ncsrr t0, mscratch\n"
        "li t1, 0x61626364\nsw t1, 0(t0)"
        :: "r"(&sink[7]) : "t0", "t1", "memory");
    CHECK_EQ("csr_broadcast_to_store_address", sink[7], 0x61626364u);

    asm volatile(
        "li t0, 1\nmul t1, %0, t0\n"
        "li t2, 0x71727374\nsw t2, 0(t1)"
        :: "r"(&sink[7]) : "t0", "t1", "t2", "memory");
    CHECK_EQ("mul_broadcast_to_store_address", sink[7], 0x71727374u);

    asm volatile(
        "li t0, 1\ndiv t1, %0, t0\n"
        "li t2, 0x81828384\nsw t2, 0(t1)"
        :: "r"(&sink[7]) : "t0", "t1", "t2", "memory");
    CHECK_EQ("div_broadcast_to_store_address", sink[7], 0x81828384u);

    asm volatile(
        "lw t0, 0(%1)\naddi t0, t0, 1\n"
        "beq t0, %2, 1f\nli %0, 0\nj 2f\n1: li %0, 1\n2:"
        : "=&r"(marker) : "r"(&source[1]), "r"(0x55667789u)
        : "t0", "memory");
    CHECK_EQ("load_broadcast_to_branch", marker, 1);

    asm volatile(
        "csrw mscratch, %2\ncsrr t0, mscratch\n"
        "beq t0, %2, 1f\nli %0, 0\nj 2f\n1: li %0, 1\n2:"
        : "=&r"(marker) : "0"(0u), "r"(0x13579bdfu)
        : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_branch", marker, 1);

    asm volatile(
        "li t0, 17\nli t1, 19\nmul t2, t0, t1\n"
        "li t3, 323\n"
        "beq t2, t3, 1f\nli %0, 0\nj 2f\n1: li %0, 1\n2:"
        : "=&r"(marker) :: "t0", "t1", "t2", "t3");
    CHECK_EQ("mul_broadcast_to_branch", marker, 1);

    asm volatile(
        "li t0, 323\nli t1, 17\ndiv t2, t0, t1\n"
        "li t3, 19\n"
        "beq t2, t3, 1f\nli %0, 0\nj 2f\n1: li %0, 1\n2:"
        : "=&r"(marker) :: "t0", "t1", "t2", "t3");
    CHECK_EQ("div_broadcast_to_branch", marker, 1);

    marker = 0;
    asm volatile(
        "la t1, 2f\ncsrw mscratch, t1\ncsrr t0, mscratch\n"
        "jalr zero, 0(t0)\nli %0, 0\nj 3f\n"
        "2: li %0, 1\n3:"
        : "+r"(marker) :: "t0", "t1", "memory");
    CHECK_EQ("csr_broadcast_to_jalr", marker, 1);

    marker = 0;
    asm volatile(
        "la t1, 2f\nli t2, 1\nmul t0, t1, t2\n"
        "jalr zero, 0(t0)\nli %0, 0\nj 3f\n"
        "2: li %0, 1\n3:"
        : "+r"(marker) :: "t0", "t1", "t2");
    CHECK_EQ("mul_broadcast_to_jalr", marker, 1);

    marker = 0;
    asm volatile(
        "la t1, 2f\nli t2, 1\ndiv t0, t1, t2\n"
        "jalr zero, 0(t0)\nli %0, 0\nj 3f\n"
        "2: li %0, 1\n3:"
        : "+r"(marker) :: "t0", "t1", "t2");
    CHECK_EQ("div_broadcast_to_jalr", marker, 1);

    /* A loaded target consumed by JALR exercises the delayed LSU lane. */
    marker = 0;
    asm volatile(
        "la t1, 2f\n"
        "sw t1, 0(%1)\n"
        "lw t0, 0(%1)\n"
        "jalr zero, 0(t0)\n"
        "li %0, 0\nj 3f\n"
        "2: li %0, 1\n3:"
        : "+r"(marker) : "r"(&jump_target) : "t0", "t1", "memory");
    CHECK_EQ("load_broadcast_to_jalr", marker, 1);

    asm volatile(
        "csrw mscratch, %1\ncsrr t0, mscratch\nlw %0, 0(t0)"
        : "=&r"(r) : "r"(&source[2]) : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_load_address", r, source[2]);

    asm volatile(
        "csrw mscratch, %1\ncsrr t0, mscratch\n"
        "csrw mepc, t0\ncsrr %0, mepc"
        : "=&r"(r) : "r"(0x12345678u) : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_csr", r, 0x12345678u);

    /* Keep all three completion classes in flight before consuming results. */
    clear_sink();
    asm volatile(
        "lw a1, 0(%3)\n"
        "li t0, 31\nli t1, 37\nmul a2, t0, t1\n"
        "addi a3, %4, 0x321\n"
        "sw a1, 0(%0)\n"
        "sw a2, 0(%1)\n"
        "sw a3, 0(%2)"
        :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),
           "r"(&source[2]), "r"(0x4000u)
        : "t0", "t1", "a1", "a2", "a3", "memory");
    CHECK_EQ("multi_completion_load", sink[0], source[2]);
    CHECK_EQ("multi_completion_mul", sink[1], 1147u);
    CHECK_EQ("multi_completion_alu", sink[2], 0x4321u);

    /* Repeated writes to one rd must leave the youngest producer observable. */
    asm volatile(
        "csrw mscratch, %2\ncsrr a5, mscratch\n"
        "li t0, 9\nli t1, 11\nmul a5, t0, t1\n"
        "lw a5, 0(%3)\n"
        "sw a5, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r)
        : "r"(&sink[6]), "r"(0xfeed0006u), "r"(&source[3])
        : "t0", "t1", "a5", "memory");
    CHECK_EQ("same_rd_youngest_producer", r, source[3]);

    asm volatile(
        "csrw mscratch, %2\ncsrr a5, mscratch\n"
        "add a5, %3, %4\n"
        "lw a5, 0(%5)\n"
        "mul a5, %3, %4\n"
        "sw a5, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r)
        : "r"(&sink[6]), "r"(0xfeed0006u), "r"(9u), "r"(11u),
          "r"(&source[0])
        : "a5", "memory");
    CHECK_EQ("same_rd_csr_alu_load_mul", r, 99u);

    /* Every producer class overwrites a5; the store must observe the DIV. */
    asm volatile(
        "addi a5, %2, 5\n"
        "lw a5, 0(%3)\n"
        "csrw mscratch, %4\ncsrr a5, mscratch\n"
        "mul a5, %2, %5\n"
        "div a5, %4, %5\n"
        "sw a5, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r)
        : "r"(&sink[6]), "r"(13u), "r"(&source[0]),
          "r"(1001u), "r"(7u)
        : "a5", "memory");
    CHECK_EQ("same_rd_all_producer_classes", r, 143u);

    asm volatile(
        "csrw mscratch, %2\ncsrr t0, mscratch\n"
        "sw t0, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r) : "r"(SEG_REG), "r"(0x1234abcdu)
        : "t0", "memory");
    CHECK_EQ("csr_broadcast_to_mmio_store", r, 0x1234abcdu);

    asm volatile(
        "li t0, 0x123\nli t1, 7\nmul t2, t0, t1\n"
        "sw t2, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r) : "r"(SEG_REG)
        : "t0", "t1", "t2", "memory");
    CHECK_EQ("mul_broadcast_to_mmio_store", r, 0x7f5u);

    boundary_finish();
}
