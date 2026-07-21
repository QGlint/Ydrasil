#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, subword_words
  li t0, 0x80ff7f01
  sw t0, 0(s0)
  li t0, 0x7f0180ff
  sw t0, 4(s0)

  lb t1, 0(s0)
  CHECK_EQ_IMM(2, t1, 1)
  lb t1, 1(s0)
  CHECK_EQ_IMM(3, t1, 0x7f)
  lb t1, 2(s0)
  CHECK_EQ_IMM(4, t1, -1)
  lb t1, 3(s0)
  CHECK_EQ_IMM(5, t1, -128)

  lbu t1, 4(s0)
  CHECK_EQ_IMM(6, t1, 0xff)
  lbu t1, 5(s0)
  CHECK_EQ_IMM(7, t1, 0x80)
  lbu t1, 6(s0)
  CHECK_EQ_IMM(8, t1, 1)
  lbu t1, 7(s0)
  CHECK_EQ_IMM(9, t1, 0x7f)

  lh t1, 0(s0)
  CHECK_EQ_IMM(10, t1, 0x7f01)
  lh t1, 2(s0)
  CHECK_EQ_IMM(11, t1, 0xffff80ff)
  lhu t1, 4(s0)
  CHECK_EQ_IMM(12, t1, 0x80ff)
  lhu t1, 6(s0)
  CHECK_EQ_IMM(13, t1, 0x7f01)

  lb t1, 3(s0)
  sw t1, 8(s0)
  lhu t2, 4(s0)
  sw t2, 12(s0)
  lw t3, 8(s0)
  CHECK_EQ_IMM(14, t3, 0xffffff80)
  lw t3, 12(s0)
  CHECK_EQ_IMM(15, t3, 0x000080ff)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
subword_words:
  .space 16
RVTEST_DATA_END
