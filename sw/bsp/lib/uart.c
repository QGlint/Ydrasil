#include "uart.h"

/*
 * UART中断模式说明：
 * 1. RX阈值中断（接收FIFO到达设定阈值）：
 *    当接收FIFO中的数据量达到设定的触发阈值时产生中断，用于通知有足够数据可读。
 *    通过IER寄存器的bit0使能（uart_enable_rx_th_int / uart_disable_rx_th_int）。
 *
 * 2. TX空中断（发送FIFO为空）：
 *    当发送FIFO为空时产生中断，通知可以继续发送数据。
 *    通过IER寄存器的bit1使能（uart_enable_tx_empt_int / uart_disable_tx_empt_int）。
 *
 * 3. RX错误中断（接收数据出错）：
 *    当接收数据发生错误（如校验错误、帧错误等）时产生中断。
 *    通过IER寄存器的bit2使能（uart_enable_rx_err_int / uart_disable_rx_err_int）。
 */

int32_t uart_init(UART_TypeDef *uart, uint32_t baudrate)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    unsigned int uart_div = SYSTEM_CLOCK / baudrate - 1;
    uart->LCR = 0x80;
    uart->DLM = (uart_div >> 8) & 0xFF;
    uart->DLL = uart_div        & 0xFF;
    uart->FCR = 0xC6;
    uart->LCR = 0x03;

    return 0;
}

int32_t uart_config_stopbit(UART_TypeDef *uart, UART_STOP_BIT stopbit)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->LCR &= 0xFFFFFFFB;
    uart->LCR |= (stopbit << 2);

    return 0;
}

int32_t uart_enable_paritybit(UART_TypeDef *uart)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->LCR |= 0x8;

    return 0;
}

int32_t uart_disable_paritybit(UART_TypeDef *uart)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->LCR &= 0xFFFFFFF7;

    return 0;
}

int32_t uart_set_parity(UART_TypeDef *uart, UART_PARITY_BIT paritybit)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->LCR &= 0xFFFFFFCF;
    uart->LCR |= (paritybit << 4);

    return 0;
}

int32_t uart_write(UART_TypeDef *uart, uint8_t val)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }
#ifndef SIMULATION_SPIKE
#ifndef SIMULATION_XLSPIKE
    while ((uart->LSR & 0x20) == 0);
#endif
    uart->THR = val;
#else
    extern void htif_putc(char ch);
    htif_putc(val);
#endif
    return 0;
}

uint8_t uart_read(UART_TypeDef *uart)
{
    uint32_t reg;
    if (__RARELY(uart == NULL)) {
        return -1;
    }
    
    while ((uart->LSR & 0x1) == 0);
    reg = uart->RBR;
    
    return (uint8_t)(reg & 0xFF);
}


int32_t uart_enable_tx_empt_int(UART_TypeDef *uart)
{
    // 使能发送FIFO为空中断（TX空中断），IER寄存器bit1
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER |= 0x2;
    return 0;
}

int32_t uart_disable_tx_empt_int(UART_TypeDef *uart)
{
    // 禁用发送FIFO为空中断（TX空中断），IER寄存器bit1
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER &= 0xFFFFFFFD;
    return 0;
}

// 接收FIFO中断触发等级
// UART_RX_FIFO_TH_1BYTE: 1字节
// UART_RX_FIFO_TH_4BYTE: 4字节
// UART_RX_FIFO_TH_8BYTE: 8字节
// UART_RX_FIFO_TH_14BYTE: 14字节
int32_t uart_set_rx_th(UART_TypeDef *uart, uint8_t th)
{
    // 设置接收FIFO触发阈值，影响RX阈值中断触发条件
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    if(th > UART_RX_FIFO_TH_14BYTE) {
       th = UART_RX_FIFO_TH_14BYTE;
    }

    uart->FCR = (th << 6);
    return 0;
}

int32_t uart_enable_rx_th_int(UART_TypeDef *uart)
{
    // 使能接收FIFO阈值中断（RX阈值中断），IER寄存器bit0
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER |= 0x1;
    return 0;
}

int32_t uart_disable_rx_th_int(UART_TypeDef *uart)
{
    // 禁用接收FIFO阈值中断（RX阈值中断），IER寄存器bit0
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER &= 0xFFFFFFFE;
    return 0;
}

int32_t uart_enable_rx_err_int(UART_TypeDef *uart)
{
    // 使能接收错误中断（RX错误中断），IER寄存器bit2
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER |= 0x4;
    return 0;
}

int32_t uart_disable_rx_err_int(UART_TypeDef *uart)
{
    // 禁用接收错误中断（RX错误中断），IER寄存器bit2
    if (__RARELY(uart == NULL)) {
        return -1;
    }

    uart->IER &= 0xFFFFFFFB;
    return 0;
}

int32_t uart_get_int_status(UART_TypeDef *uart)
{

    if (__RARELY(uart == NULL)) {
        return -1;
    }

    return uart->IIR;
}

int32_t uart_get_status(UART_TypeDef *uart)
{

    if (__RARELY(uart == NULL)) {
        return -1;
    }

    return uart->LSR;
}

int32_t uart_clear_tx_fifo(UART_TypeDef *uart)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }
    uart->FCR |= (1 << 2); // TX FIFO 清空
    return 0;
}

int32_t uart_clear_rx_fifo(UART_TypeDef *uart)
{
    if (__RARELY(uart == NULL)) {
        return -1;
    }
    uart->FCR |= (1 << 1); // RX FIFO 清空
    return 0;
}


