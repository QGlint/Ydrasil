#include <stddef.h>

#include "atk_ms601m.h"
#include "monitor_bus.h"

#define MS601M_BAUD           115200U
#define MS601M_FRAME_DATA_MAX 28U
#define MS601M_ATTITUDE_ID    0x01U

enum parser_state
{
    WAIT_HEAD_LOW,
    WAIT_HEAD_HIGH,
    WAIT_ID,
    WAIT_LENGTH,
    WAIT_DATA,
    WAIT_CHECKSUM
};

static int16_t read_le_i16(const uint8_t *data)
{
    return (int16_t)(((uint16_t)data[1] << 8) | data[0]);
}

static int32_t attitude_tenth_degrees(int16_t raw)
{
    return ((int32_t)raw * 1800) / 32768;
}

static enum parser_state parser_restart(uint8_t byte, uint8_t *checksum)
{
    if (byte == 0x55U)
    {
        *checksum = byte;
        return WAIT_HEAD_HIGH;
    }
    return WAIT_HEAD_LOW;
}

int ms601m_read_attitude(struct ms601m_attitude *attitude,
                         uint32_t timeout_ms)
{
    enum parser_state state = WAIT_HEAD_LOW;
    uint8_t frame_id = 0U;
    uint8_t frame_length = 0U;
    uint8_t frame_data[MS601M_FRAME_DATA_MAX];
    uint8_t data_index = 0U;
    uint8_t checksum = 0U;
    uint32_t start_ms;

    if (attitude == NULL || timeout_ms == 0U)
    {
        return YDRASIL_DRIVER_EINVAL;
    }

    ydrasil_bus_uart1_reset(MS601M_BAUD);
    start_ms = ydrasil_bus_millis();
    while ((uint32_t)(ydrasil_bus_millis() - start_ms) < timeout_ms)
    {
        uint8_t byte;

        if (ydrasil_bus_uart1_getc(&byte) != YDRASIL_DRIVER_OK)
        {
            ydrasil_bus_delay_ms(1U);
            continue;
        }

        switch (state)
        {
        case WAIT_HEAD_LOW:
            if (byte == 0x55U)
            {
                checksum = byte;
                state = WAIT_HEAD_HIGH;
            }
            break;
        case WAIT_HEAD_HIGH:
            if (byte == 0x55U)
            {
                checksum = (uint8_t)(checksum + byte);
                state = WAIT_ID;
            }
            else
            {
                state = parser_restart(byte, &checksum);
            }
            break;
        case WAIT_ID:
            frame_id = byte;
            checksum = (uint8_t)(checksum + byte);
            state = WAIT_LENGTH;
            break;
        case WAIT_LENGTH:
            if (byte > MS601M_FRAME_DATA_MAX)
            {
                state = parser_restart(byte, &checksum);
                break;
            }
            frame_length = byte;
            data_index = 0U;
            checksum = (uint8_t)(checksum + byte);
            state = frame_length == 0U ? WAIT_CHECKSUM : WAIT_DATA;
            break;
        case WAIT_DATA:
            frame_data[data_index++] = byte;
            checksum = (uint8_t)(checksum + byte);
            if (data_index == frame_length)
            {
                state = WAIT_CHECKSUM;
            }
            break;
        case WAIT_CHECKSUM:
            if (byte == checksum && frame_id == MS601M_ATTITUDE_ID &&
                frame_length >= 6U)
            {
                attitude->roll_tenth_degree =
                    attitude_tenth_degrees(read_le_i16(&frame_data[0]));
                attitude->pitch_tenth_degree =
                    attitude_tenth_degrees(read_le_i16(&frame_data[2]));
                attitude->yaw_tenth_degree =
                    attitude_tenth_degrees(read_le_i16(&frame_data[4]));
                return YDRASIL_DRIVER_OK;
            }
            state = parser_restart(byte, &checksum);
            break;
        default:
            state = WAIT_HEAD_LOW;
            break;
        }
    }
    return YDRASIL_DRIVER_ETIMEOUT;
}
