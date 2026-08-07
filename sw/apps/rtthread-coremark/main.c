#include <finsh.h>
#include <rtthread.h>

#include "board.h"
#include "core_portme.h"

extern int coremark_entry(void);
extern volatile rt_int32_t seed4_volatile;

static int parse_unsigned(const char *text, rt_uint32_t limit,
                          rt_uint32_t *parsed)
{
    rt_uint32_t value = 0;

    if (text == RT_NULL || *text == '\0')
    {
        return -RT_EINVAL;
    }
    while (*text != '\0')
    {
        rt_uint32_t digit;

        if (*text < '0' || *text > '9')
        {
            return -RT_EINVAL;
        }
        digit = (rt_uint32_t)(*text - '0');
        if (value > (limit - digit) / 10U)
        {
            return -RT_EINVAL;
        }
        value = value * 10U + digit;
        text++;
    }
    *parsed = value;
    return RT_EOK;
}

static int coremark_command(int argc, char **argv)
{
    rt_uint32_t iterations = ITERATIONS;
    rt_uint32_t cpu_frequency_hz = YDRASIL_CPU_FREQ_HZ;
    rt_uint32_t cycle_high;
    rt_uint32_t cycle_low;
    int result;

    if (argc > 3 ||
        (argc >= 2 &&
         parse_unsigned(argv[1], 0x7fffffffU, &iterations) != RT_EOK) ||
        (argc == 3 &&
         (parse_unsigned(argv[2], 0xffffffffU, &cpu_frequency_hz) != RT_EOK ||
          cpu_frequency_hz == 0U)))
    {
        rt_kprintf("usage: coremark [iterations] [cpu_hz]\n");
        rt_kprintf("defaults: iterations=%u cpu_hz=%u; 0 iterations=automatic\n",
                   (rt_uint32_t)ITERATIONS,
                   (rt_uint32_t)YDRASIL_CPU_FREQ_HZ);
        return -RT_EINVAL;
    }
    if ((YDRASIL_SYSCTRL_CM_STATUS & 1U) != 0U)
    {
        rt_kprintf("CoreMark monitor is already active\n");
        return -RT_EBUSY;
    }

    seed4_volatile = (rt_int32_t)iterations;
    coremark_set_cpu_frequency(cpu_frequency_hz);
    rt_kprintf("CoreMark CPU frequency: %u Hz\n", cpu_frequency_hz);
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
    rt_kprintf("Ydrasil RT-Thread monitor ready\n");
    rt_kprintf("commands: help, coremark [iterations] [cpu_hz], sensor [all|temp|imu]\n");
    return 0;
}
