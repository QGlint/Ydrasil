#include <stdint.h>

static void sort_data(int32_t *data, uint32_t len)
{
    int32_t tmp[100];

    for (uint32_t shift = 0; shift < 32; shift += 8) {
        volatile uint32_t count[256];
        for (uint32_t i = 0; i < 256; i++) count[i] = 0;
        for (uint32_t i = 0; i < len; i++) {
            uint32_t key = ((uint32_t)data[i]) ^ 0x80000000u;
            count[(key >> shift) & 0xffu]++;
        }
        for (uint32_t i = 1; i < 256; i++) count[i] += count[i - 1];
        for (uint32_t i = len; i > 0; i--) {
            uint32_t key = ((uint32_t)data[i - 1]) ^ 0x80000000u;
            tmp[--count[(key >> shift) & 0xffu]] = data[i - 1];
        }
        for (uint32_t i = 0; i < len; i++) data[i] = tmp[i];
    }
}

#define SORT_NAME "radix_sort"
#include "sort_common.h"
