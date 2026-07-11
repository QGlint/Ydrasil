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
    boundary_finish();
}
