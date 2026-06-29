.section .init // 初始化段
	.globl   _start // 声明全局入口符号
	.type    _start,@function // 声明_start为函数类型

	//       程序入口
_start:
	.option  push
	.option  norelax
	la       gp, __global_pointer$ // 加载全局指针寄存器
	.option  pop
	la       sp, _sp // 初始化堆栈指针
#ifdef SIMULATION
	csrrwi   x0, sstatus, 0x0 // 清除仿真结果标志
#endif

# 	//       拷贝.data段数据到RAM
# 	la       a0, _data_lma // a0 = .data段LMA（存储在flash/itcm的起始地址）
# 	la       a1, _data // a1 = .data段VMA（RAM/dtcm中的起始地址）
# 	la       a2, _edata // a2 = .data段结束地址
# 	bgeu     a1, a2, data_copy_end // 如果a1 >= a2，跳转到data_copy_end
# data_copy_loop:
# 	lw       t0, (a0) // 从LMA读取数据
# 	sw       t0, (a1) // 写入VMA
# 	addi     a0, a0, 4
# 	addi     a1, a1, 4
# 	bltu     a1, a2, data_copy_loop // 如果a1 < a2，继续循环
# data_copy_end:

	//       清零.bss段
	la       a0, __bss_start // a0 = .bss段起始地址
	la       a1, _end // a1 = .bss段结束地址
	bgeu     a0, a1, bss_clear_end // 如果a0 >= a1，跳转到bss_clear_end
bss_clear_loop:
	sw       zero, (a0) // 清零
	addi     a0, a0, 4
	bltu     a0, a1, bss_clear_loop // 如果a0 < a1，继续循环
bss_clear_end:

	//       设置异常和中断入口地址
#ifdef RTOS_RTTHREAD
	la       a0, SW_handler // 设置RT-Thread下的SW_handler
#else
	la       a0, trap_entry // 设置中断处理函数入口地址
#endif
	csrw     mtvec, a0
#ifndef RTOS_RTTHREAD
	//       调用SystemInit
	call     SystemInit
#endif

	li       a0, 0 // main函数参数a0 = 0
	li       a1, 0 // main函数参数a1 = 0
#ifdef RTOS_RTTHREAD
	//       Call entry function when using RT-Thread
	call     entry
#else
	call     main
#endif

loop:
	j        loop // 死循环，防止main返回
