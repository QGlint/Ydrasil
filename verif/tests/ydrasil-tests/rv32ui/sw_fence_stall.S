#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, fence_words
  li t0, 0x1111
  li t1, 3

  mul t2, t0, t1
  fence.i
  sw t2, 0(s0)

  fence
  fence.i
  sw t0, 4(s0)

  lw t5, 0(s0)
  CHECK_EQ_IMM(2, t5, 0x3333)
  lw t5, 4(s0)
  CHECK_EQ_IMM(3, t5, 0x1111)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
fence_words:
  .space 8
RVTEST_DATA_END
