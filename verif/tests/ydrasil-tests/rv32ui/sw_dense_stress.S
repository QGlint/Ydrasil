#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, dense_words
  li s1, 0x31415926
  li s2, 4
seed_loop:
  mv t0, s0
  mv t1, s1
  li t2, 128
write_loop:
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
  bnez t2, write_loop

  mv t0, s0
  mv t1, s1
  li t2, 128
check_loop:
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
  bnez t2, check_loop

  li t5, 0x9e3779b9
  add s1, s1, t5
  addi s2, s2, -1
  bnez s2, seed_loop

  la t0, dense_words
  addi t0, t0, 508
  li t1, 127
reverse_loop:
  li TESTNUM, 4
  not t2, t1
  sw t2, 0(t0)
  addi t0, t0, -4
  addi t1, t1, -1
  bgez t1, reverse_loop

  la t0, dense_words
  li t1, 0
  li t3, 128
reverse_check:
  li TESTNUM, 5
  lw t4, 0(t0)
  not t2, t1
  bne t4, t2, fail
  addi t0, t0, 4
  addi t1, t1, 1
  addi t3, t3, -1
  bnez t3, reverse_check

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
dense_words:
  .space 512
RVTEST_DATA_END
