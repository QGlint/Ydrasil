#define BOUNDARY_NAME "pipeline_drain_edges"
#include "boundary.h"

static volatile uint32_t source[8] = {
    0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u,
    0x55555555u, 0x66666666u, 0x77777777u, 0x88888888u
};
static volatile uint32_t sink[8];

int main(void)
{
    uint32_t checksum = 0;

    for (uint32_t round = 0; round < 192; round++) {
        uint32_t dividend = 10000u + round * 37u;
        uint32_t divisor = (round & 15u) + 1u;
        uint32_t csr_value = 0x90000000u ^ (round * 0x10101u);
        uint32_t index = round & 7u;
        uint32_t got_div;
        uint32_t got_csr;
        uint32_t got_load;

        asm volatile(
            "div a1, %7, %8\n"
            "csrw mscratch, %9\ncsrr a2, mscratch\n"
            "lw a3, 0(%6)\n"
            "mul a4, %8, %8\n"
            "sw a1, 0(%3)\nsw a2, 0(%4)\nsw a4, 0(%5)\n"
            "mv %0, a1\nmv %1, a2\nmv %2, a3"
            : "=&r"(got_div), "=&r"(got_csr), "=&r"(got_load)
            : "r"(&sink[index]), "r"(&sink[(index + 1u) & 7u]),
              "r"(&sink[(index + 2u) & 7u]), "r"(&source[index]),
              "r"(dividend), "r"(divisor), "r"(csr_value)
            : "a1", "a2", "a3", "a4", "memory");

        CHECK_EQ("drain_div", got_div, dividend / divisor);
        CHECK_EQ("drain_csr", got_csr, csr_value);
        CHECK_EQ("drain_load", got_load, source[index]);
        checksum ^= got_div + got_csr + got_load;
    }

    /* Stop creating long-latency work and require forward progress to resume. */
    uint32_t expected_checksum = checksum + 1u;
    asm volatile(
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "addi %0, %0, 1"
        : "+r"(checksum) : : "memory");
    CHECK_EQ("pipeline_resumes_after_drain", checksum, expected_checksum);

    for (uint32_t i = 0; i < 8; i++) {
        sink[i] = 0xa5000000u | i;
        CHECK_EQ("post_drain_store_load", sink[i], 0xa5000000u | i);
    }

    boundary_finish();
}
