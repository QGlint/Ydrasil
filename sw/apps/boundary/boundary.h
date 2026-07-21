#ifndef BOUNDARY_H
#define BOUNDARY_H

#include <stdint.h>

#include "sim_ctrl.h"
#include "xprintf.h"

#define LED_REG (*(volatile uint32_t *)0x80200040u)
#define BOUNDARY_STRESS_ROUNDS 64u

static int boundary_failures;
static volatile uint32_t boundary_checks;

volatile uint64_t tohost __attribute__((section(".tohost.tohost"), aligned(64), used)) = 0;
volatile uint64_t fromhost __attribute__((section(".tohost.fromhost"), aligned(64), used)) = 0;

static void boundary_write_tohost(uint32_t value)
{
    volatile uint32_t *words = (volatile uint32_t *)&tohost;
    ((volatile uint32_t *)&fromhost)[0] = 0;
    words[0] = value;
    words[1] = 0;
}

#define CHECK_EQ(label, actual, expected) do {                         \
    uint32_t got_ = (uint32_t)(actual);                               \
    uint32_t want_ = (uint32_t)(expected);                            \
    boundary_checks++;                                                \
    if (got_ != want_) {                                               \
        xprintf("BOUNDARY FAIL name=%s check=%s got=0x%08x want=0x%08x\n", \
                BOUNDARY_NAME, label, got_, want_);                    \
        boundary_failures++;                                          \
    }                                                                 \
} while (0)

static void boundary_finish(void)
{
    xprintf("BOUNDARY RESULT name=%s checks=%u failures=%u\n",
            BOUNDARY_NAME, boundary_checks, (uint32_t)boundary_failures);
    if (boundary_failures == 0) {
        xprintf("BOUNDARY PASS name=%s\n", BOUNDARY_NAME);
        boundary_write_tohost(1);
        LED_REG = 0x00504f53u;
    } else {
        xprintf("BOUNDARY FAIL name=%s count=%d\n",
                BOUNDARY_NAME, boundary_failures);
        boundary_write_tohost(((uint32_t)boundary_failures << 1) | 1u);
        LED_REG = 0x00bad001u;
    }
    sim_end();
    while (1) {
    }
}

#endif
