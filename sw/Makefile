# rvtest_min.mk - minimal standalone builder for riscv-tests ISA

# ====== user config ======
PROJECT_ROOT ?= $(abspath ..)

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
ifeq ($(origin CC),default)
CC := $(RISCV_PREFIX)-gcc
else
CC ?= $(RISCV_PREFIX)-gcc
endif
OBJCOPY ?= $(RISCV_PREFIX)-objcopy
OBJDUMP ?= $(RISCV_PREFIX)-objdump
AR ?= $(RISCV_PREFIX)-ar

RV_CFLAGS ?= -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -static -mcmodel=medany
LDFLAGS ?=

COREMARK_DIR := coremark
COREMARK_PORT_DIR := simple
COREMARK_OUT ?= $(PROJECT_ROOT)/build/app/coremark
COREMARK_NAME := coremark
COREMARK_ELF := $(COREMARK_OUT)/$(COREMARK_NAME).elf
COREMARK_BIN := $(COREMARK_OUT)/$(COREMARK_NAME).bin
COREMARK_DUMP := $(COREMARK_OUT)/$(COREMARK_NAME).dump
COREMARK_ITCM := $(COREMARK_OUT)/$(COREMARK_NAME).itcm
COREMARK_DTCM := $(COREMARK_OUT)/$(COREMARK_NAME).dtcm
COREMARK_ITCM_BIN := $(COREMARK_OUT)/$(COREMARK_NAME)_itcm.bin
COREMARK_DTCM_BIN := $(COREMARK_OUT)/$(COREMARK_NAME)_dtcm.bin
COREMARK_OBJDUMP := $(COREMARK_OUT)/$(COREMARK_NAME).objdump
COREMARK_MAP := $(COREMARK_OUT)/$(COREMARK_NAME).map

BSP_DIR := $(PROJECT_ROOT)/sw/bsp
BSP_INCLUDES := -I$(BSP_DIR)/include
BSP_ASM_SRCS := $(wildcard $(BSP_DIR)/*.S)
BSP_C_SRCS := \
	$(BSP_DIR)/lib/platform.c \
	$(BSP_DIR)/lib/int_handler.c \
	$(BSP_DIR)/lib/sim_ctrl.c \
	$(BSP_DIR)/lib/syscalls.c \
	$(BSP_DIR)/lib/xprintf.c
COREMARK_C_SRCS := \
	$(COREMARK_DIR)/core_list_join.c \
	$(COREMARK_DIR)/core_main.c \
	$(COREMARK_DIR)/core_matrix.c \
	$(COREMARK_DIR)/core_state.c \
	$(COREMARK_DIR)/core_util.c \
	$(COREMARK_DIR)/$(COREMARK_PORT_DIR)/core_portme.c
COREMARK_SRCS := $(BSP_ASM_SRCS) $(BSP_C_SRCS) $(COREMARK_C_SRCS)
COREMARK_CFLAGS := \
	-march=rv32im_zicsr_zifencei \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-O2 \
	-g \
	-ffunction-sections \
	-fdata-sections \
	-fno-builtin \
	-fno-common \
	-nostdlib \
	-nostartfiles \
	-static \
	-DITERATIONS=1 \
	-DCOREMARK_IGNORE_10S_ERROR=1 \
	-DHAS_FLOAT=0 \
	-DYDRASIL_SIM_CTRL=1 \
	-DSDK_BANNER=0 \
	-DPERFORMANCE_RUN=1 \
	-DFLAGS_STR=\"rv32im_zicsr_zifencei-ilp32-O2\" \
	-I$(COREMARK_DIR) \
	-I$(COREMARK_DIR)/$(COREMARK_PORT_DIR) \
	$(BSP_INCLUDES)
COREMARK_LDFLAGS := \
	-march=rv32im_zicsr_zifencei \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-nostartfiles \
	-nostdlib \
	-static \
	-T $(BSP_DIR)/link.lds \
	-Wl,-Map,$(COREMARK_MAP) \
	-Wl,--gc-sections

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
.PHONY: coremark coremark-rebuild coremark-clean coremark-clean-all
.PHONY: coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map
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

coremark: $(COREMARK_ELF) $(COREMARK_BIN) $(COREMARK_DUMP) $(COREMARK_ITCM) $(COREMARK_DTCM)
	@echo "[coremark] ELF  $(COREMARK_ELF)"
	@echo "[coremark] ITCM $(COREMARK_ITCM)"
	@echo "[coremark] DTCM $(COREMARK_DTCM)"

$(COREMARK_OUT):
	@mkdir -p $@

$(COREMARK_ELF): $(COREMARK_SRCS) $(BSP_DIR)/link.lds Makefile | $(COREMARK_OUT)
	$(CC) $(COREMARK_CFLAGS) $(COREMARK_SRCS) $(COREMARK_LDFLAGS) -lgcc -o $@

$(COREMARK_BIN): $(COREMARK_ELF)
	$(OBJCOPY) -O binary $< $@

$(COREMARK_DUMP): $(COREMARK_ELF)
	$(OBJDUMP) -d $< > $@

$(COREMARK_OBJDUMP): $(COREMARK_ELF)
	$(OBJDUMP) -h -S $< > $@

$(COREMARK_ITCM): | $(COREMARK_ELF) $(COREMARK_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.init \
		--only-section=.text \
		--only-section=.text.* \
		--only-section=.preinit_array \
		--only-section=.init_array \
		--only-section=.fini_array \
		--only-section=.ctors \
		--only-section=.dtors \
		$(COREMARK_ELF) $(COREMARK_ITCM_BIN)
	od -An -t x4 -w4 -v $(COREMARK_ITCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@

$(COREMARK_DTCM): | $(COREMARK_ELF) $(COREMARK_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.data \
		--only-section=.bss \
		--only-section=.stack \
		--set-section-flags .bss=alloc,load,contents \
		--set-section-flags .stack=alloc,load,contents \
		$(COREMARK_ELF) $(COREMARK_DTCM_BIN) || true
	@if [ -s $(COREMARK_DTCM_BIN) ]; then \
		od -An -t x4 -w4 -v $(COREMARK_DTCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@; \
	else \
		printf "00000000\n" > $@; \
	fi

coremark-rebuild: coremark-clean-all coremark

coremark-clean:
	$(MAKE) coremark-clean-all

coremark-clean-all:
	rm -rf $(COREMARK_OUT)

coremark-clean-elf:
	rm -f $(COREMARK_ELF)

coremark-clean-bin:
	rm -f $(COREMARK_BIN)

coremark-clean-dump:
	rm -f $(COREMARK_DUMP) $(COREMARK_OBJDUMP)

coremark-clean-mem:
	rm -f $(COREMARK_ITCM) $(COREMARK_DTCM) $(COREMARK_ITCM_BIN) $(COREMARK_DTCM_BIN)

coremark-clean-map:
	rm -f $(COREMARK_MAP)
