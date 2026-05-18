# rvtest_min.mk - minimal standalone builder for riscv-tests ISA

# ====== user config ======
RISCV_PREFIX ?= riscv64-elf
ARCH ?= rv32im_zicsr_zifencei
ABI  ?= ilp32

ARCH_MEM ?= harvard

COMP_MODE ?= rvtest

# 1 = force rebuild even if outputs exist
REBUILD ?= 0

# 单个测试文件（不带后缀），例：rv32ui/add
NAME ?= rv32ui_lb

# 输出目录
OUT_DIR ?= build/test
INCLUDES ?=
LDSCRIPT ?=

ifeq ($(ARCH_MEM), harvard)
	IROM_SECTIONS ?= .text .text.* .rodata .rodata.* .tohost
	DRAM_SECTIONS ?= .data .data.* .sdata .sdata.* .bss .bss.* .sbss .sbss.*
	DRAM_SECTFLAGS := --set-section-flags .bss=alloc,load,contents
	DRAM_SECTFLAGS +=--set-section-flags .sbss=alloc,load,contents
endif

# 头文件与链接脚本
ifeq ($(COMP_MODE), rvtest)
# 	INCLUDES += -I"../verif/tests/riscv-tests/env/p" -I"../verif/tests/riscv-tests/isa/macros/scalar"
	LDSCRIPT += linker/link_rvtest.ld
endif

# ====== tools ======
CC      := $(RISCV_PREFIX)-gcc
OBJCOPY := $(RISCV_PREFIX)-objcopy
OBJDUMP := $(RISCV_PREFIX)-objdump

RV_CFLAGS ?= -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -static -mcmodel=medany
LDFLAGS ?=

# ====== derived ======
SRC ?= 


ELF_DIR := $(OUT_DIR)/elf
DUMP_DIR := $(OUT_DIR)/dump
MEM_DIR := $(OUT_DIR)/mem
BIN_DIR := $(OUT_DIR)/bin


ELF  := $(OUT_DIR)/elf/$(NAME).elf
DUMP := $(OUT_DIR)/dump/$(NAME).dump
ITCM := $(OUT_DIR)/mem/$(NAME).itcm
DTCM := $(OUT_DIR)/mem/$(NAME).dtcm
ITCM_BIN  := $(OUT_DIR)/bin/$(NAME)_itcm.bin
DTCM_BIN  := $(OUT_DIR)/bin/$(NAME)_dtcm.bin

.PHONY: rv_all rv_elf rv_dump rv_mem
rv_comp_genmem:
	@if [ "$(REBUILD)" != "1" ] && [ -f "$(ELF)" ] && [ -f "$(DUMP)" ] && [ -f "$(ITCM)" ] && [ -f "$(DTCM)" ]; then \
		echo "[skip] outputs exist for $(NAME) (set REBUILD=1 to force)"; \
	else \
		$(MAKE) rv_elf rv_dump rv_mem; \
	fi

rv_elf:
	@mkdir -p $(ELF_DIR) 
	$(CC) $(RV_CFLAGS) $(INCLUDES) -T $(LDSCRIPT) $(SRC) $(LDFLAGS) -o $(ELF)

rv_dump: rv_elf
	@mkdir -p $(DUMP_DIR)
	$(OBJDUMP) -D $(ELF) > $(DUMP)

rv_mem: rv_elf
	@mkdir -p $(MEM_DIR) $(BIN_DIR)
	# ITCM: text/rodata/tohost
	$(OBJCOPY) -O binary --gap-fill=0x00\
		$(addprefix --only-section=,$(IROM_SECTIONS)) \
		$(ELF) $(ITCM_BIN)
	# DTCM: data/bss
	$(OBJCOPY) -O binary --gap-fill=0x00\
	  $(addprefix --only-section=,$(DRAM_SECTIONS)) \
		$(DRAM_SECTFLAGS) \
	  $(ELF) $(DTCM_BIN) || true
	od -An -t x4 -w4 -v $(ITCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $(ITCM)
	@if [ -s $(DTCM_BIN) ]; then \
	  od -An -t x4 -w4 -v $(DTCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $(DTCM); \
	else \
	  printf "00000000\n" > $(DTCM); \
	fi
