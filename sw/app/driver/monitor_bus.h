#ifndef YDRASIL_MONITOR_BUS_H
#define YDRASIL_MONITOR_BUS_H

#include <stddef.h>
#include <stdint.h>

enum ydrasil_driver_status
{
    YDRASIL_DRIVER_OK = 0,
    YDRASIL_DRIVER_EINVAL = -1,
    YDRASIL_DRIVER_EIO = -2,
    YDRASIL_DRIVER_ETIMEOUT = -3,
    YDRASIL_DRIVER_EEMPTY = -4
};

int ydrasil_bus_i2c_read_register(uint8_t address,
                                  uint8_t reg,
                                  uint8_t *data,
                                  size_t size);
void ydrasil_bus_uart1_reset(uint32_t baudrate);
int ydrasil_bus_uart1_getc(uint8_t *value);
void ydrasil_bus_gpio_write(uint32_t pin, int high);
int ydrasil_bus_spi0_write(uint32_t chip_select,
                           const uint8_t *data,
                           size_t size);
uint32_t ydrasil_bus_millis(void);
void ydrasil_bus_delay_ms(uint32_t milliseconds);

#endif
