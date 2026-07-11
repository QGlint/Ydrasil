#define BOUNDARY_NAME "alu_edges"
#include "boundary.h"

int main(void)
{
    uint32_t r;
    uint32_t sign = 0x80000000u;
    uint32_t minus_one = 0xffffffffu;

    asm volatile("addi %0, zero, -2048" : "=r"(r));
    CHECK_EQ("addi_min", r, 0xfffff800u);
    asm volatile("slti %0, %1, -1" : "=r"(r) : "r"(sign));
    CHECK_EQ("slti_signed", r, 1);
    asm volatile("sltiu %0, %1, -1" : "=r"(r) : "r"(sign));
    CHECK_EQ("sltiu_unsigned", r, 1);
    asm volatile("slt %0, %1, %2" : "=r"(r) : "r"(sign), "r"(minus_one));
    CHECK_EQ("slt_extremes", r, 1);
    asm volatile("sltu %0, %1, %2" : "=r"(r) : "r"(sign), "r"(minus_one));
    CHECK_EQ("sltu_extremes", r, 1);

    for (uint32_t shamt = 0; shamt <= 63; shamt += 31) {
        asm volatile("sll %0, %1, %2" : "=r"(r) : "r"(1u), "r"(shamt));
        CHECK_EQ("sll_mask", r, 1u << (shamt & 31));
        asm volatile("srl %0, %1, %2" : "=r"(r) : "r"(minus_one), "r"(shamt));
        CHECK_EQ("srl_mask", r, minus_one >> (shamt & 31));
    }

    asm volatile("add x0, %0, %1" :: "r"(minus_one), "r"(minus_one));
    asm volatile("mv %0, x0" : "=r"(r));
    CHECK_EQ("x0", r, 0);
    boundary_finish();
}
