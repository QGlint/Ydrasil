#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, overlap_bytes
  li t1, 0x11223344
  sw t1, 1(t0)
  li t1, 0x55667788
  sw t1, 2(t0)
  li t1, 0x99aabbcc
  sw t1, 3(t0)

  CHECK_BYTE(2, t0, 0, 0xa0)
  CHECK_BYTE(3, t0, 1, 0x44)
  CHECK_BYTE(4, t0, 2, 0x88)
  CHECK_BYTE(5, t0, 3, 0xcc)
  CHECK_BYTE(6, t0, 4, 0xbb)
  CHECK_BYTE(7, t0, 5, 0xaa)
  CHECK_BYTE(8, t0, 6, 0x99)
  CHECK_BYTE(9, t0, 7, 0xa7)

  li t1, 0x01020304
  sw t1, 9(t0)
  li t1, 0xa1a2a3a4
  sw t1, 11(t0)
  CHECK_BYTE(10, t0, 8, 0xa8)
  CHECK_BYTE(11, t0, 9, 0x04)
  CHECK_BYTE(12, t0,10, 0x03)
  CHECK_BYTE(13, t0,11, 0xa4)
  CHECK_BYTE(14, t0,12, 0xa3)
  CHECK_BYTE(15, t0,13, 0xa2)
  CHECK_BYTE(16, t0,14, 0xa1)
  CHECK_BYTE(17, t0,15, 0xaf)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
overlap_bytes:
  .byte 0xa0,0xa1,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7
  .byte 0xa8,0xa9,0xaa,0xab,0xac,0xad,0xae,0xaf
RVTEST_DATA_END
