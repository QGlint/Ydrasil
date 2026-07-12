#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, endian_words
  li t1, 0x80ff7f01
  sw t1, 4(t0)

  CHECK_BYTE(2, t0, 4, 0x01)
  CHECK_BYTE(3, t0, 5, 0x7f)
  CHECK_BYTE(4, t0, 6, 0xff)
  CHECK_BYTE(5, t0, 7, 0x80)

  li TESTNUM, 6
  lb t2, 6(t0)
  li t3, -1
  bne t2, t3, fail
  li TESTNUM, 7
  lb t2, 7(t0)
  li t3, -128
  bne t2, t3, fail
  li TESTNUM, 8
  lhu t2, 4(t0)
  li t3, 0x7f01
  bne t2, t3, fail
  li TESTNUM, 9
  lh t2, 6(t0)
  li t3, 0xffff80ff
  bne t2, t3, fail
  lw t2, 4(t0)
  CHECK_EQ_IMM(10, t2, 0x80ff7f01)
  lw t2, 0(t0)
  CHECK_EQ_IMM(11, t2, 0x13579bdf)
  lw t2, 8(t0)
  CHECK_EQ_IMM(12, t2, 0x2468ace0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
endian_words:
  .word 0x13579bdf
  .word 0
  .word 0x2468ace0
RVTEST_DATA_END
