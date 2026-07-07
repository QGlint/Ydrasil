OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IROM (rx) : ORIGIN = 0x80000000, LENGTH = 16K
    DRAM (rwx): ORIGIN = 0x80100000, LENGTH = 256K
}

/* 栈顶 */
_stack_top = ORIGIN(DRAM)+LENGTH(DRAM);

/* MMIO符号 */
LED_BASE     = 0x80200040;
SEG_BASE     = 0x80200020;
KEY_BASE     = 0x80200010;
SW_BASE      = 0x80200000;
COUNTER_BASE = 0x80200050;

SECTIONS
{
    .text :
    {
        *(.text.init)
        *(.text*)
    } > IROM

    .rodata :
    {
        *(.rodata*)
    } > IROM

    .data :
    {
        *(.data*)
    } > DRAM

    .bss :
    {
        *(.bss*)
        *(COMMON)
    } > DRAM


}