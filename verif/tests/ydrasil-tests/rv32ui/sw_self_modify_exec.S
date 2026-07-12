#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, generated_code
  li t1, 0x05a00513
  sw t1, 0(t0)
  li t1, 0x00008067
  sw t1, 4(t0)
  fence.i
  jalr ra, 0(t0)
  CHECK_EQ_IMM(2, a0, 0x5a)

  li t1, 0x0a500513
  sw t1, 0(t0)
  fence.i
  jalr ra, 0(t0)
  CHECK_EQ_IMM(3, a0, 0xa5)

  lw t2, 0(t0)
  CHECK_EQ_IMM(4, t2, 0x0a500513)
  lw t2, 4(t0)
  CHECK_EQ_IMM(5, t2, 0x00008067)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
generated_code:
  .word 0
  .word 0
RVTEST_DATA_END
