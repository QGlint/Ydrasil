#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, bypass_words
  li t2, 0x01010101

  lw t0, source_a
  add t1, t2, t0
  sw t1, 0(s0)
  lw t3, 0(s0)
  CHECK_EQ_IMM(2, t3, 0x13355779)

  lw t0, source_b
  sub t1, t0, t2
  sw t1, 4(s0)
  lw t3, 4(s0)
  CHECK_EQ_IMM(3, t3, 0x879accee)

  lw t0, source_a
  xor t1, t2, t0
  sw t1, 8(s0)
  lw t3, 8(s0)
  CHECK_EQ_IMM(4, t3, 0x13355779)

  lw t0, source_b
  sltu t1, t2, t0
  sw t1, 12(s0)
  lw t3, 12(s0)
  CHECK_EQ_IMM(5, t3, 1)

  lw t0, source_a
  beq t2, t0, fail
  sw t0, 16(s0)
  lw t3, 16(s0)
  CHECK_EQ_IMM(6, t3, 0x12345678)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
bypass_words:
  .space 20
source_a:
  .word 0x12345678
source_b:
  .word 0x889bcdef
RVTEST_DATA_END
