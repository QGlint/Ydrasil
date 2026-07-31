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

  # 历史 load producer 未退休时，无关的简单整数指令仍可进入第二槽。
  la s2, dual_issue_data
  lw s3, 0(s2)
  addi t0, zero, 17
  addi t1, zero, 29
  CHECK_EQ_IMM(6, t0, 17)
  CHECK_EQ_IMM(7, t1, 29)

  # 第二槽真实依赖必须等待 load completion，并使用转发值而非旧 RF 值。
  lw s4, 4(s2)
  addi t2, zero, 3
  add t3, s4, t2
  li t4, 0x13579be2
  bne t3, t4, fail

  # 连续 producer 分配/回收后，第二槽仍应读取最新 producer。
  lw s5, 8(s2)
  addi s5, s5, 1
  addi t5, zero, 5
  xor t6, s5, t5
  li t4, 0x2468acea
  bne t6, t4, fail

  # 相邻 WAW：禁止成对写同一个体系结构寄存器。
  li a0, 11
  li a0, 22
  CHECK_EQ_IMM(8, a0, 22)

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
  CHECK_EQ_IMM(9, s0, 0)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
dual_issue_data:
  .word 0x13579bdf
  .word 0x13579bdf
  .word 0x2468acee
RVTEST_DATA_END
