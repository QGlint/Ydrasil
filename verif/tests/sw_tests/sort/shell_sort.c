#include <stdint.h>

static void sort_data(int32_t *data, uint32_t len)
{
    for (uint32_t gap = len / 2; gap > 0; gap /= 2) {
        for (uint32_t i = gap; i < len; i++) {
            int32_t value = data[i];
            uint32_t j = i;
            while (j >= gap && data[j - gap] > value) {
                data[j] = data[j - gap];
                j -= gap;
            }
            data[j] = value;
        }
    }
}

#define SORT_NAME "shell_sort"
#include "sort_common.h"
