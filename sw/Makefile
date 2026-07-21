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
SORT_APP_DIR := apps/sort
SORT_APP_OUT ?= $(PROJECT_ROOT)/build/app/sort
SORT_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(SORT_APP_DIR)/*.c))))
SORT_APP_ELFS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .elf,$(SORT_APP_NAMES)))
SORT_APP_BINS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .bin,$(SORT_APP_NAMES)))
SORT_APP_DUMPS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .dump,$(SORT_APP_NAMES)))
SORT_APP_ITCMS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .itcm,$(SORT_APP_NAMES)))
SORT_APP_DTCMS := $(addprefix $(SORT_APP_OUT)/,$(addsuffix .dtcm,$(SORT_APP_NAMES)))
SORT_APP_EXTRA_CFLAGS ?=
SORT_APP_ONLY_CFLAGS ?=
BOUNDARY_APP_DIR := apps/boundary
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
.PHONY: rtthread rtthread-rebuild rtthread-clean
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

# RT-Thread + CoreMark application
RTTHREAD_DIR := $(PROJECT_ROOT)/sw/rt-thread
RTTHREAD_BSP_DIR := $(BSP_DIR)/rtthread
RTTHREAD_OUT ?= $(PROJECT_ROOT)/build/app/rtthread
RTTHREAD_NAME := rtthread
RTTHREAD_ELF := $(RTTHREAD_OUT)/$(RTTHREAD_NAME).elf
RTTHREAD_DUMP := $(RTTHREAD_OUT)/$(RTTHREAD_NAME).dump
RTTHREAD_MAP := $(RTTHREAD_OUT)/$(RTTHREAD_NAME).map
RTTHREAD_ITCM := $(RTTHREAD_OUT)/$(RTTHREAD_NAME).itcm
RTTHREAD_DTCM := $(RTTHREAD_OUT)/$(RTTHREAD_NAME).dtcm
RTTHREAD_ITCM_BIN := $(RTTHREAD_OUT)/$(RTTHREAD_NAME)_itcm.bin
RTTHREAD_DTCM_BIN := $(RTTHREAD_OUT)/$(RTTHREAD_NAME)_dtcm.bin
RTTHREAD_CONFIG := $(RTTHREAD_BSP_DIR)/rtconfig.h
RTTHREAD_ITERATIONS ?= 1
RTTHREAD_HAS_FLOAT ?= 0
RTTHREAD_SIM_CTRL ?= 1
RTTHREAD_IGNORE_10S_ERROR ?= $(RTTHREAD_SIM_CTRL)
RTTHREAD_EXTRA_CFLAGS ?=

RTTHREAD_KERNEL_C_SRCS := \
	$(RTTHREAD_DIR)/src/clock.c \
	$(RTTHREAD_DIR)/src/components.c \
	$(RTTHREAD_DIR)/src/cpu_up.c \
	$(RTTHREAD_DIR)/src/defunct.c \
	$(RTTHREAD_DIR)/src/idle.c \
	$(RTTHREAD_DIR)/src/ipc.c \
	$(RTTHREAD_DIR)/src/irq.c \
	$(RTTHREAD_DIR)/src/kservice.c \
	$(RTTHREAD_DIR)/src/object.c \
	$(RTTHREAD_DIR)/src/scheduler_comm.c \
	$(RTTHREAD_DIR)/src/scheduler_up.c \
	$(RTTHREAD_DIR)/src/thread.c \
	$(RTTHREAD_DIR)/src/timer.c \
	$(RTTHREAD_DIR)/src/klibc/kerrno.c \
	$(RTTHREAD_DIR)/src/klibc/kstdio.c \
	$(RTTHREAD_DIR)/src/klibc/kstring.c \
	$(RTTHREAD_DIR)/src/klibc/rt_vsnprintf_tiny.c \
	$(RTTHREAD_DIR)/libcpu/risc-v/common/cpuport.c
RTTHREAD_KERNEL_ASM_SRCS := \
	$(RTTHREAD_DIR)/libcpu/risc-v/common/context_gcc.S \
	$(RTTHREAD_DIR)/libcpu/risc-v/common/interrupt_gcc.S
RTTHREAD_BSP_C_SRCS := \
	$(BSP_DIR)/lib/platform.c \
	$(BSP_DIR)/lib/memory.c \
	$(BSP_DIR)/lib/sim_ctrl.c \
	$(BSP_DIR)/lib/uart.c \
	$(BSP_DIR)/lib/xprintf.c \
	$(RTTHREAD_BSP_DIR)/board.c \
	$(RTTHREAD_BSP_DIR)/main.c
RTTHREAD_BSP_ASM_SRCS := $(BSP_DIR)/startup.S
RTTHREAD_COREMARK_C_SRCS := \
	$(COREMARK_DIR)/core_list_join.c \
	$(COREMARK_DIR)/core_matrix.c \
	$(COREMARK_DIR)/core_state.c \
	$(COREMARK_DIR)/core_util.c \
	$(COREMARK_DIR)/$(COREMARK_PORT_DIR)/core_portme.c
RTTHREAD_COMMON_SRCS := $(RTTHREAD_KERNEL_C_SRCS) $(RTTHREAD_KERNEL_ASM_SRCS) \
	$(RTTHREAD_BSP_C_SRCS) $(RTTHREAD_BSP_ASM_SRCS) $(RTTHREAD_COREMARK_C_SRCS)

RTTHREAD_CFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-Os \
	-flto \
	-ffunction-sections \
	-fdata-sections \
	-fno-builtin \
	-fno-tree-loop-distribute-patterns \
	-fno-common \
	-fno-stack-protector \
	-nostdlib \
	-nostartfiles \
	-static \
	-D__RTTHREAD__ \
	-D__RT_KERNEL_SOURCE__ \
	-DRTOS_RTTHREAD=1 \
	-DCOREMARK_RTTHREAD=1 \
	-DITERATIONS=$(RTTHREAD_ITERATIONS) \
	-DHAS_FLOAT=$(RTTHREAD_HAS_FLOAT) \
	-DPERFORMANCE_RUN=1 \
	-DSDK_BANNER=0 \
	-DFLAGS_STR=\"$(ARCH)-$(ABI)-Os-RTThread\" \
	-I$(RTTHREAD_BSP_DIR) \
	-I$(RTTHREAD_DIR)/include \
	-I$(RTTHREAD_DIR)/libcpu/risc-v/common \
	-I$(COREMARK_DIR) \
	-I$(COREMARK_DIR)/$(COREMARK_PORT_DIR) \
	$(BSP_INCLUDES) \
	$(RTTHREAD_EXTRA_CFLAGS)
ifeq ($(RTTHREAD_SIM_CTRL),1)
RTTHREAD_CFLAGS += -DYDRASIL_SIM_CTRL=1
endif
ifeq ($(RTTHREAD_IGNORE_10S_ERROR),1)
RTTHREAD_CFLAGS += -DCOREMARK_IGNORE_10S_ERROR=1
endif
RTTHREAD_LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medany \
	-flto \
	-nostartfiles \
	-nostdlib \
	-static \
	-T $(BSP_LINKER_SCRIPT) \
	-Wl,-Map,$(RTTHREAD_MAP) \
	-Wl,-u,memcpy \
	-Wl,-u,memset \
	-Wl,--gc-sections

rtthread: $(RTTHREAD_ELF) $(RTTHREAD_DUMP) $(RTTHREAD_ITCM) $(RTTHREAD_DTCM)
	@echo "[rtthread] ELF  $(RTTHREAD_ELF)"
	@echo "[rtthread] ITCM $(RTTHREAD_ITCM)"
	@echo "[rtthread] DTCM $(RTTHREAD_DTCM)"

$(RTTHREAD_CONFIG): $(RTTHREAD_BSP_DIR)/.config $(RTTHREAD_DIR)/tools/env_utility.py
	@cd $(RTTHREAD_BSP_DIR) && python3 -c "import sys; sys.path.insert(0, '../../rt-thread/tools'); from env_utility import mk_rtconfig; mk_rtconfig('.config')"

$(RTTHREAD_OUT):
	@mkdir -p $@

$(RTTHREAD_ELF): $(RTTHREAD_COMMON_SRCS) $(COREMARK_DIR)/core_main.c $(RTTHREAD_CONFIG) $(BSP_LINKER_SCRIPT) Makefile | $(RTTHREAD_OUT)
	@set -eu; obj_dir="$(RTTHREAD_OUT)/obj"; rm -rf "$$obj_dir"; mkdir -p "$$obj_dir"; objects=""; index=0; \
	for src in $(RTTHREAD_COMMON_SRCS); do obj="$$obj_dir/obj_$$index.o"; \
		$(CC) $(RTTHREAD_CFLAGS) -c "$$src" -o "$$obj"; objects="$$objects $$obj"; index=$$((index + 1)); done; \
	core_obj="$$obj_dir/core_main.o"; \
	$(CC) $(RTTHREAD_CFLAGS) -Dmain=coremark_main -c "$(COREMARK_DIR)/core_main.c" -o "$$core_obj"; \
	$(CC) $(RTTHREAD_LDFLAGS) $$objects "$$core_obj" -lgcc -o "$@"

$(RTTHREAD_DUMP): $(RTTHREAD_ELF)
	$(OBJDUMP) -h -d $< > $@

$(RTTHREAD_ITCM): $(RTTHREAD_ELF) | $(RTTHREAD_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.init \
		--only-section=.text \
		--only-section=.text.* \
		$< $(RTTHREAD_ITCM_BIN)
	od -An -t x4 -w4 -v $(RTTHREAD_ITCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@

$(RTTHREAD_DTCM): $(RTTHREAD_ELF) | $(RTTHREAD_OUT)
	$(OBJCOPY) -O binary --gap-fill=0x00 \
		--only-section=.data \
		--only-section=.bss \
		--only-section=.stack \
		--set-section-flags .bss=alloc,load,contents \
		--set-section-flags .stack=alloc,load,contents \
		$< $(RTTHREAD_DTCM_BIN) || true
	@if [ -s $(RTTHREAD_DTCM_BIN) ]; then \
		od -An -t x4 -w4 -v $(RTTHREAD_DTCM_BIN) | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > $@; \
	else \
		printf "00000000\n" > $@; \
	fi

rtthread-rebuild: rtthread-clean rtthread

rtthread-clean:
	rm -rf $(RTTHREAD_OUT)

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
