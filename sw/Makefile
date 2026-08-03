# rvtest_min.mk - minimal standalone builder for riscv-tests ISA

# ====== user config ======
PROJECT_ROOT ?= $(abspath ..)

# This standalone software makefile is also invoked directly, so it cannot
# rely on the top-level config.mk to select the repository toolchain.
RISCV_TOOLCHAIN_ROOT ?= $(PROJECT_ROOT)/tools/riscv
RISCV_TOOLCHAIN_BIN ?= $(RISCV_TOOLCHAIN_ROOT)/bin
RISCV_TOOLCHAIN_TRIPLE ?= riscv64-unknown-elf
override RISCV_TOOLCHAIN_PREFIX := $(RISCV_TOOLCHAIN_BIN)/$(RISCV_TOOLCHAIN_TRIPLE)
override RISCV_PREFIX := $(RISCV_TOOLCHAIN_PREFIX)
RISCV_TOOLCHAIN_TOOLS := gcc g++ ar objcopy objdump size
RISCV_TOOLCHAIN_MISSING := $(strip $(shell \
	for tool in $(RISCV_TOOLCHAIN_TOOLS); do \
		path="$(RISCV_TOOLCHAIN_PREFIX)-$$tool"; \
		if [ ! -x "$$path" ]; then printf '%s ' "$$path"; fi; \
	done))
ifneq ($(RISCV_TOOLCHAIN_MISSING),)
$(error Required RISC-V toolchain is missing or not executable: $(RISCV_TOOLCHAIN_MISSING). Expected tools under $(RISCV_TOOLCHAIN_BIN); refusing to use a system compiler)
endif
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
override CC := $(RISCV_TOOLCHAIN_PREFIX)-gcc
override OBJCOPY := $(RISCV_TOOLCHAIN_PREFIX)-objcopy
override OBJDUMP := $(RISCV_TOOLCHAIN_PREFIX)-objdump
override AR := $(RISCV_TOOLCHAIN_PREFIX)-ar

RV_CFLAGS ?= -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -static -mcmodel=medany
LDFLAGS ?=

