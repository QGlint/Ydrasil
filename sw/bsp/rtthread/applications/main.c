#include <rtthread.h>

int main(void)
{
    rt_kprintf("Ydrasil RT-Thread BSP started\n");
    rt_kprintf("ISA profile: RV32IM (FPU disabled)\n");

#ifndef BSP_USING_MTIME_TICK
    rt_kprintf("WARNING: hardware tick is disabled; timed services are unavailable\n");
#endif

    return 0;
}
