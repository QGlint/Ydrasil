#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, loadback_1
  li t1, 0x11223344
  sw t1, 1(t0)
  lw t2, 1(t0)
  CHECK_EQ_IMM(2, t2, 0x11223344)
  CHECK_BYTE(3, t0, 0, 0xa0)
  CHECK_BYTE(4, t0, 5, 0xa5)

  la t0, loadback_2
  li t1, 0x89abcdef
  sw t1, 2(t0)
  lw t2, 2(t0)
  CHECK_EQ_IMM(5, t2, 0x89abcdef)
  CHECK_BYTE(6, t0, 1, 0xb1)
  CHECK_BYTE(7, t0, 6, 0xb6)

  la t0, loadback_3
  li t1, 0x76543210
  sw t1, 3(t0)
  lw t2, 3(t0)
  CHECK_EQ_IMM(8, t2, 0x76543210)
  CHECK_BYTE(9, t0, 2, 0xc2)
  CHECK_BYTE(10, t0, 7, 0xc7)

  li t1, 0xa1b2c3d4
  sw t1, 5(t0)
  lw t2, 5(t0)
  CHECK_EQ_IMM(11, t2, 0xa1b2c3d4)
  lw t2, 3(t0)
  CHECK_EQ_IMM(12, t2, 0xc3d43210)
  CHECK_BYTE(13, t0, 2, 0xc2)
  CHECK_BYTE(14, t0, 9, 0xc9)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
loadback_1:
  .byte 0xa0,0xa1,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7
  .align 4
loadback_2:
  .byte 0xb0,0xb1,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7
  .align 4
loadback_3:
  .byte 0xc0,0xc1,0xc2,0xc3,0xc4,0xc5,0xc6,0xc7
  .byte 0xc8,0xc9,0xca,0xcb
RVTEST_DATA_END
