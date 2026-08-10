#include <rtthread.h>

#include "board.h"
#include "monitor_bus.h"

#define MMIO32(address) (*(volatile uint32_t *)(address))

#define GPIO_DIRECTION  MMIO32(YDRASIL_GPIO_BASE + 0x00UL)
#define GPIO_OUTPUT     MMIO32(YDRASIL_GPIO_BASE + 0x08UL)

#define SPI_STATUS      MMIO32(YDRASIL_SPI0_BASE + 0x00UL)
#define SPI_CLKDIV      MMIO32(YDRASIL_SPI0_BASE + 0x04UL)
#define SPI_COMMAND     MMIO32(YDRASIL_SPI0_BASE + 0x08UL)
#define SPI_ADDRESS     MMIO32(YDRASIL_SPI0_BASE + 0x0cUL)
#define SPI_LENGTH      MMIO32(YDRASIL_SPI0_BASE + 0x10UL)
#define SPI_DUMMY       MMIO32(YDRASIL_SPI0_BASE + 0x14UL)
#define SPI_TXFIFO      MMIO32(YDRASIL_SPI0_BASE + 0x18UL)

#define SPI_STATUS_READY       (1U << 0)
#define SPI_STATUS_START_WRITE (1U << 1)
#define SPI_STATUS_CLEAR_FIFO  (1U << 4)
#define SPI_FIFO_BYTES         64U

#define I2C_PRESCALE    MMIO32(YDRASIL_I2C0_BASE + 0x00UL)
#define I2C_CONTROL     MMIO32(YDRASIL_I2C0_BASE + 0x04UL)
#define I2C_RECEIVE     MMIO32(YDRASIL_I2C0_BASE + 0x08UL)
#define I2C_STATUS      MMIO32(YDRASIL_I2C0_BASE + 0x0cUL)
#define I2C_TRANSMIT    MMIO32(YDRASIL_I2C0_BASE + 0x10UL)
#define I2C_COMMAND     MMIO32(YDRASIL_I2C0_BASE + 0x14UL)

#define I2C_STATUS_NACK (1U << 7)
#define I2C_STATUS_BUSY (1U << 6)
#define I2C_STATUS_TIP  (1U << 1)
#define I2C_CMD_START   (1U << 7)
#define I2C_CMD_STOP    (1U << 6)
#define I2C_CMD_READ    (1U << 5)
#define I2C_CMD_WRITE   (1U << 4)
#define I2C_CMD_NACK    (1U << 3)
#define I2C_CMD_ACK_IRQ (1U << 0)

#define UART_LSR_DATA_READY (1U << 0)

struct ydrasil_uart_regs
{
    volatile uint32_t rbr_thr_dll;
    volatile uint32_t ier_dlm;
    volatile uint32_t iir_fcr;
    volatile uint32_t lcr;
    volatile uint32_t mcr;
    volatile uint32_t lsr;
    volatile uint32_t msr;
    volatile uint32_t scratch;
};

static int i2c_wait_complete(void)
{
    uint32_t timeout = 1000000U;

    while ((I2C_STATUS & I2C_STATUS_TIP) != 0U && timeout != 0U)
    {
        timeout--;
    }
    if (timeout == 0U)
    {
        return YDRASIL_DRIVER_ETIMEOUT;
    }
    I2C_COMMAND = I2C_CMD_ACK_IRQ;
    return YDRASIL_DRIVER_OK;
}

static int i2c_write_byte(uint8_t value, uint32_t command)
{
    int result;

    I2C_TRANSMIT = value;
    I2C_COMMAND = command;
    result = i2c_wait_complete();
    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }
    return (I2C_STATUS & I2C_STATUS_NACK) != 0U ?
        YDRASIL_DRIVER_EIO : YDRASIL_DRIVER_OK;
}

static int i2c_read_byte(uint32_t command, uint8_t *value)
{
    int result;

    I2C_COMMAND = command;
    result = i2c_wait_complete();
    if (result == YDRASIL_DRIVER_OK)
    {
        *value = (uint8_t)I2C_RECEIVE;
    }
    return result;
}

static void i2c_stop_after_error(void)
{
    if ((I2C_STATUS & (I2C_STATUS_BUSY | I2C_STATUS_TIP)) !=
        I2C_STATUS_BUSY)
    {
        return;
    }

    I2C_TRANSMIT = 0xffU;
    I2C_COMMAND = I2C_CMD_WRITE | I2C_CMD_STOP;
    (void)i2c_wait_complete();
}

