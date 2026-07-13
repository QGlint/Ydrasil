#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, edge_words

  li t0, -2
  li t1, 3
  mulh t2, t0, t1
  sw t2, 0(s0)
  mulhsu t2, t0, t1
  sw t2, 4(s0)
  li t0, -1
  li t1, -1
  mulhu t2, t0, t1
  sw t2, 8(s0)

  li t0, 0x12345678
  div t2, t0, zero
  sw t2, 12(s0)
  divu t2, t0, zero
  sw t2, 16(s0)
  rem t2, t0, zero
  sw t2, 20(s0)
  remu t2, t0, zero
  sw t2, 24(s0)

  li t0, 0x80000000
  li t1, -1
  div t2, t0, t1
  sw t2, 28(s0)
  rem t2, t0, t1
  sw t2, 32(s0)

  li t0, 5
  li t1, 7
  divu t2, t0, t1
  sw t2, 36(s0)
  remu t2, t0, t1
  sw t2, 40(s0)
  divu t2, zero, t1
  sw t2, 44(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0xffffffff)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0xffffffff)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0xfffffffe)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0xffffffff)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0xffffffff)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 0x12345678)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 0x12345678)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 0x80000000)
  lw a0, 32(s0)
  CHECK_EQ_IMM(10, a0, 0)
  lw a0, 36(s0)
  CHECK_EQ_IMM(11, a0, 0)
  lw a0, 40(s0)
  CHECK_EQ_IMM(12, a0, 5)
  lw a0, 44(s0)
  CHECK_EQ_IMM(13, a0, 0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
edge_words:
  .space 48
RVTEST_DATA_END
