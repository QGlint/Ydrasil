#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, alu_words
  li t1, 0x1010100f
  addi t1, t1, 1
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(2, t2, 0x10101010)

  la t0, alu_words
  addi t0, t0, 4
  li t1, 0x2020201f
  addi t1, t1, 1
  nop
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(3, t2, 0x20202020)

  la t0, alu_words
  addi t0, t0, 8
  li t1, 0x3030302f
  addi t1, t1, 1
  nop
  nop
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(4, t2, 0x30303030)

  la t0, alu_words
  addi t0, t0, 12
  li t1, 0x4040403f
  addi t1, t1, 1
  nop
  nop
  nop
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(5, t2, 0x40404040)

  la t3, alu_words
  li t4, 0x5050504f
  addi t3, t3, 16
  addi t4, t4, 1
  sw t4, 0(t3)
  lw t2, 0(t3)
  CHECK_EQ_IMM(6, t2, 0x50505050)

  li t4, 0x60606060
  xor t4, t4, zero
  sw t4, 4(t3)
  lw t2, 4(t3)
  CHECK_EQ_IMM(7, t2, 0x60606060)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
alu_words:
  .space 24
RVTEST_DATA_END
