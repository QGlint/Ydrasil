#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  # 独立整数对：应允许两个槽位同时发射。
  li t0, 1
  li t1, 2
  addi t2, t0, 3
  xori t3, t1, 7
  CHECK_EQ_IMM(2, t2, 4)
  CHECK_EQ_IMM(3, t3, 5)

  # 相邻 RAW：第二条必须保留到下一拍，且不能读取旧值。
  addi t4, t2, 5
  add t5, t4, t3
  CHECK_EQ_IMM(4, t4, 9)
  CHECK_EQ_IMM(5, t5, 14)

  # 相邻 WAW：独立 producer 槽允许成对发射，年轻值必须最终可见。
  li a0, 11
  li a0, 22
  CHECK_EQ_IMM(6, a0, 22)

  # 独立位操作可以进入第二槽位。
  li a1, 0x55aa55aa
  li a2, 0x0f0f0f0f
  andn a3, a1, a2
  xnor a4, a1, a2
  li a5, 0x50a050a0
  bne a3, a5, fail
  li a5, 0xa55aa55a
  bne a4, a5, fail

  # 已采用分支后的年轻指令必须被冲刷。
  li s0, 0
  li s1, 1
  beq s1, s1, 1f
  addi s0, s0, 1
  addi s0, s0, 2
1:
  CHECK_EQ_IMM(7, s0, 0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
RVTEST_DATA_END
