#ifndef __PLIC_H__
#define __PLIC_H__

#include <stdint.h>
#include "sys_defs.h"

#define PLIC_INT_EN_ADDR        0x0000
#define PLIC_INT_MVEC_ADDR      0x0100
#define PLIC_INT_MARG_ADDR      0x0104
#define PLIC_INT_PRI_ADDR       0x1000
#define PLIC_INT_VECTABLE_ADDR  0x2000
#define PLIC_INT_OBJS_ADDR      0x3000

#define PLIC_NUM_SOURCES        11

typedef struct {
    volatile uint32_t int_en;                          // 0x0000
    uint8_t  reserved0[0x0100 - 0x0004];               // 填充到0x0100
    volatile uint32_t mvec;                            // 0x0100
    volatile uint32_t marg;                            // 0x0104
    uint8_t  reserved1[0x1000 - 0x0108];               // 填充到0x1000
    volatile uint8_t  int_pri[PLIC_NUM_SOURCES];        // 0x1000~0x1000+N-1
    uint8_t  reserved2[0x2000 - (0x1000 + PLIC_NUM_SOURCES)]; // 填充到0x2000
    volatile uint32_t vectable[PLIC_NUM_SOURCES];       // 0x2000~0x2000+N-1*4
    uint8_t  reserved3[0x3000 - (0x2000 + PLIC_NUM_SOURCES * 4)]; // 填充到0x3000
    volatile uint32_t objtable[PLIC_NUM_SOURCES];       // 0x3000~0x3000+N-1*4
} PLIC_type;

#define PLIC    ((PLIC_type *)(ALIOTH_PLIC_BASE))

// API声明
void plic_enable_irq(uint8_t irq_id);
void plic_disable_irq(uint8_t irq_id);
void plic_set_priority(uint8_t irq_id, uint8_t priority);
void plic_set_handler(uint8_t irq_id, void (*handler)(void *), void *arg);
void plic_init(void);
void plic_default_handler(void *arg);
void plic_dispatch(void);

#endif // __PLIC_H__
