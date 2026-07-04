include config.mk

SHELL := /bin/bash

# --- 自动化测试相关定义 ---
RESULT_DIR := $(LOG_DIR)/test_results
PPA_DIR ?= $(BUILD_DIR)/PPA
PPA_RVTEST_LOG ?= $(PPA_DIR)/test_all_summary.log
PPA_COREMARK_LOG ?= $(PPA_DIR)/coremark_summary.log

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER DIV_IMPL LSU_IMPL MEMS_IMPL YDRASIL_ENABLE_PIPE1_REAL ARCH ABI RISCV_PREFIX CC OBJCOPY OBJDUMP GDB QEMU TRACE_TO_CSV TRACE_COMPARE

SYN_DIR ?= $(PROJECT_ROOT)/syn
SYN_BUILD_DIR ?= $(BUILD_DIR)/syn
SYN_VENV ?= $(SYN_BUILD_DIR)/.venv
SYN_PYTHON ?= $(SYN_VENV)/bin/python
SYN_PLL_FREQ_MHZ ?= 150
SYN_PLL_SUPPORTED_FREQS := 150 200
SYN_PLL_FREQ_TAG = pll$(subst .,p,$(SYN_PLL_FREQ_MHZ))m
SYN_PLL_DEFINE = SYN_PLL_FREQ_$(subst .,P,$(SYN_PLL_FREQ_MHZ))
SYN_RTL_DEFINES = $(SYN_PLL_DEFINE)
SYN_RTL_DEFINES += SYNTHESIS
ifeq ($(DIV_IMPL),lzc)
SYN_RTL_DEFINES += YDRASIL_DIV_IMPL_LZC
else
$(error Unsupported DIV_IMPL '$(DIV_IMPL)'. Use DIV_IMPL=lzc)
endif
ifeq ($(LSU_IMPL),new)
SYN_RTL_DEFINES += YDRASIL_LSU_IMPL_NEW
else ifeq ($(LSU_IMPL),legacy)
SYN_RTL_DEFINES += YDRASIL_LSU_IMPL_LEGACY
else
$(error Unsupported LSU_IMPL '$(LSU_IMPL)'. Use LSU_IMPL=new or LSU_IMPL=legacy)
endif
ifeq ($(MEMS_IMPL),new)
SYN_RTL_DEFINES += YDRASIL_MEMS_IMPL_NEW
else ifeq ($(MEMS_IMPL),legacy)
SYN_RTL_DEFINES += YDRASIL_MEMS_IMPL_LEGACY
else
$(error Unsupported MEMS_IMPL '$(MEMS_IMPL)'. Use MEMS_IMPL=new or MEMS_IMPL=legacy)
endif
ifeq ($(YDRASIL_ENABLE_PIPE1_REAL),1)
SYN_RTL_DEFINES += YDRASIL_ENABLE_PIPE1_REAL
endif
SYN_DEFINE_ARGS = $(foreach define,$(SYN_RTL_DEFINES),--define $(define))
SYN_FREQ_BUILD_DIR ?= $(SYN_BUILD_DIR)/$(SYN_PLL_FREQ_TAG)
SYN_STAGE_ROOT ?= $(SYN_FREQ_BUILD_DIR)/project
SYN_ORIG_FPGA_DIR ?= $(PROJECT_ROOT)/FPGA
SYN_STAGE_FPGA_DIR ?= $(SYN_STAGE_ROOT)/FPGA
SYN_XPR ?= $(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.xpr
SYN_SOURCES_TCL ?= $(SYN_FREQ_BUILD_DIR)/vivado_sources.tcl
SYN_REPORT_DIR ?= $(SYN_FREQ_BUILD_DIR)/reports
SYN_LOG_DIR ?= $(SYN_FREQ_BUILD_DIR)/log
SYN_ARTIFACT_DIR ?= $(SYN_FREQ_BUILD_DIR)/artifacts
SYN_CHECKPOINT_DIR ?= $(SYN_FREQ_BUILD_DIR)/checkpoints
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

ifeq ($(filter $(SYN_PLL_FREQ_MHZ),$(SYN_PLL_SUPPORTED_FREQS)),)
$(error Unsupported SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ); supported values: $(SYN_PLL_SUPPORTED_FREQS))
endif

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests init install-bender get_spike download_and_extract_spike check_spike_prebuilt_abi build_spike_from_source check_deps spike spike_wave_to_csv sim_compare commit_check commit_spike_csv commit_hw_trace commit_hw_csv commit_compare rv_test_comp_genmem ppa_rvtest_report
.PHONY: coremark coremark_sim coremark_run coremark_result coremark-rebuild coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map
.PHONY: syn synf syn-venv syn-prep syn-stage-xpr syn-vivado syn-analyze syn-clean

