PROJECT_ROOT := $(abspath $(CURDIR))

SIM_TOOL ?= verilator
IP   ?= ydrasil_core
VERILATOR_MOD ?= cc
UVM ?= 0
USE_BENDER ?= 1
BENDER ?= bender
VERILATOR_TRACE ?= 1
# --- 内存路径配置 (指向你新生成的 split 目录) ---
ITCM_TEST_BASE := $(PROJECT_ROOT)/hw/dv/test_data/split/itcm
DTCM_TEST_BASE := $(PROJECT_ROOT)/hw/dv/test_data/split/dtcm

# 默认单次仿真的内存文件 (以 add 为例)
ITCM_MEM ?= $(ITCM_TEST_BASE)/rv32ui-p-fence_i.mem
DTCM_MEM ?= $(DTCM_TEST_BASE)/rv32ui-p-fence_i.mem

ITCM_BASE := $(PROJECT_ROOT)/hw/dv/test_data/mem/itcm
DTCM_BASE := $(PROJECT_ROOT)/hw/dv/test_data/mem/dtcm
# ITCM_MEM ?= $(ITCM_BASE)/irom2.mem
# DTCM_MEM ?= $(DTCM_BASE)/dram2.mem


PKG_MANAGER := $(shell \
	if command -v pacman >/dev/null 2>&1; then \
		echo "sudo pacman -S --needed"; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "sudo apt-get install -y"; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "sudo dnf install -y"; \
	elif command -v yum >/dev/null 2>&1; then \
		echo "sudo yum install -y"; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "brew install"; \
	else \
		echo "unknown"; \
	fi)


#------------------------------------------
# toolchain
#------------------------------------------

RISCV_PREFIX := riscv64-elf
CC      := $(RISCV_PREFIX)-gcc
OBJCOPY := $(RISCV_PREFIX)-objcopy
OBJDUMP := $(RISCV_PREFIX)-objdump

ARCH := rv32im_zicsr
ABI  := ilp32

RISCV_CFLAGS := \
    -march=$(ARCH) \
    -mabi=$(ABI) \
    -nostdlib \
    -nostartfiles \
    -static \
    -mcmodel=medany

RVTESTS_TYPE := rv32ui rv32um

RVTESTS_OUT_ROOT := $(PROJECT_ROOT)/build/riscv_tests

