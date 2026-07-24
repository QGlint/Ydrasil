#include <rtthread.h>
#include <string.h>

#include <utest.h>

#include "board.h"

int utest_testcase_run(int argc, char **argv);

static volatile int smoke_test_ran;

static void utest_smoke_unit(void)
{
    char actual[] = "ydrasil";
    const char expected[] = "ydrasil";
    char buffer_a[] = {1, 2, 3, 4};
    const char buffer_b[] = {1, 2, 3, 4};
    void *memory;

    smoke_test_ran = 1;
    uassert_int_equal(2 + 2, 4);
    uassert_int_equal((int)strlen(actual), 7);
    uassert_str_equal(actual, expected);
    uassert_buf_equal(buffer_a, buffer_b, sizeof(buffer_a));

    memory = rt_malloc(32);
    uassert_not_null(memory);
    if (memory != RT_NULL)
    {
        rt_memset(memory, 0x5a, 32);
        rt_free(memory);
    }
}

static void utest_smoke_case(void)
{
    UTEST_UNIT_RUN(utest_smoke_unit);
}

UTEST_TC_EXPORT(utest_smoke_case, "rtthread.smoke", RT_NULL, RT_NULL, 1);

static int run_smoke_testcase(void)
{
    char *argv[] = {(char *)"utest_run", (char *)"rtthread.smoke"};
    return utest_testcase_run(2, argv);
}

int main(void)
{
    utest_t result;
    int run_result;

    rt_kprintf("RT-Thread Utest smoke start\n");
    smoke_test_ran = 0;
    run_result = run_smoke_testcase();
    result = utest_handle_get();

    if (run_result == RT_EOK && smoke_test_ran && result != RT_NULL &&
        result->error == UTEST_PASSED && result->failed_num == 0)
    {
        rt_kprintf("RT_UTEST PASS tests=1 assertions=%u\n", result->passed_num);
    }
    else
    {
        rt_kprintf("RT_UTEST FAIL tests=1 assertions_passed=%u assertions_failed=%u\n",
                   result != RT_NULL ? result->passed_num : 0,
                   result != RT_NULL ? result->failed_num : 1);
    }

    ydrasil_sim_end();
    while (1)
    {
    }
}
