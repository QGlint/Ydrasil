#include <finsh.h>
#include <rtthread.h>

#include "board.h"

#define MMIO32(address) (*(volatile rt_uint32_t *)(address))

#define SPI_STATUS      MMIO32(YDRASIL_SPI0_BASE + 0x00UL)
#define SPI_CLKDIV      MMIO32(YDRASIL_SPI0_BASE + 0x04UL)
#define SPI_COMMAND     MMIO32(YDRASIL_SPI0_BASE + 0x08UL)
#define SPI_LENGTH      MMIO32(YDRASIL_SPI0_BASE + 0x10UL)
#define SPI_TXFIFO      MMIO32(YDRASIL_SPI0_BASE + 0x18UL)

#define I2C_PRESCALE    MMIO32(YDRASIL_I2C0_BASE + 0x00UL)
#define I2C_CONTROL     MMIO32(YDRASIL_I2C0_BASE + 0x04UL)
#define I2C_RECEIVE     MMIO32(YDRASIL_I2C0_BASE + 0x08UL)
#define I2C_STATUS      MMIO32(YDRASIL_I2C0_BASE + 0x0cUL)
#define I2C_TRANSMIT    MMIO32(YDRASIL_I2C0_BASE + 0x10UL)
#define I2C_COMMAND     MMIO32(YDRASIL_I2C0_BASE + 0x14UL)

#define I2C_STATUS_NACK (1U << 7)
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
    volatile rt_uint32_t rbr_thr_dll;
    volatile rt_uint32_t ier_dlm;
    volatile rt_uint32_t iir_fcr;
    volatile rt_uint32_t lcr;
    volatile rt_uint32_t mcr;
    volatile rt_uint32_t lsr;
    volatile rt_uint32_t msr;
    volatile rt_uint32_t scratch;
};

static int parse_u32(const char *text, rt_uint32_t *value)
{
    rt_uint32_t parsed = 0;

    if (text == RT_NULL || *text == '\0')
    {
        return -RT_EINVAL;
    }
    while (*text != '\0')
    {
        if (*text < '0' || *text > '9')
        {
            return -RT_EINVAL;
        }
        parsed = parsed * 10U + (rt_uint32_t)(*text - '0');
        text++;
    }
    *value = parsed;
    return RT_EOK;
}

static int spi_wait_idle(void)
{
    rt_uint32_t timeout = 1000000U;

    while ((SPI_STATUS & 1U) == 0U && timeout != 0U)
    {
        timeout--;
    }
    return timeout == 0U ? -RT_ETIMEOUT : RT_EOK;
}

static int spi_write_byte(rt_uint8_t value, rt_uint32_t chip_select)
{
    int result = spi_wait_idle();

    if (result != RT_EOK)
    {
        return result;
    }
    SPI_COMMAND = 0;
    SPI_LENGTH = 8U << 16;
    SPI_TXFIFO = (rt_uint32_t)value << 24;
    SPI_STATUS = (1U << 1) | (1U << (8U + chip_select));
    return spi_wait_idle();
}

static int spi_screen_command(int argc, char **argv)
{
    static const rt_uint8_t wake_sequence[] = {0x01U, 0x11U, 0x29U};
    rt_uint32_t chip_select = 0;
    rt_size_t index;
    int result;

    if (argc > 1 && (parse_u32(argv[1], &chip_select) != RT_EOK ||
                     chip_select > 3U))
    {
        rt_kprintf("usage: spi_screen [cs:0-3]\n");
        return -RT_EINVAL;
    }

    SPI_CLKDIV = 4U;
    for (index = 0; index < sizeof(wake_sequence); index++)
    {
        result = spi_write_byte(wake_sequence[index], chip_select);
        if (result != RT_EOK)
        {
            rt_kprintf("SPI screen transfer timed out\n");
            return result;
        }
        if (index != sizeof(wake_sequence) - 1U)
        {
            rt_thread_mdelay(index == 0U ? 5 : 120);
        }
    }
    rt_kprintf("SPI screen wake sequence sent on CS%u\n", chip_select);
    return RT_EOK;
}
MSH_CMD_EXPORT_ALIAS(spi_screen_command, spi_screen, Wake an SPI screen);

static int i2c_wait_complete(void)
{
    rt_uint32_t timeout = 1000000U;

    while ((I2C_STATUS & I2C_STATUS_TIP) != 0U && timeout != 0U)
    {
        timeout--;
    }
    if (timeout == 0U)
    {
        return -RT_ETIMEOUT;
    }
    I2C_COMMAND = I2C_CMD_ACK_IRQ;
    return RT_EOK;
}

