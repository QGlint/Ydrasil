#include "riscv_test.h"
#include "sw_test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
  li t0, (1 << 13)
  csrs mstatus, t0
  csrw fcsr, zero
  la s0, fp_values

  fld f0, 0(s0)
  fld f1, 8(s0)
  fadd.d f2, f0, f1
  fsd f2, 40(s0)
  lw a0, 40(s0)
  CHECK_EQ_IMM(2, a0, 0x00000000)
  lw a0, 44(s0)
  CHECK_EQ_IMM(3, a0, 0x400e0000)

  fmul.d f3, f0, f1
  fsd f3, 40(s0)
  lw a0, 44(s0)
  CHECK_EQ_IMM(4, a0, 0x400b0000)

  fmadd.d f3, f0, f1, f0
  fsd f3, 40(s0)
  lw a0, 44(s0)
  CHECK_EQ_IMM(5, a0, 0x40138000)

  fdiv.d f3, f1, f0
  fsd f3, 40(s0)
  lw a0, 44(s0)
  CHECK_EQ_IMM(6, a0, 0x3ff80000)

  fsqrt.d f3, f1
  fsd f3, 40(s0)
  lw a0, 44(s0)
  CHECK_EQ_IMM(7, a0, 0x3ff80000)

  fcvt.w.d a0, f0, rne
  CHECK_EQ_IMM(8, a0, 2)
  li t1, -7
  fcvt.d.w f4, t1
  fcvt.w.d a0, f4, rtz
  CHECK_EQ_IMM(9, a0, -7)

  fcvt.s.d f5, f0
  fsw f5, 40(s0)
  lw a0, 40(s0)
  CHECK_EQ_IMM(10, a0, 0x3fc00000)
  fcvt.d.s f6, f5
  feq.d a0, f6, f0
  CHECK_EQ_IMM(11, a0, 1)

  fmin.d f7, f0, f1
  feq.d a0, f7, f0
  CHECK_EQ_IMM(12, a0, 1)
  fmax.d f7, f0, f1
  fle.d a0, f1, f7
  CHECK_EQ_IMM(13, a0, 1)
  fsgnjn.d f7, f0, f1
  fclass.d a0, f7
  CHECK_EQ_IMM(14, a0, 0x2)

  csrw fflags, zero
  fld f8, 16(s0)
  fdiv.d f9, f0, f8
  fclass.d a0, f9
  CHECK_EQ_IMM(15, a0, 0x80)
  csrr a0, fflags
  andi a0, a0, 0x8
  CHECK_EQ_IMM(16, a0, 0x8)

  fld f10, 24(s0)
  fadd.s f11, f10, f5
  fclass.s a0, f11
  CHECK_EQ_IMM(17, a0, 0x200)

  fsd f0, 48(s0)
  fld f12, 48(s0)
  feq.d a0, f12, f0
  CHECK_EQ_IMM(18, a0, 1)

  SW_TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 3
fp_values:
  .dword 0x3ff8000000000000
  .dword 0x4002000000000000
  .dword 0x0000000000000000
  .dword 0x000000003f800000
  .dword 0x7ff8000000000000
  .dword 0x0000000000000000
  .dword 0x0000000000000000
RVTEST_DATA_END
