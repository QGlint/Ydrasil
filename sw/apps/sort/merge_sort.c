#include <stdint.h>

static void merge(int32_t *data, int32_t *tmp, uint32_t left,
                  uint32_t mid, uint32_t right)
{
    uint32_t i = left;
    uint32_t j = mid;
    uint32_t out = left;

    while (i < mid && j < right) {
        tmp[out++] = data[i] <= data[j] ? data[i++] : data[j++];
    }
    while (i < mid) tmp[out++] = data[i++];
    while (j < right) tmp[out++] = data[j++];
    for (i = left; i < right; i++) data[i] = tmp[i];
}

static void sort_data(int32_t *data, uint32_t len)
{
    int32_t tmp[100];

    for (uint32_t width = 1; width < len; width *= 2) {
        for (uint32_t left = 0; left < len; left += 2 * width) {
            uint32_t mid = left + width < len ? left + width : len;
            uint32_t right = left + 2 * width < len ? left + 2 * width : len;
            merge(data, tmp, left, mid, right);
        }
    }
}

#define SORT_NAME "merge_sort"
#include "sort_common.h"
