#include <stddef.h>

#include "lm75b.h"
#include "monitor_bus.h"

#define LM75B_I2C_ADDRESS 0x48U
#define LM75B_TEMPERATURE_REGISTER 0x00U

int lm75b_read_temperature_milli_c(int32_t *milli_celsius)
{
    uint8_t bytes[2];
    int16_t raw;
    int result;

    if (milli_celsius == NULL)
    {
        return YDRASIL_DRIVER_EINVAL;
    }
    result = ydrasil_bus_i2c_read_register(LM75B_I2C_ADDRESS,
                                            LM75B_TEMPERATURE_REGISTER,
                                            bytes, sizeof(bytes));
    if (result != YDRASIL_DRIVER_OK)
    {
        return result;
    }

    raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
    *milli_celsius = ((int32_t)raw >> 5) * 125;
    return YDRASIL_DRIVER_OK;
}
