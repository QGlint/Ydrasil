#include <stdint.h>
#include "sort_data.h"

#define MERGE_GUARD_WORDS 2u
static uint32_t merge_temp_ok;

static int32_t merge_canary(uint32_t index)
{
    return (int32_t)(0x4d455247u ^ (index * 0x9e3779b9u));
}

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
    int32_t arena[SORT_MAX_DATA_COUNT + 2u * MERGE_GUARD_WORDS];
    int32_t *tmp = &arena[MERGE_GUARD_WORDS];
    uint32_t total = SORT_MAX_DATA_COUNT + 2u * MERGE_GUARD_WORDS;

    for (uint32_t i = 0; i < total; i++) arena[i] = merge_canary(i);

    for (uint32_t width = 1; width < len; width *= 2) {
        for (uint32_t left = 0; left < len; left += 2 * width) {
            uint32_t mid = left + width < len ? left + width : len;
            uint32_t right = left + 2 * width < len ? left + 2 * width : len;
            merge(data, tmp, left, mid, right);
        }
    }

    for (uint32_t i = 0; i < MERGE_GUARD_WORDS; i++) {
        if (arena[i] != merge_canary(i)) merge_temp_ok = 0u;
    }
    for (uint32_t i = MERGE_GUARD_WORDS + len; i < total; i++) {
        if (arena[i] != merge_canary(i)) merge_temp_ok = 0u;
    }
}

#define SORT_DIAGNOSTICS_RESET() do { merge_temp_ok = 1u; } while (0)
#define SORT_DIAGNOSTICS_CHECK(len) (merge_temp_ok)
#define SORT_NAME "merge_sort"
#include "sort_common.h"
