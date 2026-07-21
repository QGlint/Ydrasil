#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, interlock_words
  lw t0, pointer_value
  lw t1, source_value
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(2, t2, 0x12345678)

  lw t1, source_value
  lw t1, source_value_2
  sw t1, 4(t0)
  lw t2, 4(t0)
  CHECK_EQ_IMM(3, t2, 0x89abcdef)

  lw t1, 0(t0)
  sw t1, 32(t0)
  lw t2, 32(t0)
  CHECK_EQ_IMM(4, t2, 0x12345678)

  lw t1, 32(t0)
  sw t1, 64(t0)
  lw t2, 64(t0)
  CHECK_EQ_IMM(5, t2, 0x12345678)

  lw t3, pointer_value
  lw t4, source_value_2
  addi t3, t3, 96
  addi t4, t4, 1
  sw t4, 0(t3)
  lw t2, 0(t3)
  CHECK_EQ_IMM(6, t2, 0x89abcdf0)

  sw zero, 128(s0)
  lw t1, 128(s0)
  sw t1, 132(s0)
  lw t2, 132(s0)
  CHECK_EQ_IMM(7, t2, 0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
interlock_words:
  .space 136
source_value:
  .word 0x12345678
source_value_2:
  .word 0x89abcdef
pointer_value:
  .word interlock_words
RVTEST_DATA_END
