include config.mk

SHELL := /bin/bash

# --- 自动化测试相关定义 ---
RESULT_DIR := $(LOG_DIR)/test_results

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER DIV_IMPL LSU_IMPL MEMS_IMPL ARCH ABI RISCV_PREFIX CC OBJCOPY OBJDUMP GDB QEMU

SYN_DIR ?= $(PROJECT_ROOT)/syn
SYN_BUILD_DIR ?= $(BUILD_DIR)/syn
SYN_VENV ?= $(SYN_BUILD_DIR)/.venv
SYN_PYTHON ?= $(SYN_VENV)/bin/python
SYN_XPR ?= $(PROJECT_ROOT)/FPGA/Ydrasil_FPGA.xpr
SYN_SOURCES_TCL ?= $(SYN_BUILD_DIR)/vivado_sources.tcl
SYN_REPORT_DIR ?= $(SYN_BUILD_DIR)/reports
SYN_LOG_DIR ?= $(SYN_BUILD_DIR)/log
SYN_JOBS ?= $(shell nproc)
SYN_RUN_TO ?= route
SYN_FORCE ?= 1
SYN_SYNC_SOURCES ?= 1
VIVADO ?= vivado
VIVADO_SETTINGS ?= /opt/Xilinx/Vitis/2024.2/settings64.sh
VIVADO_LICENSE_FILE ?= $(firstword $(wildcard $(HOME)/opt/vivado_2037.lic $(HOME)/*.lic $(HOME)/.Xilinx/*.lic))
BENDER_INSTALL_URL ?= https://github.com/pulp-platform/bender/releases/download/v0.32.0/bender-installer.sh

ifneq ($(VIVADO_LICENSE_FILE),)
export XILINXD_LICENSE_FILE := $(VIVADO_LICENSE_FILE)
endif

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests init install-bender get_spike download_and_extract_spike check_deps spike spike_wave_to_csv  rv_test_comp_genmem
.PHONY: coremark coremark_sim coremark_run coremark-rebuild coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map
.PHONY: syn syn-venv syn-prep syn-vivado syn-analyze syn-clean

.SECONDEXPANSION:



all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

run_all_tests: init check_deps test_all

syn: syn-vivado
	@$(MAKE) syn-analyze

syn-venv: $(SYN_VENV)/.stamp

$(SYN_VENV)/.stamp:
	@mkdir -p $(SYN_BUILD_DIR)
	$(PYTHON) -m venv $(SYN_VENV)
	@touch $@

syn-prep: syn-venv
	@mkdir -p $(SYN_BUILD_DIR)
	$(SYN_PYTHON) $(SYN_DIR)/prep_vivado_sources.py \
		--repo-root $(PROJECT_ROOT) \
		--bender $(BENDER) \
		--bender-dir $(PROJECT_ROOT)/hw/ip/jyd_fpga \
		--wrapper-dir $(PROJECT_ROOT)/hw/ip/Xilinx_ip_wrapper/rtl \
		--out $(SYN_SOURCES_TCL)

syn-vivado: syn-prep
	@mkdir -p $(SYN_REPORT_DIR) $(SYN_LOG_DIR)
	. $(VIVADO_SETTINGS) && $(VIVADO) -mode batch -nojournal -log $(SYN_LOG_DIR)/vivado.log \
		-source $(SYN_DIR)/run_vivado.tcl \
		-tclargs \
		-xpr $(SYN_XPR) \
		-sources_tcl $(SYN_SOURCES_TCL) \
		-report_dir $(SYN_REPORT_DIR) \
		-checkpoint_dir $(SYN_BUILD_DIR)/checkpoints \
		-jobs $(SYN_JOBS) \
		-run_to $(SYN_RUN_TO) \
		-sync_sources $(SYN_SYNC_SOURCES) \
		-force $(SYN_FORCE)

syn-analyze: syn-venv
	$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py --report-dir $(SYN_REPORT_DIR)
	@if [ -f "$(SYN_REPORT_DIR)/cpu150_timing_paths.rpt" ]; then \
		$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py \
			--report-dir $(SYN_REPORT_DIR) \
			--timing-report $(SYN_REPORT_DIR)/cpu150_timing_paths.rpt \
			--csv $(SYN_REPORT_DIR)/cpu150_timing_groups.csv \
			--md $(SYN_REPORT_DIR)/cpu150_timing_groups.md; \
	fi

syn-clean:
	rm -rf $(SYN_BUILD_DIR)


init: install-bender
	git submodule update --init --recursive

install-bender:
	@if command -v $(BENDER) >/dev/null 2>&1; then \
		echo "Bender is already installed: $$(command -v $(BENDER))"; \
	else \
		echo "Installing Bender from $(BENDER_INSTALL_URL)"; \
		curl --proto '=https' --tlsv1.2 -LsSf "$(BENDER_INSTALL_URL)" | sh; \
		if command -v $(BENDER) >/dev/null 2>&1; then \
			echo "Bender installed: $$(command -v $(BENDER))"; \
		else \
			echo "Error: Bender installer finished but $(BENDER) was not found in PATH."; \
			exit 1; \
		fi; \
	fi

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

COREMARK_SW_MAKE_ARGS = \
		PROJECT_ROOT=$(PROJECT_ROOT) \
		RISCV_PREFIX=$(RISCV_PREFIX) \
		ARCH=rv32im_zicsr_zifencei \
		ABI=$(ABI)

coremark:
	@$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS)

coremark-rebuild:
	@$(MAKE) -C sw coremark-rebuild $(COREMARK_SW_MAKE_ARGS)

coremark_sim: coremark comp
	@$(MAKE) -C hw/dv sim \
		ITCM_FILE=$(BUILD_DIR)/app/coremark/coremark.itcm \
		DTCM_FILE=$(BUILD_DIR)/app/coremark/coremark.dtcm \
		SIM_EXTRA_DEFINES="+cpp_timeout=10000000 +sv_timeout=10000000"

coremark_run: coremark_sim

coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map:
	@$(MAKE) -C sw $@ $(COREMARK_SW_MAKE_ARGS)


# --- 核心自动化测试逻辑 (支持 ITCM/DTCM 分离加载) ---
test_all:
	@echo "==========================================================="
	@echo "   开始全量指令集回归测试 (Types: $(RVTESTS_TYPE))"
	@echo "   编译输出: $(RVTESTS_OUT_ROOT)"
	@echo "   结果输出: $(RVTESTS_RESULT_DIR)"
	@echo "==========================================================="
	@$(MAKE) -j rv_test_comp_genmem
	@$(MAKE) comp
	@rm -rf $(RVTESTS_RESULT_DIR)
	@$(MAKE) -j rv_test_sim_all
	@$(MAKE) rv_test_report_all
	@$(MAKE) rv_test_summary_all
	@echo "==========================================================="
	@echo "   测试结束！"
	@echo "==========================================================="

include verif/tests/tests.mk

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
		if [ -n "$(PKG_UPDATE)" ] && [ "$(PKG_UPDATE)" != "true" ]; then \
			echo "Updating package metadata using: $(PKG_UPDATE)"; \
			$(PKG_UPDATE); \
		fi; \
		echo "Installing missing packages using:$(PKG_MANAGER) $$missing"; \
		$(PKG_MANAGER) $$missing; \
	fi



spike: get_spike
	@mkdir -p  $(SPIKE_OUT_DIR)
	@$(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(SPIKE_ELF) \
	> $(SPIKE_OUT_DIR)/$(SPIKE_LOG).log 2>&1

spike_wave_to_csv:
	$(PYTHON) $(TRACE_TO_CSV) --log $(SPIKE_LOG).log --csv $(SPIKE_LOG).csv --source spike

get_spike:
	@if "$(SPIKE)" -v>/dev/null 2>&1; then \
		echo "Spike is already installed."; \
	else \
		$(MAKE) download_and_extract_spike; \
	fi

download_and_extract_spike:
	$(MAKE) TOOLS="$(CURL) tar" check_deps
	@echo "Downloading Spike from: $(SPIKE_TAR_URL)"
	@mkdir -p $(dir $(SPIKE_TAR_FILE))
	$(CURL) -L $(SPIKE_TAR_URL) -o $(SPIKE_TAR_FILE)
	@if [ "$(SPIKE_INSTALL_DIR)" = "/opt/spike" ]; then \
		sudo mkdir -p "$(SPIKE_INSTALL_DIR)"; \
		sudo tar -xJf "$(SPIKE_TAR_FILE)" -C "$(SPIKE_INSTALL_DIR)" --strip-components=1; \
		sudo chmod -R a+rX "$(SPIKE_INSTALL_DIR)"; \
	else \
		mkdir -p "$(SPIKE_INSTALL_DIR)"; \
		tar -xJf "$(SPIKE_TAR_FILE)" -C "$(SPIKE_INSTALL_DIR)" --strip-components=1; \
	fi
