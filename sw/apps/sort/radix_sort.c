#include <stdint.h>
#include "sort_data.h"

#define RADIX_GUARD_WORDS 2u
#define RADIX_BUCKET_COUNT 256u
static uint32_t radix_temp_ok;

static int32_t radix_canary(uint32_t index)
{
    return (int32_t)(0x52414458u ^ (index * 0x9e3779b9u));
}

static void sort_data(int32_t *data, uint32_t len)
{
    int32_t arena[SORT_MAX_DATA_COUNT + 2u * RADIX_GUARD_WORDS];
    int32_t *tmp = &arena[RADIX_GUARD_WORDS];
    uint32_t total = SORT_MAX_DATA_COUNT + 2u * RADIX_GUARD_WORDS;

    for (uint32_t i = 0; i < total; i++) arena[i] = radix_canary(i);

    for (uint32_t shift = 0; shift < 32; shift += 8) {
        volatile uint32_t count_arena[RADIX_BUCKET_COUNT
                                      + 2u * RADIX_GUARD_WORDS];
        volatile uint32_t *count = &count_arena[RADIX_GUARD_WORDS];

        for (uint32_t i = 0; i < RADIX_BUCKET_COUNT + 2u * RADIX_GUARD_WORDS;
             i++) {
            count_arena[i] = (uint32_t)radix_canary(i);
        }
        for (uint32_t i = 0; i < RADIX_BUCKET_COUNT; i++) count[i] = 0;
        for (uint32_t i = 0; i < len; i++) {
            uint32_t key = ((uint32_t)data[i]) ^ 0x80000000u;
            count[(key >> shift) & 0xffu]++;
        }
        for (uint32_t i = 1; i < RADIX_BUCKET_COUNT; i++) {
            count[i] += count[i - 1];
        }
        for (uint32_t i = len; i > 0; i--) {
            uint32_t key = ((uint32_t)data[i - 1]) ^ 0x80000000u;
            tmp[--count[(key >> shift) & 0xffu]] = data[i - 1];
        }
        for (uint32_t i = 0; i < len; i++) data[i] = tmp[i];
        for (uint32_t i = 0; i < RADIX_GUARD_WORDS; i++) {
            if (count_arena[i] != (uint32_t)radix_canary(i)) {
                radix_temp_ok = 0u;
            }
            if (count_arena[RADIX_GUARD_WORDS + RADIX_BUCKET_COUNT + i]
                != (uint32_t)radix_canary(RADIX_GUARD_WORDS
                                          + RADIX_BUCKET_COUNT + i)) {
                radix_temp_ok = 0u;
            }
        }
    }

    for (uint32_t i = 0; i < RADIX_GUARD_WORDS; i++) {
        if (arena[i] != radix_canary(i)) radix_temp_ok = 0u;
    }
    for (uint32_t i = RADIX_GUARD_WORDS + len; i < total; i++) {
        if (arena[i] != radix_canary(i)) radix_temp_ok = 0u;
    }
}

#define SORT_DIAGNOSTICS_RESET() do { radix_temp_ok = 1u; } while (0)
#define SORT_DIAGNOSTICS_CHECK(len) (radix_temp_ok)
#define SORT_NAME "radix_sort"
#include "sort_common.h"
