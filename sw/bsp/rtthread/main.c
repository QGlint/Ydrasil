#include <rtthread.h>

#include "sim_ctrl.h"

#define COREMARK_STACK_SIZE 4096
#define COREMARK_PRIORITY   5
#define COREMARK_TIMESLICE  10

#ifdef YDRASIL_CONTEST_FPGA
#define CONTEST_SEG_REG       (*(volatile rt_uint32_t *)0x80200020u)
#define CONTEST_LED_REG       (*(volatile rt_uint32_t *)0x80200040u)
#define CONTEST_COUNTER_REG   (*(volatile rt_uint32_t *)0x80200050u)
#define CONTEST_COUNTER_START 0x80000000u
#define CONTEST_COUNTER_STOP  0xffffffffu
#define CONTEST_COREMARK_PASS 0x00504f53u
#define CONTEST_COREMARK_FAIL 0x00bad001u
#endif

extern int coremark_main(void);

static struct rt_thread coremark_thread;

rt_align(RT_ALIGN_SIZE)
static rt_uint8_t coremark_stack[COREMARK_STACK_SIZE];

static void coremark_thread_entry(void *parameter)
{
    int result;

    RT_UNUSED(parameter);

    rt_kprintf("[RTT] CoreMark thread running: %s\n", rt_thread_self()->parent.name);
#ifdef YDRASIL_CONTEST_FPGA
    CONTEST_COUNTER_REG = CONTEST_COUNTER_START;
#endif
    result = coremark_main();
    rt_kprintf("[RTT] CoreMark thread completed, result=%d\n", result);

#ifdef YDRASIL_SIM_CTRL
    sim_end();
#elif defined(YDRASIL_CONTEST_FPGA)
    rt_uint32_t elapsed_ms;

    CONTEST_COUNTER_REG = CONTEST_COUNTER_STOP;

    /* Allow the 50 MHz counter value to cross back into the CPU domain. */
    for (volatile rt_uint32_t delay = 0; delay < 256u; delay++)
    {
        __asm__ volatile ("nop");
    }

    elapsed_ms = CONTEST_COUNTER_REG;
    CONTEST_SEG_REG = elapsed_ms;
    CONTEST_LED_REG = result == 0 ? CONTEST_COREMARK_PASS : CONTEST_COREMARK_FAIL;

    while (1)
    {
    }
#endif
}

int main(void)
{
    rt_err_t result;

    rt_kprintf("[RTT] main thread running: %s\n", rt_thread_self()->parent.name);
    result = rt_thread_init(&coremark_thread,
                            "coremark",
                            coremark_thread_entry,
                            RT_NULL,
                            coremark_stack,
                            sizeof(coremark_stack),
                            COREMARK_PRIORITY,
                            COREMARK_TIMESLICE);
    if (result != RT_EOK)
    {
        rt_kprintf("[RTT] CoreMark thread init failed: %d\n", result);
        rt_hw_cpu_shutdown();
    }

    rt_kprintf("[RTT] starting CoreMark as an RT-Thread thread\n");
    result = rt_thread_startup(&coremark_thread);
    if (result != RT_EOK)
    {
        rt_kprintf("[RTT] CoreMark thread startup failed: %d\n", result);
        rt_hw_cpu_shutdown();
    }

    rt_kprintf("[RTT] CoreMark thread returned to main\n");
    return 0;
}
