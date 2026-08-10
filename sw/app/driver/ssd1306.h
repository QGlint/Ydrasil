#ifndef YDRASIL_SSD1306_H
#define YDRASIL_SSD1306_H

#include <stdint.h>

#define SSD1306_PAGE_COUNT 8U

int ssd1306_init(void);
int ssd1306_clear(void);
int ssd1306_show_line(uint8_t page, const char *text);

#endif
