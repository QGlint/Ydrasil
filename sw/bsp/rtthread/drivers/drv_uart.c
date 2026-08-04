#include <rthw.h>
#include <rtthread.h>

#include "board.h"

#define UART_RX_BUFFER_SIZE 128U
#define UART_LSR_DATA_READY (1U << 0)
#define UART_LSR_THR_EMPTY  (1U << 5)

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

struct ydrasil_uart_device
{
    struct rt_device parent;
    volatile struct ydrasil_uart_regs *regs;
    rt_uint8_t rx_buffer[UART_RX_BUFFER_SIZE];
    volatile rt_uint16_t rx_head;
    volatile rt_uint16_t rx_tail;
};

static struct ydrasil_uart_device uart0;

void ydrasil_console_putc(char ch)
{
    volatile struct ydrasil_uart_regs *regs =
        (volatile struct ydrasil_uart_regs *)YDRASIL_UART0_BASE;

    while ((regs->lsr & UART_LSR_THR_EMPTY) == 0)
    {
    }
    regs->rbr_thr_dll = (rt_uint8_t)ch;
}

static void uart_hw_configure(volatile struct ydrasil_uart_regs *regs)
{
    uint32_t divisor = (YDRASIL_APB_FREQ_HZ + (YDRASIL_UART_BAUD / 2)) /
        YDRASIL_UART_BAUD;

    regs->ier_dlm = 0;
    regs->lcr = 0x80;
    regs->rbr_thr_dll = divisor & 0xff;
    regs->ier_dlm = (divisor >> 8) & 0xff;
    regs->lcr = 0x03;
    regs->iir_fcr = 0x06;
    regs->ier_dlm = 0x01;
}

static rt_err_t uart_init(rt_device_t device)
{
    struct ydrasil_uart_device *uart =
        rt_container_of(device, struct ydrasil_uart_device, parent);

    uart->rx_head = 0;
    uart->rx_tail = 0;
    uart_hw_configure(uart->regs);
    return RT_EOK;
}

static rt_err_t uart_open(rt_device_t device, rt_uint16_t oflag)
{
    struct ydrasil_uart_device *uart =
        rt_container_of(device, struct ydrasil_uart_device, parent);

    RT_UNUSED(oflag);
    uart->regs->ier_dlm |= 0x01;
    return RT_EOK;
}

static rt_err_t uart_close(rt_device_t device)
{
    struct ydrasil_uart_device *uart =
        rt_container_of(device, struct ydrasil_uart_device, parent);

    uart->regs->ier_dlm &= ~0x01U;
    return RT_EOK;
}

static rt_ssize_t uart_read(rt_device_t device, rt_off_t position,
                            void *buffer, rt_size_t size)
{
    struct ydrasil_uart_device *uart =
        rt_container_of(device, struct ydrasil_uart_device, parent);
    rt_uint8_t *bytes = buffer;
    rt_size_t count = 0;

    RT_UNUSED(position);
    while (count < size && uart->rx_tail != uart->rx_head)
    {
        bytes[count++] = uart->rx_buffer[uart->rx_tail];
        uart->rx_tail = (uart->rx_tail + 1U) & (UART_RX_BUFFER_SIZE - 1U);
    }
    return (rt_ssize_t)count;
}

static rt_ssize_t uart_write(rt_device_t device, rt_off_t position,
                             const void *buffer, rt_size_t size)
{
    const rt_uint8_t *bytes = buffer;
    rt_size_t index;

    RT_UNUSED(device);
    RT_UNUSED(position);
    for (index = 0; index < size; index++)
    {
        if (bytes[index] == '\n')
        {
            ydrasil_console_putc('\r');
        }
        ydrasil_console_putc((char)bytes[index]);
    }
    return (rt_ssize_t)size;
}

static rt_err_t uart_control(rt_device_t device, int command, void *argument)
{
    RT_UNUSED(device);
    RT_UNUSED(command);
    RT_UNUSED(argument);
    return -RT_ENOSYS;
}

#ifdef RT_USING_DEVICE_OPS
static const struct rt_device_ops uart_ops = {
    uart_init, uart_open, uart_close, uart_read, uart_write, uart_control
};
#endif

static void uart0_irq(void *parameter)
{
    struct ydrasil_uart_device *uart = parameter;
    rt_size_t received = 0;

    while ((uart->regs->lsr & UART_LSR_DATA_READY) != 0)
    {
        rt_uint16_t next =
            (uart->rx_head + 1U) & (UART_RX_BUFFER_SIZE - 1U);
        rt_uint8_t byte = (rt_uint8_t)uart->regs->rbr_thr_dll;

        if (next != uart->rx_tail)
        {
            uart->rx_buffer[uart->rx_head] = byte;
            uart->rx_head = next;
            received++;
        }
    }

    if (received != 0 && uart->parent.rx_indicate != RT_NULL)
    {
        uart->parent.rx_indicate(&uart->parent, received);
    }
}

int ydrasil_uart0_init(void)
{
    rt_err_t result;

    rt_memset(&uart0, 0, sizeof(uart0));
    uart0.regs = (volatile struct ydrasil_uart_regs *)YDRASIL_UART0_BASE;
    uart0.parent.type = RT_Device_Class_Char;
#ifdef RT_USING_DEVICE_OPS
    uart0.parent.ops = &uart_ops;
#else
    uart0.parent.init = uart_init;
    uart0.parent.open = uart_open;
    uart0.parent.close = uart_close;
    uart0.parent.read = uart_read;
    uart0.parent.write = uart_write;
    uart0.parent.control = uart_control;
#endif
    uart0.parent.user_data = RT_NULL;

    result = rt_device_register(&uart0.parent, "uart0",
        RT_DEVICE_FLAG_RDWR | RT_DEVICE_FLAG_INT_RX | RT_DEVICE_FLAG_STREAM);
    if (result != RT_EOK)
    {
        return result;
    }
    result = rt_device_init(&uart0.parent);
    if (result != RT_EOK)
    {
        return result;
    }
    return ydrasil_plic_register(YDRASIL_IRQ_UART0, uart0_irq, &uart0);
}
