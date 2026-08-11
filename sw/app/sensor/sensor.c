#include <finsh.h>
#include <rtthread.h>
#include <stdint.h>
#include <string.h>

#include "atk_ms601m.h"
#include "monitor_bus.h"
#include "ssd1306.h"

#define SENSOR_DISPLAY_PERIOD_MS 200U
#define SENSOR_REPORT_PERIOD_MS  500U
#define SENSOR_IMU_TIMEOUT_MS    100U
#define SENSOR_THREAD_STACK_SIZE 4096U
#define SENSOR_THREAD_PRIORITY   22U
#define SENSOR_THREAD_TIMESLICE  10U
#define SENSOR_STOP_POLL_MS      10U
#define DISPLAY_STARTUP_STACK_SIZE 2048U
#define DISPLAY_STARTUP_PRIORITY   21U
#define DISPLAY_STARTUP_TIMESLICE  10U

static rt_thread_t sensor_thread;
static volatile rt_bool_t sensor_stop_requested;
static volatile rt_bool_t display_startup_pending;

struct sensor_refresh_state
{
    int display_initialized;
    int display_attitude_valid;
    struct ms601m_attitude display_attitude;
    int report_initialized;
    uint32_t report_last_ms;
    struct ms601m_attitude report_attitude;
    int sample_initialized;
    int sample_attitude_valid;
};

static uint32_t abs_i32(int32_t value)
{
    return value < 0 ? (uint32_t)(-value) : (uint32_t)value;
}

static void format_angle_value(char *buffer, size_t size, int32_t value)
{
    uint32_t magnitude = abs_i32(value);

    rt_snprintf(buffer, size, "%c%03u.%u", value < 0 ? '-' : '+',
                magnitude / 10U, magnitude % 10U);
}

