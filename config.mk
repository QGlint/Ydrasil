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

RVTESTS_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests
RVTESTSISA_DIR := $(RVTESTS_DIR)/isa

RVTESTS_ALL := $(foreach t,$(RVTESTS_TYPE), \
               $(addprefix $(t)/,$(basename $(notdir $(wildcard $(RVTESTSISA_DIR)/$(t)/*.S)))) )

# 为每个测试生成唯一目标名（替换 / 为 _）
RVTESTS_TARGETS := $(addprefix rv_comp_,$(subst /,_,$(RVTESTS_ALL)))

RVTESTS_INCLUDES := -I$(RVTESTS_DIR)/env/p -I$(RVTESTS_DIR)/isa/macros/scalar