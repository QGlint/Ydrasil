#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, dependency_words
  li t1, 0x11112222
  sw t1, 0(t0)
  li t1, 0x33334444
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(2, t2, 0x33334444)

  li t1, 0x55556666
  sw t1, 4(t0)
  li t1, 0x77778888
  sw t1, 8(t0)
  lw t2, 4(t0)
  CHECK_EQ_IMM(3, t2, 0x55556666)
  lw t2, 8(t0)
  CHECK_EQ_IMM(4, t2, 0x77778888)

  la t3, dependency_words
  li t4, 0x01020303
  addi t4, t4, 1
  sw t4, 12(t3)
  lw t2, 12(t3)
  CHECK_EQ_IMM(5, t2, 0x01020304)

  lw t4, source_word
  sw t4, 16(t3)
  lw t2, 16(t3)
  CHECK_EQ_IMM(6, t2, 0xcafebabe)

  sw zero, 20(t3)
  lw t2, 20(t3)
  CHECK_EQ_IMM(7, t2, 0)

  li t1, 0x1234
  li t2, 0x10
  mul t4, t1, t2
  sw t4, 20(t3)
  lw t2, 20(t3)
  CHECK_EQ_IMM(8, t2, 0x00012340)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
dependency_words:
  .space 24
source_word:
  .word 0xcafebabe
RVTEST_DATA_END
