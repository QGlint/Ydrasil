#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  li t0, 0x80100000
  lw s0, 0(t0)
  li t1, 0x01234567
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(2, t2, 0x01234567)
  sw s0, 0(t0)

  li t0, 0x8013fffc
  lw s1, 0(t0)
  li t1, 0x89abcdef
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(3, t2, 0x89abcdef)
  sw s1, 0(t0)

  la t0, guarded_words
  li t1, 0xa55aa55a
  sw t1, 4(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(4, t2, 0x11111111)
  lw t2, 4(t0)
  CHECK_EQ_IMM(5, t2, 0xa55aa55a)
  lw t2, 8(t0)
  CHECK_EQ_IMM(6, t2, 0x33333333)

  addi t0, t0, 1
  li t1, 0x5aa55aa5
  sw t1, 3(t0)
  addi t0, t0, -1
  lw t2, 4(t0)
  CHECK_EQ_IMM(7, t2, 0x5aa55aa5)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
guarded_words:
  .word 0x11111111
  .word 0x22222222
  .word 0x33333333
RVTEST_DATA_END
