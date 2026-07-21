#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, alu_words
  li t0, 0x80000001
  li t1, 4

  sll t2, t0, t1
  sw t2, 0(s0)
  srl t2, t0, t1
  sw t2, 4(s0)
  sra t2, t0, t1
  sw t2, 8(s0)
  slt t2, t0, t1
  sw t2, 12(s0)
  sltu t2, t0, t1
  sw t2, 16(s0)
  or t2, t0, t1
  sw t2, 20(s0)
  and t2, t0, t1
  sw t2, 24(s0)

  slti t2, t0, 0
  sw t2, 28(s0)
  sltiu t2, t0, 1
  sw t2, 32(s0)
  ori t2, t0, 0x7e
  sw t2, 36(s0)
  andi t2, t0, 0xff
  sw t2, 40(s0)
  srai t2, t0, 4
  sw t2, 44(s0)

  li t0, 1
  slli t2, t0, 31
  sw t2, 48(s0)
  li t0, 0x80000001
  srli t2, t0, 31
  sw t2, 52(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0x00000010)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0x08000000)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0xf8000000)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 1)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 0x80000005)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 0)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 1)
  lw a0, 32(s0)
  CHECK_EQ_IMM(10, a0, 0)
  lw a0, 36(s0)
  CHECK_EQ_IMM(11, a0, 0x8000007f)
  lw a0, 40(s0)
  CHECK_EQ_IMM(12, a0, 1)
  lw a0, 44(s0)
  CHECK_EQ_IMM(13, a0, 0xf8000000)
  lw a0, 48(s0)
  CHECK_EQ_IMM(14, a0, 0x80000000)
  lw a0, 52(s0)
  CHECK_EQ_IMM(15, a0, 1)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
alu_words:
  .space 56
RVTEST_DATA_END
