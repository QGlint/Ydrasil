#ifndef YDRASIL_RTTHREAD_BOARD_H
#define YDRASIL_RTTHREAD_BOARD_H

#include <stdint.h>

#define YDRASIL_ITCM_BASE      0x80000000UL
#define YDRASIL_ITCM_SIZE      (128UL * 1024UL)
#define YDRASIL_DTCM_BASE      0x80100000UL
#define YDRASIL_DTCM_SIZE      (64UL * 1024UL)

#define YDRASIL_CLINT_BASE     0x02000000UL
#define YDRASIL_PLIC_BASE      0x0c000000UL
#define YDRASIL_SYSCTRL_BASE   0x40000000UL
#define YDRASIL_GPIO_BASE      0x40001000UL
#define YDRASIL_UART0_BASE     0x40002000UL
#define YDRASIL_UART1_BASE     0x40003000UL
#define YDRASIL_SPI0_BASE      0x40004000UL
#define YDRASIL_I2C0_BASE      0x40005000UL

#define YDRASIL_APB_FREQ_HZ    50000000UL
#ifndef YDRASIL_CPU_FREQ_HZ
#define YDRASIL_CPU_FREQ_HZ    150000000UL
#endif
#define YDRASIL_TIMER_FREQ_HZ  YDRASIL_APB_FREQ_HZ
#define YDRASIL_UART_BAUD      115200UL

#define YDRASIL_SIM_STDOUT_REG 0x80200060UL
#define YDRASIL_SIM_END_REG    0x80200040UL

#define YDRASIL_MCAUSE_MEXT    11
#define YDRASIL_IRQ_UART0      0
#define YDRASIL_IRQ_UART1      1
#define YDRASIL_IRQ_SPI0       2
#define YDRASIL_IRQ_I2C0       3
#define YDRASIL_IRQ_GPIO       4
#define YDRASIL_IRQ_COUNT      8

#define YDRASIL_SYSCTRL_CM_CTRL   (*(volatile uint32_t *)(YDRASIL_SYSCTRL_BASE + 0x10UL))
#define YDRASIL_SYSCTRL_CM_STATUS (*(volatile uint32_t *)(YDRASIL_SYSCTRL_BASE + 0x14UL))
#define YDRASIL_SYSCTRL_CM_CYC_LO (*(volatile uint32_t *)(YDRASIL_SYSCTRL_BASE + 0x24UL))
#define YDRASIL_SYSCTRL_CM_CYC_HI (*(volatile uint32_t *)(YDRASIL_SYSCTRL_BASE + 0x28UL))

typedef void (*ydrasil_irq_handler_t)(void *parameter);

void ydrasil_tick_init(void);
void ydrasil_sim_end(void);
void ydrasil_console_putc(char ch);
int ydrasil_uart0_init(void);
int ydrasil_plic_init(void);
int ydrasil_plic_register(unsigned int source,
                          ydrasil_irq_handler_t handler,
                          void *parameter);

#endif
