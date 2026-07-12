#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, misaligned_1
  li t1, 0x11223344
  sw t1, 1(t0)
  CHECK_BYTE(2, t0, 0, 0xa0)
  CHECK_BYTE(3, t0, 1, 0x44)
  CHECK_BYTE(4, t0, 2, 0x33)
  CHECK_BYTE(5, t0, 3, 0x22)
  CHECK_BYTE(6, t0, 4, 0x11)
  CHECK_BYTE(7, t0, 5, 0xa5)

  la t0, misaligned_2
  li t1, 0x89abcdef
  sw t1, 2(t0)
  CHECK_BYTE(8, t0, 1, 0xb1)
  CHECK_BYTE(9, t0, 2, 0xef)
  CHECK_BYTE(10, t0, 3, 0xcd)
  CHECK_BYTE(11, t0, 4, 0xab)
  CHECK_BYTE(12, t0, 5, 0x89)
  CHECK_BYTE(13, t0, 6, 0xb6)

  la t0, misaligned_3
  li t1, 0x76543210
  sw t1, 3(t0)
  CHECK_BYTE(14, t0, 2, 0xc2)
  CHECK_BYTE(15, t0, 3, 0x10)
  CHECK_BYTE(16, t0, 4, 0x32)
  CHECK_BYTE(17, t0, 5, 0x54)
  CHECK_BYTE(18, t0, 6, 0x76)
  CHECK_BYTE(19, t0, 7, 0xc7)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
misaligned_1:
  .byte 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7
  .align 4
misaligned_2:
  .byte 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7
  .align 4
misaligned_3:
  .byte 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7
RVTEST_DATA_END
