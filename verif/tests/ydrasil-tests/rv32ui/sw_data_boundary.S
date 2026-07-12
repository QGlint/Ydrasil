#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, data_target

#define TEST_WORD(testnum, value) \
  li TESTNUM, testnum;            \
  li t1, value;                   \
  sw t1, 0(t0);                   \
  lw t2, 0(t0);                   \
  bne t1, t2, fail;               \
  lw t3, -4(t0);                  \
  li t4, 0x13579bdf;              \
  bne t3, t4, fail;               \
  lw t3, 4(t0);                   \
  li t4, 0x2468ace0;              \
  bne t3, t4, fail

  TEST_WORD(2, 0x00000000)
  TEST_WORD(3, 0xffffffff)
  TEST_WORD(4, 0x80000000)
  TEST_WORD(5, 0x7fffffff)
  TEST_WORD(6, 0xaaaaaaaa)
  TEST_WORD(7, 0x55555555)
  TEST_WORD(8, 0x01234567)
  TEST_WORD(9, 0xfedcba98)

  li t1, 1
  li t2, 32
10:
  li TESTNUM, 10
  sw t1, 0(t0)
  lw t3, 0(t0)
  bne t1, t3, fail
  slli t1, t1, 1
  addi t2, t2, -1
  bnez t2, 10b

  li t1, 1
  li t2, 32
11:
  li TESTNUM, 11
  not t3, t1
  sw t3, 0(t0)
  lw t4, 0(t0)
  bne t3, t4, fail
  slli t1, t1, 1
  addi t2, t2, -1
  bnez t2, 11b

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
  .word 0x13579bdf
data_target:
  .word 0xdeadbeef
  .word 0x2468ace0
RVTEST_DATA_END