.SECONDEXPANSION:



all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

run_all_tests: init check_deps test_all

syn: syn-vivado
	@$(MAKE) syn-analyze

synf: SYN_PLL_FREQ_MHZ := 200
synf: SYN_RUN_TO := bitstream
synf: SYN_JOBS := 40
synf: syn-vivado
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ)

syn-venv: $(SYN_VENV)/.stamp

$(SYN_VENV)/.stamp:
	@mkdir -p $(SYN_BUILD_DIR)
	$(PYTHON) -m venv $(SYN_VENV)
	@touch $@

syn-prep: syn-venv
	@mkdir -p $(SYN_FREQ_BUILD_DIR)
	$(SYN_PYTHON) $(SYN_DIR)/prep_vivado_sources.py \
		--repo-root $(PROJECT_ROOT) \
		--bender $(BENDER) \
		--bender-dir $(PROJECT_ROOT)/hw/ip/jyd_fpga \
		--wrapper-dir $(PROJECT_ROOT)/hw/ip/Xilinx_ip_wrapper/rtl \
		$(SYN_DEFINE_ARGS) \
		--out $(SYN_SOURCES_TCL)

syn-stage-xpr:
	@mkdir -p $(SYN_STAGE_ROOT)
	rm -rf \
		$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.cache \
		$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.gen \
		$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.hw \
		$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.ip_user_files \
		$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.runs
	rsync -a --delete \
		--exclude 'Ydrasil_FPGA.cache' \
		--exclude 'Ydrasil_FPGA.gen' \
		--exclude 'Ydrasil_FPGA.hw' \
		--exclude 'Ydrasil_FPGA.ip_user_files' \
		--exclude 'Ydrasil_FPGA.runs' \
		--exclude 'vivado*' \
		$(SYN_ORIG_FPGA_DIR)/ $(SYN_STAGE_FPGA_DIR)/

syn-vivado: syn-prep syn-stage-xpr
	@mkdir -p $(SYN_REPORT_DIR) $(SYN_LOG_DIR) $(SYN_ARTIFACT_DIR)
	. $(VIVADO_SETTINGS) && $(VIVADO) -mode batch -nojournal -log $(SYN_LOG_DIR)/vivado.log \
		-source $(SYN_DIR)/run_vivado.tcl \
		-tclargs \
		-xpr $(SYN_XPR) \
		-sources_tcl $(SYN_SOURCES_TCL) \
		-report_dir $(SYN_REPORT_DIR) \
		-checkpoint_dir $(SYN_CHECKPOINT_DIR) \
		-artifact_dir $(SYN_ARTIFACT_DIR) \
		-jobs $(SYN_JOBS) \
		-run_to $(SYN_RUN_TO) \
		-sync_sources $(SYN_SYNC_SOURCES) \
		-pll_freq_mhz $(SYN_PLL_FREQ_MHZ) \
		-force $(SYN_FORCE)

syn-analyze: syn-venv
	$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py \
		--report-dir $(SYN_REPORT_DIR) \
		--violation-report $(SYN_REPORT_DIR)/post_route_timing_violations.rpt
	@if [ -f "$(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_paths.rpt" ]; then \
		$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py \
			--report-dir $(SYN_REPORT_DIR) \
			--timing-report $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_paths.rpt \
			--violation-report $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_violations.rpt \
			--csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_groups.csv \
			--paths-csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_paths.csv \
			--violations-csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_violations.csv \
			--md $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_groups.md; \
	fi

syn-clean:
	rm -rf $(SYN_BUILD_DIR)


init:
	@$(MAKE) check_deps
	@$(MAKE) install-bender
	git submodule update --init --recursive
	@$(MAKE) get_spike

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
	@$(MAKE) sim_compare \
		COMPARE_NAME=rv32ui_lh \
		COMPARE_ELF=$(RVTESTS_OUT_ROOT)/rv32ui/elf/rv32ui_lh.elf \
		COMPARE_ITCM=$(RVTESTS_OUT_ROOT)/rv32ui/mem/rv32ui_lh.itcm \
		COMPARE_DTCM=$(RVTESTS_OUT_ROOT)/rv32ui/mem/rv32ui_lh.dtcm

