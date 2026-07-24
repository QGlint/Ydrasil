#include <rthw.h>
#include <rtthread.h>

#include "board.h"

#define MIE_MTIE             (1UL << 7)
#define MCAUSE_MACHINE_TIMER 7UL
#define CLINT_MTIMECMP       (*(volatile uint64_t *)(YDRASIL_CLINT_BASE + 0x4000UL))
#define CLINT_MTIME          (*(volatile uint64_t *)(YDRASIL_CLINT_BASE + 0xBFF8UL))

static uint64_t tick_cycles;

static void mtime_program_next(void)
{
    CLINT_MTIMECMP = CLINT_MTIME + tick_cycles;
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
