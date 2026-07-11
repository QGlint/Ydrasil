#define BOUNDARY_NAME "csr_counter_edges"
#include "boundary.h"

int main(void)
{
    uint32_t lo, hi, before, after;

    asm volatile("csrw mcycle, zero\ncsrw mcycleh, zero\n"
                 "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop");
    asm volatile("csrr %0, mcycle\ncsrr %1, mcycleh" : "=r"(lo), "=r"(hi));
    CHECK_EQ("mcycleh_write", hi, 0);
    CHECK_EQ("mcycle_running", lo != 0, 1);

    asm volatile("li t0, -1\ncsrw mcycle, t0\ncsrw mcycleh, zero" ::: "t0");
    for (volatile uint32_t i = 0; i < 16; i++) {
    }
    asm volatile("csrr %0, mcycleh" : "=r"(hi));
    CHECK_EQ("mcycle_carry", hi != 0, 1);

    asm volatile("csrsi mcountinhibit, 1\ncsrr %0, mcycle" : "=r"(before));
    for (volatile uint32_t i = 0; i < 64; i++) {
    }
    asm volatile("csrr %0, mcycle\ncsrci mcountinhibit, 1" : "=r"(after));
    CHECK_EQ("mcycle_inhibit", after, before);

    asm volatile("li t0, 0x13579\ncsrw mscratch, t0\ncsrr %0, mscratch"
                 : "=r"(lo) :: "t0");
    CHECK_EQ("mscratch", lo, 0x13579u);
    asm volatile("li t0, 0x55\ncsrw mie, t0\ncsrr %0, mie" : "=r"(lo) :: "t0");
    CHECK_EQ("mie", lo, 0x55u);
    asm volatile("li t0, 0xaa\ncsrw mip, t0\ncsrr %0, mip" : "=r"(lo) :: "t0");
    CHECK_EQ("mip", lo, 0xaau);
    asm volatile("li t0, 0x2468\ncsrw mtval, t0\ncsrr %0, mtval" : "=r"(lo) :: "t0");
    CHECK_EQ("mtval", lo, 0x2468u);
    asm volatile("li t0, 7\ncsrw mcounteren, t0\ncsrr %0, mcounteren"
                 : "=r"(lo) :: "t0");
    CHECK_EQ("mcounteren", lo, 7);

    asm volatile("csrr %0, misa" : "=r"(lo));
    CHECK_EQ("misa_rv32", lo >> 30, 1);
    asm volatile("csrr %0, mvendorid\ncsrr %1, mhartid" : "=r"(lo), "=r"(hi));
    CHECK_EQ("mvendorid", lo, 0);
    CHECK_EQ("mhartid", hi, 0);
    boundary_finish();
}
