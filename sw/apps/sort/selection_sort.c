#include <stdint.h>

static void sort_data(int32_t *data, uint32_t len)
{
    for (uint32_t i = 0; i + 1 < len; i++) {
        uint32_t min = i;
        for (uint32_t j = i + 1; j < len; j++) {
            if (data[j] < data[min]) {
                min = j;
            }
        }
        if (min != i) {
            int32_t tmp = data[i];
            data[i] = data[min];
            data[min] = tmp;
        }
    }
}

#define SORT_NAME "selection_sort"
#include "sort_common.h"
