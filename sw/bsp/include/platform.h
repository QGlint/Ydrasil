#ifndef PLACFORM_H
#define PLACFORM_H

#ifdef __cplusplus
extern "C" {
#endif

#include "sys_defs.h"
#include "csr_features.h"
#include "clint.h"
#include "xprintf.h"
#include "uart.h"
#include "int_handler.h"
#include "i2c.h"
#include "gpio.h"
#include "spi.h"
#include "pwm.h"
#include "plic.h"

uint32_t get_cpu_freq(void);
uint32_t measure_cpu_freq(uint32_t n);
void delay_1ms(uint32_t count);

#ifdef __cplusplus
}
#endif

#endif // PLATFORM_H