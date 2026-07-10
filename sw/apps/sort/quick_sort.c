#include <stdint.h>

static void quick_sort_range(int32_t *data, int32_t left, int32_t right)
{
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
}

static void sort_data(int32_t *data, uint32_t len)
{
    if (len > 1) quick_sort_range(data, 0, (int32_t)len - 1);
}

#define SORT_NAME "quick_sort"
#include "sort_common.h"
