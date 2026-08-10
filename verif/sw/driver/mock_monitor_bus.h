#ifndef YDRASIL_MOCK_MONITOR_BUS_H
#define YDRASIL_MOCK_MONITOR_BUS_H

#include <stddef.h>
#include <stdint.h>

void mock_monitor_reset(void);
void mock_lm75b_set_temperature(int32_t milli_celsius);
void mock_ms601m_set_attitude_raw(int16_t roll, int16_t pitch, int16_t yaw);
size_t mock_display_pixel_count(void);
void mock_display_print(void);

#endif
