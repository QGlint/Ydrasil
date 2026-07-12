#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, negative_1
  addi t0, t0, 4
  li t1, 0x11223344
  sw t1, -3(t0)
  addi t0, t0, -4
  CHECK_BYTE(2, t0, 0, 0xa0)
  CHECK_BYTE(3, t0, 1, 0x44)
  CHECK_BYTE(4, t0, 4, 0x11)
  CHECK_BYTE(5, t0, 5, 0xa5)

  la t0, negative_2
  addi t0, t0, 4
  li t1, 0x55667788
  sw t1, -2(t0)
  addi t0, t0, -4
  CHECK_BYTE(6, t0, 1, 0xb1)
  CHECK_BYTE(7, t0, 2, 0x88)
  CHECK_BYTE(8, t0, 5, 0x55)
  CHECK_BYTE(9, t0, 6, 0xb6)

  la t0, negative_3
  addi t0, t0, 4
  li t1, 0x99aabbcc
  sw t1, -1(t0)
  addi t0, t0, -4
  CHECK_BYTE(10, t0, 2, 0xc2)
  CHECK_BYTE(11, t0, 3, 0xcc)
  CHECK_BYTE(12, t0, 6, 0x99)
  CHECK_BYTE(13, t0, 7, 0xc7)

  la t0, extreme_target
  li t1, 0x0badc0de
  li t2, -2046
  add t3, t0, t2
  sw t1, 2047(t3)
  CHECK_BYTE(14, t0, 1, 0xde)
  CHECK_BYTE(15, t0, 4, 0x0b)

  li t1, 0x76543210
  li t2, 2050
  add t3, t0, t2
  sw t1, -2048(t3)
  CHECK_BYTE(16, t0, 2, 0x10)
  CHECK_BYTE(17, t0, 5, 0x76)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
negative_1:
  .byte 0xa0,0xa1,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7
negative_2:
  .byte 0xb0,0xb1,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7
negative_3:
  .byte 0xc0,0xc1,0xc2,0xc3,0xc4,0xc5,0xc6,0xc7
  .space 2048
extreme_target:
  .byte 0xd0,0xd1,0xd2,0xd3,0xd4,0xd5,0xd6,0xd7
RVTEST_DATA_END
