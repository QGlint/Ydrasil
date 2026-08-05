OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  itcm (rx)  : ORIGIN = 0x80000000, LENGTH = 16K
  dtcm (rwx) : ORIGIN = 0x80100000, LENGTH = 64K
}

SECTIONS
{
  .text :
  {
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > itcm

  . = ORIGIN(dtcm);
  .data :
  {
    *(.data .data.*)
    *(.sdata .sdata.*)
    *(.region_*)
    *(.amo_*)
    *(.s_region_*)
  } > dtcm

  .user_stack : { *(.user_stack .user_stack.*) } > dtcm
  .kernel_data : { *(.kernel_data .kernel_data.*) } > dtcm
  .kernel_stack : { *(.kernel_stack .kernel_stack.*) } > dtcm
  .page_table : { *(.page_table .page_table.*) } > dtcm
  .bss :
  {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
  } > dtcm

  _end = .;
  ASSERT(SIZEOF(.text) <= LENGTH(itcm), "riscv-dv program exceeds Ydrasil ITCM")
  ASSERT((_end - ORIGIN(dtcm)) <= LENGTH(dtcm), "riscv-dv data exceeds Ydrasil DTCM")
}
