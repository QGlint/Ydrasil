#define BOUNDARY_NAME "completion_concurrency_edges"
#include "boundary.h"

static volatile uint32_t source[8] = {
    3, 5, 7, 11, 13, 17, 19, 23
};
static volatile uint32_t sink[4];

#define RUN_ALU_LSU_THEN_MUL(PADDING) asm volatile(                         \
    "lw a1, 0(%3)\naddi a2, %4, 0x31\n" PADDING                         \
    "mul a3, %4, %5\n"                                                     \
    "sw a1, 0(%0)\nsw a2, 0(%1)\nsw a3, 0(%2)"                          \
    :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),                    \
       "r"(&source[round & 7u]), "r"(a), "r"(b)                        \
    : "a1", "a2", "a3", "memory")

#define RUN_MUL_THEN_ALU_LSU(PADDING) asm volatile(                         \
    "mul a3, %4, %5\n" PADDING                                             \
    "lw a1, 0(%3)\naddi a2, %4, 0x31\n"                                  \
    "sw a3, 0(%2)\nsw a1, 0(%0)\nsw a2, 0(%1)"                          \
    :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),                    \
       "r"(&source[round & 7u]), "r"(a), "r"(b)                        \
    : "a1", "a2", "a3", "memory")

static void run_consecutive_arbitration(uint32_t round)
{
    uint32_t a = round + 17u;
    uint32_t b = (round & 15u) + 3u;

    /* Alternate the order of a load/ALU burst and a multiply completion. */
    switch (round & 7u) {
    case 0: RUN_MUL_THEN_ALU_LSU(""); break;
    case 1: RUN_MUL_THEN_ALU_LSU("nop\n"); break;
    case 2: RUN_MUL_THEN_ALU_LSU("nop\nnop\n"); break;
    case 3: RUN_MUL_THEN_ALU_LSU("nop\nnop\nnop\n"); break;
    case 4: RUN_ALU_LSU_THEN_MUL(""); break;
    case 5: RUN_ALU_LSU_THEN_MUL("nop\n"); break;
    case 6: RUN_ALU_LSU_THEN_MUL("nop\nnop\n"); break;
    default: RUN_ALU_LSU_THEN_MUL("nop\nnop\nnop\n"); break;
    }
    CHECK_EQ("consecutive_load", sink[0], source[round & 7u]);
    CHECK_EQ("consecutive_alu", sink[1], a + 0x31u);
    CHECK_EQ("consecutive_mul", sink[2], a * b);
}

#define RUN_MIXED_SEQUENCE(PADDING) do {                                      \
    uint32_t index = round & 7u;                                              \
    uint32_t mul_a = round + 9u;                                              \
    uint32_t mul_b = round + 13u;                                             \
    asm volatile(                                                            \
        "mul a1, %4, %5\n"                                                   \
        "lw a2, 0(%3)\n"                                                     \
        PADDING                                                               \
        "addi a3, %4, 0x77\n"                                                \
        "sw a1, 0(%0)\nsw a2, 0(%1)\nsw a3, 0(%2)"                         \
        :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),                    \
           "r"(&source[index]), "r"(mul_a), "r"(mul_b)                     \
        : "a1", "a2", "a3", "memory");                                   \
    CHECK_EQ("concurrent_mul", sink[0], mul_a * mul_b);                       \
    CHECK_EQ("concurrent_load", sink[1], source[index]);                      \
    CHECK_EQ("concurrent_alu", sink[2], mul_a + 0x77u);                       \
} while (0)

int main(void)
{
    for (uint32_t round = 0; round < 256; round++) {
        sink[0] = sink[1] = sink[2] = 0;
        switch (round & 3u) {
        case 0: RUN_MIXED_SEQUENCE(""); break;
        case 1: RUN_MIXED_SEQUENCE("nop\n"); break;
        case 2: RUN_MIXED_SEQUENCE("nop\nnop\n"); break;
        default: RUN_MIXED_SEQUENCE("nop\nnop\nnop\n"); break;
        }

        /* Keep allocating while prior completions retire and slots wrap. */
        asm volatile(
            "lw a1, 0(%3)\n"
            "addi a2, %4, 1\n"
            "mul a3, %4, %5\n"
            "addi a4, %5, 2\n"
            "sw a1, 0(%0)\nsw a3, 0(%1)\nsw a4, 0(%2)"
            :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),
               "r"(&source[round & 7u]), "r"(round + 1u), "r"(round + 3u)
            : "a1", "a2", "a3", "a4", "memory");
        CHECK_EQ("wrap_load", sink[0], source[round & 7u]);
        CHECK_EQ("wrap_mul", sink[1], (round + 1u) * (round + 3u));
        CHECK_EQ("wrap_alu", sink[2], round + 5u);

        run_consecutive_arbitration(round);

        /* The DIV completes late while independent older results retire. */
        asm volatile(
            "lw a1, 0(%3)\n"
            "div a2, %4, %5\n"
            "addi a3, %4, 9\n"
            "sw a1, 0(%0)\nsw a2, 0(%1)\nsw a3, 0(%2)"
            :: "r"(&sink[0]), "r"(&sink[1]), "r"(&sink[2]),
               "r"(&source[(round + 3u) & 7u]), "r"(round + 1000u),
               "r"((round & 7u) + 1u)
            : "a1", "a2", "a3", "memory");
        CHECK_EQ("late_div_load", sink[0], source[(round + 3u) & 7u]);
        CHECK_EQ("late_div_result", sink[1],
                 (round + 1000u) / ((round & 7u) + 1u));
        CHECK_EQ("late_div_alu", sink[2], round + 1009u);
    }
    boundary_finish();
}
