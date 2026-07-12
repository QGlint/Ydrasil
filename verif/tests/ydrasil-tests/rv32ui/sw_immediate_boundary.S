#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, immediate_area
  li t1, 0x80000001
  addi t2, t0, 2047
  addi t2, t2, 1
  sw t1, -2048(t2)
  lw t3, 0(t0)
  CHECK_EQ_IMM(2, t3, 0x80000001)

  li t1, 0x7ffffffe
  addi t2, t0, 1
  sw t1, 2047(t2)
  lw t3, 2047(t2)
  CHECK_EQ_IMM(3, t3, 0x7ffffffe)

  li t1, 0x11223344
  addi t2, t0, 1
  sw t1, -1(t2)
  lw t3, 0(t0)
  CHECK_EQ_IMM(4, t3, 0x11223344)

  li t1, 0x55667788
  sw t1, 0(t0)
  lw t3, 0(t0)
  CHECK_EQ_IMM(5, t3, 0x55667788)

  li t1, 0xa5a55a5a
  addi t2, t0, 3
  sw t1, 1(t2)
  lw t3, 4(t0)
  CHECK_EQ_IMM(6, t3, 0xa5a55a5a)

  lw t3, -4(t0)
  CHECK_EQ_IMM(7, t3, 0x13579bdf)
  addi t2, t0, 2047
  addi t2, t2, 1
  lw t3, 4(t2)
  CHECK_EQ_IMM(8, t3, 0x2468ace0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
  .word 0x13579bdf
immediate_area:
  .space 2052
  .word 0x2468ace0
RVTEST_DATA_END
