#ifndef YDRASIL_SSD1306_H
#define YDRASIL_SSD1306_H

#include <stdint.h>

#define SSD1306_PAGE_COUNT 8U

enum ssd1306_controller
{
    SSD1306_CONTROLLER_SSD1306,
    SSD1306_CONTROLLER_SH1106
};

int ssd1306_configure(enum ssd1306_controller controller, int flipped);
int ssd1306_init(void);
int ssd1306_clear(void);
int ssd1306_show_line(uint8_t page, const char *text);
int ssd1306_show_frame(const char *line0, const char *line1,
                       const char *line2, const char *line3);
int ssd1306_display_off(void);
int ssd1306_display_on(void);

#endif
