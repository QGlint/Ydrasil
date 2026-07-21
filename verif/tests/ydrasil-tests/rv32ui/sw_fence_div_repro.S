#include "riscv_test.h"
#include "sw_test_macros.h"

/* 已知失败最小复现：legacy LSU 下相关 mul/div 与 fence.i 交织会丢失除法结果。 */
RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, result_words
  li t0, 0x1111
  li t1, 3
  mul t2, t0, t1
  fence.i
  sw t2, 0(s0)
  divu t3, t2, t1
  fence.i
  sw t3, 4(s0)
  lw t4, 0(s0)
  CHECK_EQ_IMM(2, t4, 0x3333)
  lw t4, 4(s0)
  CHECK_EQ_IMM(3, t4, 0x1111)
  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
result_words:
  .word 0, 0
RVTEST_DATA_END
