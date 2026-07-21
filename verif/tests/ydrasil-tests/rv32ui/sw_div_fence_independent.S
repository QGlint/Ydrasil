#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, div_fence_words
  li t0, 0x76543210
  li t1, 16

  divu t2, t0, t1
  fence.i
  sw t2, 0(s0)

  remu t3, t0, t1
  fence.i
  sw t3, 4(s0)

  li t0, -100
  li t1, 3
  div t4, t0, t1
  fence.i
  sw t4, 8(s0)

  rem t5, t0, t1
  fence.i
  sw t5, 12(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0x07654321)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0xffffffdf)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0xffffffff)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
div_fence_words:
  .space 16
RVTEST_DATA_END
