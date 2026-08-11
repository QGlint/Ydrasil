#ifndef YDRASIL_MOCK_MONITOR_BUS_H
#define YDRASIL_MOCK_MONITOR_BUS_H

#include <stddef.h>
#include <stdint.h>

void mock_monitor_reset(void);
void mock_ms601m_set_attitude_raw(int16_t roll, int16_t pitch, int16_t yaw);
size_t mock_display_pixel_count(void);
uint8_t mock_display_column(size_t page, size_t column);
size_t mock_oled_max_data_write_size(void);
size_t mock_oled_display_off_count(void);
size_t mock_oled_display_on_count(void);
void mock_display_print(void);

#endif
