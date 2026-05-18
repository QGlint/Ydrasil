include config.mk

TOOLS := verilator gtkwave spike riscv64-elf-gcc riscv64-elf-newlib riscv64-elf-gdb  qemu-system-riscv

# --- 自动化测试相关定义 ---
RESULT_DIR := $(LOG_DIR)/test_results

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER 

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean

.SECONDEXPANSION:

RVTESTS_SIM_TARGETS = $(foreach typ,$(RVTESTS_TYPE),$(addprefix rv_sim_$(typ)_, $(basename $(notdir $(wildcard $(RVTESTS_OUT_ROOT)/$(typ)/mem/*.itcm)))))
RVTESTS_SUMMARY_TARGETS = $(addprefix rv_summary_,$(RVTESTS_TYPE))
RVTESTS_REPORT_TARGETS = $(addprefix rv_report_,$(RVTESTS_TYPE))

all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

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

rv_test_sim_all: $$(RVTESTS_SIM_TARGETS)

rv_sim_%:
	@name=$*; \
	typ=$${name%%_*}; \
	base=$${name#*_}; \
	mem_dir=$(RVTESTS_OUT_ROOT)/$$typ/mem; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	mkdir -p $$result_dir; \
	$(MAKE) LOG_OUTPUT=0 Compile_optimization=0 sim \
		ITCM_FILE=$$mem_dir/$$base.itcm \
		DTCM_FILE=$$mem_dir/$$base.dtcm \
		> $$result_dir/$$base.log 2>&1; \
	cycles=$$(grep -o "CYCLES=[0-9]*" $$result_dir/$$base.log | cut -d= -f2); \
	insts=$$(grep -o "INSTS=[0-9]*" $$result_dir/$$base.log | cut -d= -f2); \
	ipc=$$(grep -o "IPC=[0-9.]*" $$result_dir/$$base.log | cut -d= -f2); \
	if grep -q "TEST_PASS" $$result_dir/$$base.log; then \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ PASSED ]" >> $$result_dir/$$base.log; \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ PASSED ]" > $$result_dir/$$base.status; \
	else \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ FAILED ]" >> $$result_dir/$$base.log; \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ FAILED ]" > $$result_dir/$$base.status; \
	fi

rv_test_report_all: $(RVTESTS_REPORT_TARGETS)

rv_report_%:
	@typ=$*; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	echo "========== $$typ =========="; \
	for f in $$(ls $$result_dir/*.status 2>/dev/null | sort); do \
		line=$$(cat $$f); \
		left=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\1/'); \
		mid=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\2/'); \
		tag=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\3/'); \
		if echo "$$tag" | grep -q "\[ PASSED \]"; then \
			echo -e "$$left\033[34m$$mid\033[0m \033[32m$$tag\033[0m"; \
		else \
			echo -e "$$left\033[34m$$mid\033[0m \033[31m$$tag\033[0m"; \
		fi; \
	done

rv_test_summary_all: $(RVTESTS_SUMMARY_TARGETS)

rv_summary_%:
	@typ=$*; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	summary_file=$(RVTESTS_RESULT_DIR)/$${typ}_summary.log; \
	rm -f $$summary_file; \
	for log in $$result_dir/*.log; do \
		[ -e "$$log" ] || continue; \
		base=$$(basename $$log .log); \
		if grep -q "TEST_PASS" $$log; then \
			echo "$$base: PASS" >> $$summary_file; \
		else \
			echo "$$base: FAIL" >> $$summary_file; \
		fi; \
	done; \
	echo "Summary: $$summary_file"

recomp:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile resim

wave:
	@$(MAKE) -C hw/dv -f Makefile wave

clean:
	rm -rf $(BUILD_DIR)

tran_coe:
	bash hw/dv/test_data/coe_to_mem.sh

check-deps:
	@missing=""; \
	for tool in $(TOOLS); do \
		if ! pacman -Qs -q $$tool >/dev/null 2>&1; then \
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
