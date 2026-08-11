#include <stddef.h>
#include <string.h>

#include "font_small.h"
#include "monitor_bus.h"
#include "ssd1306.h"

#define SSD1306_WIDTH      128U
#define SSD1306_RESET_GPIO 2U
#define SSD1306_DC_GPIO    1U
#define SSD1306_WRITE_CHUNK 4U
#define SSD1306_CHAR_STRIDE (FONT_SMALL_WIDTH + 1U)

static int initialized;
static enum ssd1306_controller active_controller =
    SSD1306_CONTROLLER_SSD1306;
static int active_flipped = 1;
static uint8_t frame_buffer[SSD1306_PAGE_COUNT][SSD1306_WIDTH];

static int oled_write(int data_mode, const uint8_t *bytes, size_t size)
{
    ydrasil_bus_gpio_write(SSD1306_DC_GPIO, data_mode);
    return ydrasil_bus_spi0_write(bytes, size);
}

static int oled_command(const uint8_t *commands, size_t size)
{
    return oled_write(0, commands, size);
}

static int oled_reset_and_configure(const uint8_t *init_sequence,
                                    size_t init_size)
{
    ydrasil_bus_gpio_write(SSD1306_DC_GPIO, 0);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 1);
    ydrasil_bus_delay_ms(10U);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 0);
    ydrasil_bus_delay_ms(10U);
    ydrasil_bus_gpio_write(SSD1306_RESET_GPIO, 1);
    ydrasil_bus_delay_ms(100U);

    return oled_command(init_sequence, init_size);
}

static int oled_set_position(uint8_t page, uint8_t column)
{
    uint8_t column_offset = active_controller == SSD1306_CONTROLLER_SH1106 ?
        2U : 0U;
    uint8_t controller_column = (uint8_t)(column + column_offset);
    uint8_t position[] = {
        (uint8_t)(0xb0U | page),
        (uint8_t)(controller_column & 0x0fU),
        (uint8_t)(0x10U | (controller_column >> 4))
    };

    return oled_command(position, sizeof(position));
}

static int oled_write_page(uint8_t page, const uint8_t *data)
{
    size_t column;
    int result = oled_set_position(page, 0U);

    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }

    for (column = 0U; column < SSD1306_WIDTH;
         column += SSD1306_WRITE_CHUNK)
    {
        result = oled_write(1, &data[column], SSD1306_WRITE_CHUNK);
        if (result != YDRASIL_DRIVER_OK)
        {
            return result;
        }
    }
    return YDRASIL_DRIVER_OK;
}

int ssd1306_clear(void)
{
    static const uint8_t zeros[SSD1306_WIDTH] = {0};
    uint8_t page;

    for (page = 0U; page < SSD1306_PAGE_COUNT; page++)
    {
        int result = oled_write_page(page, zeros);

        if (result != YDRASIL_DRIVER_OK)
        {
            return result;
        }
    }
    return YDRASIL_DRIVER_OK;
}

int ssd1306_init(void)
{
    uint8_t init_sequence[] = {
        0xae, 0xd5, 0x80, 0xa8, 0x3f, 0xd3, 0x00, 0x40,
        0x8d, 0x14, 0x20, 0x02, 0xa1, 0xc8, 0xda, 0x12,
        0x81, 0xcf, 0xd9, 0xf1, 0xdb, 0x40, 0xa4, 0xa6
    };
    int result;

    if (initialized != 0)
    {
        return YDRASIL_DRIVER_OK;
    }
    if (active_controller == SSD1306_CONTROLLER_SH1106)
    {
        init_sequence[8] = 0xadU;
        init_sequence[9] = 0x8bU;
    }
    if (active_flipped == 0)
    {
        init_sequence[12] = 0xa0U;
        init_sequence[13] = 0xc0U;
    }

    result = oled_reset_and_configure(init_sequence, sizeof(init_sequence));
    if (result == YDRASIL_DRIVER_OK)
    {
        ydrasil_bus_delay_ms(100U);
        result = oled_reset_and_configure(init_sequence,
                                          sizeof(init_sequence));
    }
    if (result == YDRASIL_DRIVER_OK)
    {
        /* Let the controller settle after the final reset release. */
        ydrasil_bus_delay_ms(100U);
        result = ssd1306_clear();
    }
    if (result == YDRASIL_DRIVER_OK)
    {
        initialized = 1;
    }
    return result;
}

int ssd1306_configure(enum ssd1306_controller controller, int flipped)
{
    if (controller != SSD1306_CONTROLLER_SSD1306 &&
        controller != SSD1306_CONTROLLER_SH1106)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    active_controller = controller;
    active_flipped = flipped != 0;
    initialized = 0;
    return ssd1306_init();
}

static void render_line(uint8_t *row, const char *text)
{
    size_t column = 0U;

    memset(row, 0, SSD1306_WIDTH);
    while (text != NULL && *text != '\0' &&
           column + FONT_SMALL_WIDTH + 1U <= SSD1306_WIDTH)
    {
        const uint8_t *glyph = font_small_columns(*text++);

        memcpy(&row[column], glyph, FONT_SMALL_WIDTH);
        column += FONT_SMALL_WIDTH + 1U;
    }
}

static void render_centered_line(uint8_t *row, const char *text)
{
    size_t length = 0U;
    size_t width;
    size_t column;

    while (text != NULL && text[length] != '\0' &&
           (length + 1U) * SSD1306_CHAR_STRIDE <= SSD1306_WIDTH)
    {
        length++;
    }
    width = length == 0U ? 0U : length * SSD1306_CHAR_STRIDE - 1U;
    column = (SSD1306_WIDTH - width) / 2U;

    memset(row, 0, SSD1306_WIDTH);
    while (length != 0U)
    {
        const uint8_t *glyph = font_small_columns(*text++);

        memcpy(&row[column], glyph, FONT_SMALL_WIDTH);
        column += SSD1306_CHAR_STRIDE;
        length--;
    }
}

int ssd1306_show_line(uint8_t page, const char *text)
{
    uint8_t row[SSD1306_WIDTH];

    if (page >= SSD1306_PAGE_COUNT)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    render_line(row, text);
    return oled_write_page(page, row);
}

int ssd1306_show_frame(const char *line0, const char *line1,
                       const char *line2, const char *line3)
{
    const char *lines[] = {line0, line1, line2, line3};
    uint8_t line;
    uint8_t page;
    int result;

    memset(frame_buffer, 0, sizeof(frame_buffer));
    for (line = 0U; line < 4U; line++)
    {
        render_centered_line(frame_buffer[line * 2U], lines[line]);
    }

    result = ssd1306_init();
    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }
    result = ssd1306_display_off();
    /* Restart at the physical top before committing the complete frame. */
    if (result == YDRASIL_DRIVER_OK)
    {
        static const uint8_t display_start_line = 0x40U;

        result = oled_command(&display_start_line,
                              sizeof(display_start_line));
    }
    for (page = 0U; result == YDRASIL_DRIVER_OK &&
         page < SSD1306_PAGE_COUNT; page += 2U)
    {
        result = oled_write_page(page, frame_buffer[page]);
    }
    if (result == YDRASIL_DRIVER_OK)
    {
        result = ssd1306_display_on();
    }
    else
    {
        (void)ssd1306_display_on();
    }
    return result;
}

int ssd1306_display_off(void)
{
    static const uint8_t display_off = 0xaeU;
    int result = oled_command(&display_off, sizeof(display_off));

    return result;
}

int ssd1306_display_on(void)
{
    static const uint8_t display_on = 0xafU;
    int result = oled_command(&display_on, sizeof(display_on));

    return result;
}
