#include "cpuport.h"

    .section .text.trap_dispatch, "ax"
    .align 2
    .globl rt_hw_do_after_save_above
    .type rt_hw_do_after_save_above, @function
rt_hw_do_after_save_above:
    addi sp, sp, -16
    STORE ra, 0(sp)

    csrr a0, mcause
    call rt_rv32_system_irq_handler

    LOAD ra, 0(sp)
    addi sp, sp, 16
    ret
