#ifndef YDRASIL_SW_TEST_MACROS_H
#define YDRASIL_SW_TEST_MACROS_H

#define CHECK_EQ_IMM(testnum, actual, expected) \
  li TESTNUM, testnum;                        \
  li t6, expected;                            \
  bne actual, t6, fail

#define CHECK_BYTE(testnum, base, offset, expected) \
  li TESTNUM, testnum;                              \
  lbu t5, offset(base);                             \
  li t6, expected;                                  \
  bne t5, t6, fail

#define SW_TEST_PASSFAIL \
  RVTEST_PASS;            \
fail:                     \
  RVTEST_FAIL

#endif
