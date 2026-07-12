#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, boundary_32
  li t1, 0x11223344
  sw t1, 29(t0)
  CHECK_BYTE(2, t0, 28, 0x5a)
  CHECK_BYTE(3, t0, 29, 0x44)
  CHECK_BYTE(4, t0, 32, 0x11)
  CHECK_BYTE(5, t0, 33, 0x5a)

  la t0, boundary_64
  li t1, 0x55667788
  sw t1, 62(t0)
  CHECK_BYTE(6, t0, 61, 0x6b)
  CHECK_BYTE(7, t0, 62, 0x88)
  CHECK_BYTE(8, t0, 65, 0x55)
  CHECK_BYTE(9, t0, 66, 0x6b)

  la t0, page_boundary
  addi t0, t0, -1
  li t1, 0x99aabbcc
  sw t1, 0(t0)
  CHECK_BYTE(10, t0, -1, 0x7c)
  CHECK_BYTE(11, t0, 0, 0xcc)
  CHECK_BYTE(12, t0, 3, 0x99)
  CHECK_BYTE(13, t0, 4, 0x7c)

  li t0, 0x8013fff8
  lw s0, 0(t0)
  lw s1, 4(t0)

  li t1, 0x0a0b0c0d
  sw t1, 1(t0)
  CHECK_BYTE(14, t0, 1, 0x0d)
  CHECK_BYTE(15, t0, 4, 0x0a)
  sw s0, 0(t0)
  sw s1, 4(t0)

  li t1, 0x1a1b1c1d
  sw t1, 2(t0)
  CHECK_BYTE(16, t0, 2, 0x1d)
  CHECK_BYTE(17, t0, 5, 0x1a)
  sw s0, 0(t0)
  sw s1, 4(t0)

  li t1, 0x2a2b2c2d
  sw t1, 3(t0)
  CHECK_BYTE(18, t0, 3, 0x2d)
  CHECK_BYTE(19, t0, 6, 0x2a)
  sw s0, 0(t0)
  sw s1, 4(t0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 5
boundary_32:
  .fill 68,1,0x5a
  .align 6
boundary_64:
  .fill 68,1,0x6b
  .align 12
  .fill 4096,1,0x7c
page_boundary:
  .fill 8,1,0x7c
RVTEST_DATA_END