int ydrasil_bus_i2c_read_register(uint8_t address,
                                  uint8_t reg,
                                  uint8_t *data,
                                  size_t size)
{
    size_t index;
    int result;

    if (address > 0x7fU || data == NULL || size == 0U)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    I2C_PRESCALE = (YDRASIL_APB_FREQ_HZ / (5U * 100000U)) - 1U;
    I2C_CONTROL = 1U << 7;

    result = i2c_write_byte((uint8_t)(address << 1),
                            I2C_CMD_START | I2C_CMD_WRITE);
    if (result == YDRASIL_DRIVER_OK)
    {
        result = i2c_write_byte(reg, I2C_CMD_WRITE);
    }
    if (result == YDRASIL_DRIVER_OK)
    {
        result = i2c_write_byte((uint8_t)((address << 1) | 1U),
                                I2C_CMD_START | I2C_CMD_WRITE);
    }

    for (index = 0U; result == YDRASIL_DRIVER_OK && index < size; index++)
    {
        uint32_t command = I2C_CMD_READ;

        if (index == size - 1U)
        {
            command |= I2C_CMD_STOP | I2C_CMD_NACK;
        }
        result = i2c_read_byte(command, &data[index]);
    }
    if (result != YDRASIL_DRIVER_OK)
    {
        i2c_stop_after_error();
    }
    return result;
}

void ydrasil_bus_uart1_reset(uint32_t baudrate)
{
    volatile struct ydrasil_uart_regs *uart =
        (volatile struct ydrasil_uart_regs *)YDRASIL_UART1_BASE;
    uint32_t divisor =
        (YDRASIL_APB_FREQ_HZ + (baudrate / 2U)) / baudrate;

    uart->ier_dlm = 0U;
    uart->lcr = 0x80U;
    uart->rbr_thr_dll = divisor & 0xffU;
    uart->ier_dlm = (divisor >> 8) & 0xffU;
    uart->lcr = 0x03U;
    uart->iir_fcr = 0x06U;

    while ((uart->lsr & UART_LSR_DATA_READY) != 0U)
    {
        (void)uart->rbr_thr_dll;
    }
}

int ydrasil_bus_uart1_getc(uint8_t *value)
{
    volatile struct ydrasil_uart_regs *uart =
        (volatile struct ydrasil_uart_regs *)YDRASIL_UART1_BASE;

    if (value == NULL)
    {
        return YDRASIL_DRIVER_EINVAL;
    }
    if ((uart->lsr & UART_LSR_DATA_READY) == 0U)
    {
        return YDRASIL_DRIVER_EEMPTY;
    }
    *value = (uint8_t)uart->rbr_thr_dll;
    return YDRASIL_DRIVER_OK;
}

void ydrasil_bus_gpio_write(uint32_t pin, int high)
{
    uint32_t mask;
    uint32_t output;

    if (pin >= 32U)
    {
        return;
    }
    mask = 1UL << pin;
    output = GPIO_OUTPUT;
    GPIO_OUTPUT = high != 0 ? (output | mask) : (output & ~mask);
    GPIO_DIRECTION = GPIO_DIRECTION | mask;
}

static int spi_wait_idle(void)
{
    uint32_t timeout = 1000000U;

    while ((SPI_STATUS & SPI_STATUS_READY) == 0U && timeout != 0U)
    {
        timeout--;
    }
    return timeout == 0U ?
        YDRASIL_DRIVER_ETIMEOUT : YDRASIL_DRIVER_OK;
}

static int spi_write_chunk(const uint8_t *data,
                           size_t size)
{
    size_t offset;
    int result;

    result = spi_wait_idle();
    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }

    SPI_STATUS = SPI_STATUS_CLEAR_FIFO;
    SPI_CLKDIV = 4U;
    SPI_COMMAND = 0U;
    SPI_ADDRESS = 0U;
    SPI_DUMMY = 0U;
    SPI_LENGTH = (uint32_t)(size * 8U) << 16;

    for (offset = 0U; offset < size; offset += 4U)
    {
        uint32_t word = 0U;
        size_t byte_index;

        for (byte_index = 0U; byte_index < 4U &&
             offset + byte_index < size; byte_index++)
        {
            word |= (uint32_t)data[offset + byte_index] <<
                    (24U - (uint32_t)byte_index * 8U);
        }
        SPI_TXFIFO = word;
    }

    SPI_STATUS = SPI_STATUS_START_WRITE;
    return spi_wait_idle();
}

int ydrasil_bus_spi0_write(const uint8_t *data,
                           size_t size)
{
    int result = YDRASIL_DRIVER_OK;

    if (data == NULL && size != 0U)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    while (size != 0U && result == YDRASIL_DRIVER_OK)
    {
        size_t chunk = size > SPI_FIFO_BYTES ? SPI_FIFO_BYTES : size;

        result = spi_write_chunk(data, chunk);
        data += chunk;
        size -= chunk;
    }
    return result;
}

uint32_t ydrasil_bus_millis(void)
{
    return (uint32_t)(((uint64_t)rt_tick_get() * 1000U) /
                      RT_TICK_PER_SECOND);
}

void ydrasil_bus_delay_ms(uint32_t milliseconds)
{
    rt_thread_mdelay(milliseconds);
}
