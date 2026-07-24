#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  li t0, (1 << 13)
  csrs mstatus, t0
  csrw fcsr, zero
  la s0, fp_words

  flw f0, 0(s0)
  flw f1, 0(s0)
  flw f2, 4(s0)
  fmv.x.w a0, f0
  CHECK_EQ_IMM(2, a0, 0x3fc00000)

  fadd.s f3, f1, f2
  li t1, 17
  li t2, 19
  add t3, t1, t2
  fmv.x.w a0, f3
  CHECK_EQ_IMM(3, a0, 0x40700000)
  CHECK_EQ_IMM(4, t3, 36)

  fmul.s f4, f1, f2
  fmv.x.w a0, f4
  CHECK_EQ_IMM(5, a0, 0x40580000)

  fmadd.s f5, f1, f2, f1
  fmv.x.w a0, f5
  CHECK_EQ_IMM(6, a0, 0x409c0000)

  fsw f5, 16(s0)
  flw f6, 16(s0)
  fmv.x.w a0, f6
  CHECK_EQ_IMM(7, a0, 0x409c0000)

  fcvt.w.s t4, f3, rtz
  CHECK_EQ_IMM(8, t4, 3)
  li t5, 7
  fcvt.s.w f7, t5
  fmv.x.w a0, f7
  CHECK_EQ_IMM(9, a0, 0x40e00000)

  flw f8, 8(s0)
  fdiv.s f9, f1, f8
  li t1, 123
  li t2, 17
  mul t3, t1, t2
  CHECK_EQ_IMM(10, t3, 2091)
  fclass.s a0, f9
  CHECK_EQ_IMM(11, a0, 0x80)
  csrr a0, fflags
  andi a0, a0, 0x8
  CHECK_EQ_IMM(12, a0, 0x8)

  csrw fflags, zero
  fcvt.w.s a0, f1, rne
  CHECK_EQ_IMM(13, a0, 2)
  fcvt.w.s a0, f1, rtz
  CHECK_EQ_IMM(14, a0, 1)
  fcvt.w.s a0, f1, rdn
  CHECK_EQ_IMM(15, a0, 1)
  fcvt.w.s a0, f1, rup
  CHECK_EQ_IMM(16, a0, 2)
  fcvt.w.s a0, f1, rmm
  CHECK_EQ_IMM(17, a0, 2)

  li t0, 3
  csrw frm, t0
  fcvt.w.s a0, f1, dyn
  CHECK_EQ_IMM(18, a0, 2)

  fmsub.s f10, f1, f2, f1
  fmv.x.w a0, f10
  CHECK_EQ_IMM(19, a0, 0x3ff00000)
  fnmsub.s f10, f1, f2, f1
  fmv.x.w a0, f10
  CHECK_EQ_IMM(20, a0, 0xbff00000)
  fnmadd.s f10, f1, f2, f1
  fmv.x.w a0, f10
  CHECK_EQ_IMM(21, a0, 0xc09c0000)

  fsqrt.s f10, f2
  fmv.x.w a0, f10
  CHECK_EQ_IMM(22, a0, 0x3fc00000)
  fsgnjn.s f10, f1, f2
  fmv.x.w a0, f10
  CHECK_EQ_IMM(23, a0, 0xbfc00000)
  fsgnjx.s f10, f1, f10
  fmv.x.w a0, f10
  CHECK_EQ_IMM(24, a0, 0xbfc00000)

  fmin.s f10, f1, f2
  fmv.x.w a0, f10
  CHECK_EQ_IMM(25, a0, 0x3fc00000)
  fmax.s f10, f1, f2
  fmv.x.w a0, f10
  CHECK_EQ_IMM(26, a0, 0x40100000)
  feq.s t0, f1, f1
  addi t0, t0, 41
  CHECK_EQ_IMM(27, t0, 42)
  flt.s a0, f1, f2
  CHECK_EQ_IMM(28, a0, 1)
  fle.s a0, f2, f1
  CHECK_EQ_IMM(29, a0, 0)

  li t0, 0x80000000
  fmv.w.x f11, t0
  fclass.s a0, f11
  CHECK_EQ_IMM(30, a0, 0x8)
  li t0, 0x00000001
  fmv.w.x f11, t0
  fclass.s a0, f11
  CHECK_EQ_IMM(31, a0, 0x20)
  li t0, 0x7f800000
  fmv.w.x f11, t0
  fclass.s a0, f11
  CHECK_EQ_IMM(32, a0, 0x80)
  li t0, 0x7fc00000
  fmv.w.x f11, t0
  fclass.s a0, f11
  CHECK_EQ_IMM(33, a0, 0x200)

  csrw fflags, zero
  li t0, 0xbf800000
  fmv.w.x f11, t0
  fsqrt.s f12, f11
  fclass.s a0, f12
  CHECK_EQ_IMM(34, a0, 0x200)
  csrr a0, fflags
  andi a0, a0, 0x10
  CHECK_EQ_IMM(35, a0, 0x10)

  csrw fflags, zero
  li t0, 0x7f7fffff
  fmv.w.x f11, t0
  fmul.s f12, f11, f11
  fclass.s a0, f12
  CHECK_EQ_IMM(36, a0, 0x80)
  csrr a0, fflags
  andi a0, a0, 0x5
  CHECK_EQ_IMM(37, a0, 0x5)

  li t0, -1
  fcvt.s.wu f11, t0
  fmv.x.w a0, f11
  CHECK_EQ_IMM(38, a0, 0x4f800000)
  fcvt.wu.s a0, f2, rtz
  CHECK_EQ_IMM(39, a0, 2)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 4
fp_words:
  .word 0x3fc00000
  .word 0x40100000
  .word 0x00000000
  .word 0x7fc00000
  .word 0x00000000
RVTEST_DATA_END
