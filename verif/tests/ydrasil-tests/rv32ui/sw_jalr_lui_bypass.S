#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, generated_code
  li t1, 0x06b00513
  sw t1, 0(t0)
  li t1, 0x00008067
  sw t1, 4(t0)
  fence.i

  lui t2, %hi(generated_code)
  jalr ra, %lo(generated_code)(t2)
  CHECK_EQ_IMM(2, a0, 0x6b)

  lw t3, 0(t0)
  CHECK_EQ_IMM(3, t3, 0x06b00513)
  lw t3, 4(t0)
  CHECK_EQ_IMM(4, t3, 0x00008067)
  lw t3, 8(t0)
  CHECK_EQ_IMM(5, t3, 0xa5a5a5a5)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
generated_code:
  .word 0
  .word 0
  .word 0xa5a5a5a5
RVTEST_DATA_END
