#include "plic.h"

void plic_enable_irq(uint8_t irq_id) {
    if (irq_id < PLIC_NUM_SOURCES) {
        PLIC->int_en |= (1U << irq_id);
    }
}

void plic_disable_irq(uint8_t irq_id) {
    if (irq_id < PLIC_NUM_SOURCES) {
        PLIC->int_en &= ~(1U << irq_id);
    }
}

void plic_set_priority(uint8_t irq_id, uint8_t priority) {
    if (irq_id < PLIC_NUM_SOURCES) {
        PLIC->int_pri[irq_id] = priority;
    }
}

void plic_set_handler(uint8_t irq_id, void (*handler)(void *), void *arg) {
    if (irq_id < PLIC_NUM_SOURCES) {
        PLIC->vectable[irq_id] = (uint32_t)handler;
        PLIC->objtable[irq_id] = (uint32_t)arg;
    }
}

void plic_default_handler(void *arg) {
    (void)arg;
    // 可以添加日志或断言等
    printf("Default PLIC handler called. No specific handler set for this IRQ.\n");
    // while (1); // 默认死循环
}

void plic_init(void) {
    for (uint8_t i = 0; i < PLIC_NUM_SOURCES; ++i) {
        plic_set_handler(i, plic_default_handler, 0);
        plic_set_priority(i, 0);
        plic_disable_irq(i);
    }
}

void plic_dispatch(void) {
    void (*handler)(void *);
    void *arg;
    handler = (void (*)(void *))(PLIC->mvec);
    arg = (void *)(PLIC->marg);
    if (handler) {
        handler(arg);
    }
}
