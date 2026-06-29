#include "sys_defs.h"
#include "clint.h"
#include "int_handler.h"

// 定时器事件中断处理
void __attribute__((weak)) timer_events_handler(void)
{
    printf("timer_events_handler called\n");
}
void __attribute__((weak)) timer0_event_handler(void)
{
    printf("timer0_event_handler called\n");
}
void __attribute__((weak)) timer1_event_handler(void)
{
    printf("timer1_event_handler called\n");
}
void __attribute__((weak)) timer2_event_handler(void)
{
    printf("timer2_event_handler called\n");
}
void __attribute__((weak)) timer3_event_handler(void)
{
    printf("timer3_event_handler called\n");
}
void __attribute__((weak)) spi_event_handler(void)
{
    printf("spi_event_handler called\n");
}
void __attribute__((weak)) i2c0_interrupt_handler(void)
{
    printf("i2c0_interrupt_handler called\n");
}
void __attribute__((weak)) i2c1_interrupt_handler(void)
{
    printf("i2c1_interrupt_handler called\n");
}
void __attribute__((weak)) uart0_event_handler(void)
{
    printf("uart0_event_handler called\n");
}
void __attribute__((weak)) uart1_event_handler(void)
{
    printf("uart1_event_handler called\n");
}
void __attribute__((weak)) gpio0_int_handler(void)
{
    printf("gpio0_int_handler called\n");
}
void __attribute__((weak)) gpio1_int_handler(void)
{
    printf("gpio1_int_handler called\n");
}

void __attribute__((weak)) machine_software_interrupt_handler(void)
{
    CLINT_ClearSWIRQ(); // 清除软件中断标志
    printf("machine_software_interrupt_handler called\n");
}

void __attribute__((weak)) machine_timer_interrupt_handler(void)
{
    printf("machine_timer_interrupt_handler called\n");
    // 清除定时器中断标志，防止中断重入
}

void __attribute__((weak)) machine_external_interrupt_handler(void)
{
    printf("machine_external_interrupt_handler called\n");
}
