#include <finsh.h>
#include <rtthread.h>

#include "board.h"

extern int coremark_entry(void);
extern volatile rt_int32_t seed4_volatile;

static int parse_iterations(const char *text, rt_uint32_t *iterations)
{
    rt_uint32_t value = 0;

    if (text == RT_NULL || *text == '\0')
    {
        return -RT_EINVAL;
    }
    while (*text != '\0')
    {
        if (*text < '0' || *text > '9')
        {
            return -RT_EINVAL;
        }
        value = value * 10U + (rt_uint32_t)(*text - '0');
        text++;
    }
    *iterations = value;
    return RT_EOK;
}

static int coremark_command(int argc, char **argv)
{
    rt_uint32_t iterations = 0;
    rt_uint32_t cycle_high;
    rt_uint32_t cycle_low;
    int result;

    if (argc > 2 ||
        (argc == 2 && parse_iterations(argv[1], &iterations) != RT_EOK))
    {
        rt_kprintf("usage: coremark [iterations, 0=automatic]\n");
        return -RT_EINVAL;
    }
    if ((YDRASIL_SYSCTRL_CM_STATUS & 1U) != 0U)
    {
        rt_kprintf("CoreMark monitor is already active\n");
        return -RT_EBUSY;
    }

    seed4_volatile = (rt_int32_t)iterations;
    result = coremark_entry();
    cycle_high = YDRASIL_SYSCTRL_CM_CYC_HI;
    cycle_low = YDRASIL_SYSCTRL_CM_CYC_LO;
    rt_kprintf("hardware monitor cycles: 0x%08x%08x\n",
               cycle_high, cycle_low);
    return result;
}
MSH_CMD_EXPORT_ALIAS(coremark_command, coremark, Run CoreMark with hardware LED timing);

int main(void)
{
    rt_kprintf("Ydrasil RT-Thread sensor and CoreMark image started\n");
    return 0;
}
