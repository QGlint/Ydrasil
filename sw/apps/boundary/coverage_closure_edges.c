#define BOUNDARY_NAME "coverage_closure_edges"
#include "boundary.h"

#define SEG_ADDR 0x80200020u

static volatile uint32_t queue_sink[4];

static void check_mmio_subword_lanes(void)
{
    volatile uint32_t *seg = (volatile uint32_t *)SEG_ADDR;
    int32_t signed_value;
    uint32_t unsigned_value;

    *seg = 0x80ff7f01u;

    asm volatile("lb %0, 0(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lb_lane0", signed_value, 0x00000001u);
    asm volatile("lb %0, 1(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lb_lane1_decode", signed_value, 0u);
    asm volatile("lb %0, 2(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lb_lane2_decode", signed_value, 0u);
    asm volatile("lb %0, 3(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lb_lane3_decode", signed_value, 0u);

    asm volatile("lbu %0, 0(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lbu_lane0", unsigned_value, 0x01u);
    asm volatile("lbu %0, 1(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lbu_lane1_decode", unsigned_value, 0u);
    asm volatile("lbu %0, 2(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lbu_lane2_decode", unsigned_value, 0u);
    asm volatile("lbu %0, 3(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lbu_lane3_decode", unsigned_value, 0u);

    asm volatile("lh %0, 0(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lh_low", signed_value, 0x00007f01u);
    asm volatile("lh %0, 2(%1)" : "=r"(signed_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lh_high_decode", signed_value, 0u);
    asm volatile("lhu %0, 0(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lhu_low", unsigned_value, 0x7f01u);
    asm volatile("lhu %0, 2(%1)" : "=r"(unsigned_value) : "r"(seg) : "memory");
    CHECK_EQ("mmio_lhu_high_decode", unsigned_value, 0u);
}

static void check_instret_writes(void)
{
    uint32_t inhibit;
    uint32_t lo;
    uint32_t hi;

    asm volatile(
        "csrsi mcountinhibit, 4\n"
        "csrr %0, mcountinhibit\n"
        "li t0, 0x89abcdef\n"
        "csrw minstret, t0\n"
        "li t1, 0x12345678\n"
        "csrw minstreth, t1\n"
        "csrr %1, minstret\n"
        "csrr %2, minstreth"
        : "=&r"(inhibit), "=&r"(lo), "=&r"(hi)
        :
        : "t0", "t1", "memory");

    CHECK_EQ("mcountinhibit_ir_set", inhibit & 4u, 4u);
    CHECK_EQ("minstret_write", lo, 0x89abcdefu);
    CHECK_EQ("minstreth_write", hi, 0x12345678u);
    asm volatile(
        "csrw minstreth, zero\n"
        "csrw minstret, zero\n"
        "csrci mcountinhibit, 4"
        ::: "memory");
}

static void check_deep_store_queue(void)
{
    for (uint32_t round = 0; round < 256; round++) {
        uint32_t a = round + 17u;
        uint32_t b = (round & 31u) + 3u;
        uint32_t expected = a * b;

        queue_sink[0] = queue_sink[1] = queue_sink[2] = queue_sink[3] = 0;
        asm volatile(
            "mul a1, %1, %2\n"
            "sw a1, 0(%0)\n"
            "sw a1, 4(%0)\n"
            "sw a1, 8(%0)\n"
            "sw a1, 12(%0)"
            :
            : "r"(&queue_sink[0]), "r"(a), "r"(b)
            : "a1", "memory");

        CHECK_EQ("deep_store_0", queue_sink[0], expected);
        CHECK_EQ("deep_store_1", queue_sink[1], expected);
        CHECK_EQ("deep_store_2", queue_sink[2], expected);
        CHECK_EQ("deep_store_3", queue_sink[3], expected);
    }
}

int main(void)
{
    check_mmio_subword_lanes();
    check_instret_writes();
    check_deep_store_queue();
    boundary_finish();
}
