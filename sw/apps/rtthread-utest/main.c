#include <rtthread.h>
#include <string.h>

#include <utest.h>

#include "board.h"

int utest_testcase_run(int argc, char **argv);

static volatile int smoke_test_ran;
static volatile int exception_test_ran;
static volatile rt_uint32_t exception_trap_count;
static volatile rt_uint32_t exception_trap_cause[3];
static volatile rt_uint32_t exception_trap_epc[3];
static volatile rt_uint32_t exception_load_value = 0x12345678U;

__attribute__((naked, aligned(4))) static void utest_exception_handler(void)
{
    __asm__ volatile(
        "la t0, exception_trap_count\n"
        "lw t1, 0(t0)\n"
        "slli t2, t1, 2\n"
        "la t3, exception_trap_cause\n"
        "add t3, t3, t2\n"
        "csrr t4, mcause\n"
        "sw t4, 0(t3)\n"
        "la t3, exception_trap_epc\n"
        "add t3, t3, t2\n"
        "csrr t4, mepc\n"
        "sw t4, 0(t3)\n"
        "addi t1, t1, 1\n"
        "sw t1, 0(t0)\n"
        "addi t4, t4, 4\n"
        "csrw mepc, t4\n"
        "mret\n");
}

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

static void utest_exception_unit(void)
{
    rt_uint32_t old_mtvec;
    rt_uint32_t old_mstatus;
    rt_uint32_t expected_epc[3];
    rt_uint32_t value;
    rt_uint32_t marker = 0;
    rt_uint32_t handler = (rt_uint32_t)(rt_ubase_t)utest_exception_handler;
    const rt_uint32_t mie_mask = 1U << 3;

    exception_test_ran = 1;
    exception_trap_count = 0;
    __asm__ volatile("csrr %0, mtvec" : "=r"(old_mtvec));
    __asm__ volatile("csrrc %0, mstatus, %1"
                     : "=r"(old_mstatus) : "r"(mie_mask) : "memory");
    __asm__ volatile("csrw mtvec, %0" :: "r"(handler) : "memory");

    /* The wrong-path ECALL must be killed before the target ECALL traps. */
    __asm__ volatile(
        "li t0, 1\n"
        "beq t0, t0, 2f\n"
        "ecall\n"
        "2: la %0, 3f\n"
        "3: ecall"
        : "=r"(expected_epc[0])
        :
        : "t0", "t1", "t2", "t3", "t4", "memory");

    /* The dependent add must complete before the following trap is accepted. */
    __asm__ volatile(
        "lw t0, 0(%2)\n"
        "addi %1, t0, 1\n"
        "la %0, 1f\n"
        "1: ecall"
        : "=r"(expected_epc[1]), "=r"(value)
        : "r"(&exception_load_value)
        : "t0", "t1", "t2", "t3", "t4", "memory");

    __asm__ volatile(
        "la %0, 1f\n"
        "1: ebreak\n"
        "addi %1, %1, 1"
        : "=r"(expected_epc[2]), "+r"(marker)
        :
        : "t0", "t1", "t2", "t3", "t4", "memory");

    __asm__ volatile(
        "csrw mtvec, %0\n"
        "csrw mstatus, %1"
        :
        : "r"(old_mtvec), "r"(old_mstatus)
        : "memory");

    uassert_int_equal(exception_trap_count, 3);
    uassert_int_equal(exception_trap_cause[0], 11);
    uassert_int_equal(exception_trap_cause[1], 11);
    uassert_int_equal(exception_trap_cause[2], 3);
    uassert_true(exception_trap_epc[0] == expected_epc[0]);
    uassert_true(exception_trap_epc[1] == expected_epc[1]);
    uassert_true(exception_trap_epc[2] == expected_epc[2]);
    uassert_int_equal(value, exception_load_value + 1);
    uassert_int_equal(marker, 1);
}

static void utest_smoke_case(void)
{
    UTEST_UNIT_RUN(utest_smoke_unit);
    UTEST_UNIT_RUN(utest_exception_unit);
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
    exception_test_ran = 0;
    run_result = run_smoke_testcase();
    result = utest_handle_get();

    if (run_result == RT_EOK && smoke_test_ran && exception_test_ran &&
        result != RT_NULL &&
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
