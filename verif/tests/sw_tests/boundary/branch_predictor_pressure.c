#define BOUNDARY_NAME "branch_predictor_pressure"
#include "boundary.h"

typedef uint32_t (*target_fn)(uint32_t);

__attribute__((noinline, aligned(64))) static uint32_t target_a(uint32_t x)
{
    return x + 0x11u;
}

__attribute__((noinline, aligned(64))) static uint32_t target_b(uint32_t x)
{
    return x ^ 0x55u;
}

__attribute__((noinline, aligned(64))) static uint32_t target_c(uint32_t x)
{
    return x - 3u;
}

int main(void)
{
    static target_fn const targets[] = {target_a, target_b, target_c, target_b};
    uint32_t actual = 0;
    uint32_t expected = 0;

    for (uint32_t i = 0; i < 512; i++) {
        uint32_t select = (i ^ (i >> 2)) & 3u;
        target_fn volatile fn = targets[select];
        actual ^= fn(i);
        if (select == 0) expected ^= i + 0x11u;
        else if (select == 2) expected ^= i - 3u;
        else expected ^= i ^ 0x55u;

        if ((i & 7u) == 0) actual ^= 0x80000000u;
        if ((i & 7u) != 0) expected ^= 0;
        else expected ^= 0x80000000u;
    }

    CHECK_EQ("indirect_targets", actual, expected);
    boundary_finish();
}
