#include <rthw.h>
#include <rtthread.h>

#include "board.h"

extern unsigned char _end;
extern unsigned char _heap_end;

static void sim_console_putc(char ch)
{
    *(volatile uint32_t *)YDRASIL_SIM_STDOUT_REG = (uint8_t)ch;
}

void rt_hw_console_output(const char *str)
{
#ifdef BSP_USING_SIM_CONSOLE
    while (*str != '\0')
    {
        if (*str == '\n')
        {
            sim_console_putc('\r');
        }
        sim_console_putc(*str++);
    }
#else
    RT_UNUSED(str);
#endif
}

void ydrasil_sim_end(void)
{
    *(volatile uint32_t *)YDRASIL_SIM_END_REG = 1;
}

void rt_hw_board_init(void)
{
    rt_hw_interrupt_init();

#ifdef RT_USING_HEAP
    rt_system_heap_init(&_end, &_heap_end);
#endif

#ifdef BSP_USING_MTIME_TICK
    ydrasil_tick_init();
#endif

#ifdef RT_USING_COMPONENTS_INIT
    rt_components_board_init();
#endif
}
