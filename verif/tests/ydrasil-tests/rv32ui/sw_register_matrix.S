#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la x1, register_area
  mv x2, x1
  mv x3, x1
  mv x4, x1
  mv x5, x1
  mv x6, x1
  mv x7, x1
  mv x8, x1
  mv x9, x1
  mv x10, x1
  mv x11, x1
  mv x12, x1
  mv x13, x1
  mv x14, x1
  mv x15, x1
  mv x16, x1
  mv x17, x1
  mv x18, x1
  mv x19, x1
  mv x20, x1
  mv x21, x1
  mv x22, x1
  mv x23, x1
  mv x24, x1
  mv x25, x1
  mv x26, x1
  mv x27, x1
  mv x28, x1
  mv x29, x1
  mv x30, x1
  mv x31, x1

  sw x0,   0(x31)
  sw x1,   4(x31)
  sw x2,   8(x31)
  sw x3,  12(x31)
  sw x4,  16(x31)
  sw x5,  20(x31)
  sw x6,  24(x31)
  sw x7,  28(x31)
  sw x8,  32(x31)
  sw x9,  36(x31)
  sw x10, 40(x31)
  sw x11, 44(x31)
  sw x12, 48(x31)
  sw x13, 52(x31)
  sw x14, 56(x31)
  sw x15, 60(x31)
  sw x16, 64(x31)
  sw x17, 68(x31)
  sw x18, 72(x31)
  sw x19, 76(x31)
  sw x20, 80(x31)
  sw x21, 84(x31)
  sw x22, 88(x31)
  sw x23, 92(x31)
  sw x24, 96(x31)
  sw x25,100(x31)
  sw x26,104(x31)
  sw x27,108(x31)
  sw x28,112(x31)
  sw x29,116(x31)
  sw x30,120(x31)
  sw x31,124(x31)

  sw x31,128(x1)
  sw x31,128(x2)
  sw x31,128(x3)
  sw x31,128(x4)
  sw x31,128(x5)
  sw x31,128(x6)
  sw x31,128(x7)
  sw x31,128(x8)
  sw x31,128(x9)
  sw x31,128(x10)
  sw x31,128(x11)
  sw x31,128(x12)
  sw x31,128(x13)
  sw x31,128(x14)
  sw x31,128(x15)
  sw x31,128(x16)
  sw x31,128(x17)
  sw x31,128(x18)
  sw x31,128(x19)
  sw x31,128(x20)
  sw x31,128(x21)
  sw x31,128(x22)
  sw x31,128(x23)
  sw x31,128(x24)
  sw x31,128(x25)
  sw x31,128(x26)
  sw x31,128(x27)
  sw x31,128(x28)
  sw x31,128(x29)
  sw x31,128(x30)
  sw x31,128(x31)
  sw x31,132(x31)

  la t0, register_area
  li TESTNUM, 2
  lw t1, 0(t0)
  bnez t1, fail
  li t2, 31
  addi t3, t0, 4
1:
  lw t1, 0(t3)
  bne t1, t0, fail
  addi t3, t3, 4
  addi t2, t2, -1
  bnez t2, 1b
  lw t1, 128(t0)
  bne t1, t0, fail
  lw t1, 132(t0)
  bne t1, t0, fail

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
register_area:
  .space 136
RVTEST_DATA_END
