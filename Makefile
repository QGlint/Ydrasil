PROJECT_ROOT := $(abspath $(CURDIR))

BUILD_DIR := $(PROJECT_ROOT)/build
WAVE_DIR  := $(BUILD_DIR)/wave
LOG_DIR   := $(BUILD_DIR)/log

TOOLS := verilator gtkwave spike riscv64-elf-gcc riscv64-elf-binutils riscv64-elf-gdb riscv64-elf-newlib qemu-system-riscv

include config.mk

# --- 自动化测试相关定义 ---
# 搜寻 ITCM 目录下所有的 .mem 文件来确定测试用例列表
UI_TEST_CASES := $(notdir $(patsubst %.mem,%,$(wildcard $(ITCM_TEST_BASE)/rv32ui-p-*.mem)))
RESULT_DIR := $(LOG_DIR)/test_results

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER ITCM_TEST_MEM DTCM_TEST_MEM ITCM_MEM DTCM_MEM Compile_optimization VERILATOR_TRACE

.PHONY: all comp sim clean wave resim test_all

all: comp sim

full : comp sim wave

comp:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile comp

sim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile sim

# --- 核心自动化测试逻辑 (支持 ITCM/DTCM 分离加载) ---
test_all: 
	@echo "==========================================================="
	@echo "   开始全量指令集回归测试 (Total: $(words $(UI_TEST_CASES)) cases)"
	@echo "   ITCM 路径: $(ITCM_TEST_BASE)"
	@echo "   DTCM 路径: $(DTCM_TEST_BASE)"
	@echo "==========================================================="
	@mkdir -p $(RESULT_DIR)
	@rm -f $(RESULT_DIR)/summary.log
	@for tst in $(UI_TEST_CASES); do \
		echo -n "Running [$$tst]  "; \
		$(MAKE) LOG_OUTPUT=0 Compile_optimization=0 comp sim \
			ITCM_MEM=$(ITCM_TEST_BASE)/$$tst.mem \
			DTCM_MEM=$(DTCM_TEST_BASE)/$$tst.mem \
			> $(RESULT_DIR)/$$tst.log 2>&1; \
		\
		cycles=$$(grep -o "CYCLES=[0-9]*" $(RESULT_DIR)/$$tst.log | cut -d= -f2);\
		insts=$$(grep -o "INSTS=[0-9]*" $(RESULT_DIR)/$$tst.log | cut -d= -f2); \
		ipc=$$(grep -o "IPC=[0-9.]*" $(RESULT_DIR)/$$tst.log | cut -d= -f2); \
		if grep -q "TEST_PASS" $(RESULT_DIR)/$$tst.log; then \
			echo -e "\033[34m [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc]\033[0m \033[32m[ PASSED ]\033[0m"; \
			echo "$$tst: PASS" >> $(RESULT_DIR)/summary.log; \
		else \
			echo -e "\033[34m [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc]\033[0m \033[31m[ FAILED ]\033[0m"; \
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

# 检查依赖并自动安装
check-deps:
	@missing=""; \
	for tool in $(TOOLS); do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "$$tool not found."; \
			missing="$$missing $$tool"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "Missing tools:$$missing"; \
		if [ "$(PKG_MANAGER)" = "unknown" ]; then \
			echo "Error: No known package manager found. Please install $(TOOLS) manually."; \
			exit 1; \
		fi; \
		echo "Installing missing packages using:$(PKG_MANAGER) $$missing"; \
		$(PKG_MANAGER) $$missing; \
	fi

