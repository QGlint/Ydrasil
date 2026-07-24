#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  csrr t0, misa
  srli t0, t0, 5
  andi t0, t0, 1
#ifdef __riscv_flen
  CHECK_EQ_IMM(2, t0, 1)
#else
  CHECK_EQ_IMM(2, t0, 0)
#endif

  csrr s1, mtvec
  la t1, fpu_illegal_handler
  csrw mtvec, t1
  li s0, 0
  .word 0x00000053
fpu_after_illegal:
  csrw mtvec, s1
  CHECK_EQ_IMM(3, s0, 1)
  SW_TEST_PASSFAIL

  .align 2
fpu_illegal_handler:
  csrr t2, mcause
  li t3, 2
  bne t2, t3, fail
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  li s0, 1
  mret
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
RVTEST_DATA_END
