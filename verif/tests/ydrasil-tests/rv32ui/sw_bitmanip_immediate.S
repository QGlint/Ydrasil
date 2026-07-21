#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, immediate_words

  li t0, 0x12345678
  rori t2, t0, 8
  sw t2, 0(s0)

  li t0, -1
  bclri t2, t0, 31
  sw t2, 4(s0)
  li t0, 0x80000000
  bexti t2, t0, 31
  sw t2, 8(s0)
  li t0, 0
  binvi t2, t0, 31
  sw t2, 12(s0)
  bseti t2, t0, 7
  sw t2, 16(s0)

  li t0, 0x01234567
  brev8 t2, t0
  sw t2, 20(s0)

  li t0, 0x80000000
  li t1, 1
  min t2, t0, t1
  sw t2, 24(s0)
  max t2, t0, t1
  sw t2, 28(s0)
  minu t2, t0, t1
  sw t2, 32(s0)
  maxu t2, t0, t1
  sw t2, 36(s0)

  max t2, t1, t0
  sw t2, 40(s0)
  minu t2, t1, t0
  sw t2, 44(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0x78123456)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0x7fffffff)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 1)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0x80000000)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0x00000080)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 0x80c4a2e6)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 0x80000000)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 1)
  lw a0, 32(s0)
  CHECK_EQ_IMM(10, a0, 1)
  lw a0, 36(s0)
  CHECK_EQ_IMM(11, a0, 0x80000000)
  lw a0, 40(s0)
  CHECK_EQ_IMM(12, a0, 1)
  lw a0, 44(s0)
  CHECK_EQ_IMM(13, a0, 1)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
immediate_words:
  .space 48
RVTEST_DATA_END
