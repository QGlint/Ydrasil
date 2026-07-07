#ifndef _UTILS_H_
#define _UTILS_H_

#include "sys_defs.h"

/**
 * \brief   NOP Instruction
 * \details
 * No Operation does nothing.
 * This instruction can be used for code alignment purposes.
 */
__STATIC_FORCEINLINE void __NOP(void)
{
  __ASM volatile("nop");
}

/**
 * \brief   Breakpoint Instruction
 * \details
 * Causes the processor to enter Debug state.
 * Debug tools can use this to investigate system state
 * when the instruction at a particular address is reached.
 */
__STATIC_FORCEINLINE void __EBREAK(void)
{
  __ASM volatile("ebreak");
}

/**
 * \brief   Environment Call Instruction
 * \details
 * The ECALL instruction is used to make a service request to
 * the execution environment.
 */
__STATIC_FORCEINLINE void __ECALL(void)
{
  __ASM volatile("ecall");
}

uint64_t get_cycle_value();

#ifdef SIMULATION
#define set_test_pass() asm("csrrwi x0, sstatus, 0x3")
#define set_test_fail() asm("csrrwi x0, sstatus, 0x1")
#endif

#endif