COREMARK_DIR := coremark
COREMARK_PORT_DIR := simple
COREMARK_OUT ?= $(PROJECT_ROOT)/build/app/coremark
COREMARK_NAME := coremark
COREMARK_ITERATIONS ?= 1
COREMARK_HAS_FLOAT ?= 1
COREMARK_EXTRA_CFLAGS ?=
COREMARK_APP_ONLY_CFLAGS ?=
COREMARK_FLAGS_STR ?= $(ARCH)-$(ABI)-O2
COREMARK_ELF := $(COREMARK_OUT)/$(COREMARK_NAME).elf
COREMARK_BIN := $(COREMARK_OUT)/$(COREMARK_NAME).bin
COREMARK_DUMP := $(COREMARK_OUT)/$(COREMARK_NAME).dump
COREMARK_ITCM := $(COREMARK_OUT)/$(COREMARK_NAME).itcm
COREMARK_DTCM := $(COREMARK_OUT)/$(COREMARK_NAME).dtcm
COREMARK_ITCM_BIN := $(COREMARK_OUT)/$(COREMARK_NAME)_itcm.bin
COREMARK_DTCM_BIN := $(COREMARK_OUT)/$(COREMARK_NAME)_dtcm.bin
COREMARK_OBJDUMP := $(COREMARK_OUT)/$(COREMARK_NAME).objdump
COREMARK_MAP := $(COREMARK_OUT)/$(COREMARK_NAME).map
SORT_APP_DIR := $(PROJECT_ROOT)/verif/tests/sw_tests/sort
SORT_APP_OUT ?= $(PROJECT_ROOT)/build/app/sort
SORT_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(SORT_APP_DIR)/*.c))))
SORT_APP_ELFS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .elf,$(SORT_APP_NAMES)))
SORT_APP_BINS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .bin,$(SORT_APP_NAMES)))
SORT_APP_DUMPS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .dump,$(SORT_APP_NAMES)))
SORT_APP_ITCMS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .itcm,$(SORT_APP_NAMES)))
SORT_APP_DTCMS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .dtcm,$(SORT_APP_NAMES)))
SORT_APP_EXTRA_CFLAGS ?=
SORT_APP_ONLY_CFLAGS ?=
BOUNDARY_APP_DIR := $(PROJECT_ROOT)/verif/tests/sw_tests/boundary
BOUNDARY_APP_OUT ?= $(PROJECT_ROOT)/build/app/boundary
BOUNDARY_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(BOUNDARY_APP_DIR)/*.c))))
BOUNDARY_APP_ELFS := $(addprefix $(BOUNDARY_APP_OUT)/,$(addsuffix .elf,$(BOUNDARY_APP_NAMES)))
BOUNDARY_APP_BINS := $(addprefix $(BOUNDARY_APP_OUT)/,$(addsuffix .bin,$(BOUNDARY_APP_NAMES)))
BOUNDARY_APP_DUMPS := $(addprefix $(BOUNDARY_APP_OUT)/,$(addsuffix .dump,$(BOUNDARY_APP_NAMES)))
BOUNDARY_APP_ITCMS := $(addprefix $(BOUNDARY_APP_OUT)/,$(addsuffix .itcm,$(BOUNDARY_APP_NAMES)))
BOUNDARY_APP_DTCMS := $(addprefix $(BOUNDARY_APP_OUT)/,$(addsuffix .dtcm,$(BOUNDARY_APP_NAMES)))
BOUNDARY_APP_ONLY_CFLAGS ?=

BSP_DIR := $(PROJECT_ROOT)/sw/bsp
BSP_LINKER_SCRIPT ?= $(BSP_DIR)/link.lds
BSP_INCLUDES := -I$(BSP_DIR)/include
BSP_ASM_SRCS := $(wildcard $(BSP_DIR)/*.S)
BSP_C_SRCS := \
	$(BSP_DIR)/lib/platform.c \
	$(BSP_DIR)/lib/int_handler.c \
	$(BSP_DIR)/lib/memory.c \
	$(BSP_DIR)/lib/sim_ctrl.c \
	$(BSP_DIR)/lib/syscalls.c \
	$(BSP_DIR)/lib/xprintf.c

# RT-Thread applications use the same software entry point as the other
# programs in this directory.  The BSP remains responsible for board/kernel
# integration; an application supplies only its own SConscript manifest.
rtthread_abs = $(abspath $(if $(filter /%,$(1)),$(1),$(PROJECT_ROOT)/$(1)))
RTTHREAD_BSP_DIR := $(PROJECT_ROOT)/sw/bsp/rtthread
RTTHREAD_SCONS ?= $(if $(strip $(SCONS)),$(SCONS),scons)
RTTHREAD_JOBS ?= $(shell nproc 2>/dev/null || echo 1)
RTTHREAD_APP ?= default
RTTHREAD_PROFILE ?= custom
RTTHREAD_OPT ?= -Os
RTTHREAD_ITERATIONS ?= 1
RTTHREAD_OUTPUT_DIR ?= $(PROJECT_ROOT)/build/app/rtthread
RTTHREAD_OUTPUT_BASENAME ?= rtthread
RTTHREAD_LINKER ?= $(BSP_LINKER_SCRIPT)
RTTHREAD_BUILD_DIR ?= $(RTTHREAD_OUTPUT_DIR)/objects
RTTHREAD_SCONS_ARGS ?=
override RTTHREAD_OUTPUT_DIR := $(call rtthread_abs,$(RTTHREAD_OUTPUT_DIR))
override RTTHREAD_LINKER := $(call rtthread_abs,$(RTTHREAD_LINKER))
override RTTHREAD_BUILD_DIR := $(call rtthread_abs,$(RTTHREAD_BUILD_DIR))

RTTHREAD_COREMARK_PROFILES ?= Os O2 O3
RTTHREAD_COREMARK_OPT_Os := -Os
RTTHREAD_COREMARK_OPT_O2 := -O2
RTTHREAD_COREMARK_OPT_O3 := -O3
# Optional per-source optimization for the CoreMark algorithm group.  Keep
# empty by default so the existing profile targets remain comparable.
RTTHREAD_COREMARK_CORE_CFLAGS ?=
RTTHREAD_COREMARK_OUTPUT_ROOT ?= $(PROJECT_ROOT)/build/app/rtthread-coremark
RTTHREAD_COREMARK_LINKER ?= $(RTTHREAD_COREMARK_OUTPUT_ROOT)/itcm-64K.lds
RTTHREAD_COREMARK_ITERATIONS ?= 1
override RTTHREAD_COREMARK_OUTPUT_ROOT := $(call rtthread_abs,$(RTTHREAD_COREMARK_OUTPUT_ROOT))
override RTTHREAD_COREMARK_LINKER := $(call rtthread_abs,$(RTTHREAD_COREMARK_LINKER))
RTTHREAD_COREMARK_BUILD_TARGETS := $(addprefix rtthread-coremark-build-,$(RTTHREAD_COREMARK_PROFILES))
RTTHREAD_UTEST_OPT ?= -Os
RTTHREAD_UTEST_OUTPUT_ROOT ?= $(PROJECT_ROOT)/build/app/rtthread-utest
RTTHREAD_UTEST_LINKER ?= $(RTTHREAD_UTEST_OUTPUT_ROOT)/itcm-64K.lds
override RTTHREAD_UTEST_OUTPUT_ROOT := $(call rtthread_abs,$(RTTHREAD_UTEST_OUTPUT_ROOT))
override RTTHREAD_UTEST_LINKER := $(call rtthread_abs,$(RTTHREAD_UTEST_LINKER))
COREMARK_C_SRCS := \
	$(COREMARK_DIR)/core_list_join.c \
	$(COREMARK_DIR)/core_main.c \
	$(COREMARK_DIR)/core_matrix.c \
	$(COREMARK_DIR)/core_state.c \
	$(COREMARK_DIR)/core_util.c \
	$(COREMARK_DIR)/$(COREMARK_PORT_DIR)/core_portme.c
COREMARK_SRCS := $(BSP_ASM_SRCS) $(BSP_C_SRCS) $(COREMARK_C_SRCS)
COREMARK_CFLAGS := \
	-march=$(ARCH) \
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
	-DITERATIONS=$(COREMARK_ITERATIONS) \
	-DCOREMARK_IGNORE_10S_ERROR=1 \
	-DHAS_FLOAT=$(COREMARK_HAS_FLOAT) \
	-DYDRASIL_SIM_CTRL=1 \
	-DSDK_BANNER=0 \
	-DPERFORMANCE_RUN=1 \
	-DFLAGS_STR=\"$(COREMARK_FLAGS_STR)\" \
	-I$(COREMARK_DIR) \
	-I$(COREMARK_DIR)/$(COREMARK_PORT_DIR) \
	$(BSP_INCLUDES) \
	$(COREMARK_EXTRA_CFLAGS)
COREMARK_LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-nostartfiles \
	-nostdlib \
	-static \
	-T $(BSP_LINKER_SCRIPT) \
	-Wl,-Map,$(COREMARK_MAP) \
	-Wl,--gc-sections
SORT_APP_CFLAGS := \
	-march=$(ARCH) \
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
	-DYDRASIL_SIM_CTRL=1 \
	-DSDK_BANNER=0 \
	-I$(SORT_APP_DIR) \
	$(BSP_INCLUDES) \
	$(SORT_APP_EXTRA_CFLAGS)
SORT_APP_LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-nostartfiles \
	-nostdlib \
	-static \
	-T $(BSP_LINKER_SCRIPT) \
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
.PHONY: coremark coremark-rebuild coremark-clean coremark-clean-all sort_app sort_app-rebuild sort_app-clean
.PHONY: boundary_app boundary_app-rebuild boundary_app-clean
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

ifneq ($(strip $(COREMARK_APP_ONLY_CFLAGS)),)
$(COREMARK_ELF): $(COREMARK_SRCS) $(BSP_LINKER_SCRIPT) Makefile | $(COREMARK_OUT)
	@set -eu; obj_dir="$(COREMARK_OUT)/obj"; rm -rf "$$obj_dir"; mkdir -p "$$obj_dir"; objects=""; \
	for src in $(BSP_ASM_SRCS) $(BSP_C_SRCS); do base=$${src##*/}; base=$${base%.*}; obj="$$obj_dir/bsp_$$base.o"; \
		$(CC) $(COREMARK_CFLAGS) -c "$$src" -o "$$obj"; objects="$$objects $$obj"; done; \
	for src in $(COREMARK_C_SRCS); do base=$${src##*/}; base=$${base%.*}; obj="$$obj_dir/app_$$base.o"; \
		$(CC) $(COREMARK_CFLAGS) $(COREMARK_APP_ONLY_CFLAGS) -c "$$src" -o "$$obj"; objects="$$objects $$obj"; done; \
	$(CC) $(COREMARK_LDFLAGS) $$objects -lgcc -o "$@"
else
$(COREMARK_ELF): $(COREMARK_SRCS) $(BSP_LINKER_SCRIPT) Makefile | $(COREMARK_OUT)
	$(CC) $(COREMARK_CFLAGS) $(COREMARK_SRCS) $(COREMARK_LDFLAGS) -lgcc -o $@
endif

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

sort_app: $(SORT_APP_ELFS) $(SORT_APP_BINS) $(SORT_APP_DUMPS) $(SORT_APP_ITCMS) $(SORT_APP_DTCMS)
	@echo "[sort_app] built: $(SORT_APP_NAMES)"

$(SORT_APP_OUT):
	@mkdir -p $@

ifneq ($(strip $(SORT_APP_ONLY_CFLAGS)),)
$(SORT_APP_OUT)/%.elf: $(SORT_APP_DIR)/%.c $(SORT_APP_DIR)/sort_common.h $(SORT_APP_DIR)/sort_data.h $(BSP_LINKER_SCRIPT) Makefile | $(SORT_APP_OUT)
	@set -eu; obj_dir="$(SORT_APP_OUT)/obj/$*"; rm -rf "$$obj_dir"; mkdir -p "$$obj_dir"; objects=""; \
	for src in $(BSP_ASM_SRCS) $(BSP_C_SRCS); do base=$${src##*/}; base=$${base%.*}; obj="$$obj_dir/bsp_$$base.o"; \
		$(CC) $(SORT_APP_CFLAGS) -c "$$src" -o "$$obj"; objects="$$objects $$obj"; done; \
	app_obj="$$obj_dir/app_$*.o"; $(CC) $(SORT_APP_CFLAGS) $(SORT_APP_ONLY_CFLAGS) -c "$<" -o "$$app_obj"; \
	$(CC) $(SORT_APP_LDFLAGS) $$objects "$$app_obj" -Wl,-Map,$(@:.elf=.map) -lgcc -o "$@"
else
$(SORT_APP_OUT)/%.elf: $(SORT_APP_DIR)/%.c $(SORT_APP_DIR)/sort_common.h $(SORT_APP_DIR)/sort_data.h $(BSP_LINKER_SCRIPT) Makefile | $(SORT_APP_OUT)
	$(CC) $(SORT_APP_CFLAGS) $(BSP_ASM_SRCS) $(BSP_C_SRCS) $< $(SORT_APP_LDFLAGS) -Wl,-Map,$(@:.elf=.map) -lgcc -o $@
endif

$(SORT_APP_OUT)/%.bin: $(SORT_APP_OUT)/%.elf
	$(OBJCOPY) -O binary $< $@

$(SORT_APP_OUT)/%.dump: $(SORT_APP_OUT)/%.elf
	$(OBJDUMP) -d $< > $@

$(SORT_APP_OUT)/%.itcm: $(SORT_APP_OUT)/%.elf | $(SORT_APP_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.init \
		--only-section=.text \
		--only-section=.text.* \
		--only-section=.preinit_array \
		--only-section=.init_array \
		--only-section=.fini_array \
		--only-section=.ctors \
		--only-section=.dtors \
		$< $(@:.itcm=_itcm.bin)
	od -An -t x4 -w4 -v $(@:.itcm=_itcm.bin) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@

$(SORT_APP_OUT)/%.dtcm: $(SORT_APP_OUT)/%.elf | $(SORT_APP_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.data \
		--only-section=.bss \
		--only-section=.stack \
		--set-section-flags .bss=alloc,load,contents \
		--set-section-flags .stack=alloc,load,contents \
		$< $(@:.dtcm=_dtcm.bin) || true
	@if [ -s $(@:.dtcm=_dtcm.bin) ]; then \
		od -An -t x4 -w4 -v $(@:.dtcm=_dtcm.bin) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@; \
	else \
		printf "00000000\n" > $@; \
	fi

sort_app-rebuild: sort_app-clean sort_app

sort_app-clean:
	rm -rf $(SORT_APP_OUT)

boundary_app: $(BOUNDARY_APP_ELFS) $(BOUNDARY_APP_BINS) $(BOUNDARY_APP_DUMPS) $(BOUNDARY_APP_ITCMS) $(BOUNDARY_APP_DTCMS)
	@echo "[boundary_app] built: $(BOUNDARY_APP_NAMES)"

$(BOUNDARY_APP_OUT):
	@mkdir -p $@

ifneq ($(strip $(BOUNDARY_APP_ONLY_CFLAGS)),)
$(BOUNDARY_APP_OUT)/%.elf: $(BOUNDARY_APP_DIR)/%.c $(BOUNDARY_APP_DIR)/boundary.h $(BSP_ASM_SRCS) $(BSP_C_SRCS) $(BSP_DIR)/link.lds Makefile | $(BOUNDARY_APP_OUT)
	@set -eu; \
	obj_dir="$(BOUNDARY_APP_OUT)/obj/$*"; rm -rf "$$obj_dir"; mkdir -p "$$obj_dir"; objects=""; \
	for src in $(BSP_ASM_SRCS) $(BSP_C_SRCS); do \
		base=$${src##*/}; base=$${base%.*}; obj="$$obj_dir/$$base.o"; \
		$(CC) $(SORT_APP_CFLAGS) $(BOUNDARY_EXTRA_CFLAGS) -I$(BOUNDARY_APP_DIR) -c "$$src" -o "$$obj"; \
		objects="$$objects $$obj"; \
	done; \
	app_obj="$$obj_dir/$*.o"; \
	$(CC) $(SORT_APP_CFLAGS) $(BOUNDARY_EXTRA_CFLAGS) $(BOUNDARY_APP_ONLY_CFLAGS) -I$(BOUNDARY_APP_DIR) -c "$<" -o "$$app_obj"; \
	$(CC) $(SORT_APP_LDFLAGS) $$objects "$$app_obj" -Wl,-Map,$(@:.elf=.map) -lgcc -o "$@"
else
$(BOUNDARY_APP_OUT)/%.elf: $(BOUNDARY_APP_DIR)/%.c $(BOUNDARY_APP_DIR)/boundary.h $(BSP_ASM_SRCS) $(BSP_C_SRCS) $(BSP_DIR)/link.lds Makefile | $(BOUNDARY_APP_OUT)
	$(CC) $(SORT_APP_CFLAGS) $(BOUNDARY_EXTRA_CFLAGS) -I$(BOUNDARY_APP_DIR) $(BSP_ASM_SRCS) $(BSP_C_SRCS) $< $(SORT_APP_LDFLAGS) -Wl,-Map,$(@:.elf=.map) -lgcc -o $@
endif

$(BOUNDARY_APP_OUT)/%.bin: $(BOUNDARY_APP_OUT)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BOUNDARY_APP_OUT)/%.dump: $(BOUNDARY_APP_OUT)/%.elf
	$(OBJDUMP) -d $< > $@

$(BOUNDARY_APP_OUT)/%.itcm: $(BOUNDARY_APP_OUT)/%.elf | $(BOUNDARY_APP_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 --only-section=.init --only-section=.text --only-section=.text.* --only-section=.text.vector $< $(@:.itcm=_itcm.bin)
	od -An -t x4 -w4 -v $(@:.itcm=_itcm.bin) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@

$(BOUNDARY_APP_OUT)/%.dtcm: $(BOUNDARY_APP_OUT)/%.elf | $(BOUNDARY_APP_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 --only-section=.tohost --only-section=.data --only-section=.bss --only-section=.stack --set-section-flags .bss=alloc,load,contents --set-section-flags .stack=alloc,load,contents $< $(@:.dtcm=_dtcm.bin) || true
	@if [ -s $(@:.dtcm=_dtcm.bin) ]; then od -An -t x4 -w4 -v $(@:.dtcm=_dtcm.bin) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@; else printf "00000000\n" > $@; fi

boundary_app-rebuild: boundary_app-clean
	@$(MAKE) boundary_app

boundary_app-clean:
	rm -rf $(BOUNDARY_APP_OUT)

.PHONY: rtthread rtthread-build rtthread-clean rtthread-coremark \
	rtthread-coremark-build rtthread-coremark-build-all rtthread-coremark-clean \
	rtthread-utest rtthread-utest-build rtthread-utest-clean \
	$(RTTHREAD_COREMARK_BUILD_TARGETS)

rtthread: rtthread-build

rtthread-build:
	@mkdir -p "$(RTTHREAD_OUTPUT_DIR)"
	@cd "$(RTTHREAD_BSP_DIR)" && \
		PYTHONDONTWRITEBYTECODE=1 \
		RTT_APP="$(RTTHREAD_APP)" \
		RTT_APP_PROFILE="$(RTTHREAD_PROFILE)" \
		RTT_APP_ITERATIONS="$(RTTHREAD_ITERATIONS)" \
		RTT_OPT="$(RTTHREAD_OPT)" \
		RTT_OUTPUT_DIR="$(RTTHREAD_OUTPUT_DIR)" \
		RTT_OUTPUT_BASENAME="$(RTTHREAD_OUTPUT_BASENAME)" \
		RTT_LINKER="$(RTTHREAD_LINKER)" \
		RTT_BUILD_DIR="$(RTTHREAD_BUILD_DIR)" \
		RTT_COREMARK_CORE_CFLAGS="$(RTTHREAD_COREMARK_CORE_CFLAGS)" \
		RTT_CC_PREFIX="$(RISCV_TOOLCHAIN_PREFIX)-" \
		RTT_EXEC_PATH="$(RISCV_TOOLCHAIN_BIN)" \
		$(RTTHREAD_SCONS) -j$(RTTHREAD_JOBS) $(RTTHREAD_SCONS_ARGS)

rtthread-clean:
	rm -rf "$(RTTHREAD_OUTPUT_DIR)"

rtthread-coremark: rtthread-coremark-build

rtthread-coremark-build: rtthread-coremark-build-all

rtthread-coremark-build-all: $(RTTHREAD_COREMARK_BUILD_TARGETS)

$(RTTHREAD_COREMARK_LINKER): $(BSP_LINKER_SCRIPT)
	@mkdir -p "$(dir $@)"
	@sed 's/LENGTH = 16K/LENGTH = 64K/' "$<" > "$@"
	@grep -q 'LENGTH = 64K' "$@"

define RTTHREAD_COREMARK_BUILD_template
rtthread-coremark-build-$(1): $(RTTHREAD_COREMARK_LINKER)
	@$(MAKE) --no-print-directory rtthread \
		RTTHREAD_APP=rtthread-coremark \
		RTTHREAD_PROFILE=$(1) \
		RTTHREAD_OPT="$(RTTHREAD_COREMARK_OPT_$(1))" \
		RTTHREAD_COREMARK_CORE_CFLAGS="$(RTTHREAD_COREMARK_CORE_CFLAGS)" \
		RTTHREAD_ITERATIONS=$(RTTHREAD_COREMARK_ITERATIONS) \
		RTTHREAD_OUTPUT_DIR="$(RTTHREAD_COREMARK_OUTPUT_ROOT)/$(1)" \
		RTTHREAD_OUTPUT_BASENAME=rtthread_coremark \
		RTTHREAD_LINKER="$(RTTHREAD_COREMARK_LINKER)"
endef
$(foreach profile,$(RTTHREAD_COREMARK_PROFILES),$(eval $(call RTTHREAD_COREMARK_BUILD_template,$(profile))))

rtthread-coremark-clean:
	rm -rf "$(RTTHREAD_COREMARK_OUTPUT_ROOT)"

rtthread-utest: rtthread-utest-build

rtthread-utest-build: $(RTTHREAD_UTEST_LINKER)
	@$(MAKE) --no-print-directory rtthread \
		RTTHREAD_APP=rtthread-utest \
		RTTHREAD_PROFILE=utest \
		RTTHREAD_OPT="$(RTTHREAD_UTEST_OPT)" \
		RTTHREAD_OUTPUT_DIR="$(RTTHREAD_UTEST_OUTPUT_ROOT)" \
		RTTHREAD_OUTPUT_BASENAME=rtthread_utest \
		RTTHREAD_LINKER="$(RTTHREAD_UTEST_LINKER)"

$(RTTHREAD_UTEST_LINKER): $(BSP_LINKER_SCRIPT)
	@mkdir -p "$(dir $@)"
	@sed 's/LENGTH = 16K/LENGTH = 64K/' "$<" > "$@"
	@grep -q 'LENGTH = 64K' "$@"

rtthread-utest-clean:
	rm -rf "$(RTTHREAD_UTEST_OUTPUT_ROOT)"
