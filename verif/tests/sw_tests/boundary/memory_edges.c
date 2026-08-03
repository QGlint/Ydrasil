#define BOUNDARY_NAME "memory_edges"
#include "boundary.h"

static volatile uint32_t word;

int main(void)
{
    uint32_t r;
    volatile uint8_t *bytes = (volatile uint8_t *)&word;
    volatile uint16_t *halves = (volatile uint16_t *)&word;


    word = 0xa5a5a5a5u;
    bytes[0] = 0x11;
    CHECK_EQ("sb_lane0", word, 0xa5a5a511u);
    bytes[3] = 0x80;
    CHECK_EQ("sb_lane3", word, 0x80a5a511u);
    halves[1] = 0x7f01;
    CHECK_EQ("sh_lane1", word, 0x7f01a511u);

    bytes[0] = 0x80;
    asm volatile("lb %0, 0(%1)" : "=r"(r) : "r"(bytes));
    CHECK_EQ("lb_sign", r, 0xffffff80u);
    asm volatile("lbu %0, 0(%1)" : "=r"(r) : "r"(bytes));
    CHECK_EQ("lbu_zero", r, 0x80u);
    halves[0] = 0x8001;
    asm volatile("lh %0, 0(%1)" : "=r"(r) : "r"(halves));
    CHECK_EQ("lh_sign", r, 0xffff8001u);
    asm volatile("lhu %0, 0(%1)" : "=r"(r) : "r"(halves));
    CHECK_EQ("lhu_zero", r, 0x8001u);

    word = 0x12345678u;
    asm volatile("lw %0, 0(%1)\naddi %0, %0, 1"
                 : "=&r"(r) : "r"(&word) : "memory");
    CHECK_EQ("load_use", r, 0x12345679u);

    /* Same-address stores exercise byte enables and ordering before load-back. */
    word = 0;
    asm volatile(
        "li t0, 0x89\nsb t0, 0(%1)\n"
        "li t0, 0x7654\nsh t0, 2(%1)\n"
        "lw %0, 0(%1)"
        : "=&r"(r) : "r"(&word) : "t0", "memory");
    CHECK_EQ("mixed_store_size_load", r, 0x76540089u);

    /* The load is admitted behind a store whose data is still a producer. */
    asm volatile(
        "li t0, 0x1234\nli t1, 9\nmul t2, t0, t1\n"
        "sw t2, 0(%1)\nlw %0, 0(%1)"
        : "=&r"(r) : "r"(&word) : "t0", "t1", "t2", "memory");
    CHECK_EQ("load_behind_pending_store", r, 0xa3d4u);

    asm volatile("sw %1, 0(%2)\nnop\nnop\nlw %0, 0(%2)"
                 : "=&r"(r) : "r"(0xcafebabeu), "r"(&word) : "memory");
    CHECK_EQ("load_after_completed_store", r, 0xcafebabeu);
    boundary_finish();
}
