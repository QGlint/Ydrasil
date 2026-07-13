#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, bitmanip_words
  li t0, 0x0f0f0f0f
  li t1, 0x33333333

  andn t2, t0, t1
  sw t2, 0(s0)
  orn t2, t0, t1
  sw t2, 4(s0)
  xnor t2, t0, t1
  sw t2, 8(s0)

  li t0, 0x12345678
  li t1, 8
  rol t2, t0, t1
  sw t2, 12(s0)
  ror t2, t0, t1
  sw t2, 16(s0)

  li t0, 0x01000000
  clz t2, t0
  sw t2, 20(s0)
  li t0, 0x00000100
  ctz t2, t0
  sw t2, 24(s0)
  li t0, 0xf0f0f0f0
  cpop t2, t0
  sw t2, 28(s0)

  li t0, 0x00000080
  sext.b t2, t0
  sw t2, 32(s0)
  li t0, 0x00008001
  sext.h t2, t0
  sw t2, 36(s0)
  zext.h t2, t2
  sw t2, 40(s0)

  li t0, 0x00010000
  orc.b t2, t0
  sw t2, 44(s0)
  li t0, 0x12345678
  rev8 t2, t0
  sw t2, 48(s0)

  li t0, 0
  li t1, 31
  bset t2, t0, t1
  sw t2, 52(s0)
  li t0, -1
  bclr t2, t0, t1
  sw t2, 56(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0x0c0c0c0c)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0xcfcfcfcf)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0xc3c3c3c3)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0x34567812)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0x78123456)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 7)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 8)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 16)
  lw a0, 32(s0)
  CHECK_EQ_IMM(10, a0, 0xffffff80)
  lw a0, 36(s0)
  CHECK_EQ_IMM(11, a0, 0xffff8001)
  lw a0, 40(s0)
  CHECK_EQ_IMM(12, a0, 0x00008001)
  lw a0, 44(s0)
  CHECK_EQ_IMM(13, a0, 0x00ff0000)
  lw a0, 48(s0)
  CHECK_EQ_IMM(14, a0, 0x78563412)
  lw a0, 52(s0)
  CHECK_EQ_IMM(15, a0, 0x80000000)
  lw a0, 56(s0)
  CHECK_EQ_IMM(16, a0, 0x7fffffff)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
bitmanip_words:
  .space 60
RVTEST_DATA_END
