// See LICENSE for license details.

#ifndef _UART_H
#define _UART_H

#ifdef __cplusplus
 extern "C" {
#endif

#include "sys_defs.h"

typedef enum uart_stop_bit {
    UART_STOP_BIT_1 = 0,
    UART_STOP_BIT_2 = 1
} UART_STOP_BIT;

typedef enum uart_parity_bit {
    UART_ODD   = 0,
    UART_EVEN  = 1,
    UART_SPACE = 2,
    UART_MARK  = 3
} UART_PARITY_BIT;

int32_t uart_init(UART_TypeDef *uart, uint32_t baudrate);
int32_t uart_config_stopbit(UART_TypeDef *uart, UART_STOP_BIT stopbit);
int32_t uart_enable_paritybit(UART_TypeDef *uart);
int32_t uart_disable_paritybit(UART_TypeDef *uart);
int32_t uart_set_parity(UART_TypeDef *uart, UART_PARITY_BIT paritybit);
int32_t uart_write(UART_TypeDef *uart, uint8_t val);
uint8_t uart_read(UART_TypeDef *uart);
int32_t uart_enable_tx_empt_int(UART_TypeDef *uart);
int32_t uart_disable_tx_empt_int(UART_TypeDef *uart);
int32_t uart_set_rx_th(UART_TypeDef *uart, uint8_t th);
int32_t uart_enable_rx_th_int(UART_TypeDef *uart);
int32_t uart_disable_rx_th_int(UART_TypeDef *uart);
int32_t uart_enable_rx_err_int(UART_TypeDef *uart);
int32_t uart_disable_rx_err_int(UART_TypeDef *uart);
int32_t uart_get_int_status(UART_TypeDef *uart);
int32_t uart_get_status(UART_TypeDef *uart);
int32_t uart_clear_tx_fifo(UART_TypeDef *uart);
int32_t uart_clear_rx_fifo(UART_TypeDef *uart);

// UART RX FIFO中断触发等级宏定义
#define UART_RX_FIFO_TH_1BYTE   0
#define UART_RX_FIFO_TH_4BYTE   1
#define UART_RX_FIFO_TH_8BYTE   2
#define UART_RX_FIFO_TH_14BYTE  3

#ifdef __cplusplus
}
#endif
#endif /* _UART_H */
