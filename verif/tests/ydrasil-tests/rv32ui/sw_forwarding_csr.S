#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, csr_words
  li t0, 0x12345678
  csrw mscratch, t0

  li t1, 0x00ff00ff
  csrrc t2, mscratch, t1
  sw t2, 0(s0)
  csrr t2, mscratch
  sw t2, 4(s0)

  csrrsi t2, mscratch, 1
  sw t2, 8(s0)
  csrrci t2, mscratch, 1
  sw t2, 12(s0)

  csrrwi t2, mscratch, 31
  sw t2, 16(s0)
  csrr t2, mscratch
  sw t2, 20(s0)
  csrw mscratch, zero

  lw a0, 0(s0)
  CHECK_EQ_IMM(2, a0, 0x12345678)
  lw a0, 4(s0)
  CHECK_EQ_IMM(3, a0, 0x12005600)
  lw a0, 8(s0)
  CHECK_EQ_IMM(4, a0, 0x12005600)
  lw a0, 12(s0)
  CHECK_EQ_IMM(5, a0, 0x12005601)
  lw a0, 16(s0)
  CHECK_EQ_IMM(6, a0, 0x12005600)
  lw a0, 20(s0)
  CHECK_EQ_IMM(7, a0, 31)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
csr_words:
  .space 24
RVTEST_DATA_END
