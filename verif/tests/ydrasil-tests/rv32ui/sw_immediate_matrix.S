#include "riscv_test.h"
#include "sw_test_macros.h"

#define TEST_IMM(testnum, immediate, value) \
  li TESTNUM, testnum;                    \
  la t0, immediate_target;                \
  li t1, value;                           \
  li t2, -(immediate);                    \
  add t3, t0, t2;                         \
  sw t1, immediate(t3);                   \
  lw t4, 0(t0);                           \
  bne t1, t4, fail

RVTEST_RV32U
RVTEST_CODE_BEGIN
  TEST_IMM(2, -2048, 0x00000002)
  TEST_IMM(3, -2044, 0x00000003)
  TEST_IMM(4, -1025, 0x00000004)
  TEST_IMM(5, -1024, 0x00000005)
  TEST_IMM(6,  -513, 0x00000006)
  TEST_IMM(7,  -512, 0x00000007)
  TEST_IMM(8,  -257, 0x00000008)
  TEST_IMM(9,  -256, 0x00000009)
  TEST_IMM(10, -129, 0x0000000a)
  TEST_IMM(11, -128, 0x0000000b)
  TEST_IMM(12,  -65, 0x0000000c)
  TEST_IMM(13,  -64, 0x0000000d)
  TEST_IMM(14,  -33, 0x0000000e)
  TEST_IMM(15,  -32, 0x0000000f)
  TEST_IMM(16,  -17, 0x00000010)
  TEST_IMM(17,  -16, 0x00000011)
  TEST_IMM(18,   -9, 0x00000012)
  TEST_IMM(19,   -8, 0x00000013)
  TEST_IMM(20,   -5, 0x00000014)
  TEST_IMM(21,   -4, 0x00000015)
  TEST_IMM(22,   -1, 0x00000016)
  TEST_IMM(23,    0, 0x00000017)
  TEST_IMM(24,    1, 0x00000018)
  TEST_IMM(25,    3, 0x00000019)
  TEST_IMM(26,    4, 0x0000001a)
  TEST_IMM(27,    7, 0x0000001b)
  TEST_IMM(28,    8, 0x0000001c)
  TEST_IMM(29,   15, 0x0000001d)
  TEST_IMM(30,   16, 0x0000001e)
  TEST_IMM(31,   31, 0x0000001f)
  TEST_IMM(32,   32, 0x00000020)
  TEST_IMM(33,   63, 0x00000021)
  TEST_IMM(34,   64, 0x00000022)
  TEST_IMM(35,  127, 0x00000023)
  TEST_IMM(36,  128, 0x00000024)
  TEST_IMM(37,  255, 0x00000025)
  TEST_IMM(38,  256, 0x00000026)
  TEST_IMM(39,  511, 0x00000027)
  TEST_IMM(40,  512, 0x00000028)
  TEST_IMM(41, 1023, 0x00000029)
  TEST_IMM(42, 1024, 0x0000002a)
  TEST_IMM(43, 2044, 0x0000002b)
  TEST_IMM(44, 2047, 0x0000002c)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
  .space 2048
immediate_target:
  .word 0
  .space 2048
RVTEST_DATA_END