COREMARK_SW_MAKE_ARGS = \
		PROJECT_ROOT=$(PROJECT_ROOT) \
		RISCV_PREFIX=$(RISCV_PREFIX) \
		ARCH=rv32im_zicsr_zifencei \
		ABI=$(ABI)
COREMARK_RESULT_LOG ?= $(HW_TRACE_OUT_DIR)/coremark/hw.log
COREMARK_SIM_COMPARE ?= none

coremark:
	@$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS)

coremark-rebuild:
	@$(MAKE) -C sw coremark-rebuild $(COREMARK_SW_MAKE_ARGS)

coremark_sim: coremark comp
	@set +e; \
	rm -f $(COREMARK_RESULT_LOG); \
	$(MAKE) sim_compare \
		COMPARE_NAME=coremark \
		COMPARE_ELF=$(BUILD_DIR)/app/coremark/coremark.elf \
		COMPARE_ITCM=$(BUILD_DIR)/app/coremark/coremark.itcm \
		COMPARE_DTCM=$(BUILD_DIR)/app/coremark/coremark.dtcm \
		SIM_COMPARE=$(COREMARK_SIM_COMPARE) \
		COMPARE_SIM_EXTRA_DEFINES="+cpp_timeout=10000000 +sv_timeout=10000000"; \
	rc=$$?; \
	$(MAKE) --no-print-directory coremark_result; \
	exit $$rc

coremark_run: coremark_sim

coremark_result:
	@mkdir -p "$(PPA_DIR)"; \
	rm -f "$(PPA_COREMARK_LOG)"; \
	if [ -f "$(COREMARK_RESULT_LOG)" ]; then \
		echo "[COREMARK] Result from $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
		tmp=$$(mktemp); \
		awk '{ \
			line=$$0; \
			if (line ~ /^PERF_[A-Z0-9_]+:/) { \
				print line; \
			} else if (match(line, /(core[[:space:]]+0:|3[[:space:]]+0x)/)) { \
				prefix=substr(line, 1, RSTART - 1); \
				if (length(prefix) > 0) printf "%s", prefix; \
			} else if (line == "") { \
				printf "\n"; \
			} \
		} END { printf "\n"; }' "$(COREMARK_RESULT_LOG)" > $$tmp; \
		if grep -Eq '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_[A-Z0-9_]+:|\[[0-9]+\]crc)' "$$tmp"; then \
			grep -E '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_[A-Z0-9_]+:|\[[0-9]+\]crc)' "$$tmp" | tee -a "$(PPA_COREMARK_LOG)"; \
		else \
			echo "[COREMARK] No CoreMark result lines found in $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
		fi; \
		rm -f $$tmp; \
	else \
		echo "[COREMARK] HW log not found: $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
	fi

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
	@$(MAKE) ppa_rvtest_report
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
	@env $(SPIKE_RUN_ENV) $(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(SPIKE_ELF) \
	> $(SPIKE_OUT_DIR)/$(SPIKE_LOG).log 2>&1

spike_wave_to_csv:
	$(PYTHON) $(TRACE_TO_CSV) --log $(SPIKE_TRACE_LOG) --csv $(SPIKE_TRACE_CSV) --source spike

sim_compare:
	@mkdir -p $(COMPARE_OUT_DIR) $(COMPARE_HW_OUT_DIR) $(dir $(COMPARE_HW_LOG)) $(dir $(COMPARE_SPIKE_LOG)) $(dir $(COMPARE_HW_CSV)) $(dir $(COMPARE_SPIKE_CSV))
ifeq ($(SIM_COMPARE),none)
	@echo "[SIM] HW only: $(COMPARE_NAME)"
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(abspath $(COMPARE_ITCM)) \
		DTCM_FILE=$(abspath $(COMPARE_DTCM)) \
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_EXTRA_DEFINES)" \
		> $(COMPARE_HW_LOG) 2>&1
	@echo "[SIM] HW log: $(COMPARE_HW_LOG)"
