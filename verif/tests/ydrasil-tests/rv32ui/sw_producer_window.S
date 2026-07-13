#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, producer_words
  li t2, 0x1111
  li t3, 3

  mul t1, t2, t3
  sw t1, 0(t0)
  lw t4, 0(t0)
  CHECK_EQ_IMM(2, t4, 0x3333)

  mul t1, t2, t3
  nop
  sw t1, 4(t0)
  lw t4, 4(t0)
  CHECK_EQ_IMM(3, t4, 0x3333)

  mul t1, t2, t3
  nop
  nop
  sw t1, 8(t0)
  lw t4, 8(t0)
  CHECK_EQ_IMM(4, t4, 0x3333)

  mul t1, t2, t3
  nop
  nop
  nop
  sw t1, 12(t0)
  lw t4, 12(t0)
  CHECK_EQ_IMM(5, t4, 0x3333)

  mul t1, t2, t3
  nop
  nop
  nop
  nop
  sw t1, 16(t0)
  lw t4, 16(t0)
  CHECK_EQ_IMM(6, t4, 0x3333)

  li t2, 0x8010
  li t3, 0x10000
  mul t0, t2, t3
  li t1, 0x55667788
  sw t1, 96(t0)
  lw t4, 96(t0)
  CHECK_EQ_IMM(7, t4, 0x55667788)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
producer_words:
  .space 20
RVTEST_DATA_END
