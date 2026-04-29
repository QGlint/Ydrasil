PROJECT_ROOT := $(abspath $(CURDIR))

BUILD_DIR := $(PROJECT_ROOT)/build
WAVE_DIR  := $(BUILD_DIR)/wave
LOG_DIR   := $(BUILD_DIR)/log

SIM_TOOL ?= verilator
IP  ?= ydrasil_core
VERILATOR_MOD ?= sv
UVM ?= 0
USE_BENDER ?= 1
BENDER ?= bender

# 默认内存路径
# ITCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem_generated/rv32ui-p-add.mem
# # DTCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem/dram0.mem

ITCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem_generated/rv32ui-p-sw.mem
DTCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem_generated/rv32ui-p-sw.mem

# --- 自动化测试相关定义 ---
# 测试数据所在的真实路径
TEST_SRC_DIR := $(PROJECT_ROOT)/hw/dv/test_data/mem_generated
# 搜寻所有 rv32ui-p 开头的 .mem 文件，并提取其基本名称
UI_TEST_CASES := $(notdir $(patsubst %.mem,%,$(wildcard $(TEST_SRC_DIR)/rv32ui-p-*.mem)))
# 测试结果存放路径
RESULT_DIR := $(LOG_DIR)/test_results

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER ITCM_MEM DTCM_MEM

.PHONY: all comp sim clean wave resim test_all

all: comp sim

full : comp sim wave

comp:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile comp

sim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile sim

# --- 核心自动化测试逻辑 ---
test_all: 
	@echo "==========================================================="
	@echo "   开始全量指令集回归测试 (Total: $(words $(UI_TEST_CASES)) cases)"
	@echo "==========================================================="
	@mkdir -p $(RESULT_DIR)
	@rm -f $(RESULT_DIR)/summary.log
	@for tst in $(UI_TEST_CASES); do \
		echo -n "Running [$$tst] ... "; \
		$(MAKE) LOG_OUTPUT=0 comp sim \
			ITCM_MEM=$(TEST_SRC_DIR)/$$tst.mem \
			DTCM_MEM=$(TEST_SRC_DIR)/$$tst.mem \
			> $(RESULT_DIR)/$$tst.log 2>&1; \
		\
		if grep -q "TEST_PASS" $(RESULT_DIR)/$$tst.log; then \
			echo -e "\033[32m[ PASSED ]\033[0m"; \
			echo "$$tst: PASS" >> $(RESULT_DIR)/summary.log; \
		else \
			echo -e "\033[31m[ FAILED ]\033[0m"; \
			echo "$$tst: FAIL (Check $(RESULT_DIR)/$$tst.log)" >> $(RESULT_DIR)/summary.log; \
		fi \
	done
	@echo "==========================================================="
	@echo "   测试结束！结果汇总于: $(RESULT_DIR)/summary.log"
	@echo "==========================================================="

resim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile resim

wave:
	@$(MAKE) -C hw/dv -f Makefile wave

clean:
	rm -rf $(BUILD_DIR)

tran_coe:
	bash hw/dv/test_data/coe_to_mem.sh