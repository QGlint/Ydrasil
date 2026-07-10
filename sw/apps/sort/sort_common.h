#ifndef SORT_COMMON_H
#define SORT_COMMON_H

#include <stdint.h>

#include "sort_data.h"
#include "xprintf.h"

#define LED_REG ((volatile uint32_t *)0x80200040u)

static uint32_t sort_checksum(const int32_t *data, uint32_t len)
{
    uint32_t checksum = 0x13579bdfu;

    for (uint32_t i = 0; i < len; i++) {
        checksum ^= (uint32_t)data[i] + 0x9e3779b9u
                    + (checksum << 6) + (checksum >> 2);
    }
    return checksum;
}

static int sort_run(void)
{
    int32_t data[SORT_DATA_COUNT] = SORT_DATA_INITIALIZER;

    sort_data(data, SORT_DATA_COUNT);
    for (uint32_t i = 1; i < SORT_DATA_COUNT; i++) {
        if (data[i - 1] > data[i]) {
            xprintf("SORT FAIL name=%s index=%u\n", SORT_NAME, i);
            *LED_REG = 0x00bad001u;
            return 1;
        }
    }

    xprintf("SORT PASS name=%s count=%u checksum=0x%08x first=%d last=%d\n",
            SORT_NAME, SORT_DATA_COUNT, sort_checksum(data, SORT_DATA_COUNT),
            data[0], data[SORT_DATA_COUNT - 1]);
    *LED_REG = 0x00504f53u;
    return 0;
}

int main(void)
{
    (void)sort_run();
    while (1) {
    }
}

#endif
