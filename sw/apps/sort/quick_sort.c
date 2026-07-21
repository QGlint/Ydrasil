#include <stdint.h>

static uint32_t quick_sort_depth;
static uint32_t quick_sort_max_depth;

static void quick_sort_range(int32_t *data, int32_t left, int32_t right)
{
    quick_sort_depth++;
    if (quick_sort_depth > quick_sort_max_depth) {
        quick_sort_max_depth = quick_sort_depth;
    }
    while (left < right) {
        int32_t i = left;
        int32_t j = right;
        int32_t pivot = data[left + (right - left) / 2];

        while (i <= j) {
            while (data[i] < pivot) i++;
            while (data[j] > pivot) j--;
            if (i <= j) {
                int32_t tmp = data[i];
                data[i++] = data[j];
                data[j--] = tmp;
            }
        }
        if (j - left < right - i) {
            if (left < j) quick_sort_range(data, left, j);
            left = i;
        } else {
            if (i < right) quick_sort_range(data, i, right);
            right = j;
        }
    }
    quick_sort_depth--;
}

static void sort_data(int32_t *data, uint32_t len)
{
    if (len > 1) quick_sort_range(data, 0, (int32_t)len - 1);
}

#define SORT_DIAGNOSTICS_RESET() \
    do { quick_sort_depth = 0u; quick_sort_max_depth = 0u; } while (0)
#define SORT_DIAGNOSTICS_CHECK(len) \
    (quick_sort_depth == 0u && ((len) < 2u ? quick_sort_max_depth == 0u \
                                           : quick_sort_max_depth <= 8u))
#define SORT_NAME "quick_sort"
#include "sort_common.h"
