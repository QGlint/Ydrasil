#include <stdint.h>

static void sort_data(int32_t *data, uint32_t len)
{
    for (uint32_t i = 1; i < len; i++) {
        int32_t key = data[i];
        uint32_t j = i;
        while (j > 0 && data[j - 1] > key) {
            data[j] = data[j - 1];
            j--;
        }
        data[j] = key;
    }
}

#define SORT_NAME "insertion_sort"
#include "sort_common.h"
