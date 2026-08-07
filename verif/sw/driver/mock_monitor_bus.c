#include <stdio.h>
#include <string.h>

#include "mock_monitor_bus.h"
#include "monitor_bus.h"

#define MOCK_LM75B_ADDRESS 0x48U
#define MOCK_OLED_DC_GPIO  1U
#define MOCK_OLED_CS       0U
#define MOCK_OLED_WIDTH    128U
#define MOCK_OLED_PAGES    8U

static uint8_t lm75b_temperature[2];
static uint8_t uart_frame[32];
static size_t uart_frame_size;
static size_t uart_frame_offset;
static uint8_t framebuffer[MOCK_OLED_PAGES][MOCK_OLED_WIDTH];
static uint8_t oled_page;
static uint8_t oled_column;
static int oled_data_mode;
static uint32_t elapsed_ms;

void mock_monitor_reset(void)
{
    memset(lm75b_temperature, 0, sizeof(lm75b_temperature));
    memset(uart_frame, 0, sizeof(uart_frame));
    memset(framebuffer, 0, sizeof(framebuffer));
    uart_frame_size = 0U;
    uart_frame_offset = 0U;
    oled_page = 0U;
    oled_column = 0U;
    oled_data_mode = 0;
    elapsed_ms = 0U;
}

void mock_lm75b_set_temperature(int32_t milli_celsius)
{
    int32_t raw_11bit = milli_celsius / 125;
    int16_t encoded = (int16_t)(raw_11bit * 32);

    lm75b_temperature[0] = (uint8_t)((uint16_t)encoded >> 8);
    lm75b_temperature[1] = (uint8_t)encoded;
}

static void append_i16_le(size_t offset, int16_t value)
{
    uart_frame[offset] = (uint8_t)value;
    uart_frame[offset + 1U] = (uint8_t)((uint16_t)value >> 8);
}

void mock_ms601m_set_attitude_raw(int16_t roll, int16_t pitch, int16_t yaw)
{
    size_t index;
    uint8_t checksum = 0U;

    uart_frame[0] = 0x55U;
    uart_frame[1] = 0x55U;
    uart_frame[2] = 0x01U;
    uart_frame[3] = 0x06U;
    append_i16_le(4U, roll);
    append_i16_le(6U, pitch);
    append_i16_le(8U, yaw);
    for (index = 0U; index < 10U; index++)
    {
        checksum = (uint8_t)(checksum + uart_frame[index]);
    }
    uart_frame[10] = checksum;
    uart_frame_size = 11U;
    uart_frame_offset = 0U;
}

int ydrasil_bus_i2c_read_register(uint8_t address,
                                  uint8_t reg,
                                  uint8_t *data,
                                  size_t size)
{
    if (address != MOCK_LM75B_ADDRESS || reg != 0U || data == NULL ||
        size != sizeof(lm75b_temperature))
    {
        return YDRASIL_DRIVER_EIO;
    }
    memcpy(data, lm75b_temperature, sizeof(lm75b_temperature));
    return YDRASIL_DRIVER_OK;
}

void ydrasil_bus_uart1_reset(uint32_t baudrate)
{
    (void)baudrate;
    uart_frame_offset = 0U;
}

int ydrasil_bus_uart1_getc(uint8_t *value)
{
    if (value == NULL)
    {
        return YDRASIL_DRIVER_EINVAL;
    }
    if (uart_frame_offset >= uart_frame_size)
    {
        return YDRASIL_DRIVER_EEMPTY;
    }
    *value = uart_frame[uart_frame_offset++];
    return YDRASIL_DRIVER_OK;
}

void ydrasil_bus_gpio_write(uint32_t pin, int high)
{
    if (pin == MOCK_OLED_DC_GPIO)
    {
        oled_data_mode = high != 0;
    }
}

static void process_oled_command(uint8_t command)
{
    if ((command & 0xf8U) == 0xb0U)
    {
        oled_page = command & 0x07U;
    }
    else if ((command & 0xf0U) == 0x00U)
    {
        oled_column = (uint8_t)((oled_column & 0xf0U) | (command & 0x0fU));
    }
    else if ((command & 0xf0U) == 0x10U)
    {
        oled_column = (uint8_t)((oled_column & 0x0fU) |
                                ((command & 0x0fU) << 4));
    }
}

int ydrasil_bus_spi0_write(uint32_t chip_select,
                           const uint8_t *data,
                           size_t size)
{
    size_t index;

    if (chip_select != MOCK_OLED_CS || (data == NULL && size != 0U))
    {
        return YDRASIL_DRIVER_EINVAL;
    }
    for (index = 0U; index < size; index++)
    {
        if (oled_data_mode == 0)
        {
            process_oled_command(data[index]);
        }
        else if (oled_page < MOCK_OLED_PAGES &&
                 oled_column < MOCK_OLED_WIDTH)
        {
            framebuffer[oled_page][oled_column++] = data[index];
        }
    }
    return YDRASIL_DRIVER_OK;
}

uint32_t ydrasil_bus_millis(void)
{
    return elapsed_ms;
}

void ydrasil_bus_delay_ms(uint32_t milliseconds)
{
    elapsed_ms += milliseconds;
}

size_t mock_display_pixel_count(void)
{
    size_t page;
    size_t column;
    size_t count = 0U;

    for (page = 0U; page < MOCK_OLED_PAGES; page++)
    {
        for (column = 0U; column < MOCK_OLED_WIDTH; column++)
        {
            uint8_t pixels = framebuffer[page][column];

            while (pixels != 0U)
            {
                count += pixels & 1U;
                pixels >>= 1;
            }
        }
    }
    return count;
}

void mock_display_print(void)
{
    size_t page;

    for (page = 0U; page < MOCK_OLED_PAGES; page++)
    {
        size_t last_column = 0U;
        size_t column;
        unsigned int row;

        for (column = 0U; column < MOCK_OLED_WIDTH; column++)
        {
            if (framebuffer[page][column] != 0U)
            {
                last_column = column + 1U;
            }
        }
        if (last_column == 0U)
        {
            continue;
        }

        printf("OLED page %zu\n", page);
        for (row = 0U; row < 7U; row++)
        {
            for (column = 0U; column < last_column; column++)
            {
                putchar((framebuffer[page][column] & (1U << row)) != 0U ?
                        '#' : ' ');
            }
            putchar('\n');
        }
    }
}
