#include <stdint.h>

#include "platform.h"
#include "xprintf.h"

#define LED_REG ((volatile uint32_t *)0x80200040u)

static void insertion_sort(int32_t *data, uint32_t len)
{
    for (uint32_t i = 1; i < len; i++) {
        int32_t key = data[i];
        uint32_t j = i;

        while ((j > 0) && (data[j - 1] > key)) {
            data[j] = data[j - 1];
            j--;
        }
        data[j] = key;
    }
}

static uint32_t checksum_sorted(const int32_t *data, uint32_t len)
{
    uint32_t checksum = 0x13579bdfu;

    for (uint32_t i = 0; i < len; i++) {
        checksum ^= (uint32_t)data[i] + 0x9e3779b9u + (checksum << 6) + (checksum >> 2);
    }

    return checksum;
}

int main(void)
{
    int32_t data[] = {
        42, -7, 1024, 0, 17, -256, 99, 3,
        3, 2048, -1, 77, 12, -99, 512, 6
    };
    const uint32_t len = sizeof(data) / sizeof(data[0]);

    insertion_sort(data, len);

    for (uint32_t i = 1; i < len; i++) {
        if (data[i - 1] > data[i]) {
            xprintf("SORT FAIL index=%u\n", i);
            *LED_REG = 0x00bad001u;
            while (1) {
            }
        }
    }

    xprintf("SORT PASS checksum=0x%08x first=%d last=%d\n",
            checksum_sorted(data, len), data[0], data[len - 1]);
    *LED_REG = 0x00504f53u;

    while (1) {
    }
}
