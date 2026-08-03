#include <stdint.h>

static void sort_data(int32_t *data, uint32_t len)
{
    for (uint32_t end = len; end > 1; end--) {
        int swapped = 0;
        for (uint32_t i = 1; i < end; i++) {
            if (data[i - 1] > data[i]) {
                int32_t tmp = data[i - 1];
                data[i - 1] = data[i];
                data[i] = tmp;
                swapped = 1;
            }
        }
        if (!swapped) {
            break;
        }
    }
}

#define SORT_NAME "bubble_sort"
#include "sort_common.h"
