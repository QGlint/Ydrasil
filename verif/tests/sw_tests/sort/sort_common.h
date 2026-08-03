#ifndef SORT_COMMON_H
#define SORT_COMMON_H

#include <stdint.h>

#include "sort_data.h"
#include "xprintf.h"

#define LED_REG ((volatile uint32_t *)0x80200040u)
#define SORT_GUARD_WORDS 4u
#define SORT_CHECKS_PER_CASE 5u

#ifndef SORT_DIAGNOSTICS_RESET
#define SORT_DIAGNOSTICS_RESET() ((void)0)
#endif

#ifndef SORT_DIAGNOSTICS_CHECK
#define SORT_DIAGNOSTICS_CHECK(len) (1)
#endif

struct sort_multiset_hash {
    uint32_t sum;
    uint32_t square_sum;
    uint32_t xor_mix;
};

static uint32_t sort_mix32(uint32_t value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

static uint32_t sort_rotate_left(uint32_t value, uint32_t shift)
{
    shift &= 31u;
    return shift == 0u ? value : (value << shift) | (value >> (32u - shift));
}

static struct sort_multiset_hash sort_hash_multiset(const int32_t *data,
                                                     uint32_t len)
{
    struct sort_multiset_hash hash = {0x13579bdfu, 0x2468ace0u, 0xa5a5a5a5u};

    for (uint32_t i = 0; i < len; i++) {
        uint32_t value = sort_mix32((uint32_t)data[i] ^ 0x80000000u);
        hash.sum += value;
        hash.square_sum += value * value;
        hash.xor_mix ^= sort_rotate_left(value, value);
    }
    return hash;
}

static int sort_hash_equal(struct sort_multiset_hash left,
                           struct sort_multiset_hash right)
{
    return left.sum == right.sum && left.square_sum == right.square_sum
           && left.xor_mix == right.xor_mix;
}

static uint32_t sort_checksum(const int32_t *data, uint32_t len)
{
    uint32_t checksum = 0x13579bdfu;

    for (uint32_t i = 0; i < len; i++) {
        checksum ^= (uint32_t)data[i] + 0x9e3779b9u
                    + (checksum << 6) + (checksum >> 2);
    }
    return checksum;
}

static int32_t sort_canary(uint32_t index)
{
    return (int32_t)(0xc001c0deu ^ (index * 0x9e3779b9u));
}

static void sort_reference(int32_t *data, uint32_t len)
{
    for (uint32_t i = 1; i < len; i++) {
        int32_t value = data[i];
        uint32_t j = i;
        while (j > 0u && data[j - 1u] > value) {
            data[j] = data[j - 1u];
            j--;
        }
        data[j] = value;
    }
}

static uint32_t sort_random_next(uint32_t *state)
{
    uint32_t value = *state;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    *state = value;
    return value;
}

static void sort_fill_generated(int32_t *data, uint32_t len, uint32_t pattern)
{
    static const uint32_t seeds[] = {
        0x12345678u, 0x9e3779b9u, 0xc001d00du
    };
    uint32_t random_state = pattern >= 6u ? seeds[pattern - 6u] : 0u;

    for (uint32_t i = 0; i < len; i++) {
        switch (pattern) {
        case 0u:
            data[i] = (int32_t)i - (int32_t)(len / 2u);
            break;
        case 1u:
            data[i] = (int32_t)(len - 1u - i) - (int32_t)(len / 2u);
            break;
        case 2u:
            data[i] = -17;
            break;
        case 3u:
            data[i] = (int32_t)((i * 17u + 3u) % 7u) - 3;
            break;
        case 4u:
            data[i] = 0;
            break;
        case 5u: {
            static const int32_t extremes[] = {
                INT32_MIN, INT32_MAX, -1, 0, 1, INT32_MAX, INT32_MIN
            };
            data[i] = extremes[i % (sizeof(extremes) / sizeof(extremes[0]))];
            break;
        }
        default: {
            data[i] = (int32_t)sort_random_next(&random_state);
            break;
        }
        }
    }

    if (pattern == 4u && len != 0u) {
        data[len / 2u] = (len & 1u) ? INT32_MIN : INT32_MAX;
    }
}

static void sort_prepare_arena(int32_t *arena, const int32_t *input,
                               uint32_t len)
{
    uint32_t total = SORT_MAX_DATA_COUNT + 2u * SORT_GUARD_WORDS;

    for (uint32_t i = 0; i < total; i++) arena[i] = sort_canary(i);
    for (uint32_t i = 0; i < len; i++) arena[SORT_GUARD_WORDS + i] = input[i];
}

static int sort_guards_valid(const int32_t *arena, uint32_t len)
{
    uint32_t total = SORT_MAX_DATA_COUNT + 2u * SORT_GUARD_WORDS;

    for (uint32_t i = 0; i < SORT_GUARD_WORDS; i++) {
        if (arena[i] != sort_canary(i)) return 0;
    }
    for (uint32_t i = SORT_GUARD_WORDS + len; i < total; i++) {
        if (arena[i] != sort_canary(i)) return 0;
    }
    return 1;
}

static int sort_case(const int32_t *input, uint32_t len, uint32_t case_id,
                     uint32_t *suite_signature)
{
    int32_t arena[SORT_MAX_DATA_COUNT + 2u * SORT_GUARD_WORDS];
    int32_t reference[SORT_MAX_DATA_COUNT];
    int32_t *data = &arena[SORT_GUARD_WORDS];
    struct sort_multiset_hash before;

    for (uint32_t i = 0; i < len; i++) reference[i] = input[i];
    sort_prepare_arena(arena, input, len);
    before = sort_hash_multiset(data, len);
    sort_reference(reference, len);
    SORT_DIAGNOSTICS_RESET();
    sort_data(data, len);

    if (!sort_guards_valid(arena, len)) {
        xprintf("SORT FAIL name=%s case=%u len=%u reason=guard\n",
                SORT_NAME, case_id, len);
        return 0;
    }
    if (!sort_hash_equal(before, sort_hash_multiset(data, len))) {
        xprintf("SORT FAIL name=%s case=%u len=%u reason=multiset\n",
                SORT_NAME, case_id, len);
        return 0;
    }
    for (uint32_t i = 0; i < len; i++) {
        if (data[i] != reference[i]) {
            xprintf("SORT FAIL name=%s case=%u len=%u reason=reference index=%u\n",
                    SORT_NAME, case_id, len, i);
            return 0;
        }
    }
    for (uint32_t i = 1; i < len; i++) {
        if (data[i - 1u] > data[i]) {
            xprintf("SORT FAIL name=%s case=%u len=%u reason=order index=%u\n",
                    SORT_NAME, case_id, len, i);
            return 0;
        }
    }
    if (!SORT_DIAGNOSTICS_CHECK(len)) {
        xprintf("SORT FAIL name=%s case=%u len=%u reason=algorithm_diag\n",
                SORT_NAME, case_id, len);
        return 0;
    }

    *suite_signature ^= sort_mix32(sort_checksum(data, len) + case_id);
    return 1;
}

static int sort_run(void)
{
    static const uint32_t lengths[] = {0u, 1u, 2u, 3u, 31u, 32u, 33u,
                                       99u, 100u, 101u};
    static const int32_t legacy[SORT_LEGACY_DATA_COUNT] =
        SORT_LEGACY_DATA_INITIALIZER;
    int32_t input[SORT_MAX_DATA_COUNT];
    uint32_t case_id = 0u;
    uint32_t checks = 0u;
    uint32_t signature = 0x6d2b79f5u;

    for (uint32_t pattern = 0; pattern < 9u; pattern++) {
        for (uint32_t length_index = 0;
             length_index < sizeof(lengths) / sizeof(lengths[0]);
             length_index++) {
            uint32_t len = lengths[length_index];
            sort_fill_generated(input, len, pattern);
            if (!sort_case(input, len, case_id, &signature)) goto fail;
            case_id++;
            checks += SORT_CHECKS_PER_CASE;
        }
    }

    if (!sort_case(legacy, SORT_LEGACY_DATA_COUNT, case_id, &signature)) goto fail;
    case_id++;
    checks += SORT_CHECKS_PER_CASE;
    if (case_id != SORT_TOTAL_CASE_COUNT) goto fail;

    xprintf("SORT SUITE PASS name=%s cases=%u checks=%u signature=0x%08x\n",
            SORT_NAME, case_id, checks, signature);
    *LED_REG = 0x00504f53u;
    return 0;

fail:
    *LED_REG = 0x00bad001u;
    return 1;
}

int main(void)
{
    (void)sort_run();
    while (1) {
    }
}

#endif
