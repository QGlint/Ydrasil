#define BOUNDARY_NAME "muldiv_edges"
#include "boundary.h"

int main(void)
{
    uint32_t r;
    uint32_t zero = 0;
    uint32_t min = 0x80000000u;
    uint32_t neg_one = 0xffffffffu;

    asm volatile("div %0, %1, %2" : "=r"(r) : "r"(0x12345678u), "r"(zero));
    CHECK_EQ("div_zero", r, 0xffffffffu);
    asm volatile("rem %0, %1, %2" : "=r"(r) : "r"(0x12345678u), "r"(zero));
    CHECK_EQ("rem_zero", r, 0x12345678u);
    asm volatile("div %0, %1, %2" : "=r"(r) : "r"(min), "r"(neg_one));
    CHECK_EQ("div_overflow", r, min);
    asm volatile("rem %0, %1, %2" : "=r"(r) : "r"(min), "r"(neg_one));
    CHECK_EQ("rem_overflow", r, 0);
    asm volatile("mulh %0, %1, %2" : "=r"(r) : "r"(min), "r"(2u));
    CHECK_EQ("mulh_signed", r, 0xffffffffu);
    asm volatile("mulhu %0, %1, %2" : "=r"(r) : "r"(min), "r"(2u));
    CHECK_EQ("mulhu", r, 1u);
    boundary_finish();
}
