#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, mul_div_words
  li t1, 0x1234
  li t2, 0x10
  mul t3, t1, t2
  sw t3, 0(t0)
  lw t4, 0(t0)
  CHECK_EQ_IMM(2, t4, 0x00012340)

  li t1, 0x12345678
  li t2, 0x1234
  divu t3, t1, t2
  sw t3, 4(t0)
  lw t4, 4(t0)
  CHECK_EQ_IMM(3, t4, 0x00010004)

  li t1, 0x12345678
  li t2, 0x1234
  remu t3, t1, t2
  sw t3, 8(t0)
  lw t4, 8(t0)
  CHECK_EQ_IMM(4, t4, 0x00000da8)

  li t1, 0x8010
  li t2, 0x10000
  mul t0, t1, t2
  li t3, 0x76543210
  sw t3, 64(t0)
  lw t4, 64(t0)
  CHECK_EQ_IMM(5, t4, 0x76543210)

  la t0, mul_div_words
  li t1, 0x1111
  li t2, 3
  mul t3, t1, t2
  li t5, 0x2222
  mul t6, t5, t2
  sw t3, 12(t0)
  sw t6, 16(t0)
  lw t4, 12(t0)
  CHECK_EQ_IMM(6, t4, 0x00003333)
  lw t4, 16(t0)
  CHECK_EQ_IMM(7, t4, 0x00006666)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
mul_div_words:
  .space 20
RVTEST_DATA_END
