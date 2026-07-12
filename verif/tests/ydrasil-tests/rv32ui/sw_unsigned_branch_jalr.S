#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, control_words
  li t0, 1
  li t1, -1

  bltu t0, t1, 1f
  sw t1, 0(s0)
1:
  li t2, 0x11111111
  sw t2, 4(s0)

  bgeu t1, t0, 2f
  sw t1, 8(s0)
2:
  li t2, 0x22222222
  sw t2, 12(s0)

  bltu t1, t0, 3f
  li t2, 0x33333333
  sw t2, 16(s0)
3:
  bgeu t0, t1, 4f
  li t2, 0x44444444
  sw t2, 20(s0)
4:
  la t2, jalr_store
  addi t2, t2, 0
  jalr ra, 0(t2)
  li t2, 0x66666666
  sw t2, 28(s0)
  j check_results

jalr_store:
  li t2, 0x55555555
  sw t2, 24(s0)
  ret

check_results:
  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0x11111111)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0x22222222)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0x33333333)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 0x44444444)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 0x55555555)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 0x66666666)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
control_words:
  .space 32
RVTEST_DATA_END
