#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, stress_words
  li t1, 0x1aceb00c
  li t2, 64
1:
  li TESTNUM, 2
  sw t1, 0(t0)
  slli t3, t1, 13
  xor t1, t1, t3
  srli t3, t1, 17
  xor t1, t1, t3
  slli t3, t1, 5
  xor t1, t1, t3
  addi t0, t0, 4
  addi t2, t2, -1
  bnez t2, 1b

  la t0, stress_words
  li t1, 0x1aceb00c
  li t2, 64
2:
  li TESTNUM, 3
  lw t4, 0(t0)
  bne t4, t1, fail
  slli t3, t1, 13
  xor t1, t1, t3
  srli t3, t1, 17
  xor t1, t1, t3
  slli t3, t1, 5
  xor t1, t1, t3
  addi t0, t0, 4
  addi t2, t2, -1
  bnez t2, 2b

  la t0, stress_words
  lw t4, -4(t0)
  CHECK_EQ_IMM(4, t4, 0x13579bdf)
  lw t4, 256(t0)
  CHECK_EQ_IMM(5, t4, 0x2468ace0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
  .word 0x13579bdf
stress_words:
  .space 256
  .word 0x2468ace0
RVTEST_DATA_END
