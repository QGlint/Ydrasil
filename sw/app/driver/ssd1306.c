#include <stddef.h>
#include <string.h>

#include "font_small.h"
#include "monitor_bus.h"
#include "ssd1306.h"

#define SSD1306_WIDTH      128U
#define SSD1306_RESET_GPIO 2U
#define SSD1306_DC_GPIO    1U

static int initialized;

static int oled_write(int data_mode, const uint8_t *bytes, size_t size)
{
    ydrasil_bus_gpio_write(SSD1306_DC_GPIO, data_mode);
    return ydrasil_bus_spi0_write(bytes, size);
}

static int oled_command(const uint8_t *commands, size_t size)
{
    return oled_write(0, commands, size);
}

int ssd1306_clear(void)
{
    static const uint8_t zeros[SSD1306_WIDTH] = {0};
    uint8_t page;

    for (page = 0U; page < SSD1306_PAGE_COUNT; page++)
    {
        uint8_t position[] = {(uint8_t)(0xb0U | page), 0x00U, 0x10U};
        int result = oled_command(position, sizeof(position));

        if (result != YDRASIL_DRIVER_OK)
        {
            return result;
        }
        result = oled_write(1, zeros, sizeof(zeros));
        if (result != YDRASIL_DRIVER_OK)
        {
            return result;
        }
    }
    return YDRASIL_DRIVER_OK;
}

int ssd1306_init(void)
{
    static const uint8_t init_sequence[] = {
        0xae, 0xd5, 0x80, 0xa8, 0x3f, 0xd3, 0x00, 0x40,
        0x8d, 0x14, 0x20, 0x02, 0xa1, 0xc8, 0xda, 0x12,
        0x81, 0xcf, 0xd9, 0xf1, 0xdb, 0x40, 0xa4, 0xa6,
        0xaf
    };
    int result;

    if (initialized != 0)
    {
        return YDRASIL_DRIVER_OK;
    }

    ydrasil_bus_gpio_write(SSD1306_DC_GPIO, 0);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 1);
    ydrasil_bus_delay_ms(10U);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 0);
    ydrasil_bus_delay_ms(10U);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 1);
    ydrasil_bus_delay_ms(100U);

    result = oled_command(init_sequence, sizeof(init_sequence));
    if (result == YDRASIL_DRIVER_OK)
    {
        result = ssd1306_clear();
    }
    if (result == YDRASIL_DRIVER_OK)
    {
        initialized = 1;
    }
    return result;
}

int ssd1306_show_line(uint8_t page, const char *text)
{
    uint8_t row[SSD1306_WIDTH];
    uint8_t position[] = {(uint8_t)(0xb0U | page), 0x00U, 0x10U};
    size_t column = 0U;
    int result;

    if (page >= SSD1306_PAGE_COUNT)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    memset(row, 0, sizeof(row));
    while (text != NULL && *text != '\0' &&
           column + FONT_SMALL_WIDTH + 1U <= sizeof(row))
    {
        const uint8_t *glyph = font_small_columns(*text++);

        memcpy(&row[column], glyph, FONT_SMALL_WIDTH);
        column += FONT_SMALL_WIDTH + 1U;
    }

    result = oled_command(position, sizeof(position));
    if (result == YDRASIL_DRIVER_OK)
    {
        result = oled_write(1, row, sizeof(row));
    }
    return result;
}
