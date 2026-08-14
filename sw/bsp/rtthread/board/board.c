#include <rthw.h>
#include <rtthread.h>

#include "board.h"

extern unsigned char _end;
extern unsigned char _heap_end;

static void board_require(rt_err_t result)
{
    RT_ASSERT(result == RT_EOK);
    while (result != RT_EOK)
    {
    }
}

static void sim_console_putc(char ch)
{
    *(volatile uint32_t *)YDRASIL_SIM_STDOUT_REG = (uint8_t)ch;
}

void rt_hw_console_output(const char *str)
{
    while (*str != '\0')
    {
        if (*str == '\n')
        {
#ifdef BSP_USING_UART0
            ydrasil_console_putc('\r');
#elif defined(BSP_USING_SIM_CONSOLE)
            sim_console_putc('\r');
#endif
        }
#ifdef BSP_USING_UART0
        ydrasil_console_putc(*str++);
#elif defined(BSP_USING_SIM_CONSOLE)
        sim_console_putc(*str++);
#else
        str++;
#endif
    }
}

void ydrasil_sim_end(void)
{
    *(volatile uint32_t *)YDRASIL_SIM_END_REG = 1;
}

void rt_hw_board_init(void)
{
    rt_hw_interrupt_init();

#ifdef BSP_USING_PLIC
    /* Nano compiles RT_ASSERT expressions out when RT_DEBUG is disabled. */
    board_require(ydrasil_plic_init());
#endif

#ifdef BSP_USING_UART0
    board_require(ydrasil_uart0_init());
    (void)rt_console_set_device(RT_CONSOLE_DEVICE_NAME);
    board_require(rt_console_get_device() != RT_NULL ? RT_EOK : -RT_ERROR);
#endif

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
