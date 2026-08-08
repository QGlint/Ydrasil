#include "coremark.h"
#include <rthw.h>
#include "board.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#else
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif

volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static CORETIMETYPE start_ticks;
static CORETIMETYPE stop_ticks;
static rt_base_t benchmark_irq_level;
static rt_bool_t benchmark_irq_locked;
static rt_bool_t monitor_started;

static int set_monitor_state(ee_u32 control, ee_u32 expected)
{
    ee_u32 timeout = 1000000U;

    YDRASIL_SYSCTRL_CM_CTRL = control;
    while ((YDRASIL_SYSCTRL_CM_STATUS & 1U) != expected && timeout != 0U)
    {
        timeout--;
    }
    return timeout == 0U ? -RT_ETIMEOUT : RT_EOK;
}

static CORETIMETYPE read_monitor_cycles(void)
{
    ee_u32 high_before;
    ee_u32 low;
    ee_u32 high_after;

    do
    {
        high_before = YDRASIL_SYSCTRL_CM_CYC_HI;
        low = YDRASIL_SYSCTRL_CM_CYC_LO;
        high_after = YDRASIL_SYSCTRL_CM_CYC_HI;
    } while (high_before != high_after);

    return ((CORETIMETYPE)high_after << 32) | low;
}

void start_time(void)
{
    benchmark_irq_level = rt_hw_interrupt_disable();
    benchmark_irq_locked = RT_TRUE;
    monitor_started = set_monitor_state(1U, 1U) == RT_EOK;
    start_ticks = 0U;
}

void stop_time(void)
{
    if (monitor_started)
    {
        (void)set_monitor_state(2U, 0U);
        stop_ticks = read_monitor_cycles();
    }
    else
    {
        YDRASIL_SYSCTRL_CM_CTRL = 2U;
        stop_ticks = 0U;
    }
    monitor_started = RT_FALSE;

    if (benchmark_irq_locked)
    {
        benchmark_irq_locked = RT_FALSE;
        rt_hw_interrupt_enable(benchmark_irq_level);
    }
}

CORE_TICKS get_time(void)
{
    return stop_ticks - start_ticks;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)ticks / (secs_ret)YDRASIL_CPU_FREQ_HZ;
}

void portable_init(core_portable *port, int *argc, char *argv[])
{
    RT_UNUSED(argc);
    RT_UNUSED(argv);
    port->portable_id = 1;
}

void portable_fini(core_portable *port)
{
    port->portable_id = 0;
}

void *portable_malloc(ee_size_t size)
{
    return rt_malloc(size);
}

void portable_free(void *pointer)
{
    rt_free(pointer);
}
