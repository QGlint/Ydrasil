#include <rtthread.h>

int main(void)
{
    volatile float lhs = 3.25f;
    volatile float rhs = 1.5f;
    volatile float result = lhs * rhs + 0.5f;

    rt_kprintf("Ydrasil RT-Thread BSP started\n");
    rt_kprintf("RV32F smoke test: %d.%02d\n",
               (int)result, ((int)(result * 100.0f)) % 100);

#ifndef BSP_USING_MTIME_TICK
    rt_kprintf("WARNING: hardware tick is disabled; timed services are unavailable\n");
#endif

    return 0;
}
