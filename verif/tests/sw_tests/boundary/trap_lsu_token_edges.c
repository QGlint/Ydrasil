#define BOUNDARY_NAME "trap_lsu_token_edges"
#include "boundary.h"

static volatile uint32_t trap_count;
static volatile uint32_t older_store;
static volatile uint32_t wrong_path_store;
static volatile uint32_t post_trap_store;

__attribute__((naked)) static void handler(void)
{
    asm volatile(
        "la t0, trap_count\nlw t1, 0(t0)\naddi t1, t1, 1\nsw t1, 0(t0)\n"
        "csrr t0, mepc\naddi t0, t0, 4\ncsrw mepc, t0\nmret\n");
}

static void verify_post_trap_token(uint32_t value)
{
    uint32_t observed;
    asm volatile(
        "addi t0, %2, 1\nsw t0, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(observed) : "r"(&post_trap_store), "r"(value)
        : "t0", "memory");
    CHECK_EQ("post_trap_new_token", observed, value + 1);
}

int main(void)
{
    uint32_t target = (uint32_t)(uintptr_t)handler;
    asm volatile("csrw mtvec, %0" :: "r"(target));

    older_store = 0;
    asm volatile(
        "csrw mscratch, %1\ncsrr t0, mscratch\n"
        "sw t0, 0(%0)\necall"
        :: "r"(&older_store), "r"(0x12345678u)
        : "t0", "t1", "memory");
    CHECK_EQ("older_store_survives_trap", older_store, 0x12345678u);
    CHECK_EQ("first_trap", trap_count, 1);
    verify_post_trap_token(0x100u);

    wrong_path_store = 0;
    asm volatile(
        "li t0, 1\nbeq t0, t0, 1f\n"
        "csrr t1, mscratch\nsw t1, 0(%0)\n"
        "1: ecall"
        :: "r"(&wrong_path_store) : "t0", "t1", "memory");
    CHECK_EQ("younger_wrong_path_store_killed", wrong_path_store, 0);
    CHECK_EQ("second_trap", trap_count, 2);
    verify_post_trap_token(0x200u);

    older_store = 0;
    asm volatile(
        "li t0, 1000\nli t1, 7\ndiv t2, t0, t1\n"
        "sw t2, 0(%0)\necall"
        :: "r"(&older_store) : "t0", "t1", "t2", "memory");
    CHECK_EQ("div_store_survives_trap", older_store, 142u);
    CHECK_EQ("third_trap", trap_count, 3);
    verify_post_trap_token(0x300u);

    boundary_finish();
}
