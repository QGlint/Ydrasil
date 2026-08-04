#include <rthw.h>
#include <rtthread.h>

#include "board.h"

#define MIE_MTIE             (1UL << 7)
#define MCAUSE_MACHINE_TIMER 7UL
#define CLINT_MTIMECMP_LO    (*(volatile uint32_t *)(YDRASIL_CLINT_BASE + 0x4000UL))
#define CLINT_MTIMECMP_HI    (*(volatile uint32_t *)(YDRASIL_CLINT_BASE + 0x4004UL))
#define CLINT_MTIME_LO       (*(volatile uint32_t *)(YDRASIL_CLINT_BASE + 0xBFF8UL))
#define CLINT_MTIME_HI       (*(volatile uint32_t *)(YDRASIL_CLINT_BASE + 0xBFFCUL))

static uint64_t tick_cycles;

static uint64_t mtime_read(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do
    {
        high_before = CLINT_MTIME_HI;
        low = CLINT_MTIME_LO;
        high_after = CLINT_MTIME_HI;
    } while (high_before != high_after);

    return ((uint64_t)high_after << 32) | low;
}

static void mtimecmp_write(uint64_t value)
{
    CLINT_MTIMECMP_HI = UINT32_MAX;
    CLINT_MTIMECMP_LO = (uint32_t)value;
    CLINT_MTIMECMP_HI = (uint32_t)(value >> 32);
}

static void mtime_program_next(void)
{
    mtimecmp_write(mtime_read() + tick_cycles);
}

static void mtime_isr(int vector, void *param)
{
    RT_UNUSED(vector);
    RT_UNUSED(param);

    mtime_program_next();
    rt_tick_increase();
}

void ydrasil_tick_init(void)
{
    tick_cycles = YDRASIL_TIMER_FREQ_HZ / RT_TICK_PER_SECOND;
    RT_ASSERT(tick_cycles != 0);

    rt_hw_interrupt_install(MCAUSE_MACHINE_TIMER, mtime_isr, RT_NULL, "mtime");
    mtime_program_next();
    __asm__ volatile ("csrs mie, %0" :: "r"(MIE_MTIE));
}
