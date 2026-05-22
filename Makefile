include config.mk

TOOLS := verilator gtkwave spike riscv64-elf-gcc riscv64-elf-newlib riscv64-elf-gdb  qemu-system-riscv

# --- 自动化测试相关定义 ---
RESULT_DIR := $(LOG_DIR)/test_results

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER 

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests init

.SECONDEXPANSION:



all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

run_all_tests: init check_deps rv_test_comp_genmem test_all


run_all_tests:
	git submodule update --init --recursive

comp:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv comp

sim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv sim

comp_and_sim_cpu: comp
	@$(MAKE) -C hw/dv sim \
		ITCM_FILE=$(RVTESTS_OUT_ROOT)/rv32ui/mem/rv32ui_lh.itcm \
		DTCM_FILE=$(RVTESTS_OUT_ROOT)/rv32ui/mem/rv32ui_lh.dtcm


# --- 核心自动化测试逻辑 (支持 ITCM/DTCM 分离加载) ---
test_all:
	@echo "==========================================================="
	@echo "   开始全量指令集回归测试 (Types: $(RVTESTS_TYPE))"
	@echo "   编译输出: $(RVTESTS_OUT_ROOT)"
	@echo "   结果输出: $(RVTESTS_RESULT_DIR)"
	@echo "==========================================================="
	@$(MAKE) -j rv_test_comp_genmem
	@$(MAKE) comp
	@$(MAKE) -j rv_test_sim_all
	@$(MAKE) rv_test_report_all
	@$(MAKE) rv_test_summary_all
	@echo "==========================================================="
	@echo "   测试结束！"
	@echo "==========================================================="



recomp:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile resim

wave:
	@$(MAKE) -C hw/dv -f Makefile wave

clean:
	rm -rf $(BUILD_DIR)

tran_coe:
	bash hw/dv/test_data/coe_to_mem.sh

check_deps:
	@missing=""; \
	for tool in $(TOOLS); do \
		if ! $(PKG_EXISTS) $$tool >/dev/null 2>&1; then \
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

include verif/tests/tests.mk

spike:
	$(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(SPIKE_ELF) \
	> $(SPIKE_LOG).log 2>&1

spike_wave_to_csv:
	$(PYTHON) $(TRACE_TO_CSV) --log $(SPIKE_LOG).log --csv $(SPIKE_LOG).csv --source spike
