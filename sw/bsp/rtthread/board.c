#include <rtthread.h>

#include "platform.h"
#include "sim_ctrl.h"

void rt_hw_console_output(const char *str)
{
    xputs(str);
}

void rt_hw_board_init(void)
{
    SystemInit();
    rt_kprintf("[RTT] Ydrasil BSP initialized\n");
    rt_kprintf("[RTT] CPU clock: %u Hz\n", (unsigned int)SYSTEM_CLOCK);
}

void rt_hw_cpu_shutdown(void)
{
#ifdef YDRASIL_SIM_CTRL
    sim_end();
#endif

    while (1)
    {
    }
}