static int i2c_write_byte(rt_uint8_t value, rt_uint32_t command)
{
    int result;

    I2C_TRANSMIT = value;
    I2C_COMMAND = command;
    result = i2c_wait_complete();
    if (result != RT_EOK)
    {
        return result;
    }
    return (I2C_STATUS & I2C_STATUS_NACK) != 0U ? -RT_EIO : RT_EOK;
}

static int i2c_read_byte(rt_uint32_t command, rt_uint8_t *value)
{
    int result;

    I2C_COMMAND = command;
    result = i2c_wait_complete();
    if (result == RT_EOK)
    {
        *value = (rt_uint8_t)I2C_RECEIVE;
    }
    return result;
}

static int i2c_temp_command(int argc, char **argv)
{
    rt_uint32_t address = 0x48U;
    rt_uint8_t msb;
    rt_uint8_t lsb;
    rt_int32_t half_degrees;
    int result;

    if (argc > 1 && (parse_u32(argv[1], &address) != RT_EOK ||
                     address > 0x7fU))
    {
        rt_kprintf("usage: i2c_temp [7-bit-address-decimal]\n");
        return -RT_EINVAL;
    }

    I2C_PRESCALE = (YDRASIL_APB_FREQ_HZ / (5U * 100000U)) - 1U;
    I2C_CONTROL = 1U << 7;

    result = i2c_write_byte((rt_uint8_t)(address << 1),
                            I2C_CMD_START | I2C_CMD_WRITE);
    if (result == RT_EOK)
    {
        result = i2c_write_byte(0x00U, I2C_CMD_WRITE);
    }
    if (result == RT_EOK)
    {
        result = i2c_write_byte((rt_uint8_t)((address << 1) | 1U),
                                I2C_CMD_START | I2C_CMD_WRITE);
    }
    if (result == RT_EOK)
    {
        result = i2c_read_byte(I2C_CMD_READ, &msb);
    }
    if (result == RT_EOK)
    {
        result = i2c_read_byte(I2C_CMD_READ | I2C_CMD_STOP | I2C_CMD_NACK,
                               &lsb);
    }
    if (result != RT_EOK)
    {
        rt_kprintf("I2C temperature sensor at 0x%02x did not respond (%d)\n",
                   address, result);
        return result;
    }

    half_degrees = ((rt_int16_t)(((rt_uint16_t)msb << 8) | lsb)) >> 7;
    rt_kprintf("temperature: %d.%d C (raw 0x%02x%02x)\n",
               half_degrees / 2, (half_degrees < 0 ? -half_degrees : half_degrees) % 2 * 5,
               msb, lsb);
    return RT_EOK;
}
MSH_CMD_EXPORT_ALIAS(i2c_temp_command, i2c_temp, Read an I2C temperature sensor);

static void uart1_configure(struct ydrasil_uart_regs *uart)
{
    rt_uint32_t divisor =
        (YDRASIL_APB_FREQ_HZ + (YDRASIL_UART_BAUD / 2U)) / YDRASIL_UART_BAUD;

    uart->ier_dlm = 0;
    uart->lcr = 0x80U;
    uart->rbr_thr_dll = divisor & 0xffU;
    uart->ier_dlm = (divisor >> 8) & 0xffU;
    uart->lcr = 0x03U;
    uart->iir_fcr = 0x06U;
}

static int uart_gyro_command(int argc, char **argv)
{
    struct ydrasil_uart_regs *uart =
        (struct ydrasil_uart_regs *)YDRASIL_UART1_BASE;
    rt_uint32_t byte_count = 12U;
    rt_uint32_t index;
    rt_uint32_t wait_ms;

    if (argc > 1 && (parse_u32(argv[1], &byte_count) != RT_EOK ||
                     byte_count == 0U || byte_count > 128U))
    {
        rt_kprintf("usage: uart_gyro [bytes:1-128]\n");
        return -RT_EINVAL;
    }

    uart1_configure(uart);
    rt_kprintf("gyro UART bytes:");
    for (index = 0; index < byte_count; index++)
    {
        wait_ms = 2000U;
        while ((uart->lsr & UART_LSR_DATA_READY) == 0U && wait_ms != 0U)
        {
            rt_thread_mdelay(1);
            wait_ms--;
        }
        if (wait_ms == 0U)
        {
            rt_kprintf(" timeout after %u byte(s)\n", index);
            return -RT_ETIMEOUT;
        }
        rt_kprintf(" %02x", (rt_uint8_t)uart->rbr_thr_dll);
    }
    rt_kprintf("\n");
    return RT_EOK;
}
MSH_CMD_EXPORT_ALIAS(uart_gyro_command, uart_gyro, Read bytes from a UART gyroscope);
