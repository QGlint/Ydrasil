#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, bitmanip_matrix
  li t0, 2

  li t3, 0x11111111
  sh1add t1, t0, s0
  sw t3, 0(t1)
  li t3, 0x22222222
  sh2add t1, t0, s0
  sw t3, 0(t1)
  li t3, 0x33333333
  sh3add t1, t0, s0
  sw t3, 0(t1)

  li t0, 0x12345678
  li t1, 1
  clmul t2, t0, t1
  sw t2, 20(s0)
  clmulh t2, t0, t1
  sw t2, 24(s0)
  clmulr t2, t0, t1
  sw t2, 28(s0)

  li t1, 0x9abcdef0
  pack t2, t0, t1
  sw t2, 32(s0)
  packh t2, t0, t1
  sw t2, 36(s0)

  li t0, 0x0000ffff
  zip t2, t0
  sw t2, 40(s0)
  unzip t2, t2
  sw t2, 44(s0)

  li t0, 0x01234567
  li t1, 0x12345678
  xperm4 t2, t0, t1
  sw t2, 48(s0)
  li t0, 0x00010203
  li t1, 0x01020304
  xperm8 t2, t0, t1
  sw t2, 52(s0)

  li t0, 0x80000000
  li t1, 31
  bext t2, t0, t1
  sw t2, 56(s0)
  li t0, 0
  binv t2, t0, t1
  sw t2, 60(s0)

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0x11111111)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0x22222222)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0x33333333)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 0x12345678)
  lw a0, 24(s0)
  CHECK_EQ_IMM(8, a0, 0)
  lw a0, 28(s0)
  CHECK_EQ_IMM(9, a0, 0)
  lw a0, 32(s0)
  CHECK_EQ_IMM(10, a0, 0xdef05678)
  lw a0, 36(s0)
  CHECK_EQ_IMM(11, a0, 0x0000f078)
  lw a0, 40(s0)
  CHECK_EQ_IMM(12, a0, 0x55555555)
  lw a0, 44(s0)
  CHECK_EQ_IMM(13, a0, 0x0000ffff)
  lw a0, 48(s0)
  CHECK_EQ_IMM(14, a0, 0x65432100)
  lw a0, 52(s0)
  CHECK_EQ_IMM(15, a0, 0x02010000)
  lw a0, 56(s0)
  CHECK_EQ_IMM(16, a0, 1)
  lw a0, 60(s0)
  CHECK_EQ_IMM(17, a0, 0x80000000)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .balign 256
bitmanip_matrix:
  .space 64
RVTEST_DATA_END
