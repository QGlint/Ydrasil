#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, control_words
  li t0, 1
  beq t0, t0, 1f
  sw t0, 0(s0)
1:
  li t1, 0x11111111
  sw t1, 4(s0)

  bne t0, t0, 2f
  li t1, 0x22222222
  sw t1, 8(s0)
2:
  jal ra, store_subroutine
  fence
  li t1, 0x44444444
  sw t1, 16(s0)
  fence

  la t2, indirect_store
  jalr ra, 0(t2)

  lw t3, 0(s0)
  CHECK_EQ_IMM(2, t3, 0)
  lw t3, 4(s0)
  CHECK_EQ_IMM(3, t3, 0x11111111)
  lw t3, 8(s0)
  CHECK_EQ_IMM(4, t3, 0x22222222)
  lw t3, 12(s0)
  CHECK_EQ_IMM(5, t3, 0x33333333)
  lw t3, 16(s0)
  CHECK_EQ_IMM(6, t3, 0x44444444)
  lw t3, 20(s0)
  CHECK_EQ_IMM(7, t3, 0x55555555)
  j control_done

store_subroutine:
  li t1, 0x33333333
  sw t1, 12(s0)
  ret

indirect_store:
  li t1, 0x55555555
  sw t1, 20(s0)
  ret

control_done:
  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
control_words:
  .space 24
RVTEST_DATA_END
