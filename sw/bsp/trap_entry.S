#define REGBYTES 4
#define STORE sw
#define LOAD lw

    .section .text.vector
    .align   2
    .global  trap_entry
    .weak    trap_entry
    .global  vector_table

vector_table:
    .word    instruction_addr_misaligned_handler // 0 指令地址不对齐
    .word    instruction_access_fault_handler // 1 指令访问错误
    .word    illegal_instruction_handler // 2 非法指令
#ifdef RTOS_RTTHREAD
    .word    cause3_handler // 3 软件中断/断点分流
#else
    .word    cause3_handler // 3 软件中断/断点分流
#endif
    .word    load_misaligned_handler // 4 加载地址不对齐
    .word    load_access_fault_handler // 5 加载访问错误
    .word    store_misaligned_handler // 6 存储/AMO地址不对齐
    .word    cause7_handler // 7 定时器中断/存储访问错误分流
    .word    environment_call_from_u_mode_handler // 8 ECALL来自U模式
    .word    environment_call_from_s_mode_handler // 9 ECALL来自S模式
    .word    reserved_handler // 10 保留
    .word    cause11_handler // 11 外部中断/ECALL来自M模式分流
    .word    instruction_page_fault_handler // 12 指令页错误
    .word    load_page_fault_handler // 13 加载页错误
    .word    reserved_handler // 14 保留
    .word    store_page_fault_handler // 15 存储/AMO页错误
    .word    timer0_event_handler // 16
    .word    timer1_event_handler // 17
    .word    timer2_event_handler // 18
    .word    timer3_event_handler // 19
    .word    spi_event_handler // 20
    .word    i2c0_interrupt_handler // 21
    .word    i2c1_interrupt_handler // 22
    .word    uart0_event_handler // 23
    .word    uart1_event_handler // 24
    .word    gpio0_int_handler // 25
    .word    gpio1_int_handler // 26


    //       异常处理函数弱符号声明
    .weak    instruction_addr_misaligned_handler
    .weak    instruction_access_fault_handler
    .weak    illegal_instruction_handler
    .weak    ebreak_handler
    .weak    load_misaligned_handler
    .weak    load_access_fault_handler
    .weak    store_misaligned_handler
    .weak    store_access_fault_handler
    .weak    environment_call_from_u_mode_handler
    .weak    environment_call_from_s_mode_handler
    .weak    reserved_handler
    .weak    ecall_handler
    .weak    instruction_page_fault_handler
    .weak    load_page_fault_handler
    .weak    store_page_fault_handler
    .weak    machine_software_interrupt_handler
    .weak    machine_timer_interrupt_handler
    .weak    machine_external_interrupt_handler

handle_exception_unknown:
    j        handle_exception_unknown

illegal_instruction_handler:
#ifdef SIMULATION
    call     sim_ctrl_init
    la       a0, illegal_instruction_msg
    jal      ra, xputs
#endif
illegal_instruction_loop:
    j        illegal_instruction_loop

instruction_addr_misaligned_handler:
    j        instruction_addr_misaligned_handler

ecall_handler:
    j        ecall_handler

ebreak_handler:
    j        ebreak_handler

load_misaligned_handler:
    j        load_misaligned_handler

store_misaligned_handler:
    j        store_misaligned_handler

instruction_access_fault_handler:
    j        instruction_access_fault_handler

load_access_fault_handler:
    j        load_access_fault_handler

store_access_fault_handler:
    j        store_access_fault_handler

environment_call_from_u_mode_handler:
    j        environment_call_from_u_mode_handler

environment_call_from_s_mode_handler:
    j        environment_call_from_s_mode_handler

instruction_page_fault_handler:
    j        instruction_page_fault_handler

load_page_fault_handler:
    j        load_page_fault_handler

store_page_fault_handler:
    j        store_page_fault_handler

reserved_handler:
    j        reserved_handler

    //       cause=3分流handler
cause3_handler:
    csrr     t0, mcause
    srli     t1, t0, 31 // 取Interrupt位
    beqz     t1, ebreak_handler // Interrupt=0，异常，跳转断点
#ifdef RTOS_RTTHREAD
    j        SW_handler // Interrupt=1，RT-Thread下跳转SW_handler
#else
    j        machine_software_interrupt_handler // Interrupt=1，中断
#endif

    //       cause=7分流handler
cause7_handler:
    csrr     t0, mcause
    srli     t1, t0, 31 // 取Interrupt位
    beqz     t1, store_access_fault_handler // Interrupt=0，异常，跳转存储/AMO访问错误
    j        machine_timer_interrupt_handler // Interrupt=1，中断
    j        machine_software_interrupt_handler // Interrupt=1，中断

    //       cause=11分流handler
cause11_handler:
    csrr     t0, mcause
    srli     t1, t0, 31 // 取Interrupt位
    beqz     t1, ecall_handler // Interrupt=0，异常，跳转ECALL来自M模式
    j        machine_external_interrupt_handler // Interrupt=1，中断


#ifdef SIMULATION
    .section .rodata
illegal_instruction_msg:
    .string  "illegal instruction exception handler entered\n"
#endif

    /*       异常和中断总入口 */
trap_entry:
    addi     sp, sp, -32*17
    sw       x1, 0*4(sp)
    sw       x5, 1*4(sp)
    sw       x6, 2*4(sp)
    sw       x7, 3*4(sp)
    sw       x10, 4*4(sp)
    sw       x11, 5*4(sp)
    sw       x12, 6*4(sp)
    sw       x13, 7*4(sp)
    sw       x14, 8*4(sp)
    sw       x15, 9*4(sp)
    sw       x16, 10*4(sp)
    sw       x17, 11*4(sp)
    sw       x28, 12*4(sp)
    sw       x29, 13*4(sp)
    sw       x30, 14*4(sp)
    sw       x31, 15*4(sp)
    /*       保存异常(中断)返回地址 */
    csrr     x10, mepc
    sw       x10, 16*4(sp)

    /*       读取异常(中断)号 */
    csrr     a1, mcause
/* 计算偏移地址:
    id       * 4 */
    slli     a1, a1, 2
    la       a0, vector_table
    add      a1, a0, a1
    /*       读取异常(中断)处理函数地址 */
    lw       a1, 0(a1)
    /*       跳转到异常(中断)处理函数 */
    jalr     ra, 0(a1)

    /*       恢复异常(中断)返回地址 */
    lw       x10, 16*4(sp)
    csrw     mepc, x10
    lw       x1, 0*4(sp)
    lw       x5, 1*4(sp)
    lw       x6, 2*4(sp)
    lw       x7, 3*4(sp)
    lw       x10, 4*4(sp)
    lw       x11, 5*4(sp)
    lw       x12, 6*4(sp)
    lw       x13, 7*4(sp)
    lw       x14, 8*4(sp)
    lw       x15, 9*4(sp)
    lw       x16, 10*4(sp)
    lw       x17, 11*4(sp)
    lw       x28, 12*4(sp)
    lw       x29, 13*4(sp)
    lw       x30, 14*4(sp)
    lw       x31, 15*4(sp)
    addi     sp, sp, 32*17
    mret

#ifdef SIMULATION
    .section .rodata
illegal_instruction_msg:
    .string  "illegal instruction exception handler entered\n"
#endif