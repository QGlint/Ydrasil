#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  la s0, bypass_words
  li t2, 0x01010101

  lw t0, source_a
  add t1, t2, t0
  sw t1, 0(s0)
  lw t3, 0(s0)
  CHECK_EQ_IMM(2, t3, 0x13355779)

  lw t0, source_b
  sub t1, t0, t2
  sw t1, 4(s0)
  lw t3, 4(s0)
  CHECK_EQ_IMM(3, t3, 0x879accee)

  lw t0, source_a
  xor t1, t2, t0
  sw t1, 8(s0)
  lw t3, 8(s0)
  CHECK_EQ_IMM(4, t3, 0x13355779)

  lw t0, source_b
  sltu t1, t2, t0
  sw t1, 12(s0)
  lw t3, 12(s0)
  CHECK_EQ_IMM(5, t3, 1)

  lw t0, source_a
  beq t2, t0, fail
  sw t0, 16(s0)
  lw t3, 16(s0)
  CHECK_EQ_IMM(6, t3, 0x12345678)

  # store 使本地热数据项失效，随后的冷 load 必须保持立即消费者，
  # 直到匹配的 LSU 完成事件到达。
  li t4, 0x10203040
  sw t4, 20(s0)
  lw t0, 20(s0)
  add t1, t0, t2
  sw t1, 24(s0)
  lw t3, 24(s0)
  CHECK_EQ_IMM(7, t3, 0x11213141)

  # 前一次读取已填充热数据项，再用立即消费者覆盖单周期本地完成路径。
  lw t0, 20(s0)
  xor t1, t0, t2
  sw t1, 28(s0)
  lw t3, 28(s0)
  CHECK_EQ_IMM(8, t3, 0x11213141)

  # 连续 load-use 对在完成与架构写回重叠时仍须保持 producer 标签和值独立。
  lw t0, source_a
  add t1, t0, t2
  lw t3, source_b
  sub t4, t3, t2
  xor t5, t1, t4
  sw t5, 32(s0)
  lw t3, 32(s0)
  CHECK_EQ_IMM(9, t3, 0x94af9b97)

  # 预测错误的跳转清除错误路径 load 及消费者；随后复用相同目的寄存器，
  # 检查旧完成事件不会错误释放新的 producer。
  li t6, 0xdeadbeef
  beq zero, zero, 1f
  lw t0, source_b
  add t6, t0, t2
1:
  lw t0, source_a
  add t6, t0, t2
  sw t6, 36(s0)
  lw t3, 36(s0)
  CHECK_EQ_IMM(10, t3, 0x13355779)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
bypass_words:
  .space 40
source_a:
  .word 0x12345678
source_b:
  .word 0x889bcdef
RVTEST_DATA_END
