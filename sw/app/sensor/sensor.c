#include <finsh.h>
#include <rtthread.h>
#include <stdint.h>
#include <string.h>

#include "atk_ms601m.h"
#include "lm75b.h"
#include "monitor_bus.h"
#include "ssd1306.h"

static uint32_t abs_i32(int32_t value)
{
    return value < 0 ? (uint32_t)(-value) : (uint32_t)value;
}

static void format_tenth(char *buffer, size_t size,
                         const char *label, int32_t value)
{
    uint32_t magnitude = abs_i32(value);

    rt_snprintf(buffer, size, "%s%c%u.%u", label,
                value < 0 ? '-' : '+', magnitude / 10U, magnitude % 10U);
}

static void print_temperature(int32_t milli_celsius)
{
    uint32_t magnitude = abs_i32(milli_celsius);

    rt_kprintf("LM75B: %c%u.%03u C\n", milli_celsius < 0 ? '-' : '+',
               magnitude / 1000U, magnitude % 1000U);
}

static void print_attitude(const struct ms601m_attitude *attitude)
{
    uint32_t roll = abs_i32(attitude->roll_tenth_degree);
    uint32_t pitch = abs_i32(attitude->pitch_tenth_degree);
    uint32_t yaw = abs_i32(attitude->yaw_tenth_degree);

    rt_kprintf("MS601M: roll=%c%u.%u pitch=%c%u.%u yaw=%c%u.%u deg\n",
               attitude->roll_tenth_degree < 0 ? '-' : '+',
               roll / 10U, roll % 10U,
               attitude->pitch_tenth_degree < 0 ? '-' : '+',
               pitch / 10U, pitch % 10U,
               attitude->yaw_tenth_degree < 0 ? '-' : '+',
               yaw / 10U, yaw % 10U);
}

static int display_sensor_lines(const char *temperature,
                                const char *attitude,
                                const char *yaw)
{
    const char *lines[] = {"YDRASIL SENSOR", temperature, attitude, yaw};
    size_t index;
    int result;

    result = ssd1306_init();
    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }
    result = ssd1306_clear();
    for (index = 0U; result == YDRASIL_DRIVER_OK &&
         index < sizeof(lines) / sizeof(lines[0]); index++)
    {
        result = ssd1306_show_line((uint8_t)(index * 2U), lines[index]);
    }
    return result;
}

static int sensor_command(int argc, char **argv)
{
    int want_temperature = 1;
    int want_imu = 1;
    int32_t milli_celsius = 0;
    struct ms601m_attitude attitude = {0};
    char temperature_line[22] = "TEMP NO DATA";
    char attitude_line[22] = "MS601M NO DATA";
    char yaw_line[22] = "";
    int temperature_result = YDRASIL_DRIVER_OK;
    int imu_result = YDRASIL_DRIVER_OK;
    int display_result;

    if (argc > 2)
    {
        rt_kprintf("usage: sensor [all|temp|imu]\n");
        return YDRASIL_DRIVER_EINVAL;
    }
    if (argc == 2)
    {
        if (strcmp(argv[1], "temp") == 0)
        {
            want_imu = 0;
        }
        else if (strcmp(argv[1], "imu") == 0)
        {
            want_temperature = 0;
        }
        else if (strcmp(argv[1], "all") != 0)
        {
            rt_kprintf("usage: sensor [all|temp|imu]\n");
            return YDRASIL_DRIVER_EINVAL;
        }
    }

    if (want_temperature != 0)
    {
        temperature_result =
            lm75b_read_temperature_milli_c(&milli_celsius);
        if (temperature_result == YDRASIL_DRIVER_OK)
        {
            print_temperature(milli_celsius);
            format_tenth(temperature_line, sizeof(temperature_line), "TEMP ",
                         milli_celsius / 100);
        }
        else
        {
            rt_kprintf("LM75B read failed: %d\n", temperature_result);
        }
    }
    else
    {
        temperature_line[0] = '\0';
    }

    if (want_imu != 0)
    {
        imu_result = ms601m_read_attitude(&attitude, 1000U);
        if (imu_result == YDRASIL_DRIVER_OK)
        {
            char roll[10];
            char pitch[10];

            print_attitude(&attitude);
            format_tenth(roll, sizeof(roll), "R",
                         attitude.roll_tenth_degree);
            format_tenth(pitch, sizeof(pitch), "P",
                         attitude.pitch_tenth_degree);
            rt_snprintf(attitude_line, sizeof(attitude_line), "%s %s", roll,
                        pitch);
            format_tenth(yaw_line, sizeof(yaw_line), "Y",
                         attitude.yaw_tenth_degree);
        }
        else
        {
            rt_kprintf("MS601M attitude timeout: %d\n", imu_result);
        }
    }
    else
    {
        attitude_line[0] = '\0';
    }

    display_result = display_sensor_lines(temperature_line, attitude_line,
                                          yaw_line);
    if (display_result != YDRASIL_DRIVER_OK)
    {
        rt_kprintf("SSD1306 update failed: %d\n", display_result);
        return display_result;
    }
    if (want_temperature != 0 &&
        temperature_result != YDRASIL_DRIVER_OK)
    {
        return temperature_result;
    }
    if (want_imu != 0 && imu_result != YDRASIL_DRIVER_OK)
    {
        return imu_result;
    }
    return YDRASIL_DRIVER_OK;
}
MSH_CMD_EXPORT_ALIAS(sensor_command, sensor,
                     Read LM75B/MS601M and update the SSD1306);
