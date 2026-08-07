#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "atk_ms601m.h"
#include "lm75b.h"
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
        "YDRASIL SENSOR",
        "TEMP +23.6",
        "R+90.0 P-45.0",
        "Y+22.5"
    };
    int32_t milli_celsius;
    struct ms601m_attitude attitude;
    size_t index;

    mock_monitor_reset();
    mock_lm75b_set_temperature(23625);
    mock_ms601m_set_attitude_raw(16384, -8192, 4096);

    require(lm75b_read_temperature_milli_c(&milli_celsius) ==
            YDRASIL_DRIVER_OK, "LM75B read failed");
    require(milli_celsius == 23625, "LM75B conversion mismatch");

    require(ms601m_read_attitude(&attitude, 100U) == YDRASIL_DRIVER_OK,
            "MS601M frame parse failed");
    require(attitude.roll_tenth_degree == 900,
            "MS601M roll conversion mismatch");
    require(attitude.pitch_tenth_degree == -450,
            "MS601M pitch conversion mismatch");
    require(attitude.yaw_tenth_degree == 225,
            "MS601M yaw conversion mismatch");

    require(ssd1306_init() == YDRASIL_DRIVER_OK, "SSD1306 init failed");
    require(ssd1306_clear() == YDRASIL_DRIVER_OK, "SSD1306 clear failed");
    for (index = 0U; index < sizeof(lines) / sizeof(lines[0]); index++)
    {
        require(ssd1306_show_line((uint8_t)(index * 2U), lines[index]) ==
                YDRASIL_DRIVER_OK, "SSD1306 line update failed");
    }
    require(mock_display_pixel_count() > 300U,
            "SSD1306 framebuffer remained blank");

    printf("LM75B=%d milli-C MS601M=%d,%d,%d tenth-deg pixels=%zu\n",
           (int)milli_celsius,
           (int)attitude.roll_tenth_degree,
           (int)attitude.pitch_tenth_degree,
           (int)attitude.yaw_tenth_degree,
           mock_display_pixel_count());
    mock_display_print();
    puts("DRIVER_SIM_PASS");
    return EXIT_SUCCESS;
}
