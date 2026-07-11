#ifndef BOUNDARY_H
#define BOUNDARY_H

#include <stdint.h>

#include "sim_ctrl.h"
#include "xprintf.h"

#define LED_REG (*(volatile uint32_t *)0x80200040u)
#define BOUNDARY_STRESS_ROUNDS 64u

static int boundary_failures;

#define CHECK_EQ(label, actual, expected) do {                         \
    uint32_t got_ = (uint32_t)(actual);                               \
    uint32_t want_ = (uint32_t)(expected);                            \
    if (got_ != want_) {                                               \
        xprintf("BOUNDARY FAIL name=%s check=%s got=0x%08x want=0x%08x\n", \
                BOUNDARY_NAME, label, got_, want_);                    \
        boundary_failures++;                                          \
    }                                                                 \
} while (0)

static void boundary_finish(void)
{
    if (boundary_failures == 0) {
        xprintf("BOUNDARY PASS name=%s\n", BOUNDARY_NAME);
        LED_REG = 0x00504f53u;
    } else {
        xprintf("BOUNDARY FAIL name=%s count=%d\n",
                BOUNDARY_NAME, boundary_failures);
        LED_REG = 0x00bad001u;
    }
    sim_end();
    while (1) {
    }
}

#endif
