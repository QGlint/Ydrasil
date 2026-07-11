#define BOUNDARY_NAME "bitmanip_pressure"
#include "boundary.h"

static const uint32_t patterns[] = {
    0, 1, 0xffffffffu, 0x80000000u, 0x7fffffffu,
    0xaaaaaaaau, 0x55555555u, 0x01234567u, 0x89abcdefu
};

int main(void)
{
    uint32_t signature = 0;
    for (uint32_t n = 0; n < BOUNDARY_STRESS_ROUNDS; n++) {
        uint32_t a = patterns[n % 9];
        uint32_t b = patterns[(n * 5 + 1) % 9];
        uint32_t r;
#define RUN2(insn) asm volatile(#insn " %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); signature ^= r
        RUN2(sh1add); RUN2(sh2add); RUN2(sh3add);
        RUN2(andn); RUN2(orn); RUN2(xnor);
        RUN2(rol); RUN2(ror); RUN2(min); RUN2(max); RUN2(minu); RUN2(maxu);
        RUN2(bclr); RUN2(bext); RUN2(binv); RUN2(bset);
        RUN2(clmul); RUN2(clmulh); RUN2(clmulr);
        RUN2(pack); RUN2(packh); RUN2(xperm4); RUN2(xperm8);
#undef RUN2
#define RUN1(insn) asm volatile(#insn " %0, %1" : "=r"(r) : "r"(a)); signature ^= r
        RUN1(clz); RUN1(ctz); RUN1(cpop); RUN1(orc.b); RUN1(rev8);
        RUN1(sext.b); RUN1(sext.h); RUN1(zext.h); RUN1(brev8);
#undef RUN1
    }
    CHECK_EQ("signature_changed", signature != 0, 1);
    boundary_finish();
}
