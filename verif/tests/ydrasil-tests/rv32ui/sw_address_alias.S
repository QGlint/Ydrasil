#include "riscv_test.h"
#include "sw_test_macros.h"

#define STORE_CHECK(testnum, offset, value) \
  li TESTNUM, testnum;                   \
  li t1, value;                          \
  sw t1, offset(t0);                     \
  lw t2, offset(t0);                     \
  bne t1, t2, fail

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la t0, alias_area
  STORE_CHECK(2,    0, 0x11111111)
  STORE_CHECK(3,   32, 0x22222222)
  STORE_CHECK(4,   64, 0x33333333)
  STORE_CHECK(5,  256, 0x44444444)
  STORE_CHECK(6, 1024, 0x55555555)

  addi t3, t0, 2047
  addi t3, t3, 1
  li t1, 0x66666666
  sw t1, 2044(t3)
  lw t2, 2044(t3)
  CHECK_EQ_IMM(7, t2, 0x66666666)

  li t1, 0x77777777
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(8, t2, 0x77777777)
  lw t2, 32(t0)
  CHECK_EQ_IMM(9, t2, 0x22222222)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 12
alias_area:
  .space 4096
  .word 0
RVTEST_DATA_END
