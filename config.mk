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