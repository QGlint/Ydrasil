include config.mk

SHELL := /bin/bash

# --- 自动化测试相关定义 ---
RESULT_DIR := $(LOG_DIR)/test_results
PPA_DIR ?= $(BUILD_DIR)/PPA
PPA_RVTEST_LOG ?= $(PPA_DIR)/test_all_summary.log
PPA_COREMARK_LOG ?= $(PPA_DIR)/coremark_summary.log
SORT_APP_DIR := $(PROJECT_ROOT)/sw/apps/sort
SORT_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(SORT_APP_DIR)/*.c))))
SORT_SIM_TARGETS := $(addprefix sort_sim_,$(SORT_APP_NAMES))
SORT_RESULT_DIR ?= $(RESULT_DIR)/sort
BOUNDARY_APP_DIR := $(PROJECT_ROOT)/sw/apps/boundary
BOUNDARY_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(BOUNDARY_APP_DIR)/*.c))))
BOUNDARY_SIM_TARGETS := $(addprefix boundary_sim_,$(BOUNDARY_APP_NAMES))
BOUNDARY_RESULT_DIR ?= $(RESULT_DIR)/boundary
PPA_BOUNDARY_LOG ?= $(PPA_DIR)/boundary_summary.log
PPA_SORT_LOG ?= $(PPA_DIR)/sort_summary.log
PPA_COE_LOG ?= $(PPA_DIR)/$(COE_SIMPLE_NAME)_summary.log
COE_SIMPLE_NAME ?= coe_loop2
COE_SIMPLE_ITCM ?= $(BUILD_DIR)/fpga_coe_m3/irom_M3_loop2.itcm
COE_SIMPLE_DTCM ?= $(BUILD_DIR)/fpga_coe_m3/dram_M_loop2.dtcm
COE_SIMPLE_LOG ?= $(HW_TRACE_OUT_DIR)/$(COE_SIMPLE_NAME)/hw.log
COE_SIMPLE_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +perip_debug +commit_trace +cpp_timeout=2000000 +sv_timeout=2000000
COE_ISA_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +perip_debug +commit_trace +cpp_timeout=2000000 +sv_timeout=2000000
COE_EXPECT_SEG ?= 0x37800000
COE_EXPECT_CNT_START ?= 0x80000000
COE_EXPECT_CNT_STOP ?= 0xffffffff
COE_EXPECT_CNT_READ ?= 0x00000000
COE_EXPECT_LED ?= 0x078b7323
COE_LOOP5_DIR ?= $(BUILD_DIR)/fpga_coe_m3
COE_LOOP5_ITCM_BIN ?= $(COE_LOOP5_DIR)/irom_M3_loop5_itcm.bin
COE_LOOP5_ITCM ?= $(COE_LOOP5_DIR)/irom_M3_loop5.itcm
COE_LOOP5_DTCM ?= $(COE_LOOP5_DIR)/dram_M_loop5.dtcm

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD VERILATOR_COVERAGE UVM USE_BENDER BENDER DIV_IMPL ARCH ABI RISCV_PREFIX CC OBJCOPY OBJDUMP GDB QEMU TRACE_TO_CSV TRACE_COMPARE

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
SYN_BIT_DIR ?= $(SYN_FREQ_BUILD_DIR)/bit
SYN_CHECKPOINT_DIR ?= $(SYN_FREQ_BUILD_DIR)/checkpoints
SYN_JOBS ?= $(shell nproc)
ifeq ($(HOSTNAME),servera437)
SYN_IMPL_RUNS ?= 4
SYN_THREADS_PER_RUN ?= 8
else
SYN_IMPL_RUNS ?= 1
SYN_THREADS_PER_RUN ?= $(shell nproc)
endif
SYN_IMPL_MODE ?= sweep
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

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests init install-bender get_spike download_and_extract_spike check_spike_prebuilt_abi build_spike_from_source check_deps spike spike_wave_to_csv sim_compare commit_check commit_spike_csv commit_hw_trace commit_hw_csv commit_compare rv_test_comp_genmem ppa_rvtest_report ppa_perf_report coe_simple coe_smoke coe_smoke_led coe_isa_probes coverage_all coverage_clean coverage_report
.PHONY: coremark coremark_sim coremark_run coremark_result coremark-rebuild coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map sort_app sort_all sort_sim_all sort_report sort_app_sim sort_app-rebuild sort_app-clean boundary_app boundary_all boundary_sim_all boundary_report boundary_app-rebuild boundary_app-clean coe_loop5 coe_loop5_gen
.PHONY: syn synf syn-extreme syn-venv syn-prep syn-stage-xpr syn-vivado syn-analyze syn-clean

.SECONDEXPANSION:



all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

run_all_tests: init check_deps test_all

coverage_clean:
	rm -rf "$(COVERAGE_DIR)"

coverage_all: coverage_clean
	@mkdir -p "$(COVERAGE_DATA_DIR)"
	@$(MAKE) comp VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	-@$(MAKE) boundary_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	-@$(MAKE) test_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	-@$(MAKE) sort_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	-@$(MAKE) coremark_sim VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	-@$(MAKE) coe_loop5 VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coverage_report
	@$(MAKE) ppa_perf_report

ppa_perf_report:
	@bash sw/scripts/collect_perf_stats.sh "$(HW_TRACE_OUT_DIR)" "$(PPA_DIR)"

coverage_report:
	@mkdir -p "$(COVERAGE_DIR)"; \
	set -- $$(find "$(COVERAGE_DATA_DIR)" -type f -name '*.dat' | sort); \
	if [ "$$#" -eq 0 ]; then echo "[COVERAGE] No data files found in $(COVERAGE_DATA_DIR)"; exit 1; fi; \
	echo "[COVERAGE] Merging $$# test databases" | tee "$(COVERAGE_SUMMARY)"; \
	verilator_coverage --write "$(COVERAGE_MERGED)" "$$@" 2>&1 | tee -a "$(COVERAGE_SUMMARY)"; \
	verilator_coverage --write-info "$(COVERAGE_INFO)" "$(COVERAGE_MERGED)"; \
	rm -rf "$(COVERAGE_ANNOTATE_DIR)"; \
	verilator_coverage --annotate "$(COVERAGE_ANNOTATE_DIR)" "$(COVERAGE_MERGED)" 2>&1 | tee -a "$(COVERAGE_SUMMARY)"; \
	total=$$(awk -F'[:,]' '/^DA:/{total++} END{print total+0}' "$(COVERAGE_INFO)"); \
	hit=$$(awk -F'[:,]' '/^DA:/ && $$3>0{hit++} END{print hit+0}' "$(COVERAGE_INFO)"); \
	percent=$$(awk -v h="$$hit" -v t="$$total" 'BEGIN{if(t) printf "%.2f",100*h/t; else print "0.00"}'); \
	{ echo "[COVERAGE] LCOV source-line coverage: $$hit/$$total ($$percent%)"; \
	  echo "[COVERAGE] Merged data: $(COVERAGE_MERGED)"; \
	  echo "[COVERAGE] LCOV: $(COVERAGE_INFO)"; \
	  echo "[COVERAGE] Annotated RTL: $(COVERAGE_ANNOTATE_DIR)"; \
	  echo "[COVERAGE] Summary: $(COVERAGE_SUMMARY)"; \
	} | tee -a "$(COVERAGE_SUMMARY)"

syn: syn-vivado
	@$(MAKE) syn-analyze

synf: SYN_PLL_FREQ_MHZ := 200
synf: SYN_RUN_TO := bitstream
synf: SYN_JOBS := 40
synf: SYN_IMPL_RUNS := 5
synf: SYN_THREADS_PER_RUN := 8
synf: syn-vivado
	@src="$(SYN_ARTIFACT_DIR)/jyd_fpga.bit"; \
	if [ ! -f "$$src" ]; then \
		echo "Error: best bitstream not found: $$src"; \
		exit 1; \
	fi; \
	mkdir -p "$(SYN_BIT_DIR)"; \
	timestamp=$$(date '+%Y%m%d_%H%M'); \
	dst="$(SYN_BIT_DIR)/jyd_fpga$${timestamp}.bit"; \
	cp "$$src" "$$dst"; \
	echo "[SYN] Best bitstream: $$dst"
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ)

syn-extreme: SYN_PLL_FREQ_MHZ := 200
syn-extreme: SYN_RUN_TO := bitstream
syn-extreme: SYN_IMPL_MODE := extreme
syn-extreme: SYN_IMPL_RUNS := 1
syn-extreme: syn-vivado
	@$(MAKE) syn-analyze SYN_IMPL_MODE=extreme SYN_IMPL_RUNS=1

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
		-threads_per_run $(SYN_THREADS_PER_RUN) \
		-impl_runs $(SYN_IMPL_RUNS) \
		-impl_mode $(SYN_IMPL_MODE) \
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
		ARCH=rv32im_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs \
		ABI=$(ABI)
SORT_APP_SW_MAKE_ARGS = \
		PROJECT_ROOT=$(PROJECT_ROOT) \
		RISCV_PREFIX=$(RISCV_PREFIX) \
		ARCH=rv32im_zicsr_zifencei \
		ABI=$(ABI)
BOUNDARY_APP_SW_MAKE_ARGS = $(COREMARK_SW_MAKE_ARGS)
COREMARK_RESULT_LOG ?= $(HW_TRACE_OUT_DIR)/coremark/hw.log
COREMARK_SIM_COMPARE ?= none
COMPARE_TRACE_DEFINES = $(if $(filter none,$(SIM_COMPARE)),,$(if $(findstring +commit_trace,$(COMPARE_SIM_EXTRA_DEFINES)),,+commit_trace))
COMPARE_SIM_DEFINES = $(strip $(COMPARE_SIM_EXTRA_DEFINES) $(COMPARE_TRACE_DEFINES))

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

sort_app:
	@$(MAKE) -C sw sort_app $(SORT_APP_SW_MAKE_ARGS)

sort_app-rebuild:
	@$(MAKE) -C sw sort_app-rebuild $(SORT_APP_SW_MAKE_ARGS)

sort_all:
	@echo "==========================================================="
	@echo "   Sort regression: $(SORT_APP_NAMES)"
	@echo "==========================================================="
	@$(MAKE) -j sort_app
	@$(MAKE) comp
	@rm -rf "$(SORT_RESULT_DIR)"
	@$(MAKE) -j sort_sim_all
	@$(MAKE) sort_report

sort_sim_all: $(SORT_SIM_TARGETS)

sort_sim_%:
	@name=$*; \
	result_dir="$(SORT_RESULT_DIR)"; \
	hw_log="$(HW_TRACE_OUT_DIR)/sort/$$name/hw.log"; \
	run_log="$$result_dir/$$name.log"; \
	status="$$result_dir/$$name.status"; \
	mkdir -p "$$result_dir"; \
	rm -f "$$hw_log" "$$run_log" "$$status"; \
	if $(MAKE) --no-print-directory sim_compare \
		SIM_COMPARE=none \
		COMPARE_NAME="sort/$$name" \
		COMPARE_ELF="$(BUILD_DIR)/app/sort/$$name.elf" \
		COMPARE_ITCM="$(BUILD_DIR)/app/sort/$$name.itcm" \
		COMPARE_DTCM="$(BUILD_DIR)/app/sort/$$name.dtcm" \
		COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=2000000 +sv_timeout=2000000" \
		>"$$run_log" 2>&1 && grep -q "SORT PASS name=$$name count=100" "$$hw_log"; then \
		result=PASS; \
	else \
		result=FAIL; \
	fi; \
	cycles=$$(grep -o 'CYCLES=[0-9]*' "$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	insts=$$(grep -o 'INSTS=[0-9]*' "$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	ipc=$$(grep -o 'IPC=[0-9.]*' "$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	[ -n "$$cycles" ] || cycles=N/A; \
	[ -n "$$insts" ] || insts=N/A; \
	[ -n "$$ipc" ] || ipc=N/A; \
	echo "[$$name] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [$$result]" > "$$status"

sort_report:
	@mkdir -p "$(PPA_DIR)"; \
	rm -f "$(PPA_SORT_LOG)"; \
	failed=0; \
	for status in $$(find "$(SORT_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | sort); do \
		line=$$(cat "$$status"); \
		echo "$$line" | tee -a "$(PPA_SORT_LOG)"; \
		if echo "$$line" | grep -q '\[FAIL\]'; then \
			failed=1; \
			name=$$(basename "$$status" .status); \
			tail -40 "$(SORT_RESULT_DIR)/$$name.log"; \
		fi; \
	done; \
	count=$$(find "$(SORT_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | wc -l); \
	if [ "$$count" -ne "$(words $(SORT_APP_NAMES))" ]; then \
		echo "[SORT] Missing status files: expected $(words $(SORT_APP_NAMES)), got $$count"; \
		failed=1; \
	fi; \
	echo "[PPA] Sort report: $(PPA_SORT_LOG)"; \
	exit $$failed

sort_app_sim: sort_all

boundary_app:
	@$(MAKE) -C sw boundary_app $(BOUNDARY_APP_SW_MAKE_ARGS)

boundary_app-rebuild:
	@$(MAKE) -C sw boundary_app-rebuild $(BOUNDARY_APP_SW_MAKE_ARGS)

boundary_all:
	@echo "==========================================================="
	@echo "   Boundary regression: $(BOUNDARY_APP_NAMES)"
	@echo "==========================================================="
	@$(MAKE) -j boundary_app
	@$(MAKE) comp
	@rm -rf "$(BOUNDARY_RESULT_DIR)"
	@$(MAKE) -j boundary_sim_all
	@$(MAKE) boundary_report

boundary_sim_all: $(BOUNDARY_SIM_TARGETS)

boundary_sim_%:
	@name=$*; result_dir="$(BOUNDARY_RESULT_DIR)"; hw_log="$(HW_TRACE_OUT_DIR)/boundary/$$name/hw.log"; run_log="$$result_dir/$$name.log"; status="$$result_dir/$$name.status"; \
	mkdir -p "$$result_dir"; rm -f "$$hw_log" "$$run_log" "$$status"; \
	if $(MAKE) --no-print-directory sim_compare SIM_COMPARE=none COMPARE_NAME="boundary/$$name" COMPARE_ELF="$(BUILD_DIR)/app/boundary/$$name.elf" COMPARE_ITCM="$(BUILD_DIR)/app/boundary/$$name.itcm" COMPARE_DTCM="$(BUILD_DIR)/app/boundary/$$name.dtcm" COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=2000000 +sv_timeout=2000000" >"$$run_log" 2>&1 && grep -q "BOUNDARY PASS name=$$name" "$$hw_log"; then result=PASS; else result=FAIL; fi; \
	echo "[$$name] [$$result]" > "$$status"

boundary_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_BOUNDARY_LOG)"; failed=0; \
	for status in $$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | sort); do line=$$(cat "$$status"); echo "$$line" | tee -a "$(PPA_BOUNDARY_LOG)"; if echo "$$line" | grep -q '\[FAIL\]'; then failed=1; name=$$(basename "$$status" .status); tail -40 "$(BOUNDARY_RESULT_DIR)/$$name.log"; fi; done; \
	count=$$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | wc -l); \
	if [ "$$count" -ne "$(words $(BOUNDARY_APP_NAMES))" ]; then echo "[BOUNDARY] Missing status files: expected $(words $(BOUNDARY_APP_NAMES)), got $$count"; failed=1; fi; \
	echo "[PPA] Boundary report: $(PPA_BOUNDARY_LOG)"; exit $$failed

coremark_result:
	@mkdir -p "$(PPA_DIR)"; \
	rm -f "$(PPA_COREMARK_LOG)"; \
	if [ -f "$(COREMARK_RESULT_LOG)" ]; then \
		echo "[COREMARK] Result from $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
		tmp=$$(mktemp); \
		awk '{ \
			line=$$0; \
			if (line ~ /^(PERF_METRIC:|PERF_STALL:|PERF_SCOREBOARD_DETAIL:|PERF_LOAD_DETAIL:|PERF_ALU_DETAIL:|PERF_PENDING_DETAIL:|PERF_LSU_HOT:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:)/) { \
				print line; \
			} else if (match(line, /(core[[:space:]]+0:|3[[:space:]]+0x)/)) { \
				prefix=substr(line, 1, RSTART - 1); \
				if (length(prefix) > 0) printf "%s", prefix; \
			} else if (line !~ /^(make(\\[[0-9]+\\])?:|\\[VERILATOR RUN\\]|cd |C\\+\\+ timeout set to|Trace is |Loading memory from|No itcm_init defined|\\[TB\\]|Simulation finished at|- .*Verilog \\$finish|\\[CLEAN EMPTY LOG\\])/) { \
				print line; \
			} else if (line == "") { \
				printf "\n"; \
			} \
		} END { printf "\n"; }' "$(COREMARK_RESULT_LOG)" > $$tmp; \
		if grep -Eq '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_METRIC:|PERF_STALL:|PERF_SCOREBOARD_DETAIL:|PERF_LOAD_DETAIL:|PERF_ALU_DETAIL:|PERF_PENDING_DETAIL:|PERF_LSU_HOT:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:|\[[0-9]+\]crc)' "$$tmp"; then \
			grep -E '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_METRIC:|PERF_STALL:|PERF_SCOREBOARD_DETAIL:|PERF_LOAD_DETAIL:|PERF_ALU_DETAIL:|PERF_PENDING_DETAIL:|PERF_LSU_HOT:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:|\[[0-9]+\]crc)' "$$tmp" | tee -a "$(PPA_COREMARK_LOG)"; \
		else \
			echo "[COREMARK] No CoreMark result lines found in $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
		fi; \
		rm -f $$tmp; \
	else \
		echo "[COREMARK] HW log not found: $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
	fi

coe_simple: comp
	@set -e; \
	rm -f "$(COE_SIMPLE_LOG)"; \
	$(MAKE) sim_compare \
		SIM_COMPARE=none \
		COMPARE_NAME="$(COE_SIMPLE_NAME)" \
		COMPARE_ITCM="$(COE_SIMPLE_ITCM)" \
		COMPARE_DTCM="$(COE_SIMPLE_DTCM)" \
		COMPARE_SIM_EXTRA_DEFINES="$(COE_SIMPLE_SIM_EXTRA_DEFINES)"; \
	log="$(COE_SIMPLE_LOG)"; \
	ok=1; \
	if [ ! -f "$$log" ]; then \
		echo "[COE_SIMPLE] Missing log: $$log"; \
		exit 1; \
	fi; \
	if ! grep -q "SEG write $(COE_EXPECT_SEG)" "$$log"; then \
		echo "[COE_SIMPLE] Expected SEG write $(COE_EXPECT_SEG) not found"; \
		ok=0; \
	fi; \
	if ! grep -q "CNT write $(COE_EXPECT_CNT_START)" "$$log"; then \
		echo "[COE_SIMPLE] Expected CNT start/write $(COE_EXPECT_CNT_START) not found"; \
		ok=0; \
	fi; \
	if [ -n "$(COE_EXPECT_CNT_STOP)" ] && ! grep -q "CNT write $(COE_EXPECT_CNT_STOP)" "$$log"; then \
		echo "[COE_SIMPLE] Expected CNT stop/write $(COE_EXPECT_CNT_STOP) not found"; \
		ok=0; \
	fi; \
	if [ -n "$(COE_EXPECT_CNT_READ)" ] && ! grep -q "CNT read.*$(COE_EXPECT_CNT_READ)" "$$log"; then \
		echo "[COE_SIMPLE] Expected CNT read $(COE_EXPECT_CNT_READ) not found"; \
		ok=0; \
	fi; \
	if ! grep -q "LED write $(COE_EXPECT_LED)" "$$log"; then \
		echo "[COE_SIMPLE] Expected LED write $(COE_EXPECT_LED) not found"; \
		ok=0; \
	fi; \
	if [ "$$ok" -ne 1 ]; then \
		echo "[COE_SIMPLE] Peripheral trace from $$log:"; \
		grep -E "LED write|SEG write|CNT write|CNT read|\\[PERIP\\]|\\[TB\\]|Simulation finished" "$$log" | tail -200; \
		echo "[COE_SIMPLE] Last commit/PC trace from $$log:"; \
		grep -E "^core   0:|^3 0x|timeout pc=|TEST_FAIL|fail testnum|RISCV_TEST|Simulation finished" "$$log" | tail -200; \
		exit 1; \
	fi; \
	mkdir -p "$(PPA_DIR)"; \
	{ echo "[COE_SIMPLE] PASS $(COE_SIMPLE_NAME)"; \
	  grep -E "LED write|SEG write|CNT write|CNT read|PERF_" "$$log"; \
	} > "$(PPA_COE_LOG)"; \
	echo "[COE_SIMPLE] PASS $(COE_SIMPLE_NAME)"; \
	grep -E "LED write|SEG write|CNT write|CNT read|PERF_|\\[PERIP\\]|\\[TB\\]|Simulation finished" "$$log" | tail -100

coe_loop5_gen:
	@mkdir -p "$(COE_LOOP5_DIR)"
	perl sw/make_m3_loop_variant.pl \
		"$(COE_LOOP5_DIR)/irom_M3_loop2_itcm.bin" "$(COE_LOOP5_ITCM_BIN)" 4
	od -An -t x4 -w4 -v "$(COE_LOOP5_ITCM_BIN)" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$(COE_LOOP5_ITCM)"
	cp "$(COE_LOOP5_DIR)/dram_M_loop2.dtcm" "$(COE_LOOP5_DTCM)"
	$(OBJDUMP) -D -b binary -m riscv:rv32 "$(COE_LOOP5_ITCM_BIN)" > "$(COE_LOOP5_DIR)/irom_M3_loop5.dump"

coe_loop5: coe_loop5_gen
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_loop5 \
		COE_SIMPLE_ITCM=$(COE_LOOP5_ITCM) \
		COE_SIMPLE_DTCM=$(COE_LOOP5_DTCM) \
		COE_EXPECT_CNT_READ=0x00000002 \
		COE_EXPECT_SEG=0x37800002

coe_smoke:
	@$(MAKE) coe_simple
	@$(MAKE) coe_isa_probes
	@$(MAKE) coe_smoke_led

coe_smoke_led:
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_smoke_led_dbg \
		COE_SIMPLE_ITCM=$(BUILD_DIR)/fpga_coe_m3/irom_M3_smoke_led.itcm \
		COE_SIMPLE_DTCM=$(BUILD_DIR)/fpga_coe_m3/dram_M_smoke_led.dtcm \
		COE_EXPECT_CNT_STOP= \
		COE_EXPECT_CNT_READ= \
		COE_EXPECT_LED=0x00020001

coe_isa_probes: comp
	@set -e; \
	for probe in isa1 isa2; do \
		case "$$probe" in \
			isa1) seg=0x37000000 ;; \
			isa2) seg=0x00800000 ;; \
		esac; \
		name=coe_$${probe}_probe; \
		rm -f "$(HW_TRACE_OUT_DIR)/$$name/hw.log"; \
		$(MAKE) sim_compare \
			SIM_COMPARE=none \
			COMPARE_NAME="$$name" \
			COMPARE_ITCM="$(BUILD_DIR)/fpga_coe_m3/irom_M3_$${probe}_probe.itcm" \
			COMPARE_DTCM="$(BUILD_DIR)/fpga_coe_m3/dram_M_loop2.dtcm" \
			COMPARE_SIM_EXTRA_DEFINES="$(COE_ISA_SIM_EXTRA_DEFINES)"; \
		log="$(HW_TRACE_OUT_DIR)/$$name/hw.log"; \
		ok=1; \
		if ! grep -q "SEG write $$seg" "$$log"; then \
			echo "[COE_ISA] $$probe expected SEG write $$seg not found"; \
			ok=0; \
		fi; \
		if ! grep -q "CNT write 0x80000000" "$$log"; then \
			echo "[COE_ISA] $$probe expected CNT start not found"; \
			ok=0; \
		fi; \
		if ! grep -q "LED write 0x00020000" "$$log"; then \
			echo "[COE_ISA] $$probe expected LED write 0x00020000 not found"; \
			ok=0; \
		fi; \
		if [ "$$ok" -ne 1 ]; then \
			echo "[COE_ISA] Peripheral trace from $$log:"; \
			grep -E "LED write|SEG write|CNT write|CNT read|\\[PERIP\\]|\\[TB\\]|Simulation finished" "$$log" | tail -200; \
			echo "[COE_ISA] Last commit/PC trace from $$log:"; \
			grep -E "^core   0:|^3 0x|timeout pc=|TEST_FAIL|fail testnum|RISCV_TEST|Simulation finished" "$$log" | tail -200; \
			exit 1; \
		fi; \
		echo "[COE_ISA] PASS $$probe"; \
		grep -E "LED write|SEG write|CNT write|CNT read|Simulation finished" "$$log" | tail -20; \
	done

coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map:
	@$(MAKE) -C sw $@ $(COREMARK_SW_MAKE_ARGS)

sort_app-clean:
	@$(MAKE) -C sw sort_app-clean $(SORT_APP_SW_MAKE_ARGS)

boundary_app-clean:
	@$(MAKE) -C sw boundary_app-clean $(BOUNDARY_APP_SW_MAKE_ARGS)


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
	@mkdir -p $(COMPARE_OUT_DIR) $(COMPARE_HW_OUT_DIR) $(dir $(COMPARE_HW_LOG)) $(dir $(COMPARE_SPIKE_LOG)) $(dir $(COMPARE_HW_CSV)) $(dir $(COMPARE_SPIKE_CSV)) $(COVERAGE_DATA_DIR)
ifeq ($(SIM_COMPARE),none)
	@echo "[SIM] HW only: $(COMPARE_NAME)"
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(abspath $(COMPARE_ITCM)) \
		DTCM_FILE=$(abspath $(COMPARE_DTCM)) \
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_DEFINES) $(if $(filter 1,$(VERILATOR_COVERAGE)),+coverage_file=$(abspath $(COMPARE_COVERAGE_FILE)),)" \
		> $(COMPARE_HW_LOG) 2>&1
	@echo "[SIM] HW log: $(COMPARE_HW_LOG)"
else ifeq ($(SIM_COMPARE),realtime)
	@$(MAKE) get_spike
	@echo "[SIM] Realtime compare: $(COMPARE_NAME)"
	$(PYTHON) $(TRACE_COMPARE) --mode realtime \
		--hw-cmd "$(MAKE) -C hw/dv sim VERILATOR_TRACE=0 LOG_OUTPUT=0 ITCM_FILE=$(abspath $(COMPARE_ITCM)) DTCM_FILE=$(abspath $(COMPARE_DTCM)) SIM_EXTRA_DEFINES='$(COMPARE_SIM_DEFINES)'" \
		--spike-cmd "env $(SPIKE_RUN_ENV) $(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(abspath $(COMPARE_ELF))" \
		--hw-log $(COMPARE_HW_LOG) \
		--spike-log $(COMPARE_SPIKE_LOG) \
		--merge-stderr \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
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
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_DEFINES) $(if $(filter 1,$(VERILATOR_COVERAGE)),+coverage_file=$(abspath $(COMPARE_COVERAGE_FILE)),)" \
		> $(COMPARE_HW_LOG) 2>&1
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_HW_LOG) --csv $(COMPARE_HW_CSV) --source ydrasil
	@echo "[SIM] HW CSV: $(COMPARE_HW_CSV)"
	@set +e; \
	$(PYTHON) $(TRACE_COMPARE) --mode csv \
		--hw-csv $(COMPARE_HW_CSV) \
		--spike-csv $(COMPARE_SPIKE_CSV) \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
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
		SIM_EXTRA_DEFINES="+cpp_timeout=1000000 +sv_timeout=1000000 +commit_trace" \
		> $(HW_TRACE_LOG) 2>&1

commit_hw_csv: commit_hw_trace
	$(PYTHON) $(TRACE_TO_CSV) --log $(HW_TRACE_LOG) --csv $(HW_TRACE_CSV) --source ydrasil

commit_compare: commit_spike_csv commit_hw_csv
	$(PYTHON) $(TRACE_COMPARE) --mode csv \
		--hw-csv $(HW_TRACE_CSV) \
		--spike-csv $(SPIKE_TRACE_CSV) \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
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
