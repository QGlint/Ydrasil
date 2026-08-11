#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "atk_ms601m.h"
#include "mock_monitor_bus.h"
#include "monitor_bus.h"
#include "ssd1306.h"

static void require(int condition, const char *message)
{
    if (condition == 0)
    {
        fprintf(stderr, "DRIVER_SIM_FAIL: %s\n", message);
        exit(EXIT_FAILURE);
    }
}

int main(void)
{
    static const char *lines[] = {
        "Ydrsail",
        "ANGLE SENSOR",
        "R+90.0 P-45.0",
        "Y+22.5"
    };
    struct ms601m_attitude attitude;
    size_t display_off_count;
    size_t display_on_count;

    mock_monitor_reset();
    mock_ms601m_set_attitude_raw(16384, -8192, 4096);

    require(ms601m_read_attitude(&attitude, 100U) == YDRASIL_DRIVER_OK,
            "MS601M frame parse failed");
    require(attitude.roll_tenth_degree == 900,
            "MS601M roll conversion mismatch");
    require(attitude.pitch_tenth_degree == -450,
            "MS601M pitch conversion mismatch");
    require(attitude.yaw_tenth_degree == 225,
            "MS601M yaw conversion mismatch");

    require(ssd1306_init() == YDRASIL_DRIVER_OK, "SSD1306 init failed");
    display_off_count = mock_oled_display_off_count();
    display_on_count = mock_oled_display_on_count();
    require(ssd1306_show_frame(lines[0], lines[1], lines[2], lines[3]) ==
            YDRASIL_DRIVER_OK, "SSD1306 frame update failed");
    require(mock_oled_display_off_count() == display_off_count + 1U &&
            mock_oled_display_on_count() == display_on_count + 1U,
            "SSD1306 frame was not committed with one off/on pair");
    require(mock_display_pixel_count() > 300U,
            "SSD1306 framebuffer remained blank");
    require(mock_display_column(0U, 43U) == 0x07U &&
            mock_display_column(0U, 45U) == 0x70U,
            "SSD1306 title position is incorrect");
    require(mock_display_column(1U, 0U) == 0U &&
            mock_display_column(2U, 28U) == 0x7eU,
            "SSD1306 page position is incorrect");
    require(mock_oled_max_data_write_size() <= 4U,
            "SSD1306 data transfer exceeded the resynchronization chunk");
    require(ssd1306_show_line(2U, "T") == YDRASIL_DRIVER_OK,
            "SSD1306 short line update failed");
    require(mock_display_column(2U, 6U) == 0U,
            "SSD1306 short line left stale pixels");

    mock_monitor_reset();
    require(ssd1306_configure(SSD1306_CONTROLLER_SH1106, 1) ==
            YDRASIL_DRIVER_OK, "SH1106 profile initialization failed");
    require(ssd1306_show_line(0U, "T") == YDRASIL_DRIVER_OK,
            "SH1106 line update failed");
    require(ssd1306_display_on() == YDRASIL_DRIVER_OK,
            "SH1106 display enable failed");
    require(mock_display_column(0U, 0U) == 0U &&
            mock_display_column(0U, 2U) == 0x01U,
            "SH1106 two-column offset is incorrect");

    printf("MS601M=%d,%d,%d tenth-deg pixels=%zu\n",
           (int)attitude.roll_tenth_degree,
           (int)attitude.pitch_tenth_degree,
           (int)attitude.yaw_tenth_degree,
           mock_display_pixel_count());
    mock_display_print();
    puts("DRIVER_SIM_PASS");
    return EXIT_SUCCESS;
}
