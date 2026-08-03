#include <stdint.h>

static void sift_down(int32_t *data, uint32_t root, uint32_t len)
{
    while (root * 2 + 1 < len) {
        uint32_t child = root * 2 + 1;
        if (child + 1 < len && data[child] < data[child + 1]) child++;
        if (data[root] >= data[child]) return;
        int32_t tmp = data[root];
        data[root] = data[child];
        data[child] = tmp;
        root = child;
    }
}

static void sort_data(int32_t *data, uint32_t len)
{
    for (uint32_t i = len / 2; i > 0; i--) sift_down(data, i - 1, len);
    for (uint32_t end = len; end > 1; end--) {
        int32_t tmp = data[0];
        data[0] = data[end - 1];
        data[end - 1] = tmp;
        sift_down(data, 0, end - 1);
    }
}

#define SORT_NAME "heap_sort"
#include "sort_common.h"