else ifeq ($(SIM_COMPARE),realtime)
	@$(MAKE) get_spike
	@echo "[SIM] Realtime compare: $(COMPARE_NAME)"
	$(PYTHON) $(TRACE_COMPARE) --mode realtime \
		--hw-cmd "$(MAKE) --no-print-directory -C hw/dv sim VERILATOR_TRACE=0 LOG_OUTPUT=0 ITCM_FILE=$(abspath $(COMPARE_ITCM)) DTCM_FILE=$(abspath $(COMPARE_DTCM)) SIM_EXTRA_DEFINES='$(COMPARE_SIM_EXTRA_DEFINES)'" \
		--spike-cmd "env $(SPIKE_RUN_ENV) $(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(abspath $(COMPARE_ELF))" \
		--hw-log $(COMPARE_HW_LOG) \
		--spike-log $(COMPARE_SPIKE_LOG) \
		--hw-source ydrasil \
		--spike-source spike \
		--merge-stderr \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
		--max-rows $(SIM_COMPARE_MAX_ROWS) \
		> $(COMPARE_LOG) 2>&1
	@cat $(COMPARE_LOG)
else ifeq ($(SIM_COMPARE),csv)
	@$(MAKE) get_spike
	@echo "[SIM] CSV compare: $(COMPARE_NAME)"
	@env $(SPIKE_RUN_ENV) $(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(abspath $(COMPARE_ELF)) \
		> $(COMPARE_SPIKE_LOG) 2>&1
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_SPIKE_LOG) --csv $(COMPARE_SPIKE_CSV) --source spike
	@echo "[SIM] Spike CSV: $(COMPARE_SPIKE_CSV)"
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(abspath $(COMPARE_ITCM)) \
		DTCM_FILE=$(abspath $(COMPARE_DTCM)) \
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_EXTRA_DEFINES)" \
		> $(COMPARE_HW_LOG) 2>&1
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_HW_LOG) --csv $(COMPARE_HW_CSV) --source ydrasil
	@echo "[SIM] HW CSV: $(COMPARE_HW_CSV)"
	@set +e; \
	$(PYTHON) $(TRACE_COMPARE) --mode csv \
		--hw-csv $(COMPARE_HW_CSV) \
		--spike-csv $(COMPARE_SPIKE_CSV) \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
		--max-rows $(SIM_COMPARE_MAX_ROWS) \
		--context-lines 10 \
		> $(COMPARE_LOG) 2>&1; \
	rc=$$?; \
	cat $(COMPARE_LOG); \
	exit $$rc
else
	$(error Unsupported SIM_COMPARE=$(SIM_COMPARE). Use csv, realtime, or none)
endif

commit_check: sim_compare

commit_spike_csv: spike
	$(PYTHON) $(TRACE_TO_CSV) --log $(SPIKE_TRACE_LOG) --csv $(SPIKE_TRACE_CSV) --source spike

commit_hw_trace:
	@mkdir -p $(dir $(HW_TRACE_LOG)) $(dir $(HW_TRACE_CSV))
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(SPIKE_MEM_BASE).itcm \
		DTCM_FILE=$(SPIKE_MEM_BASE).dtcm \
		SIM_EXTRA_DEFINES="+cpp_timeout=1000000 +sv_timeout=1000000" \
		> $(HW_TRACE_LOG) 2>&1

commit_hw_csv: commit_hw_trace
	$(PYTHON) $(TRACE_TO_CSV) --log $(HW_TRACE_LOG) --csv $(HW_TRACE_CSV) --source ydrasil

commit_compare: commit_spike_csv commit_hw_csv
	$(PYTHON) $(TRACE_COMPARE) --mode csv \
		--hw-csv $(HW_TRACE_CSV) \
		--spike-csv $(SPIKE_TRACE_CSV) \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
		--max-rows $(SIM_COMPARE_MAX_ROWS) \
		--context-lines 10

