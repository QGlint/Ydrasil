#include <rthw.h>
#include <rtthread.h>

#include "board.h"

#define MIE_MEIE             (1UL << 11)
#define PLIC_PENDING         (*(volatile uint32_t *)(YDRASIL_PLIC_BASE + 0x00UL))
#define PLIC_ENABLE          (*(volatile uint32_t *)(YDRASIL_PLIC_BASE + 0x04UL))
#define PLIC_CLAIM           (*(volatile uint32_t *)(YDRASIL_PLIC_BASE + 0x08UL))
#define PLIC_FORCE           (*(volatile uint32_t *)(YDRASIL_PLIC_BASE + 0x0cUL))

struct irq_entry
{
    ydrasil_irq_handler_t handler;
    void *parameter;
};

static struct irq_entry irq_table[YDRASIL_IRQ_COUNT];

int ydrasil_plic_register(unsigned int source,
                          ydrasil_irq_handler_t handler,
                          void *parameter)
{
    rt_base_t level;

    if (source >= YDRASIL_IRQ_COUNT || handler == RT_NULL)
    {
        return -RT_EINVAL;
    }

    level = rt_hw_interrupt_disable();
    irq_table[source].handler = handler;
    irq_table[source].parameter = parameter;
    PLIC_ENABLE |= 1UL << source;
    rt_hw_interrupt_enable(level);
    return RT_EOK;
}

static void mext_isr(int vector, void *parameter)
{
    uint32_t claim;
    unsigned int source;
    unsigned int dispatch_count = 0;

    RT_UNUSED(vector);
    RT_UNUSED(parameter);

    while ((claim = PLIC_CLAIM) != 0 && dispatch_count < YDRASIL_IRQ_COUNT * 2)
    {
        source = claim - 1;
        if (source < YDRASIL_IRQ_COUNT && irq_table[source].handler != RT_NULL)
        {
            irq_table[source].handler(irq_table[source].parameter);
        }
        PLIC_CLAIM = claim;
        dispatch_count++;
    }
}

int ydrasil_plic_init(void)
{
    rt_memset(irq_table, 0, sizeof(irq_table));
    PLIC_ENABLE = 0;
    PLIC_FORCE = 0;
    while (PLIC_PENDING != 0)
    {
        uint32_t claim = PLIC_CLAIM;
        if (claim == 0)
        {
            break;
        }
        PLIC_CLAIM = claim;
    }

    rt_hw_interrupt_install(YDRASIL_MCAUSE_MEXT, mext_isr,
                            RT_NULL, "mext");
    __asm__ volatile ("csrs mie, %0" :: "r"(MIE_MEIE));
    return RT_EOK;
}
