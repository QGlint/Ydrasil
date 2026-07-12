#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  la t0, load_words
  lw t1, source_data
  sw t1, 0(t0)
  lw t2, 0(t0)
  CHECK_EQ_IMM(2, t2, 0x11223344)

  lw t1, source_data
  nop
  sw t1, 4(t0)
  lw t2, 4(t0)
  CHECK_EQ_IMM(3, t2, 0x11223344)

  lw t1, source_data
  nop
  nop
  sw t1, 8(t0)
  lw t2, 8(t0)
  CHECK_EQ_IMM(4, t2, 0x11223344)

  la t3, pointer_word
  lw t0, 0(t3)
  li t1, 0x55667788
  sw t1, 12(t0)
  lw t2, 12(t0)
  CHECK_EQ_IMM(5, t2, 0x55667788)

  lw t1, source_data
  addi t1, t1, 1
  sw t1, 16(t0)
  lw t2, 16(t0)
  CHECK_EQ_IMM(6, t2, 0x11223345)

  lw t1, source_data
  lw t1, source_data_2
  sw t1, 20(t0)
  lw t2, 20(t0)
  CHECK_EQ_IMM(7, t2, 0x89abcdef)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
load_words:
  .space 24
source_data:
  .word 0x11223344
source_data_2:
  .word 0x89abcdef
pointer_word:
  .word load_words
RVTEST_DATA_END
