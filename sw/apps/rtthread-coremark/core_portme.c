#include "coremark.h"
#include "board.h"

#define CLINT_MTIME_LO (*(volatile ee_u32 *)(YDRASIL_CLINT_BASE + 0xbff8UL))

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

static void set_monitor_state(ee_u32 control, ee_u32 expected)
{
    ee_u32 timeout = 10000U;

    YDRASIL_SYSCTRL_CM_CTRL = control;
    while ((YDRASIL_SYSCTRL_CM_STATUS & 1U) != expected && timeout != 0U)
    {
        timeout--;
    }
}

void start_time(void)
{
    set_monitor_state(1U, 1U);
    start_ticks = CLINT_MTIME_LO;
}

void stop_time(void)
{
    stop_ticks = CLINT_MTIME_LO;
    set_monitor_state(2U, 0U);
}

CORE_TICKS get_time(void)
{
    return stop_ticks - start_ticks;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)ticks / (secs_ret)YDRASIL_TIMER_FREQ_HZ;
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
