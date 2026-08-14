#include <rthw.h>
#include <rtthread.h>

#define YDRASIL_IRQ_VECTOR_COUNT 32U
#define MCAUSE_INTERRUPT         (1UL << 31)

struct ydrasil_irq_entry
{
    rt_isr_handler_t handler;
    void *parameter;
};

static struct ydrasil_irq_entry irq_table[YDRASIL_IRQ_VECTOR_COUNT];

static void unhandled_irq(int vector, void *parameter)
{
    (void)parameter;
    rt_kprintf("unhandled interrupt %d\n", vector);
}

void rt_hw_interrupt_init(void)
{
    rt_uint32_t vector;

    for (vector = 0; vector < YDRASIL_IRQ_VECTOR_COUNT; vector++)
    {
        irq_table[vector].handler = unhandled_irq;
        irq_table[vector].parameter = RT_NULL;
    }
}

rt_isr_handler_t rt_hw_interrupt_install(int vector,
                                         rt_isr_handler_t handler,
                                         void *parameter,
                                         const char *name)
{
    rt_isr_handler_t previous = RT_NULL;

    (void)name;
    if (vector >= 0 && vector < (int)YDRASIL_IRQ_VECTOR_COUNT)
    {
        previous = irq_table[vector].handler;
        if (handler != RT_NULL)
        {
            irq_table[vector].handler = handler;
            irq_table[vector].parameter = parameter;
        }
    }
    return previous;
}

void rt_rv32_system_irq_handler(rt_uint32_t mcause)
{
    rt_uint32_t vector = mcause & 0x1fU;

    if ((mcause & MCAUSE_INTERRUPT) != 0U &&
        vector < YDRASIL_IRQ_VECTOR_COUNT)
    {
        irq_table[vector].handler((int)vector, irq_table[vector].parameter);
    }
    else
    {
        rt_kprintf("unhandled exception 0x%08x\n", mcause);
    }
}