get_spike:
	@if [ -x "$(SPIKE)" ]; then \
		if env $(SPIKE_RUN_ENV) "$(SPIKE)" $(SPIKE_CHECK_ARGS) >/dev/null 2>&1; then \
			echo "Spike is already installed: $(SPIKE)"; \
		else \
			echo "Error: Spike exists but cannot run: $(SPIKE)"; \
			env $(SPIKE_RUN_ENV) "$(SPIKE)" $(SPIKE_CHECK_ARGS); \
			exit 1; \
		fi; \
	else \
		echo "Deploying Spike ($(SPIKE_DEPLOY_MODE)) to $(SPIKE_INSTALL_DIR)"; \
		case "$(SPIKE_DEPLOY_MODE)" in \
			source|source-sudo) $(MAKE) build_spike_from_source ;; \
			prebuilt) $(MAKE) download_and_extract_spike ;; \
			*) echo "Error: Unsupported SPIKE_DEPLOY_MODE=$(SPIKE_DEPLOY_MODE)"; exit 1 ;; \
		esac; \
		if env $(SPIKE_RUN_ENV) "$(SPIKE)" $(SPIKE_CHECK_ARGS) >/dev/null 2>&1; then \
			echo "Spike installed: $(SPIKE)"; \
		else \
			echo "Error: Spike was deployed but cannot run: $(SPIKE)"; \
			env $(SPIKE_RUN_ENV) "$(SPIKE)" $(SPIKE_CHECK_ARGS); \
			exit 1; \
		fi; \
	fi

download_and_extract_spike: check_spike_prebuilt_abi
	$(MAKE) TOOLS="$(CURL) tar" check_deps
	@echo "Downloading Spike from: $(SPIKE_TAR_URL)"
	@mkdir -p $(dir $(SPIKE_TAR_FILE))
	$(CURL) -L $(SPIKE_TAR_URL) -o $(SPIKE_TAR_FILE)
	@mkdir -p "$(SPIKE_INSTALL_DIR)"
	tar -xJf "$(SPIKE_TAR_FILE)" -C "$(SPIKE_INSTALL_DIR)" --strip-components=1

check_spike_prebuilt_abi:
	@if ldconfig -p 2>/dev/null | grep -q "$(SPIKE_PREBUILT_BOOST_REGEX)"; then \
		exit 0; \
	elif find /usr/lib /usr/local/lib /opt -name "$(SPIKE_PREBUILT_BOOST_REGEX)" -print -quit 2>/dev/null | grep -q .; then \
		exit 0; \
	else \
		echo "Error: prebuilt Spike requires $(SPIKE_PREBUILT_BOOST_REGEX)."; \
		echo "Use an Arch-compatible system with that Boost regex ABI, or set SPIKE_DEPLOY_MODE=source."; \
		exit 1; \
	fi

build_spike_from_source:
	$(MAKE) TOOLS="$(SPIKE_BUILD_TOOLS)" check_deps
	@mkdir -p $(SPIKE_SRC_BUILD_DIR)
	@if [ ! -w "$(SPIKE_SRC_BUILD_DIR)" ]; then \
		$(SPIKE_INSTALL_SUDO) chown -R "$$(id -u):$$(id -g)" "$(SPIKE_SRC_BUILD_DIR)"; \
	fi
	$(SPIKE_INSTALL_SUDO) mkdir -p "$(SPIKE_SRC_INSTALL_DIR)"
	cd $(SPIKE_SRC_BUILD_DIR) && CC=$(SPIKE_HOST_CC) CXX=$(SPIKE_HOST_CXX) AR=$(SPIKE_HOST_AR) RANLIB=$(SPIKE_HOST_RANLIB) $(SPIKE_SRC_DIR)/configure \
		--prefix=$(SPIKE_SRC_INSTALL_DIR) \
		--enable-commitlog \
		--with-target=$(RISCV_PREFIX)
	$(MAKE) -C $(SPIKE_SRC_BUILD_DIR) -j$(SPIKE_BUILD_JOBS) CC=$(SPIKE_HOST_CC) CXX=$(SPIKE_HOST_CXX) AR=$(SPIKE_HOST_AR) RANLIB=$(SPIKE_HOST_RANLIB)
	$(SPIKE_INSTALL_SUDO) $(MAKE) -C $(SPIKE_SRC_BUILD_DIR) install CC=$(SPIKE_HOST_CC) CXX=$(SPIKE_HOST_CXX) AR=$(SPIKE_HOST_AR) RANLIB=$(SPIKE_HOST_RANLIB)
	$(SPIKE_INSTALL_SUDO) chmod -R a+rX "$(SPIKE_SRC_INSTALL_DIR)"
	@echo "Built Spike: $(SPIKE_SRC_INSTALL_DIR)/bin/spike"