static int attitude_changed(const struct ms601m_attitude *left,
                            const struct ms601m_attitude *right)
{
    return left->roll_tenth_degree != right->roll_tenth_degree ||
           left->pitch_tenth_degree != right->pitch_tenth_degree ||
           left->yaw_tenth_degree != right->yaw_tenth_degree;
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

static int display_lines(const char *line1, const char *line2,
                         const char *line3, const char *line4)
{
    return ssd1306_show_frame(line1, line2, line3, line4);
}

static int display_idle_screen(void)
{
    return ssd1306_show_frame("Ydrsail", "RT-Thread", "", "");
}

static void display_startup_worker(void *parameter)
{
    int result;

    (void)parameter;
    result = display_lines("Ydrsail", "RT-Thread", "", "");
    display_startup_pending = RT_FALSE;
    if (result != YDRASIL_DRIVER_OK)
    {
        rt_kprintf("OLED startup display failed: %d\n", result);
    }
}

int sensor_display_startup(void)
{
    rt_thread_t thread;
    int result;

    if (display_startup_pending != RT_FALSE)
    {
        return -RT_EBUSY;
    }

    display_startup_pending = RT_TRUE;
    thread = rt_thread_create("oled_init", display_startup_worker, RT_NULL,
                              DISPLAY_STARTUP_STACK_SIZE,
                              DISPLAY_STARTUP_PRIORITY,
                              DISPLAY_STARTUP_TIMESLICE);
    if (thread == RT_NULL)
    {
        display_startup_pending = RT_FALSE;
        return -RT_ENOMEM;
    }
    result = rt_thread_startup(thread);
    if (result != RT_EOK)
    {
        display_startup_pending = RT_FALSE;
        rt_thread_delete(thread);
        return result;
    }
    return YDRASIL_DRIVER_OK;
}

static int display_attitude(const struct ms601m_attitude *attitude,
                            int attitude_valid)
{
    char attitude_line[22] = "R NO DATA";
    char yaw_line[22] = "Y NO DATA";

    if (attitude_valid != 0)
    {
        char roll[7];
        char pitch[7];
        char yaw[7];

        format_angle_value(roll, sizeof(roll), attitude->roll_tenth_degree);
        format_angle_value(pitch, sizeof(pitch),
                           attitude->pitch_tenth_degree);
        format_angle_value(yaw, sizeof(yaw), attitude->yaw_tenth_degree);
        rt_snprintf(attitude_line, sizeof(attitude_line), "R %s P %s", roll,
                    pitch);
        rt_snprintf(yaw_line, sizeof(yaw_line), "Y %s", yaw);
    }

    return display_lines("Ydrsail", "ANGLE SENSOR", attitude_line, yaw_line);
}

static int refresh_sensors(struct sensor_refresh_state *state,
                           uint32_t now_ms)
{
    struct ms601m_attitude attitude = {0};
    int imu_result = ms601m_read_attitude(&attitude,
                                          SENSOR_IMU_TIMEOUT_MS);
    int attitude_valid = imu_result == YDRASIL_DRIVER_OK;
    int display_changed = !state->display_initialized ||
        state->display_attitude_valid != attitude_valid ||
        (attitude_valid != 0 &&
         attitude_changed(&attitude, &state->display_attitude));

    if (!state->sample_initialized ||
        state->sample_attitude_valid != attitude_valid)
    {
        if (attitude_valid == 0)
        {
            rt_kprintf("MS601M attitude timeout: %d\n", imu_result);
        }
        state->sample_initialized = 1;
        state->sample_attitude_valid = attitude_valid;
    }

    if (attitude_valid != 0 &&
        (!state->report_initialized ||
         (attitude_changed(&attitude, &state->report_attitude) &&
          (uint32_t)(now_ms - state->report_last_ms) >=
              SENSOR_REPORT_PERIOD_MS)))
    {
        print_attitude(&attitude);
        state->report_attitude = attitude;
        state->report_last_ms = now_ms;
        state->report_initialized = 1;
    }

    if (display_changed != 0)
    {
        int result = display_attitude(&attitude, attitude_valid);

        if (result != YDRASIL_DRIVER_OK)
        {
            rt_kprintf("OLED update failed: %d\n", result);
            return result;
        }
        state->display_initialized = 1;
        state->display_attitude_valid = attitude_valid;
        if (attitude_valid != 0)
        {
            state->display_attitude = attitude;
        }
    }
    return YDRASIL_DRIVER_OK;
}

static void wait_for_next_refresh(uint32_t start_ms)
{
    while (sensor_stop_requested == RT_FALSE)
    {
        uint32_t elapsed = ydrasil_bus_millis() - start_ms;
        uint32_t remaining;

        if (elapsed >= SENSOR_DISPLAY_PERIOD_MS)
        {
            break;
        }
        remaining = SENSOR_DISPLAY_PERIOD_MS - elapsed;
        ydrasil_bus_delay_ms(remaining < SENSOR_STOP_POLL_MS ?
                             remaining : SENSOR_STOP_POLL_MS);
    }
}

static void sensor_worker(void *parameter)
{
    int display_result;
    struct sensor_refresh_state state = {0};

    (void)parameter;

    while (sensor_stop_requested == RT_FALSE)
    {
        uint32_t start_ms = ydrasil_bus_millis();
        int result = refresh_sensors(&state, start_ms);

        if (result != YDRASIL_DRIVER_OK)
        {
            rt_kprintf("sensor refresh failed: %d\n", result);
        }
        wait_for_next_refresh(start_ms);
    }

    display_result = display_idle_screen();
    sensor_stop_requested = RT_FALSE;
    sensor_thread = RT_NULL;
    if (display_result != YDRASIL_DRIVER_OK)
    {
        rt_kprintf("OLED idle screen failed: %d\n", display_result);
    }
    rt_kprintf("sensor monitor stopped\n");
}

static int parse_sensor_mode(const char *argument)
{
    if (argument == RT_NULL || strcmp(argument, "all") == 0 ||
        strcmp(argument, "imu") == 0)
    {
        return YDRASIL_DRIVER_OK;
    }
    return YDRASIL_DRIVER_EINVAL;
}

static int sensor_command(int argc, char **argv)
{
    rt_thread_t thread;
    int result;

    if (argc == 2 && strcmp(argv[1], "stop") == 0)
    {
        if (sensor_thread == RT_NULL)
        {
            rt_kprintf("sensor monitor is not running\n");
            return YDRASIL_DRIVER_OK;
        }
        sensor_stop_requested = RT_TRUE;
        rt_kprintf("sensor monitor stop requested\n");
        return YDRASIL_DRIVER_OK;
    }
    if (argc > 2 || parse_sensor_mode(argc == 2 ? argv[1] : RT_NULL) !=
        YDRASIL_DRIVER_OK)
    {
        rt_kprintf("usage: sensor [all|imu|stop]\n");
        return YDRASIL_DRIVER_EINVAL;
    }
    if (sensor_thread != RT_NULL)
    {
        rt_kprintf("sensor monitor is already running\n");
        return -RT_EBUSY;
    }
    if (display_startup_pending != RT_FALSE)
    {
        rt_kprintf("OLED startup display is still in progress\n");
        return -RT_EBUSY;
    }

    sensor_stop_requested = RT_FALSE;
    thread = rt_thread_create("sensor", sensor_worker,
                              RT_NULL,
                              SENSOR_THREAD_STACK_SIZE,
                              SENSOR_THREAD_PRIORITY,
                              SENSOR_THREAD_TIMESLICE);
    if (thread == RT_NULL)
    {
        rt_kprintf("sensor monitor thread allocation failed\n");
        return -RT_ENOMEM;
    }
    sensor_thread = thread;
    result = rt_thread_startup(thread);
    if (result != RT_EOK)
    {
        sensor_thread = RT_NULL;
        rt_thread_delete(thread);
        rt_kprintf("sensor monitor thread startup failed: %d\n", result);
        return result;
    }

    rt_kprintf("sensor monitor started: 200 ms display, 500 ms report\n");
    return YDRASIL_DRIVER_OK;
}
MSH_CMD_EXPORT_ALIAS(sensor_command, sensor,
                     Start or stop the MS601M angle monitor);

struct oled_profile
{
    const char *name;
    enum ssd1306_controller controller;
    int flipped;
};

static int oled_test_command(int argc, char **argv)
{
    static const struct oled_profile profiles[] = {
        {"ssd1306", SSD1306_CONTROLLER_SSD1306, 1},
        {"ssd1306-flip", SSD1306_CONTROLLER_SSD1306, 0},
        {"sh1106", SSD1306_CONTROLLER_SH1106, 1},
        {"sh1106-flip", SSD1306_CONTROLLER_SH1106, 0}
    };
    static const char *test_lines[] = {
        "Ydrsail", "ANGLE TEST", "R+90.0 P-45.0", "Y+22.5"
    };
    const struct oled_profile *selected = RT_NULL;
    size_t index;
    int result;

    if (argc == 2)
    {
        for (index = 0U; index < sizeof(profiles) / sizeof(profiles[0]);
             index++)
        {
            if (strcmp(argv[1], profiles[index].name) == 0)
            {
                selected = &profiles[index];
                break;
            }
        }
    }
    if (selected == RT_NULL)
    {
        rt_kprintf("usage: oled_test "
                   "[ssd1306|ssd1306-flip|sh1106|sh1106-flip]\n");
        return YDRASIL_DRIVER_EINVAL;
    }
    if (sensor_thread != RT_NULL)
    {
        rt_kprintf("run 'sensor stop' before changing the OLED profile\n");
        return -RT_EBUSY;
    }
    if (display_startup_pending != RT_FALSE)
    {
        rt_kprintf("OLED startup display is still in progress\n");
        return -RT_EBUSY;
    }

    result = ssd1306_configure(selected->controller, selected->flipped);
    if (result == YDRASIL_DRIVER_OK)
    {
        result = ssd1306_show_frame(test_lines[0], test_lines[1],
                                    test_lines[2], test_lines[3]);
    }
    if (result != YDRASIL_DRIVER_OK)
    {
        rt_kprintf("OLED test failed: %d\n", result);
        return result;
    }

    rt_kprintf("OLED profile selected: %s\n", selected->name);
    return YDRASIL_DRIVER_OK;
}
MSH_CMD_EXPORT_ALIAS(oled_test_command, oled_test,
                     Select an OLED controller profile and show a test pattern);
