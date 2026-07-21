#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, half_bytes
  li t0, 0x80ff7f01
  sw t0, 1(s0)

  lh t1, 3(s0)
  CHECK_EQ_IMM(2, t1, 0xffff80ff)
  lhu t1, 3(s0)
  CHECK_EQ_IMM(3, t1, 0x80ff)

  li t0, 0x017f80ff
  sw t0, 5(s0)
  lh t1, 7(s0)
  CHECK_EQ_IMM(4, t1, 0x017f)
  lhu t1, 7(s0)
  CHECK_EQ_IMM(5, t1, 0x017f)

  lh t1, 3(s0)
  sw t1, 12(s0)
  lhu t1, 7(s0)
  sw t1, 11(s0)

  lw t2, 11(s0)
  CHECK_EQ_IMM(6, t2, 0x0000017f)
  CHECK_BYTE(7, s0, 0, 0xa0)
  CHECK_BYTE(8, s0, 9, 0xa9)
  CHECK_BYTE(9, s0, 15, 0xff)
  CHECK_BYTE(10, s0, 16, 0xa0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
half_bytes:
  .byte 0xa0,0xa1,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7
  .byte 0xa8,0xa9,0xaa,0xab,0xac,0xad,0xae,0xaf
  .byte 0xa0,0xa1,0xa2,0xa3
RVTEST_DATA_END
