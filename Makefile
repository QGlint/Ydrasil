include config.mk

SHELL := /bin/bash
# 硬件verilator编译 VERILATOR_IGNORE_ALL=0 不忽略所有语法检查
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
BOUNDARY_OPT_PROFILES ?= O0 O1 O2 O3 Os Og O2_noinline O3_app_unroll
BOUNDARY_OPT_JOBS ?= $(shell nproc)
BOUNDARY_OPT_APP_ROOT ?= $(BUILD_DIR)/app/boundary-opt
BOUNDARY_OPT_RESULT_DIR ?= $(RESULT_DIR)/boundary-opt
BOUNDARY_OPT_RUN_DIR ?= $(BUILD_DIR)/boundary-opt-run
PPA_BOUNDARY_OPT_LOG ?= $(PPA_DIR)/boundary_opt_summary.log
APP_OPT_PROFILES ?= O0 O1 O2 O3 Os Og O2_noinline O3_app_unroll
APP_OPT_JOBS ?= $(shell nproc)
APP_OPT_ITCM_BYTES ?= 16384
APP_OPT_EXPANDED_ITCM_BYTES ?= 32768
APP_OPT_EXPANDED_ITCM_KIB ?= 32
APP_OPT_EXPANDED_ITCM_ADDR_WIDTH ?= 13
APP_OPT_EXPANDED_OBJ_DIR ?= $(BUILD_DIR)/ydrasil_core_tb-itcm-expanded
APP_OPT_EXPANDED_LOG_DIR ?= $(BUILD_DIR)/log/itcm-expanded
APP_OPT_EXPANDED_LINKER ?= $(BUILD_DIR)/app/opt-link/itcm-$(APP_OPT_EXPANDED_ITCM_KIB)K.lds
APP_OPT_CFLAGS_O0 ?= -O0
APP_OPT_CFLAGS_O1 ?= -O1
APP_OPT_CFLAGS_O2 ?= -O2
APP_OPT_CFLAGS_O3 ?= -O3
APP_OPT_CFLAGS_Os ?= -Os
APP_OPT_CFLAGS_Og ?= -Og
APP_OPT_CFLAGS_O2_noinline ?= -O2 -fno-inline -fno-inline-functions
APP_OPT_CFLAGS_O3_app_unroll ?= -O3 -funroll-loops
COREMARK_OPT_BSP_CFLAGS_O3 ?= -Os
COREMARK_OPT_APP_CFLAGS_O3 ?= -O3
COREMARK_OPT_BSP_CFLAGS_O3_app_unroll ?= -Os
COREMARK_OPT_APP_CFLAGS_O3_app_unroll ?= -O3 -funroll-loops
SORT_OPT_BSP_CFLAGS_O3_app_unroll ?= -Os
SORT_OPT_APP_CFLAGS_O3_app_unroll ?= -O3 -funroll-loops
COREMARK_OPT_ROOT ?= $(BUILD_DIR)/app/coremark-opt
COREMARK_OPT_RESULT_DIR ?= $(RESULT_DIR)/coremark-opt
PPA_COREMARK_OPT_LOG ?= $(PPA_DIR)/coremark_opt_summary.log
COREMARK_OPT_TIMEOUT ?= 2000000
COREMARK_OPT_TIMEOUT_O0 ?= 5000000
SORT_OPT_ROOT ?= $(BUILD_DIR)/app/sort-opt
SORT_OPT_RESULT_DIR ?= $(RESULT_DIR)/sort-opt
PPA_SORT_OPT_LOG ?= $(PPA_DIR)/sort_opt_summary.log
SORT_SIM_TIMEOUT ?= 20000000
SORT_OPT_TIMEOUT ?= 20000000
SORT_OPT_TIMEOUT_O0 ?= 50000000
COREMARK_OPT_BUILD_TARGETS := $(addprefix coremark_opt_build_,$(APP_OPT_PROFILES))
COREMARK_OPT_SIM_TARGETS := $(addprefix coremark_opt_sim_,$(APP_OPT_PROFILES))
SORT_OPT_BUILD_TARGETS := $(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),sort_opt_build_$(profile)_$(app)))
SORT_OPT_SIM_TARGETS := $(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),sort_opt_sim_$(profile)_$(app)))
COVERAGE_QUICK_TARGETS ?= boundary_all test_all coremark_sim coe_loop5
COVERAGE_QUICK_SUMMARY ?= $(PPA_DIR)/coverage_quick_summary.log
COVERAGE_CLOSURE_DIR ?= $(BUILD_DIR)/coverage-closure
COVERAGE_CLOSURE_DATA ?= $(COVERAGE_CLOSURE_DIR)/data/boundary_coverage_closure_edges.dat
COVERAGE_CLOSURE_MERGED ?= $(COVERAGE_CLOSURE_DIR)/merged.dat
COVERAGE_CLOSURE_INFO ?= $(COVERAGE_CLOSURE_DIR)/coverage.info
COVERAGE_CLOSURE_ANNOTATED ?= $(COVERAGE_CLOSURE_DIR)/annotated
COVERAGE_CLOSURE_BASES ?=
REGRESSION_TARGETS ?= coverage_all regression_sort regression_sort_opt riscv_dv_random
REGRESSION_SUMMARY ?= $(PPA_DIR)/regression_summary.log
REGRESSION_STATUS_REPORT ?= $(PPA_DIR)/regression_status.log
REGRESSION_LOG_DIR ?= $(BUILD_DIR)/log/regression
REGRESSION_RUN_ID ?=
REGRESSION_CONTEXT_LINES ?= 12
REGRESSION_CACHE_TOOL ?= $(PROJECT_ROOT)/verif/regression/cache.py
REGRESSION_CACHE_DIR ?= $(BUILD_DIR)/regression-cache
REGRESSION_CONTROL_DIR ?= $(BUILD_DIR)/regression-control
REGRESSION_STOP_FILE ?= $(REGRESSION_CONTROL_DIR)/STOP
REGRESSION_RUNNER_FILE ?= $(REGRESSION_CONTROL_DIR)/runner.json
COVERAGE_ALL_CACHE_DIR ?= $(REGRESSION_CACHE_DIR)/coverage-all
REGRESSION_SORT_COVERAGE_DIR ?= $(REGRESSION_CACHE_DIR)/coverage/sort
REGRESSION_SORT_OPT_COVERAGE_DIR ?= $(REGRESSION_CACHE_DIR)/coverage/sort-opt
REGRESSION_TOTAL_COVERAGE_DIR ?= $(BUILD_DIR)/coverage-total
REGRESSION_TOTAL_COVERAGE_DATA ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/merged.dat
REGRESSION_TOTAL_COVERAGE_INFO ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/coverage.info
REGRESSION_TOTAL_COVERAGE_ANNOTATED ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/annotated
REGRESSION_TOTAL_COVERAGE_SUMMARY ?= $(PPA_DIR)/regression_coverage_summary.log
REGRESSION_TOTAL_COVERAGE_UNCOVERED ?= $(PPA_DIR)/regression_coverage_uncovered.log
RISCV_DV_ROOT ?= $(PROJECT_ROOT)/verif/riscv-dv
RISCV_DV_DRIVER ?= $(RISCV_DV_ROOT)/ydrasil_regression.py
RISCV_DV_WORK_ROOT ?= $(BUILD_DIR)/riscv-dv
RISCV_DV_VENV ?= $(RISCV_DV_WORK_ROOT)/venv
RISCV_DV_PYTHON ?= $(RISCV_DV_VENV)/bin/python
RISCV_DV_VENV_STAMP ?= $(RISCV_DV_VENV)/.generator-ready
RISCV_DV_MODEL_DIR ?= $(RISCV_DV_WORK_ROOT)/model
RISCV_DV_MODEL_BIN ?= $(RISCV_DV_MODEL_DIR)/ydrasil_core_tb
RISCV_DV_MODEL_FINGERPRINT ?= $(RISCV_DV_MODEL_DIR)/.rtl-fingerprint
RISCV_DV_LINKER ?= $(RISCV_DV_ROOT)/ydrasil/link.ld
RISCV_DV_START_SEED ?= 1
RISCV_DV_COUNT ?= 2000
RISCV_DV_JOBS ?= 20
RISCV_DV_INSTR_COUNT ?= 400
RISCV_DV_SUBPROGRAMS ?= 0
RISCV_DV_SIM_TIMEOUT ?= 500000
RISCV_DV_CASE_TIMEOUT ?= 600
RISCV_DV_SPIKE_MAXSTEPS ?= 200000
RISCV_DV_KEEP_FAILURES ?= 20
RISCV_DV_KEEP_RUNS ?= 5
RISCV_DV_COVERAGE_BATCH ?= 20
RISCV_DV_STOP_REPORT ?= 1
RISCV_DV_RERUN ?= 0
RISCV_DV_MAX_CACHE_GB ?= 4
RISCV_DV_SUMMARY ?= $(PPA_DIR)/riscv_dv_summary.log
RISCV_DV_ARCH ?= rv32im_zicsr_zifencei
RISCV_DV_ABI ?= ilp32
RISCV_DV_GCC ?= $(RISCV_PREFIX)-gcc
RISCV_DV_OBJCOPY ?= $(RISCV_PREFIX)-objcopy
RISCV_DV_COMMON_ARGS = \
	--project-root "$(PROJECT_ROOT)" \
	--dv-root "$(RISCV_DV_ROOT)" \
	--work-root "$(RISCV_DV_WORK_ROOT)" \
	--python "$(RISCV_DV_PYTHON)" \
	--gcc "$(shell command -v $(RISCV_DV_GCC) 2>/dev/null)" \
	--objcopy "$(shell command -v $(RISCV_DV_OBJCOPY) 2>/dev/null)" \
	--make "$(shell command -v $(MAKE) 2>/dev/null)" \
	--spike "$(abspath $(SPIKE))" \
	--model-dir "$(RISCV_DV_MODEL_DIR)" \
	--linker "$(RISCV_DV_LINKER)" \
	--arch "$(RISCV_DV_ARCH)" \
	--abi "$(RISCV_DV_ABI)" \
	--start-seed "$(RISCV_DV_START_SEED)" \
	--count "$(RISCV_DV_COUNT)" \
	--jobs "$(RISCV_DV_JOBS)" \
	--instr-count "$(RISCV_DV_INSTR_COUNT)" \
	--subprograms "$(RISCV_DV_SUBPROGRAMS)" \
	--sim-timeout "$(RISCV_DV_SIM_TIMEOUT)" \
	--case-timeout "$(RISCV_DV_CASE_TIMEOUT)" \
	--spike-maxsteps "$(RISCV_DV_SPIKE_MAXSTEPS)" \
	--keep-failures "$(RISCV_DV_KEEP_FAILURES)" \
	--keep-runs "$(RISCV_DV_KEEP_RUNS)" \
	--max-cache-gb "$(RISCV_DV_MAX_CACHE_GB)" \
	--coverage-batch "$(RISCV_DV_COVERAGE_BATCH)" \
	--external-stop-file "$(REGRESSION_STOP_FILE)" \
	--verilator-coverage "$(shell command -v verilator_coverage 2>/dev/null)" \
	$(if $(filter 1,$(RISCV_DV_RERUN)),--rerun,)
BOUNDARY_OPT_CFLAGS_O0 ?= -O0
BOUNDARY_OPT_CFLAGS_O1 ?= -O1
BOUNDARY_OPT_CFLAGS_O2 ?= -O2
BOUNDARY_OPT_CFLAGS_O3 ?= -O3
BOUNDARY_OPT_CFLAGS_Os ?= -Os
BOUNDARY_OPT_CFLAGS_Og ?= -Og
BOUNDARY_OPT_CFLAGS_O2_noinline ?= -O2 -fno-inline -fno-inline-functions
BOUNDARY_OPT_CFLAGS_O3_app_unroll ?= -Os
BOUNDARY_OPT_APP_CFLAGS_O3_app_unroll ?= -O3 -funroll-loops
BOUNDARY_OPT_SPIKE_MAXSTEPS ?= 100000
BOUNDARY_OPT_SPIKE_MAXSTEPS_exception_stress ?= 1000000
BOUNDARY_OPT_SPIKE_SKIP_APPS ?= csr_counter_edges coverage_closure_edges
BOUNDARY_SIM_TIMEOUT ?= 2000000
COVERAGE_QUICK_TIMEOUT ?= 750000
COVERAGE_QUICK_MARGIN_PERCENT ?= 50
COVERAGE_QUICK_TIMEOUT_PAD ?= 10000
COVERAGE_QUICK_TICKS_PER_CYCLE ?= 2
COVERAGE_QUICK_BOUNDARY_MIN ?= 200000
COVERAGE_QUICK_ISA_MIN ?= 50000
COVERAGE_QUICK_COREMARK_MIN ?= 550000
COVERAGE_QUICK_COE_MIN ?= 300000
COREMARK_SIM_TIMEOUT ?= 10000000
COE_SIM_TIMEOUT ?= 2000000
BOUNDARY_OPT_BUILD_TARGETS := $(addprefix boundary_opt_build_,$(BOUNDARY_OPT_PROFILES))
BOUNDARY_OPT_SIM_TARGETS := $(foreach profile,$(BOUNDARY_OPT_PROFILES),$(foreach app,$(BOUNDARY_APP_NAMES),boundary_opt_sim_$(profile)_$(app)))
BOUNDARY_OPT_SW_DEPS := $(wildcard $(BOUNDARY_APP_DIR)/*.c $(BOUNDARY_APP_DIR)/*.h $(PROJECT_ROOT)/sw/bsp/*.S $(PROJECT_ROOT)/sw/bsp/lib/*.c $(PROJECT_ROOT)/sw/bsp/include/*.h) $(PROJECT_ROOT)/sw/Makefile
PPA_SORT_LOG ?= $(PPA_DIR)/sort_summary.log
SORT_EXPECT_CASES ?= 91
SORT_EXPECT_CHECKS ?= 455
SORT_EXPECT_SIGNATURE ?= c02bdfa9
PPA_COE_LOG ?= $(PPA_DIR)/$(COE_SIMPLE_NAME)_summary.log
COE_M3_DIR ?= $(BUILD_DIR)/fpga_coe_m3
COE_TO_MEM ?= $(PROJECT_ROOT)/sw/coe_to_mem.pl
COE_LOOP_PATCH ?= $(PROJECT_ROOT)/sw/make_m3_loop_variant.pl
COE_LOOP_LINA_PATCH ?= $(PROJECT_ROOT)/sw/make_m3_loop_lina.pl
COE_M3_ITCM ?= $(COE_M3_DIR)/irom_M3.itcm
COE_M3_ITCM_BIN ?= $(COE_M3_DIR)/irom_M3_itcm.bin
COE_M3_DTCM ?= $(COE_M3_DIR)/dram_M.dtcm
COE_LOOP2_ITCM_BIN ?= $(COE_M3_DIR)/irom_M3_loop2_itcm.bin
COE_LOOP2_ITCM ?= $(COE_M3_DIR)/irom_M3_loop2.itcm
COE_LOOP2_DTCM ?= $(COE_M3_DIR)/dram_M_loop2.dtcm
COE_SIMPLE_NAME ?= coe_loop2
COE_SIMPLE_ITCM ?= $(COE_LOOP2_ITCM)
COE_SIMPLE_DTCM ?= $(COE_LOOP2_DTCM)
COE_SIMPLE_LOG ?= $(HW_TRACE_OUT_DIR)/$(COE_SIMPLE_NAME)/hw.log
COE_SIMPLE_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +perip_debug +commit_trace +cpp_timeout=$(COE_SIM_TIMEOUT) +sv_timeout=$(COE_SIM_TIMEOUT)
COE_ISA_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +perip_debug +commit_trace +cpp_timeout=$(COE_SIM_TIMEOUT) +sv_timeout=$(COE_SIM_TIMEOUT)
COE_EXPECT_SEG ?= 0x37800000
COE_EXPECT_SEG_REGEX ?=
COE_EXPECT_CNT_START ?= 0x80000000
COE_EXPECT_CNT_STOP ?= 0xffffffff
COE_EXPECT_CNT_READ ?= 0x00000000
COE_REQUIRE_CNT_READ ?= 0
COE_EXPECT_LED ?= 0x078b7323
COE_LOOP5_DIR ?= $(COE_M3_DIR)
COE_LOOP5_ITCM_BIN ?= $(COE_LOOP5_DIR)/irom_M3_loop5_itcm.bin
COE_LOOP5_ITCM ?= $(COE_LOOP5_DIR)/irom_M3_loop5.itcm
COE_LOOP5_DTCM ?= $(COE_LOOP5_DIR)/dram_M_loop5.dtcm
COE_LOOP5_DUMP ?= $(COE_LOOP5_DIR)/irom_M3_loop5.dump
COE_LOOP_LINA_DIR ?= $(COE_M3_DIR)
COE_LOOP_LINA_SCALE ?= 5
COE_LOOP_LINA_SIM_TIMEOUT ?= 5000000
COE_LOOP_LINA_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +finish_on_terminal_led +perip_debug +cpp_timeout=$(COE_LOOP_LINA_SIM_TIMEOUT) +sv_timeout=$(COE_LOOP_LINA_SIM_TIMEOUT)
COE_LOOP_LINA_ITCM_BIN ?= $(COE_LOOP_LINA_DIR)/irom_M3_loop_lina_itcm.bin
COE_LOOP_LINA_ITCM ?= $(COE_LOOP_LINA_DIR)/irom_M3_loop_lina.itcm
COE_LOOP_LINA_DTCM ?= $(COE_LOOP_LINA_DIR)/dram_M_loop_lina.dtcm
COE_LOOP_LINA_DUMP ?= $(COE_LOOP_LINA_DIR)/irom_M3_loop_lina.dump
COE_MFLINA_DIR ?= $(BUILD_DIR)/fpga_coe_mflina
COE_MFLINA_PATCH ?= $(PROJECT_ROOT)/sw/make_mf_lina.pl
COE_MFLINA_IROM_SOURCE ?= $(PROJECT_ROOT)/FPGA/coe/irom_MF.coe
COE_MFLINA_DRAM_SOURCE ?= $(PROJECT_ROOT)/FPGA/coe/dram_MF.coe
COE_MFLINA_MATRIX_ITERATIONS ?= 8
COE_MFLINA_OUTER_ITERATIONS ?= 1
COE_MFLINA_SORT_LENGTH ?= 100
COE_MFLINA_SORT_OUTER_ITERATIONS ?= 1
COE_MFLINA_PRIME_LIMIT ?= 20
COE_MFLINA_RANDOM_OUTER_ITERATIONS ?= 5
COE_MFLINA_CRC_LENGTH ?= 1024
COE_MFLINA_CRC_OUTER_ITERATIONS ?= 1
COE_MFLINA_SIM_TIMEOUT ?= 5000000
COE_MFLINA_SIM_EXTRA_DEFINES ?= +no_finish_on_led +no_finish_on_tohost +finish_on_terminal_led +perip_debug +cpp_timeout=$(COE_MFLINA_SIM_TIMEOUT) +sv_timeout=$(COE_MFLINA_SIM_TIMEOUT)
COE_MFLINA_SOURCE_ITCM_BIN ?= $(COE_MFLINA_DIR)/irom_MF_itcm.bin
COE_MFLINA_ITCM_BIN ?= $(COE_MFLINA_DIR)/irom_MFlina_itcm.bin
COE_MFLINA_ITCM ?= $(COE_MFLINA_DIR)/irom_MFlina.itcm
COE_MFLINA_DTCM ?= $(COE_MFLINA_DIR)/dram_MF.dtcm
COE_MFLINA_DUMP ?= $(COE_MFLINA_DIR)/irom_MFlina.dump

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD COVERAGE VERILATOR_COVERAGE UVM USE_BENDER BENDER DIV_IMPL FPU LSU_IMPL MEMS_IMPL ARCH ABI RISCV_PREFIX CC OBJCOPY OBJDUMP GDB QEMU TRACE_TO_CSV TRACE_COMPARE

SYN_DIR ?= $(PROJECT_ROOT)/syn
SYN_BUILD_DIR ?= $(BUILD_DIR)/syn
SYN_VENV ?= $(SYN_BUILD_DIR)/.venv
SYN_PYTHON ?= $(SYN_VENV)/bin/python
SYN_PLL_FREQ_MHZ ?= 150
SYN_PLL_SUPPORTED_FREQS := 150 200 225 240 250
SYN_PLL_FREQ_TAG = pll$(subst .,p,$(SYN_PLL_FREQ_MHZ))m
SYN_PLL_DEFINE = SYN_PLL_FREQ_$(subst .,P,$(SYN_PLL_FREQ_MHZ))
SYN_RTL_DEFINES = $(SYN_PLL_DEFINE)
SYN_RTL_DEFINES += SYNTHESIS
SYN_RTL_DEFINES += $(if $(filter 1,$(FPU)),YDRASIL_ENABLE_FPU)
SYN_PROFILE ?= official
SYN_PROFILE_SUFFIX = $(if $(filter official,$(SYN_PROFILE)),,-$(SYN_PROFILE))$(if $(filter 1,$(FPU)),-fpu)
SYN_ENABLE_ILA ?= 0
SYN_BOARD_XDC ?=
SYN_RTL_DEFINES += $(if $(filter 1,$(SYN_ENABLE_ILA)),SYN_BOARD_ILA)
ifeq ($(DIV_IMPL),lzc)
SYN_RTL_DEFINES += YDRASIL_DIV_IMPL_LZC
else
$(error Unsupported DIV_IMPL '$(DIV_IMPL)'. Use DIV_IMPL=lzc)
endif
SYN_DEFINE_ARGS = $(foreach define,$(SYN_RTL_DEFINES),--define $(define))
SYN_FREQ_BUILD_DIR ?= $(SYN_BUILD_DIR)/$(SYN_PLL_FREQ_TAG)$(SYN_PROFILE_SUFFIX)
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
IROM_COE ?= $(PROJECT_ROOT)/FPGA/coe/irom_MF.coe
DRAM_COE ?= $(PROJECT_ROOT)/FPGA/coe/dram_MF.coe
SYN_MEMORY_DIR ?= $(SYN_FREQ_BUILD_DIR)/memory
SYN_STAGED_IROM_COE ?= $(SYN_MEMORY_DIR)/irom.coe
SYN_STAGED_DRAM_COE ?= $(SYN_MEMORY_DIR)/dram.coe
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

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests regression regression_all regression_status regression_stop regression_clean regression_sort regression_sort_opt regression_suite_coverage_merge regression_coverage_report init install-bender get_spike download_and_extract_spike check_spike_prebuilt_abi build_spike_from_source check_deps spike spike_wave_to_csv sim_compare commit_check commit_spike_csv commit_hw_trace commit_hw_csv commit_compare rv_test_comp_genmem ppa_rvtest_report ppa_perf_report coe_simple coe_smoke coe_smoke_led coe_isa_probes coverage_all coverage_all_run coverage_quick coverage_closure coverage_closure_merge coverage_clean coverage_report sw_boundary_test sw_coverage sw_coverage_clean sw_run_mode sw_coverage_report
.PHONY: coremark coremark_sim coremark_run coremark_result coremark-rebuild coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map coremark_opt_all coremark_opt_build_all coremark_opt_sim_all coremark_opt_report coremark_opt_clean $(COREMARK_OPT_BUILD_TARGETS) $(COREMARK_OPT_SIM_TARGETS) sort_app sort_all sort_sim_all sort_report sort_app_sim sort_app-rebuild sort_app-clean sort_opt_all sort_opt_build_all sort_opt_sim_all sort_opt_report sort_opt_clean $(SORT_OPT_BUILD_TARGETS) $(SORT_OPT_SIM_TARGETS) boundary_app boundary_all boundary_sim_all boundary_report boundary_app-rebuild boundary_app-clean boundary_opt_all boundary_opt_build_all boundary_opt_sim_all boundary_opt_report boundary_opt_clean $(BOUNDARY_OPT_BUILD_TARGETS) $(BOUNDARY_OPT_SIM_TARGETS) coe_loop2_gen coe_loop5 coe_loop5_gen coe_loop_lina coe_loop_lina_gen loop_lina coe_MFlina coe_MFlina_gen coe_mflina coe_mflina_gen rtthread rtthread-clean rtthread-coremark rtthread-coremark-clean
.PHONY: riscv_dv_venv riscv_dv_model riscv_dv_prepare riscv_dv_run riscv_dv_random riscv_dv_random_status riscv_dv_regression riscv_dv_count riscv_dv_repro riscv_dv_estimate riscv_dv_stop riscv_dv_coverage_report riscv_dv_cleanup riscv_dv_distclean
.PHONY: syn synf syn225 syn240 syn250 synf-board syn-extreme syn-venv syn-prep syn-stage-xpr syn-stage-memory syn-vivado syn-analyze syn-clean

.SECONDEXPANSION:



all: comp_and_sim_cpu

full : comp_and_sim_cpu wave

run_all_tests: init check_deps test_all

$(RISCV_DV_VENV_STAMP): $(RISCV_DV_ROOT)/requirements-generator.txt
	@mkdir -p "$(RISCV_DV_WORK_ROOT)"
	@if [ ! -x "$(RISCV_DV_PYTHON)" ]; then python3 -m venv "$(RISCV_DV_VENV)"; fi
	@"$(RISCV_DV_PYTHON)" -m pip install --disable-pip-version-check -r "$<"
	@"$(RISCV_DV_PYTHON)" -c 'import bitstring, pandas, tabulate, vsc, yaml'
	@touch "$@"

riscv_dv_venv: $(RISCV_DV_VENV_STAMP)

riscv_dv_model:
	@set -e; rebuild=0; \
	fingerprint=$$($(PYTHON) "$(REGRESSION_CACHE_TOOL)" fingerprint --project-root "$(PROJECT_ROOT)" --scope rtl); \
	if [ ! -x "$(RISCV_DV_MODEL_BIN)" ]; then rebuild=1; \
	elif [ ! -f "$(RISCV_DV_MODEL_FINGERPRINT)" ] || [ "$$(cat "$(RISCV_DV_MODEL_FINGERPRINT)")" != "$$fingerprint" ]; then rebuild=1; fi; \
	if [ "$$rebuild" -eq 0 ] && find "$(PROJECT_ROOT)/hw/dv" "$(PROJECT_ROOT)/hw/ip" -type f -path '*/dv/*' \
		\( -name '*.sv' -o -name '*.v' -o -name '*.cpp' -o -name '*.h' -o -name 'Bender.yml' \) \
		-newer "$(RISCV_DV_MODEL_BIN)" -print -quit | grep -q .; then rebuild=1; fi; \
	if [ "$$rebuild" -eq 1 ]; then \
		echo "[RISCV-DV] Compiling shared Verilator model once"; \
		$(MAKE) --no-print-directory comp OBJ_DIR="$(RISCV_DV_MODEL_DIR)" \
			VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 Compile_optimization=1; \
		printf '%s\n' "$$fingerprint" > "$(RISCV_DV_MODEL_FINGERPRINT)"; \
	else echo "[RISCV-DV] Reusing model: $(RISCV_DV_MODEL_BIN)"; fi

riscv_dv_prepare: riscv_dv_venv get_spike
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" prepare $(RISCV_DV_COMMON_ARGS)

# Deliberately has no prepare dependency: execution never regenerates cached programs.
riscv_dv_run: riscv_dv_venv riscv_dv_model get_spike
	@mkdir -p "$(PPA_DIR)"
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" run $(RISCV_DV_COMMON_ARGS); rc=$$?; \
	summary=$$(find "$(RISCV_DV_WORK_ROOT)/runs" -mindepth 2 -maxdepth 2 -name summary.log -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); \
	if [ -n "$$summary" ]; then cp "$$summary" "$(RISCV_DV_SUMMARY)"; echo "[RISCV-DV] Summary: $$summary"; fi; \
	exit $$rc

riscv_dv_random: riscv_dv_venv riscv_dv_model get_spike
	@mkdir -p "$(PPA_DIR)"
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" continuous $(RISCV_DV_COMMON_ARGS); rc=$$?; \
	summary=$$(find "$(RISCV_DV_WORK_ROOT)/runs" -mindepth 2 -maxdepth 2 -name summary.log -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); \
	if [ -n "$$summary" ]; then cp "$$summary" "$(RISCV_DV_SUMMARY)"; echo "[RISCV-DV] Summary: $$summary"; fi; \
	exit $$rc

riscv_dv_random_status: riscv_dv_venv
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" status $(RISCV_DV_COMMON_ARGS)

riscv_dv_regression: riscv_dv_venv
	@set +e; rc=0; \
	$(MAKE) --no-print-directory riscv_dv_model || rc=$$?; \
	if [ "$$rc" -eq 0 ]; then $(MAKE) --no-print-directory riscv_dv_prepare || rc=$$?; fi; \
	if [ "$$rc" -eq 0 ]; then $(MAKE) --no-print-directory riscv_dv_run || rc=$$?; fi; \
	$(MAKE) --no-print-directory riscv_dv_cleanup; cleanup_rc=$$?; \
	if [ "$$rc" -eq 0 ] && [ "$$cleanup_rc" -ne 0 ]; then rc=$$cleanup_rc; fi; \
	exit "$$rc"

riscv_dv_count:
	@if [ -z "$(RISCV_DV_NUM)" ]; then echo "Usage: make riscv_dv_count RISCV_DV_NUM=<number>"; exit 2; fi
	@$(MAKE) --no-print-directory riscv_dv_regression RISCV_DV_COUNT="$(RISCV_DV_NUM)"

riscv_dv_repro: riscv_dv_venv riscv_dv_model get_spike
	@if [ -z "$(RISCV_DV_SEED)" ]; then echo "Usage: make riscv_dv_repro RISCV_DV_SEED=<seed>"; exit 2; fi
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" reproduce $(RISCV_DV_COMMON_ARGS) --seed "$(RISCV_DV_SEED)"

riscv_dv_estimate: riscv_dv_venv
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" estimate $(RISCV_DV_COMMON_ARGS)

riscv_dv_stop:
	@mkdir -p "$(RISCV_DV_WORK_ROOT)"; touch "$(RISCV_DV_WORK_ROOT)/STOP"
	@echo "[RISCV-DV] Graceful stop requested; no new seeds will start."
	@runner="$(RISCV_DV_WORK_ROOT)/runner.json"; \
	if [ -f "$$runner" ]; then \
		pid=$$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$$runner"); \
		echo "[RISCV-DV] Waiting for runner PID $$pid to merge active coverage..."; \
		while kill -0 "$$pid" 2>/dev/null; do sleep 2; done; \
	else echo "[RISCV-DV] No active runner found."; fi
	@rm -f "$(RISCV_DV_WORK_ROOT)/STOP"
	@if [ "$(RISCV_DV_STOP_REPORT)" = "1" ]; then $(MAKE) --no-print-directory riscv_dv_coverage_report; fi

riscv_dv_coverage_report:
	@mkdir -p "$(PPA_DIR)"; \
	data=$$("$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" coverage-path $(RISCV_DV_COMMON_ARGS)); \
	if [ -z "$$data" ]; then echo "[RISCV-DV] No merged coverage database found"; exit 2; fi; \
	cov_dir="$${data%/*}"; info="$$cov_dir/coverage.info"; annotated="$$cov_dir/annotated"; \
	summary="$(PPA_DIR)/riscv_dv_coverage_summary.log"; uncovered="$(PPA_DIR)/riscv_dv_uncovered.log"; \
	verilator_coverage --write-info "$$info" "$$data"; \
	rm -rf "$$annotated"; verilator_coverage --annotate "$$annotated" "$$data" >/dev/null; \
	databases=$$(find "$$cov_dir" -maxdepth 1 -name 'merged.dat' -type f | wc -l); \
	$(PYTHON) "$(PROJECT_ROOT)/verif/coverage/coverage_summary.py" \
		--data "$$data" --info "$$info" --annotated "$$annotated" \
		--databases "$$databases" --summary "$$summary" --uncovered "$$uncovered"; \
	echo "[RISCV-DV] Coverage data: $$data"; echo "[RISCV-DV] Coverage info: $$info"

riscv_dv_cleanup: riscv_dv_venv
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" cleanup $(RISCV_DV_COMMON_ARGS)

riscv_dv_distclean: riscv_dv_venv
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" cleanup $(RISCV_DV_COMMON_ARGS) --all
	@rm -rf "$(RISCV_DV_MODEL_DIR)" "$(RISCV_DV_VENV)"

regression_suite_coverage_merge:
	@set -e; data_dir="$(REGRESSION_SUITE_COVERAGE_DIR)/data"; output="$(REGRESSION_SUITE_COVERAGE_DIR)/merged.dat"; \
	set -- $$(find "$$data_dir" -type f -name '*.dat' | sort); \
	if [ "$$#" -eq 0 ]; then echo "[REGRESSION] No coverage data in $$data_dir"; exit 2; fi; \
	mkdir -p "$(REGRESSION_SUITE_COVERAGE_DIR)"; \
	verilator_coverage --write "$$output.next" "$$@"; mv "$$output.next" "$$output"; \
	verilator_coverage --write-info "$(REGRESSION_SUITE_COVERAGE_DIR)/coverage.info" "$$output"; \
	rm -rf "$$data_dir"; \
	echo "[REGRESSION] Suite coverage merged: $$output ($$# inputs removed)"

regression_sort:
	@set -e; state="$(REGRESSION_CACHE_DIR)/sort.json"; merged="$(REGRESSION_SORT_COVERAGE_DIR)/merged.dat"; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope sort \
		--state "$$state" --artifact "$$merged" --artifact "$(PPA_SORT_LOG)" --artifact "$(SORT_RESULT_DIR)"; then \
		echo "[REGRESSION] SKIP sort_all: completed inputs unchanged"; exit 0; \
	fi; \
	start_fp=$$($(PYTHON) "$(REGRESSION_CACHE_TOOL)" fingerprint --project-root "$(PROJECT_ROOT)" --scope sort); \
	rm -f "$$state"; rm -rf "$(REGRESSION_SORT_COVERAGE_DIR)"; \
	$(MAKE) --no-print-directory sort_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 \
		COVERAGE_DATA_DIR="$(REGRESSION_SORT_COVERAGE_DIR)/data"; \
	$(MAKE) --no-print-directory regression_suite_coverage_merge \
		REGRESSION_SUITE_COVERAGE_DIR="$(REGRESSION_SORT_COVERAGE_DIR)"; \
	$(PYTHON) "$(REGRESSION_CACHE_TOOL)" record --project-root "$(PROJECT_ROOT)" --scope sort \
		--state "$$state" --expected-fingerprint "$$start_fp" \
		--artifact "$$merged" --artifact "$(PPA_SORT_LOG)" --artifact "$(SORT_RESULT_DIR)"

regression_sort_opt:
	@set -e; state="$(REGRESSION_CACHE_DIR)/sort_opt.json"; merged="$(REGRESSION_SORT_OPT_COVERAGE_DIR)/merged.dat"; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope sort_opt \
		--state "$$state" --artifact "$$merged" --artifact "$(PPA_SORT_OPT_LOG)" --artifact "$(SORT_OPT_RESULT_DIR)"; then \
		echo "[REGRESSION] SKIP sort_opt_all: completed inputs unchanged"; exit 0; \
	fi; \
	start_fp=$$($(PYTHON) "$(REGRESSION_CACHE_TOOL)" fingerprint --project-root "$(PROJECT_ROOT)" --scope sort_opt); \
	rm -f "$$state"; rm -rf "$(REGRESSION_SORT_OPT_COVERAGE_DIR)"; \
	$(MAKE) --no-print-directory sort_opt_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 \
		COVERAGE_DATA_DIR="$(REGRESSION_SORT_OPT_COVERAGE_DIR)/data"; \
	$(MAKE) --no-print-directory regression_suite_coverage_merge \
		REGRESSION_SUITE_COVERAGE_DIR="$(REGRESSION_SORT_OPT_COVERAGE_DIR)"; \
	$(PYTHON) "$(REGRESSION_CACHE_TOOL)" record --project-root "$(PROJECT_ROOT)" --scope sort_opt \
		--state "$$state" --expected-fingerprint "$$start_fp" \
		--artifact "$$merged" --artifact "$(PPA_SORT_OPT_LOG)" --artifact "$(SORT_OPT_RESULT_DIR)"

regression_coverage_report:
	@set -e; sources=(); \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope coverage_all \
		--state "$(REGRESSION_CACHE_DIR)/coverage_all.json" --artifact "$(COVERAGE_ALL_CACHE_DIR)/merged.dat" >/dev/null; then \
		sources+=("$(COVERAGE_ALL_CACHE_DIR)/merged.dat"); fi; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope sort \
		--state "$(REGRESSION_CACHE_DIR)/sort.json" --artifact "$(REGRESSION_SORT_COVERAGE_DIR)/merged.dat" >/dev/null; then \
		sources+=("$(REGRESSION_SORT_COVERAGE_DIR)/merged.dat"); fi; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope sort_opt \
		--state "$(REGRESSION_CACHE_DIR)/sort_opt.json" --artifact "$(REGRESSION_SORT_OPT_COVERAGE_DIR)/merged.dat" >/dev/null; then \
		sources+=("$(REGRESSION_SORT_OPT_COVERAGE_DIR)/merged.dat"); fi; \
	riscv_data=$$("$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" coverage-path $(RISCV_DV_COMMON_ARGS) 2>/dev/null || true); \
	if [ -n "$$riscv_data" ] && [ -f "$$riscv_data" ]; then sources+=("$$riscv_data"); fi; \
	if [ "$${#sources[@]}" -eq 0 ]; then echo "[REGRESSION] No current-RTL coverage suites are complete"; exit 2; fi; \
	rm -rf "$(REGRESSION_TOTAL_COVERAGE_DIR)"; mkdir -p "$(REGRESSION_TOTAL_COVERAGE_DIR)" "$(PPA_DIR)"; \
	echo "[REGRESSION] Merging $${#sources[@]} suite databases"; printf '  %s\n' "$${sources[@]}"; \
	verilator_coverage --write "$(REGRESSION_TOTAL_COVERAGE_DATA)" "$${sources[@]}"; \
	verilator_coverage --write-info "$(REGRESSION_TOTAL_COVERAGE_INFO)" "$(REGRESSION_TOTAL_COVERAGE_DATA)"; \
	verilator_coverage --annotate "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED)" "$(REGRESSION_TOTAL_COVERAGE_DATA)" >/dev/null; \
	$(PYTHON) "$(PROJECT_ROOT)/verif/coverage/coverage_summary.py" \
		--data "$(REGRESSION_TOTAL_COVERAGE_DATA)" --info "$(REGRESSION_TOTAL_COVERAGE_INFO)" \
		--annotated "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED)" --databases "$${#sources[@]}" \
		--summary "$(REGRESSION_TOTAL_COVERAGE_SUMMARY)" --uncovered "$(REGRESSION_TOTAL_COVERAGE_UNCOVERED)"; \
	echo "[REGRESSION] Total coverage: $(REGRESSION_TOTAL_COVERAGE_DATA)"

regression:
	@set +e; failed=0; stopped=0; run_id="$(REGRESSION_RUN_ID)"; \
	if [ -z "$$run_id" ]; then run_id="$$(date '+%Y%m%d_%H%M%S')_$$$$"; fi; \
	run_dir="$(REGRESSION_LOG_DIR)/$$run_id"; mkdir -p "$$run_dir" "$(PPA_DIR)" "$(REGRESSION_CONTROL_DIR)"; \
	summary="$$run_dir/summary.log"; rm -f "$(REGRESSION_STOP_FILE)"; \
	printf '{"pid":%s,"run_id":"%s"}\n' "$$$$" "$$run_id" > "$(REGRESSION_RUNNER_FILE)"; \
	trap 'rm -f "$(REGRESSION_RUNNER_FILE)" "$(REGRESSION_STOP_FILE)"' EXIT; \
	echo "[REGRESSION] Run: $$run_id" | tee "$$summary"; \
	echo "[REGRESSION] Targets: $(REGRESSION_TARGETS)" | tee -a "$$summary"; \
	for target in $(REGRESSION_TARGETS); do \
		if [ -f "$(REGRESSION_STOP_FILE)" ]; then echo "[REGRESSION] STOP before $$target" | tee -a "$$summary"; stopped=1; break; fi; \
		safe_target=$$(printf '%s' "$$target" | tr '/:' '__'); run_log="$$run_dir/$$safe_target.log"; \
		marker="$$run_dir/.$$safe_target.start"; : > "$$marker"; \
		echo "[REGRESSION] RUN  $$target" | tee -a "$$summary"; \
		if $(MAKE) --no-print-directory "$$target" VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 >"$$run_log" 2>&1; then \
			echo "[REGRESSION] PASS $$target log=$$run_log" | tee -a "$$summary"; \
		else \
			diagnostic="$$run_dir/$$safe_target.failure.log"; \
			{ echo "TARGET=$$target"; echo "RUN_LOG=$$run_log"; \
			  grep -n -C "$(REGRESSION_CONTEXT_LINES)" -Ei 'SORT FAIL|TEST_FAIL|(^|[^[:alpha:]])(FAIL|ERROR|FATAL|timeout)' "$$run_log" | tail -800; \
			  echo "--- command tail ---"; tail -120 "$$run_log"; } > "$$diagnostic" 2>&1; \
			echo "[REGRESSION] FAIL $$target log=$$run_log diagnostic=$$diagnostic" | tee -a "$$summary"; failed=1; \
		fi; \
		rm -f "$$marker"; \
		if [ -f "$(REGRESSION_STOP_FILE)" ]; then stopped=1; break; fi; \
	done; \
	if [ "$$stopped" -eq 1 ] && [ -f "$(REGRESSION_STOP_FILE)" ]; then \
		echo "[REGRESSION] Total coverage merge delegated to regression_stop" | tee -a "$$summary"; \
	elif $(MAKE) --no-print-directory regression_coverage_report; then \
		echo "[REGRESSION] PASS regression_coverage_report" | tee -a "$$summary"; \
	else echo "[REGRESSION] FAIL regression_coverage_report" | tee -a "$$summary"; failed=1; fi; \
	overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[REGRESSION] CORRECTNESS=$$overall STOPPED=$$stopped" | tee -a "$$summary"; \
	cp "$$summary" "$(REGRESSION_SUMMARY)"; echo "[REGRESSION] Summary: $$summary"; \
	exit "$$failed"

regression_all: regression

regression_status:
	@set -e; mkdir -p "$(PPA_DIR)"; report="$(REGRESSION_STATUS_REPORT)"; tmp="$$report.tmp.$$$$"; \
	trap 'rm -f "$$tmp"' EXIT; \
	latest_regression=$$(find "$(REGRESSION_LOG_DIR)" -mindepth 2 -maxdepth 2 -name summary.log -type f \
		-printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); \
	latest_riscv_dv=$$(find "$(RISCV_DV_WORK_ROOT)/runs" -mindepth 2 -maxdepth 2 -name summary.log -type f \
		-printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); \
	report_runner() { \
		label="$$1"; file="$$2"; \
		if [ ! -f "$$file" ]; then echo "[RUNNER] $$label=IDLE"; return; fi; \
		pid=$$($(PYTHON) -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$$file" 2>/dev/null || true); \
		state=STALE; if [ -n "$$pid" ] && kill -0 "$$pid" 2>/dev/null; then state=ACTIVE; fi; \
		printf '[RUNNER] %s=%s ' "$$label" "$$state"; tr -d '\n' < "$$file"; printf '\n'; \
	}; \
	{ \
		echo "[REGRESSION STATUS] Generated: $$(date '+%Y-%m-%d %H:%M:%S %z')"; \
		echo "[REGRESSION STATUS] Project: $(PROJECT_ROOT)"; \
		echo; echo "===== LATEST REGRESSION ====="; \
		if [ -n "$$latest_regression" ]; then echo "REPORT=$$latest_regression"; cat "$$latest_regression"; \
		else echo "REPORT=NONE"; fi; \
		echo; echo "===== LATEST RISCV-DV ====="; \
		if [ -n "$$latest_riscv_dv" ]; then echo "REPORT=$$latest_riscv_dv"; cat "$$latest_riscv_dv"; \
		else echo "REPORT=NONE"; fi; \
		echo; echo "===== TOTAL COVERAGE ====="; \
		if [ -s "$(REGRESSION_TOTAL_COVERAGE_SUMMARY)" ]; then cat "$(REGRESSION_TOTAL_COVERAGE_SUMMARY)"; \
		else echo "REPORT=NONE"; fi; \
		echo; echo "===== RUNNERS ====="; \
		report_runner regression "$(REGRESSION_RUNNER_FILE)"; \
		report_runner riscv-dv "$(RISCV_DV_WORK_ROOT)/runner.json"; \
	} > "$$tmp"; \
	mv "$$tmp" "$$report"; trap - EXIT; cat "$$report"; echo; echo "[REGRESSION STATUS] Report: $$report"

regression_stop:
	@set +e; mkdir -p "$(REGRESSION_CONTROL_DIR)"; touch "$(REGRESSION_STOP_FILE)"; \
	pid=""; if [ -f "$(REGRESSION_RUNNER_FILE)" ]; then \
		pid=$$($(PYTHON) -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$(REGRESSION_RUNNER_FILE)" 2>/dev/null); fi; \
	echo "[REGRESSION] Global graceful stop requested"; \
	$(MAKE) --no-print-directory riscv_dv_stop RISCV_DV_JOBS=20 RISCV_DV_STOP_REPORT=0 || true; \
	if [ -n "$$pid" ]; then echo "[REGRESSION] Waiting for regression PID $$pid to finalize..."; \
		while kill -0 "$$pid" 2>/dev/null; do sleep 2; done; fi; \
	$(MAKE) --no-print-directory regression_coverage_report; rc=$$?; \
	$(MAKE) --no-print-directory riscv_dv_cleanup; cleanup_rc=$$?; \
	if [ "$$rc" -eq 0 ] && [ "$$cleanup_rc" -ne 0 ]; then rc=$$cleanup_rc; fi; \
	rm -f "$(REGRESSION_STOP_FILE)"; exit "$$rc"

regression_clean: coverage_clean
	@rm -rf "$(REGRESSION_LOG_DIR)" "$(REGRESSION_CACHE_DIR)" "$(REGRESSION_CONTROL_DIR)" "$(REGRESSION_TOTAL_COVERAGE_DIR)"
	@rm -f "$(REGRESSION_SUMMARY)" "$(REGRESSION_STATUS_REPORT)" "$(REGRESSION_TOTAL_COVERAGE_SUMMARY)" "$(REGRESSION_TOTAL_COVERAGE_UNCOVERED)"
	@$(MAKE) --no-print-directory regression

coverage_clean:
	rm -rf "$(COVERAGE_DIR)"

coverage_all:
	@set -e; state="$(REGRESSION_CACHE_DIR)/coverage_all.json"; merged="$(COVERAGE_ALL_CACHE_DIR)/merged.dat"; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope coverage_all \
		--state "$$state" --artifact "$$merged" --artifact "$(COVERAGE_ALL_CACHE_DIR)/summary.log"; then \
		echo "[REGRESSION] SKIP coverage_all: completed inputs unchanged"; exit 0; \
	fi; \
	start_fp=$$($(PYTHON) "$(REGRESSION_CACHE_TOOL)" fingerprint --project-root "$(PROJECT_ROOT)" --scope coverage_all); \
	rm -f "$$state"; rm -rf "$(COVERAGE_ALL_CACHE_DIR)"; \
	$(MAKE) --no-print-directory coverage_all_run COVERAGE_DIR="$(COVERAGE_ALL_CACHE_DIR)"; \
	rm -rf "$(COVERAGE_ALL_CACHE_DIR)/data"; \
	$(PYTHON) "$(REGRESSION_CACHE_TOOL)" record --project-root "$(PROJECT_ROOT)" --scope coverage_all \
		--state "$$state" --expected-fingerprint "$$start_fp" \
		--artifact "$$merged" --artifact "$(COVERAGE_ALL_CACHE_DIR)/summary.log"

coverage_all_run: coverage_clean
	@mkdir -p "$(COVERAGE_DATA_DIR)"
	@$(MAKE) comp VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) boundary_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) boundary_opt_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coremark_opt_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) test_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coremark_sim VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coe_loop5 VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coe_loop_lina VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coverage_report
	@$(MAKE) ppa_perf_report

coverage_quick: coverage_clean
	@mkdir -p "$(COVERAGE_DATA_DIR)" "$(PPA_DIR)"
	@$(MAKE) comp VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@set +e; failed=0; rm -f "$(COVERAGE_QUICK_SUMMARY)"; \
	echo "[COVERAGE QUICK] Targets: $(COVERAGE_QUICK_TARGETS)" | tee "$(COVERAGE_QUICK_SUMMARY)"; \
	for target in $(COVERAGE_QUICK_TARGETS); do \
		measured=0; minimum=$(COVERAGE_QUICK_TIMEOUT); \
		if [ -s "$(PPA_DIR)/perf_stats.csv" ]; then \
			case "$$target" in \
				boundary_all) pattern='^boundary(-opt)?/'; minimum=$(COVERAGE_QUICK_BOUNDARY_MIN) ;; \
				test_all) pattern='^rv32'; minimum=$(COVERAGE_QUICK_ISA_MIN) ;; \
				coremark_sim) pattern='^coremark$$'; minimum=$(COVERAGE_QUICK_COREMARK_MIN) ;; \
				coe_loop5) pattern='^coe_loop5$$'; minimum=$(COVERAGE_QUICK_COE_MIN) ;; \
				*) pattern='a^' ;; \
			esac; \
			measured=$$(awk -F, -v p="$$pattern" 'NR>1 && $$1 ~ p && $$2 ~ /^[0-9]+$$/ && $$2>m {m=$$2} END{print m+0}' "$(PPA_DIR)/perf_stats.csv"); \
		else \
			case "$$target" in \
				boundary_all) minimum=$(COVERAGE_QUICK_BOUNDARY_MIN) ;; \
				test_all) minimum=$(COVERAGE_QUICK_ISA_MIN) ;; \
				coremark_sim) minimum=$(COVERAGE_QUICK_COREMARK_MIN) ;; \
				coe_loop5) minimum=$(COVERAGE_QUICK_COE_MIN) ;; \
			esac; \
		fi; \
		budget=$$(( (measured * $(COVERAGE_QUICK_TICKS_PER_CYCLE) * (100 + $(COVERAGE_QUICK_MARGIN_PERCENT)) + 99) / 100 + $(COVERAGE_QUICK_TIMEOUT_PAD) )); \
		if [ "$$budget" -lt "$$minimum" ]; then budget=$$minimum; fi; \
		echo "[COVERAGE QUICK] RUN  $$target timeout=$$budget measured_cycles=$$measured" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; \
		if $(MAKE) --no-print-directory "$$target" VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 \
			SIM_COMPARE_TIMEOUT="$$budget" \
			BOUNDARY_SIM_TIMEOUT="$$budget" \
			COREMARK_SIM_TIMEOUT="$$budget" \
			COE_SIM_TIMEOUT="$$budget"; then \
			echo "[COVERAGE QUICK] PASS $$target" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; \
		else \
			echo "[COVERAGE QUICK] FAIL $$target" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; failed=1; \
		fi; \
	done; \
	if $(MAKE) --no-print-directory coverage_report; then \
		echo "[COVERAGE QUICK] PASS coverage_report" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; \
		grep '^\[COVERAGE\] LCOV source-line coverage:' "$(COVERAGE_SUMMARY)" | tail -1 | tee -a "$(COVERAGE_QUICK_SUMMARY)"; \
	else \
		echo "[COVERAGE QUICK] FAIL coverage_report" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; failed=1; \
	fi; \
	dat_count=$$(find "$(COVERAGE_DATA_DIR)" -type f -name '*.dat' | wc -l); \
	overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[COVERAGE QUICK] CORRECTNESS=$$overall coverage_databases=$$dat_count" | tee -a "$(COVERAGE_QUICK_SUMMARY)"; \
	echo "[COVERAGE QUICK] Summary: $(COVERAGE_QUICK_SUMMARY)"; \
	exit "$$failed"

coverage_closure:
	@set -e; \
	rm -rf "$(COVERAGE_CLOSURE_DIR)"; \
	$(MAKE) --no-print-directory -C sw \
		"$(BUILD_DIR)/app/boundary/coverage_closure_edges.itcm" \
		"$(BUILD_DIR)/app/boundary/coverage_closure_edges.dtcm" \
		"$(BUILD_DIR)/app/boundary/coverage_closure_edges.elf"; \
	$(MAKE) --no-print-directory comp VERILATOR_COVERAGE=1 VERILATOR_TRACE=0; \
	$(MAKE) --no-print-directory boundary_sim_coverage_closure_edges \
		VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 \
		COVERAGE_DIR="$(COVERAGE_CLOSURE_DIR)"; \
	grep -q '\[coverage_closure_edges\] \[PASS\]' \
		"$(BOUNDARY_RESULT_DIR)/coverage_closure_edges.status"; \
	test -s "$(COVERAGE_CLOSURE_DATA)"; \
	verilator_coverage --write "$(COVERAGE_CLOSURE_MERGED).next" \
		"$(COVERAGE_CLOSURE_DATA)"; \
	mv "$(COVERAGE_CLOSURE_MERGED).next" "$(COVERAGE_CLOSURE_MERGED)"; \
	verilator_coverage --write-info "$(COVERAGE_CLOSURE_INFO)" \
		"$(COVERAGE_CLOSURE_MERGED)"; \
	rm -rf "$(COVERAGE_CLOSURE_ANNOTATED)"; \
	verilator_coverage --annotate "$(COVERAGE_CLOSURE_ANNOTATED)" \
		"$(COVERAGE_CLOSURE_MERGED)" >/dev/null; \
	echo "[COVERAGE CLOSURE] PASS data=$(COVERAGE_CLOSURE_MERGED)"

coverage_closure_merge: coverage_closure
	@set -e; \
	if [ -z "$(strip $(COVERAGE_CLOSURE_BASES))" ]; then \
		echo "[COVERAGE CLOSURE] Set COVERAGE_CLOSURE_BASES to suite-level databases"; \
		exit 2; \
	fi; \
	set -- $(COVERAGE_CLOSURE_BASES) "$(COVERAGE_CLOSURE_MERGED)"; \
	for input in "$$@"; do \
		if [ ! -s "$$input" ]; then echo "[COVERAGE CLOSURE] Missing $$input"; exit 2; fi; \
	done; \
	databases=$$#; \
	mkdir -p "$(REGRESSION_TOTAL_COVERAGE_DIR)" "$(PPA_DIR)"; \
	verilator_coverage --write "$(REGRESSION_TOTAL_COVERAGE_DATA).next" "$$@"; \
	verilator_coverage --write-info "$(REGRESSION_TOTAL_COVERAGE_INFO).next" \
		"$(REGRESSION_TOTAL_COVERAGE_DATA).next"; \
	rm -rf "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED).next"; \
	verilator_coverage --annotate "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED).next" \
		"$(REGRESSION_TOTAL_COVERAGE_DATA).next" >/dev/null; \
	mv "$(REGRESSION_TOTAL_COVERAGE_DATA).next" \
		"$(REGRESSION_TOTAL_COVERAGE_DATA)"; \
	mv "$(REGRESSION_TOTAL_COVERAGE_INFO).next" \
		"$(REGRESSION_TOTAL_COVERAGE_INFO)"; \
	rm -rf "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED)"; \
	mv "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED).next" \
		"$(REGRESSION_TOTAL_COVERAGE_ANNOTATED)"; \
	$(PYTHON) "$(PROJECT_ROOT)/verif/coverage/coverage_summary.py" \
		--data "$(REGRESSION_TOTAL_COVERAGE_DATA)" \
		--info "$(REGRESSION_TOTAL_COVERAGE_INFO)" \
		--annotated "$(REGRESSION_TOTAL_COVERAGE_ANNOTATED)" \
		--databases "$$databases" \
		--summary "$(REGRESSION_TOTAL_COVERAGE_SUMMARY)" \
		--uncovered "$(REGRESSION_TOTAL_COVERAGE_UNCOVERED)"; \
	echo "[COVERAGE CLOSURE] merged into $(REGRESSION_TOTAL_COVERAGE_DATA)"

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

sw_coverage_clean:
	rm -rf "$(SW_COVERAGE_DIR)" "$(SW_BOUNDARY_DIR)/coverage-models" "$(SW_BOUNDARY_DIR)/coverage-results"

sw_run_mode:
	@set -eu; \
	mode="$(SW_MODE)"; \
	obj_dir="$(SW_OBJ_DIR)"; \
	result_root="$(SW_RESULT_ROOT)"; \
	if [ -z "$$mode" ] || [ -z "$$obj_dir" ] || [ -z "$$result_root" ]; then \
		echo "[SW] SW_MODE, SW_OBJ_DIR and SW_RESULT_ROOT are required"; exit 2; \
	fi; \
	mkdir -p "$$result_root/$$mode"; \
	if [ "$(SW_COVERAGE)" = "1" ]; then mkdir -p "$(SW_COVERAGE_DATA_DIR)/$$mode"; fi; \
	tests="$(SW_TEST_LIST)"; \
	if [ "$(SW_INCLUDE_OFFICIAL)" = "1" ]; then tests="rv32ui_sw $$tests"; fi; \
	for test in $$tests; do \
		if [ "$$test" = "rv32ui_sw" ]; then \
			base="$(RVTESTS_OUT_ROOT)/rv32ui"; \
		else \
			base="$(SW_TEST_OUT_ROOT)"; \
		fi; \
		elf="$$base/elf/$$test.elf"; itcm="$$base/mem/$$test.itcm"; dtcm="$$base/mem/$$test.dtcm"; \
		for input in "$$elf" "$$itcm" "$$dtcm"; do \
			if [ ! -s "$$input" ]; then echo "[SW][$$mode][$$test] missing or empty: $$input"; exit 1; fi; \
		done; \
		log_dir="$$result_root/$$mode/$$test"; mkdir -p "$$log_dir"; \
		cov_file="$(SW_COVERAGE_DATA_DIR)/$$mode/$$test.dat"; \
		if [ "$(SW_COVERAGE)" = "1" ]; then rm -f "$$cov_file"; fi; \
		echo "[SW][$$mode] Running $$test"; \
		$(MAKE) --no-print-directory sim_compare \
			SIM_COMPARE=none LSU_IMPL="$$mode" OBJ_DIR="$$obj_dir" \
			VERILATOR_COVERAGE="$(SW_COVERAGE)" VERILATOR_TRACE=0 \
			COMPARE_NAME="sw/$$mode/$$test" COMPARE_ELF="$$elf" \
			COMPARE_ITCM="$$itcm" COMPARE_DTCM="$$dtcm" \
			COMPARE_HW_OUT_DIR="$$log_dir" COMPARE_HW_LOG="$$log_dir/hw.log" \
			COMPARE_COVERAGE_FILE="$$cov_file"; \
		if ! grep -q "TEST_PASS" "$$log_dir/hw.log"; then \
			echo "[SW][$$mode][$$test] FAIL: TEST_PASS not found"; tail -80 "$$log_dir/hw.log"; exit 1; \
		fi; \
		if grep -Eq '\$readmem file not found|timeout reached' "$$log_dir/hw.log"; then \
			echo "[SW][$$mode][$$test] FAIL: invalid memory load or timeout"; exit 1; \
		fi; \
		if [ "$(SW_COVERAGE)" = "1" ] && [ ! -s "$$cov_file" ]; then \
			echo "[SW][$$mode][$$test] FAIL: coverage database missing"; exit 1; \
		fi; \
		echo "[SW][$$mode][$$test] PASS"; \
	done

sw_boundary_test: rv_comp_rv32ui_sw
	@$(MAKE) sw_test_comp_all REBUILD=1
	@rm -rf "$(SW_BOUNDARY_DIR)/functional-models" "$(SW_BOUNDARY_DIR)/functional-results"
	@$(MAKE) comp LSU_IMPL=legacy VERILATOR_COVERAGE=0 VERILATOR_TRACE=0 OBJ_DIR="$(SW_BOUNDARY_DIR)/functional-models/legacy"
	@$(MAKE) sw_run_mode SW_MODE=legacy SW_OBJ_DIR="$(SW_BOUNDARY_DIR)/functional-models/legacy" \
		SW_RESULT_ROOT="$(SW_BOUNDARY_DIR)/functional-results" SW_COVERAGE=0 SW_INCLUDE_OFFICIAL=1 \
		SW_TEST_LIST="$(SW_ALIGNED_TESTS)"
	@$(MAKE) comp LSU_IMPL=new VERILATOR_COVERAGE=0 VERILATOR_TRACE=0 OBJ_DIR="$(SW_BOUNDARY_DIR)/functional-models/new"
	@$(MAKE) sw_run_mode SW_MODE=new SW_OBJ_DIR="$(SW_BOUNDARY_DIR)/functional-models/new" \
		SW_RESULT_ROOT="$(SW_BOUNDARY_DIR)/functional-results" SW_COVERAGE=0 SW_INCLUDE_OFFICIAL=1 \
		SW_TEST_LIST="$(SW_ALL_TESTS)"

sw_coverage:
	@$(MAKE) sw_coverage_clean
	@$(MAKE) rv_comp_rv32ui_sw
	@$(MAKE) sw_test_comp_all REBUILD=1
	@mkdir -p "$(SW_COVERAGE_DATA_DIR)"
	@$(MAKE) comp LSU_IMPL=legacy VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 OBJ_DIR="$(SW_BOUNDARY_DIR)/coverage-models/legacy"
	@$(MAKE) sw_run_mode SW_MODE=legacy SW_OBJ_DIR="$(SW_BOUNDARY_DIR)/coverage-models/legacy" \
		SW_RESULT_ROOT="$(SW_BOUNDARY_DIR)/coverage-results" SW_COVERAGE=1 SW_INCLUDE_OFFICIAL=1 \
		SW_TEST_LIST="$(SW_ALIGNED_TESTS)"
	@$(MAKE) comp LSU_IMPL=new VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 OBJ_DIR="$(SW_BOUNDARY_DIR)/coverage-models/new"
	@$(MAKE) sw_run_mode SW_MODE=new SW_OBJ_DIR="$(SW_BOUNDARY_DIR)/coverage-models/new" \
		SW_RESULT_ROOT="$(SW_BOUNDARY_DIR)/coverage-results" SW_COVERAGE=1 SW_INCLUDE_OFFICIAL=1 \
		SW_TEST_LIST="$(SW_ALL_TESTS)"
	@$(MAKE) sw_coverage_report

sw_coverage_report:
	@mkdir -p "$(SW_COVERAGE_DIR)"; \
	for mode_spec in legacy:$(SW_LEGACY_DB_COUNT) new:$(SW_NEW_DB_COUNT); do \
		mode=$${mode_spec%%:*}; expected=$${mode_spec##*:}; mode_dir="$(SW_COVERAGE_DIR)/$$mode"; \
		mkdir -p "$$mode_dir"; \
		set -- $$(find "$(SW_COVERAGE_DATA_DIR)/$$mode" -type f -name '*.dat' | sort); \
		if [ "$$#" -ne "$$expected" ]; then echo "[COVERAGE] $$mode expected $$expected databases, found $$#"; exit 1; fi; \
		verilator_coverage --write "$$mode_dir/merged.dat" "$$@" > "$$mode_dir/merge.log"; \
		verilator_coverage --write-info "$$mode_dir/coverage.info" "$$mode_dir/merged.dat"; \
		rm -rf "$$mode_dir/annotated"; \
		verilator_coverage --annotate "$$mode_dir/annotated" "$$mode_dir/merged.dat" > "$$mode_dir/annotate.log"; \
		$(PYTHON) "$(PROJECT_ROOT)/verif/coverage/coverage_summary.py" \
			--data "$$mode_dir/merged.dat" --info "$$mode_dir/coverage.info" \
			--annotated "$$mode_dir/annotated" --databases "$$expected" \
			--summary "$$mode_dir/summary.log" --uncovered "$$mode_dir/uncovered_sw_path.log" > "$$mode_dir/report.log"; \
	done; \
	set -- $$(find "$(SW_COVERAGE_DATA_DIR)" -type f -name '*.dat' | sort); \
	if [ "$$#" -ne $(SW_TOTAL_DB_COUNT) ]; then echo "[COVERAGE] Expected $(SW_TOTAL_DB_COUNT) SW databases, found $$#"; exit 1; fi; \
	verilator_coverage --write "$(SW_COVERAGE_MERGED)" "$$@" > "$(SW_COVERAGE_DIR)/merge.log"; \
	verilator_coverage --write-info "$(SW_COVERAGE_INFO)" "$(SW_COVERAGE_MERGED)"; \
	rm -rf "$(SW_COVERAGE_ANNOTATE_DIR)"; \
	verilator_coverage --annotate "$(SW_COVERAGE_ANNOTATE_DIR)" "$(SW_COVERAGE_MERGED)" > "$(SW_COVERAGE_DIR)/annotate.log"; \
	$(PYTHON) "$(PROJECT_ROOT)/verif/coverage/coverage_summary.py" \
		--data "$(SW_COVERAGE_MERGED)" --info "$(SW_COVERAGE_INFO)" \
		--annotated "$(SW_COVERAGE_ANNOTATE_DIR)" --databases $(SW_TOTAL_DB_COUNT) \
		--summary "$(SW_COVERAGE_SUMMARY)" --uncovered "$(SW_COVERAGE_UNCOVERED)"

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
	ltx_src="$(SYN_ARTIFACT_DIR)/jyd_fpga.ltx"; \
	if [ -f "$$ltx_src" ]; then \
		ltx_dst="$${dst%.bit}.ltx"; cp "$$ltx_src" "$$ltx_dst"; \
		echo "[SYN] ILA probes: $$ltx_dst"; \
	fi; \
	echo "[SYN] Best bitstream: $$dst"
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE=$(SYN_PROFILE)

syn225: SYN_PLL_FREQ_MHZ := 225
syn240: SYN_PLL_FREQ_MHZ := 240
syn250: SYN_PLL_FREQ_MHZ := 250
syn225 syn240 syn250: SYN_RUN_TO := bitstream
syn225 syn240 syn250: SYN_JOBS := 40
syn225 syn240 syn250: SYN_IMPL_RUNS := 5
syn225 syn240 syn250: SYN_THREADS_PER_RUN := 8
syn225 syn240 syn250: syn-vivado
	@src="$(SYN_ARTIFACT_DIR)/jyd_fpga.bit"; \
	if [ ! -f "$$src" ]; then \
		echo "Error: best bitstream not found: $$src"; \
		exit 1; \
	fi; \
	mkdir -p "$(SYN_BIT_DIR)"; \
	timestamp=$$(date '+%Y%m%d_%H%M'); \
	dst="$(SYN_BIT_DIR)/jyd_fpga$${timestamp}.bit"; \
	cp "$$src" "$$dst"; \
	ltx_src="$(SYN_ARTIFACT_DIR)/jyd_fpga.ltx"; \
	if [ -f "$$ltx_src" ]; then \
		ltx_dst="$${dst%.bit}.ltx"; cp "$$ltx_src" "$$ltx_dst"; \
		echo "[SYN] ILA probes: $$ltx_dst"; \
	fi; \
	echo "[SYN] Best bitstream: $$dst"
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE=$(SYN_PROFILE)

synf-board: SYN_PROFILE := board-ag10-ah10
synf-board: SYN_ENABLE_ILA := 1
synf-board: SYN_BOARD_XDC = $(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.srcs/constrs_1/new/board_ag10_ah10.xdc
synf-board: synf

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
		$(if $(filter 1,$(FPU)),--target fpu) \
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

syn-stage-memory:
	@test -f "$(IROM_COE)" || { echo "Error: IROM COE not found: $(IROM_COE)"; exit 1; }
	@test -f "$(DRAM_COE)" || { echo "Error: DRAM COE not found: $(DRAM_COE)"; exit 1; }
	@mkdir -p "$(SYN_MEMORY_DIR)"
	cp "$(IROM_COE)" "$(SYN_STAGED_IROM_COE)"
	cp "$(DRAM_COE)" "$(SYN_STAGED_DRAM_COE)"
	@printf 'IROM_COE=%s\nDRAM_COE=%s\n' "$(abspath $(IROM_COE))" "$(abspath $(DRAM_COE))" > "$(SYN_MEMORY_DIR)/sources.txt"

syn-vivado: syn-prep syn-stage-xpr syn-stage-memory
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
		-board_xdc "$(SYN_BOARD_XDC)" \
		-enable_ila $(SYN_ENABLE_ILA) \
		-irom_coe "$(SYN_STAGED_IROM_COE)" \
		-dram_coe "$(SYN_STAGED_DRAM_COE)" \
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
BOUNDARY_APP_SW_MAKE_ARGS += BOUNDARY_EXTRA_CFLAGS="$(BOUNDARY_EXTRA_CFLAGS)"
COREMARK_RESULT_LOG ?= $(HW_TRACE_OUT_DIR)/coremark/hw.log
COREMARK_SIM_COMPARE ?= none
COMPARE_TRACE_DEFINES = $(if $(filter none,$(SIM_COMPARE)),,$(if $(findstring +commit_trace,$(COMPARE_SIM_EXTRA_DEFINES)),,+commit_trace))
COMPARE_SIM_DEFINES = $(strip $(COMPARE_SIM_EXTRA_DEFINES) $(COMPARE_TRACE_DEFINES))

coremark:
	@$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS)

coremark-rebuild:
	@$(MAKE) -C sw coremark-rebuild $(COREMARK_SW_MAKE_ARGS)

rtthread:
	@$(MAKE) -C sw rtthread

rtthread-clean:
	@$(MAKE) -C sw rtthread-clean

rtthread-coremark:
	@$(MAKE) -C sw rtthread-coremark-build

rtthread-coremark-clean:
	@$(MAKE) -C sw rtthread-coremark-clean

coremark_sim: coremark comp
	@set +e; \
	rm -f $(COREMARK_RESULT_LOG); \
	$(MAKE) sim_compare \
		COMPARE_NAME=coremark \
		COMPARE_ELF=$(BUILD_DIR)/app/coremark/coremark.elf \
		COMPARE_ITCM=$(BUILD_DIR)/app/coremark/coremark.itcm \
		COMPARE_DTCM=$(BUILD_DIR)/app/coremark/coremark.dtcm \
		SIM_COMPARE=$(COREMARK_SIM_COMPARE) \
		COMPARE_SIM_EXTRA_DEFINES="+cpp_timeout=$(COREMARK_SIM_TIMEOUT) +sv_timeout=$(COREMARK_SIM_TIMEOUT)"; \
	rc=$$?; \
	$(MAKE) --no-print-directory coremark_result; \
	exit $$rc

coremark_run: coremark_sim

$(APP_OPT_EXPANDED_LINKER): $(PROJECT_ROOT)/sw/bsp/link.lds
	@mkdir -p "$(dir $@)"
	@actual=$$((1 << ($(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH) + 2))); \
	requested=$(APP_OPT_EXPANDED_ITCM_BYTES); kib=$$(( $(APP_OPT_EXPANDED_ITCM_KIB) * 1024 )); \
	if [ "$$actual" -ne "$$requested" ] || [ "$$kib" -ne "$$requested" ]; then \
		echo "Expanded ITCM settings disagree: bytes=$$requested KiB=$(APP_OPT_EXPANDED_ITCM_KIB) addr_width=$(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH)"; exit 2; \
	fi
	@sed 's/LENGTH = 16K/LENGTH = $(APP_OPT_EXPANDED_ITCM_KIB)K/' "$<" > "$@"
	@grep -q 'LENGTH = $(APP_OPT_EXPANDED_ITCM_KIB)K' "$@" || \
		{ echo "Failed to generate expanded ITCM linker script: $@"; rm -f "$@"; exit 2; }

app_opt_comp_expanded_if_needed:
	@needed=0; for root in $(APP_OPT_STATUS_ROOTS); do \
		if [ -d "$$root" ] && grep -Rql '^STATE=READY_EXPANDED ' "$$root"; then needed=1; break; fi; \
	done; \
	if [ "$$needed" -eq 1 ]; then \
		echo "[APP OPT] Compiling dedicated expanded ITCM model: $(APP_OPT_EXPANDED_ITCM_BYTES) bytes"; \
		$(MAKE) comp VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) VERILATOR_TRACE=0 \
			OBJ_DIR="$(APP_OPT_EXPANDED_OBJ_DIR)" LOG_DIR="$(APP_OPT_EXPANDED_LOG_DIR)" \
			ITCM_ADDR_WIDTH_OVERRIDE=$(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH); \
	else \
		echo "[APP OPT] No oversized image; expanded ITCM model is not used"; \
	fi

coremark_opt_all: coremark_opt_clean
	@echo "[COREMARK OPT] Profiles: $(APP_OPT_PROFILES)"
	@$(MAKE) -j$(APP_OPT_JOBS) coremark_opt_build_all
	@$(MAKE) comp VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) VERILATOR_TRACE=0
	@$(MAKE) app_opt_comp_expanded_if_needed APP_OPT_STATUS_ROOTS="$(COREMARK_OPT_ROOT)"
	@$(MAKE) -j$(APP_OPT_JOBS) coremark_opt_sim_all
	@$(MAKE) coremark_opt_report

coremark_opt_build_all: $(COREMARK_OPT_BUILD_TARGETS)
coremark_opt_sim_all: $(COREMARK_OPT_SIM_TARGETS)

define COREMARK_OPT_template
coremark_opt_build_$(1): $(APP_OPT_EXPANDED_LINKER)
	+@profile="$(1)"; out="$(COREMARK_OPT_ROOT)/$(1)"; log="$$$$out/build.log"; expanded_log="$$$$out/build-expanded.log"; \
	rm -rf "$$$$out"; mkdir -p "$$$$out"; set +e; \
	$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS) COREMARK_OUT="$$$$out" \
		COREMARK_EXTRA_CFLAGS="$(if $(COREMARK_OPT_BSP_CFLAGS_$(1)),$(COREMARK_OPT_BSP_CFLAGS_$(1)),$(APP_OPT_CFLAGS_$(1)))" \
		COREMARK_APP_ONLY_CFLAGS="$(COREMARK_OPT_APP_CFLAGS_$(1))" COREMARK_FLAGS_STR="$(1)" \
		>"$$$$log" 2>&1; rc=$$$$?; set -e; state=BUILD_FAIL; bytes=0; capacity=$(APP_OPT_ITCM_BYTES); expanded=NO; \
	if [ "$$$$rc" -eq 0 ] && [ -s "$$$$out/coremark_itcm.bin" ]; then \
		bytes=$$$$(wc -c < "$$$$out/coremark_itcm.bin"); \
		if [ "$$$$bytes" -le "$(APP_OPT_ITCM_BYTES)" ]; then state=READY; else rc=1; fi; \
	fi; \
	if { [ "$$$$rc" -ne 0 ] && grep -Eq 'region .itcm. overflowed|will not fit in region .itcm' "$$$$log"; } || [ "$$$$bytes" -gt "$(APP_OPT_ITCM_BYTES)" ]; then \
		echo "[COREMARK OPT][$$$$profile] 16 KiB ITCM exceeded; rebuilding for $(APP_OPT_EXPANDED_ITCM_KIB) KiB simulation only"; set +e; \
		$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS) COREMARK_OUT="$$$$out" \
			BSP_LINKER_SCRIPT="$(APP_OPT_EXPANDED_LINKER)" \
			COREMARK_EXTRA_CFLAGS="$(if $(COREMARK_OPT_BSP_CFLAGS_$(1)),$(COREMARK_OPT_BSP_CFLAGS_$(1)),$(APP_OPT_CFLAGS_$(1)))" \
			COREMARK_APP_ONLY_CFLAGS="$(COREMARK_OPT_APP_CFLAGS_$(1))" COREMARK_FLAGS_STR="$(1)" \
			>"$$$$expanded_log" 2>&1; expanded_rc=$$$$?; set -e; \
		if [ "$$$$expanded_rc" -eq 0 ] && [ -s "$$$$out/coremark_itcm.bin" ]; then \
			bytes=$$$$(wc -c < "$$$$out/coremark_itcm.bin"); capacity=$(APP_OPT_EXPANDED_ITCM_BYTES); expanded=YES; \
			if [ "$$$$bytes" -le "$(APP_OPT_EXPANDED_ITCM_BYTES)" ]; then state=READY_EXPANDED; else state=SKIP_SIZE; fi; \
		elif grep -Eq 'region .itcm. overflowed|will not fit in region .itcm' "$$$$expanded_log"; then state=SKIP_SIZE; \
		else state=BUILD_FAIL; fi; \
	fi; \
	echo "STATE=$$$$state ITCM_BYTES=$$$$bytes ITCM_CAPACITY_BYTES=$$$$capacity EXPANDED_ITCM=$$$$expanded FLAGS=$(APP_OPT_CFLAGS_$(1))" | tee "$$$$out/build.status"

coremark_opt_sim_$(1):
	+@profile="$(1)"; out="$(COREMARK_OPT_ROOT)/$(1)"; result_dir="$(COREMARK_OPT_RESULT_DIR)"; \
	status="$$$$result_dir/$$$$profile.status"; run_log="$$$$result_dir/$$$$profile.log"; \
	mkdir -p "$$$$result_dir"; build_state=$$$$(sed -n 's/^STATE=\([^ ]*\).*/\1/p' "$$$$out/build.status"); \
	bytes=$$$$(sed -n 's/.*ITCM_BYTES=\([0-9]*\).*/\1/p' "$$$$out/build.status"); \
	capacity=$$$$(sed -n 's/.*ITCM_CAPACITY_BYTES=\([0-9]*\).*/\1/p' "$$$$out/build.status"); expanded=$$$$(sed -n 's/.*EXPANDED_ITCM=\([^ ]*\).*/\1/p' "$$$$out/build.status"); \
	if [ "$$$$build_state" != READY ] && [ "$$$$build_state" != READY_EXPANDED ]; then \
		echo "[$$$$profile] [SKIP] reason=$$$$build_state itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded score=N/A" > "$$$$status"; exit 0; \
	fi; \
	model_args=""; if [ "$$$$build_state" = READY_EXPANDED ]; then \
		model_args="OBJ_DIR=$(APP_OPT_EXPANDED_OBJ_DIR) LOG_DIR=$(APP_OPT_EXPANDED_LOG_DIR) ITCM_ADDR_WIDTH_OVERRIDE=$(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH)"; \
	fi; \
	set +e; $(MAKE) --no-print-directory sim_compare SIM_COMPARE=none \
		COMPARE_NAME="coremark-opt/$$$$profile" COMPARE_ELF="$$$$out/coremark.elf" \
		COMPARE_ITCM="$$$$out/coremark.itcm" COMPARE_DTCM="$$$$out/coremark.dtcm" \
		COMPARE_SIM_EXTRA_DEFINES="+cpp_timeout=$(if $(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT)) +sv_timeout=$(if $(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT))" \
		$$$$model_args \
		>"$$$$run_log" 2>&1; rc=$$$$?; set -e; hw_log="$(HW_TRACE_OUT_DIR)/coremark-opt/$$$$profile/hw.log"; \
	result=FAIL; if [ "$$$$rc" -eq 0 ] && grep -q 'Correct operation validated' "$$$$hw_log" && \
		grep -q 'COREMARK DONE' "$$$$hw_log"; then result=PASS; fi; \
	cycles=$$$$(grep -o 'CYCLES=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	insts=$$$$(grep -o 'INSTS=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	ipc=$$$$(grep -o 'IPC=[0-9.]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	score=$$$$(sed -n 's/^CoreMark 1\.0 : *\([0-9.]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	echo "[$$$$profile] [$$$$result] itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded cycles=$$$${cycles:-N/A} insts=$$$${insts:-N/A} ipc=$$$${ipc:-N/A} score=$$$${score:-N/A}" > "$$$$status"
endef
$(foreach profile,$(APP_OPT_PROFILES),$(eval $(call COREMARK_OPT_template,$(profile))))

coremark_opt_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_COREMARK_OPT_LOG)"; failed=0; pass=0; skip=0; expanded_count=0; \
	for profile in $(APP_OPT_PROFILES); do status="$(COREMARK_OPT_RESULT_DIR)/$$profile.status"; \
		if [ ! -f "$$status" ]; then echo "[$$profile] [FAIL] missing status" | tee -a "$(PPA_COREMARK_OPT_LOG)"; failed=1; continue; fi; \
		line=$$(cat "$$status"); if ! echo "$$line" | grep -q ' score='; then \
			score=$$(sed -n 's/^CoreMark 1\.0 : *\([0-9.]*\).*/\1/p' "$(HW_TRACE_OUT_DIR)/coremark-opt/$$profile/hw.log" 2>/dev/null | tail -1); \
			line="$$line score=$${score:-N/A}"; \
		fi; echo "$$line" | tee -a "$(PPA_COREMARK_OPT_LOG)"; \
		if echo "$$line" | grep -q 'expanded_itcm=YES'; then expanded_count=$$((expanded_count+1)); fi; \
		if echo "$$line" | grep -q '\[PASS\]'; then pass=$$((pass+1)); elif echo "$$line" | grep -q '\[SKIP\]'; then skip=$$((skip+1)); else failed=1; fi; \
	done; overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[COREMARK OPT] ITCM original=$(APP_OPT_ITCM_BYTES) expanded=$(APP_OPT_EXPANDED_ITCM_BYTES) expanded_runs=$$expanded_count" | tee -a "$(PPA_COREMARK_OPT_LOG)"; \
	echo "[COREMARK OPT] CORRECTNESS=$$overall passed=$$pass skipped=$$skip total=$(words $(APP_OPT_PROFILES))" | tee -a "$(PPA_COREMARK_OPT_LOG)"; exit $$failed

coremark_opt_clean:
	@rm -rf "$(COREMARK_OPT_ROOT)" "$(COREMARK_OPT_RESULT_DIR)" "$(HW_TRACE_OUT_DIR)/coremark-opt"

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
		COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=$(SORT_SIM_TIMEOUT) +sv_timeout=$(SORT_SIM_TIMEOUT)" \
		>"$$run_log" 2>&1 \
			&& [ "$$(grep -Ec "^SORT SUITE PASS name=$$name cases=$(SORT_EXPECT_CASES) checks=$(SORT_EXPECT_CHECKS) signature=0x$(SORT_EXPECT_SIGNATURE)$$" "$$hw_log")" -eq 1 ] \
			&& ! grep -q "^SORT FAIL name=$$name " "$$hw_log"; then \
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

sort_opt_all: sort_opt_clean
	@echo "[SORT OPT] Profiles: $(APP_OPT_PROFILES), apps: $(SORT_APP_NAMES)"
	@$(MAKE) -j$(APP_OPT_JOBS) sort_opt_build_all
	@$(MAKE) comp VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) VERILATOR_TRACE=0
	@$(MAKE) app_opt_comp_expanded_if_needed APP_OPT_STATUS_ROOTS="$(SORT_OPT_ROOT)"
	@$(MAKE) -j$(APP_OPT_JOBS) sort_opt_sim_all
	@$(MAKE) sort_opt_report

sort_opt_build_all: $(SORT_OPT_BUILD_TARGETS)
sort_opt_sim_all: $(SORT_OPT_SIM_TARGETS)

define SORT_OPT_template
sort_opt_build_$(1)_$(2): $(APP_OPT_EXPANDED_LINKER)
	+@profile="$(1)"; name="$(2)"; out="$(SORT_OPT_ROOT)/$(1)"; meta="$$$$out/meta"; \
	mkdir -p "$$$$out" "$$$$meta"; log="$$$$meta/$$$$name.build.log"; expanded_log="$$$$meta/$$$$name.build-expanded.log"; set +e; \
	$(MAKE) -C sw sort_app $(SORT_APP_SW_MAKE_ARGS) SORT_APP_OUT="$$$$out" SORT_APP_NAMES="$$$$name" \
		SORT_APP_EXTRA_CFLAGS="$(if $(SORT_OPT_BSP_CFLAGS_$(1)),$(SORT_OPT_BSP_CFLAGS_$(1)),$(APP_OPT_CFLAGS_$(1)))" \
		SORT_APP_ONLY_CFLAGS="$(SORT_OPT_APP_CFLAGS_$(1))" >"$$$$log" 2>&1; rc=$$$$?; set -e; state=BUILD_FAIL; bytes=0; capacity=$(APP_OPT_ITCM_BYTES); expanded=NO; \
	if [ "$$$$rc" -eq 0 ] && [ -s "$$$$out/$$$${name}_itcm.bin" ]; then \
		bytes=$$$$(wc -c < "$$$$out/$$$${name}_itcm.bin"); \
		if [ "$$$$bytes" -le "$(APP_OPT_ITCM_BYTES)" ]; then state=READY; else rc=1; fi; \
	fi; \
	if { [ "$$$$rc" -ne 0 ] && grep -Eq 'region .itcm. overflowed|will not fit in region .itcm' "$$$$log"; } || [ "$$$$bytes" -gt "$(APP_OPT_ITCM_BYTES)" ]; then \
		echo "[SORT OPT][$$$$profile/$$$$name] 16 KiB ITCM exceeded; rebuilding for $(APP_OPT_EXPANDED_ITCM_KIB) KiB simulation only"; set +e; \
		$(MAKE) -C sw sort_app $(SORT_APP_SW_MAKE_ARGS) SORT_APP_OUT="$$$$out" SORT_APP_NAMES="$$$$name" \
			BSP_LINKER_SCRIPT="$(APP_OPT_EXPANDED_LINKER)" \
			SORT_APP_EXTRA_CFLAGS="$(if $(SORT_OPT_BSP_CFLAGS_$(1)),$(SORT_OPT_BSP_CFLAGS_$(1)),$(APP_OPT_CFLAGS_$(1)))" \
			SORT_APP_ONLY_CFLAGS="$(SORT_OPT_APP_CFLAGS_$(1))" >"$$$$expanded_log" 2>&1; expanded_rc=$$$$?; set -e; \
		if [ "$$$$expanded_rc" -eq 0 ] && [ -s "$$$$out/$$$${name}_itcm.bin" ]; then \
			bytes=$$$$(wc -c < "$$$$out/$$$${name}_itcm.bin"); capacity=$(APP_OPT_EXPANDED_ITCM_BYTES); expanded=YES; \
			if [ "$$$$bytes" -le "$(APP_OPT_EXPANDED_ITCM_BYTES)" ]; then state=READY_EXPANDED; else state=SKIP_SIZE; fi; \
		elif grep -Eq 'region .itcm. overflowed|will not fit in region .itcm' "$$$$expanded_log"; then state=SKIP_SIZE; \
		else state=BUILD_FAIL; fi; \
	fi; \
	echo "STATE=$$$$state ITCM_BYTES=$$$$bytes ITCM_CAPACITY_BYTES=$$$$capacity EXPANDED_ITCM=$$$$expanded FLAGS=$(APP_OPT_CFLAGS_$(1))" > "$$$$meta/$$$$name.build.status"

sort_opt_sim_$(1)_$(2):
	+@profile="$(1)"; name="$(2)"; out="$(SORT_OPT_ROOT)/$(1)"; meta="$$$$out/meta"; \
	result_dir="$(SORT_OPT_RESULT_DIR)/$$$$profile"; mkdir -p "$$$$result_dir"; status="$$$$result_dir/$$$$name.status"; \
	build_state=$$$$(sed -n 's/^STATE=\([^ ]*\).*/\1/p' "$$$$meta/$$$$name.build.status"); \
	bytes=$$$$(sed -n 's/.*ITCM_BYTES=\([0-9]*\).*/\1/p' "$$$$meta/$$$$name.build.status"); \
	capacity=$$$$(sed -n 's/.*ITCM_CAPACITY_BYTES=\([0-9]*\).*/\1/p' "$$$$meta/$$$$name.build.status"); expanded=$$$$(sed -n 's/.*EXPANDED_ITCM=\([^ ]*\).*/\1/p' "$$$$meta/$$$$name.build.status"); \
	if [ "$$$$build_state" != READY ] && [ "$$$$build_state" != READY_EXPANDED ]; then \
		echo "[$$$$profile/$$$$name] [SKIP] reason=$$$$build_state itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded" > "$$$$status"; exit 0; \
	fi; \
	model_args=""; if [ "$$$$build_state" = READY_EXPANDED ]; then \
		model_args="OBJ_DIR=$(APP_OPT_EXPANDED_OBJ_DIR) LOG_DIR=$(APP_OPT_EXPANDED_LOG_DIR) ITCM_ADDR_WIDTH_OVERRIDE=$(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH)"; \
	fi; \
	run_log="$$$$result_dir/$$$$name.log"; set +e; $(MAKE) --no-print-directory sim_compare SIM_COMPARE=none \
		COMPARE_NAME="sort-opt/$$$$profile/$$$$name" COMPARE_ELF="$$$$out/$$$$name.elf" \
		COMPARE_ITCM="$$$$out/$$$$name.itcm" COMPARE_DTCM="$$$$out/$$$$name.dtcm" \
		COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=$(if $(SORT_OPT_TIMEOUT_$(1)),$(SORT_OPT_TIMEOUT_$(1)),$(SORT_OPT_TIMEOUT)) +sv_timeout=$(if $(SORT_OPT_TIMEOUT_$(1)),$(SORT_OPT_TIMEOUT_$(1)),$(SORT_OPT_TIMEOUT))" \
		$$$$model_args \
		>"$$$$run_log" 2>&1; rc=$$$$?; set -e; hw_log="$(HW_TRACE_OUT_DIR)/sort-opt/$$$$profile/$$$$name/hw.log"; \
	result=FAIL; if [ "$$$$rc" -eq 0 ] \
		&& [ "$$$$(grep -Ec "^SORT SUITE PASS name=$$$$name cases=$(SORT_EXPECT_CASES) checks=$(SORT_EXPECT_CHECKS) signature=0x$(SORT_EXPECT_SIGNATURE)$$$$" "$$$$hw_log")" -eq 1 ] \
		&& ! grep -q "^SORT FAIL name=$$$$name " "$$$$hw_log"; then result=PASS; fi; \
	cycles=$$$$(grep -o 'CYCLES=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	insts=$$$$(grep -o 'INSTS=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	ipc=$$$$(grep -o 'IPC=[0-9.]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	echo "[$$$$profile/$$$$name] [$$$$result] itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded cycles=$$$${cycles:-N/A} insts=$$$${insts:-N/A} ipc=$$$${ipc:-N/A}" > "$$$$status"
endef
$(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),$(eval $(call SORT_OPT_template,$(profile),$(app)))))

sort_opt_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_SORT_OPT_LOG)"; failed=0; pass=0; skip=0; expanded_count=0; total=$(words $(SORT_OPT_SIM_TARGETS)); \
	for profile in $(APP_OPT_PROFILES); do for name in $(SORT_APP_NAMES); do status="$(SORT_OPT_RESULT_DIR)/$$profile/$$name.status"; \
		if [ ! -f "$$status" ]; then echo "[$$profile/$$name] [FAIL] missing status" | tee -a "$(PPA_SORT_OPT_LOG)"; failed=1; continue; fi; \
		line=$$(cat "$$status"); echo "$$line" | tee -a "$(PPA_SORT_OPT_LOG)"; \
		if echo "$$line" | grep -q 'expanded_itcm=YES'; then expanded_count=$$((expanded_count+1)); fi; \
		if echo "$$line" | grep -q '\[PASS\]'; then pass=$$((pass+1)); elif echo "$$line" | grep -q '\[SKIP\]'; then skip=$$((skip+1)); else failed=1; fi; \
	done; done; overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[SORT OPT] ITCM original=$(APP_OPT_ITCM_BYTES) expanded=$(APP_OPT_EXPANDED_ITCM_BYTES) expanded_runs=$$expanded_count" | tee -a "$(PPA_SORT_OPT_LOG)"; \
	echo "[SORT OPT] CORRECTNESS=$$overall passed=$$pass skipped=$$skip total=$$total" | tee -a "$(PPA_SORT_OPT_LOG)"; exit $$failed

sort_opt_clean:
	@rm -rf "$(SORT_OPT_ROOT)" "$(SORT_OPT_RESULT_DIR)" "$(HW_TRACE_OUT_DIR)/sort-opt"

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
	if $(MAKE) --no-print-directory sim_compare SIM_COMPARE=none COMPARE_NAME="boundary/$$name" COMPARE_ELF="$(BUILD_DIR)/app/boundary/$$name.elf" COMPARE_ITCM="$(BUILD_DIR)/app/boundary/$$name.itcm" COMPARE_DTCM="$(BUILD_DIR)/app/boundary/$$name.dtcm" COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=$(BOUNDARY_SIM_TIMEOUT) +sv_timeout=$(BOUNDARY_SIM_TIMEOUT)" >"$$run_log" 2>&1 && grep -q "BOUNDARY PASS name=$$name" "$$hw_log"; then result=PASS; else result=FAIL; fi; \
	echo "[$$name] [$$result]" > "$$status"

boundary_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_BOUNDARY_LOG)"; failed=0; \
	for status in $$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | sort); do line=$$(cat "$$status"); echo "$$line" | tee -a "$(PPA_BOUNDARY_LOG)"; if echo "$$line" | grep -q '\[FAIL\]'; then failed=1; name=$$(basename "$$status" .status); tail -40 "$(BOUNDARY_RESULT_DIR)/$$name.log"; fi; done; \
	count=$$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | wc -l); \
	if [ "$$count" -ne "$(words $(BOUNDARY_APP_NAMES))" ]; then echo "[BOUNDARY] Missing status files: expected $(words $(BOUNDARY_APP_NAMES)), got $$count"; failed=1; fi; \
	echo "[PPA] Boundary report: $(PPA_BOUNDARY_LOG)"; exit $$failed

boundary_opt_all: boundary_opt_clean
	@echo "==========================================================="
	@echo "   Boundary compiler optimization regression"
	@echo "   Profiles: $(BOUNDARY_OPT_PROFILES)"
	@echo "   Matrix: $(words $(BOUNDARY_OPT_PROFILES)) x $(words $(BOUNDARY_APP_NAMES)) = $(words $(BOUNDARY_OPT_SIM_TARGETS)) runs"
	@echo "==========================================================="
	@$(MAKE) -j$(BOUNDARY_OPT_JOBS) boundary_opt_build_all
	@$(MAKE) comp
	@$(MAKE) -j$(BOUNDARY_OPT_JOBS) boundary_opt_sim_all
	@$(MAKE) boundary_opt_report

boundary_opt_build_all: $(BOUNDARY_OPT_BUILD_TARGETS)

boundary_opt_sim_all: $(BOUNDARY_OPT_SIM_TARGETS)

define BOUNDARY_OPT_BUILD_template
boundary_opt_build_$(1): $(BOUNDARY_OPT_APP_ROOT)/$(1)/.built

$(BOUNDARY_OPT_APP_ROOT)/$(1)/.built: $(BOUNDARY_OPT_SW_DEPS)
	@echo "[BOUNDARY OPT][$(1)] BSP: $(BOUNDARY_OPT_CFLAGS_$(1)) $(BOUNDARY_EXTRA_CFLAGS) APP: $(BOUNDARY_OPT_APP_CFLAGS_$(1))"
	+@$(MAKE) -C sw boundary_app $(BOUNDARY_APP_SW_MAKE_ARGS) \
		BOUNDARY_APP_OUT="$(BOUNDARY_OPT_APP_ROOT)/$(1)" \
		BOUNDARY_EXTRA_CFLAGS="$(BOUNDARY_OPT_CFLAGS_$(1)) $(BOUNDARY_EXTRA_CFLAGS)" \
		BOUNDARY_APP_ONLY_CFLAGS="$(BOUNDARY_OPT_APP_CFLAGS_$(1))"
	@printf 'BSP_CFLAGS=%s\nAPP_CFLAGS=%s\n' \
		"$(BOUNDARY_OPT_CFLAGS_$(1)) $(BOUNDARY_EXTRA_CFLAGS)" \
		"$(BOUNDARY_OPT_APP_CFLAGS_$(1))" > "$(BOUNDARY_OPT_APP_ROOT)/$(1)/flags.txt"
	@touch "$$@"
endef
$(foreach profile,$(BOUNDARY_OPT_PROFILES),$(eval $(call BOUNDARY_OPT_BUILD_template,$(profile))))

define BOUNDARY_OPT_SIM_template
boundary_opt_sim_$(1)_$(2): $(BOUNDARY_OPT_APP_ROOT)/$(1)/.built
	+@profile="$(1)"; name="$(2)"; \
	result_dir="$(BOUNDARY_OPT_RESULT_DIR)/$$$$profile"; \
	tmp_dir="$(BOUNDARY_OPT_RUN_DIR)/$$$$profile"; \
	hw_dir="$(HW_TRACE_OUT_DIR)/boundary-opt/$$$$profile/$$$$name"; \
	hw_log="$$$$hw_dir/hw.log"; run_log="$$$$result_dir/$$$$name.log"; \
	status="$$$$result_dir/$$$$name.status"; tmp_log="$$$$tmp_dir/$$$$name.log.tmp"; \
	tmp_status="$$$$tmp_dir/$$$$name.status.tmp"; app_dir="$(BOUNDARY_OPT_APP_ROOT)/$$$$profile"; \
	mkdir -p "$$$$result_dir" "$$$$tmp_dir" "$$$$hw_dir"; \
	rm -f "$$$$hw_log" "$$$$run_log" "$$$$status" "$$$$tmp_log" "$$$$tmp_status"; \
	compare_mode=csv; if [[ " $(BOUNDARY_OPT_SPIKE_SKIP_APPS) " == *" $$$$name "* ]]; then compare_mode=none; fi; \
	set +e; \
	$(MAKE) --no-print-directory sim_compare SIM_COMPARE="$$$$compare_mode" \
		COMPARE_NAME="boundary-opt/$$$$profile/$$$$name" \
		COMPARE_ELF="$$$$app_dir/$$$$name.elf" \
		COMPARE_ITCM="$$$$app_dir/$$$$name.itcm" \
		COMPARE_DTCM="$$$$app_dir/$$$$name.dtcm" \
		COMPARE_HW_OUT_DIR="$$$$hw_dir" COMPARE_HW_LOG="$$$$hw_log" \
		COMPARE_COMPLETE_PROGRAM=1 COMPARE_ALLOW_SPIKE_TAIL=1 COMPARE_MAX_SPIKE_TAIL=16 \
		COMPARE_GPR_IGNORE_MASK=0x1800 \
		SPIKE_MAXSTEPS=$(if $(BOUNDARY_OPT_SPIKE_MAXSTEPS_$(2)),$(BOUNDARY_OPT_SPIKE_MAXSTEPS_$(2)),$(BOUNDARY_OPT_SPIKE_MAXSTEPS)) \
		COMPARE_SIM_EXTRA_DEFINES="+perip_debug +cpp_timeout=$(BOUNDARY_SIM_TIMEOUT) +sv_timeout=$(BOUNDARY_SIM_TIMEOUT)" \
		>"$$$$tmp_log" 2>&1; run_rc=$$$$?; set -e; \
	self_check=FAIL; assertions=FAIL; spike_diff=FAIL; result=FAIL; \
	if grep -Eq "BOUNDARY PASS name=$$$$name|LED write 0x00504f53" "$$$$hw_log"; then self_check=PASS; fi; \
	if grep -q "Simulation finished" "$$$$hw_log" && \
	   ! grep -Eq '(%Error|Assertion failed|ASSERT_[A-Z_]+)' "$$$$hw_log"; then assertions=PASS; fi; \
	if [ "$$$$compare_mode" = none ]; then spike_diff=SKIP; \
	elif grep -q '^MATCH: YES' "$$$$tmp_log"; then spike_diff=PASS; fi; \
	if [ "$$$$run_rc" -eq 0 ] && [ "$$$$self_check" = PASS ] && \
	   [ "$$$$assertions" = PASS ] && [ "$$$$spike_diff" = PASS ]; then result=PASS; fi; \
	if [ "$$$$run_rc" -eq 0 ] && [ "$$$$self_check" = PASS ] && \
	   [ "$$$$assertions" = PASS ] && [ "$$$$spike_diff" = SKIP ]; then result=PARTIAL; fi; \
	mv "$$$$tmp_log" "$$$$run_log"; \
	echo "[$$$$profile/$$$$name] [$$$$result] SELF_CHECK=$$$$self_check ASSERTIONS=$$$$assertions SPIKE_DIFF=$$$$spike_diff" > "$$$$tmp_status"; \
	mv "$$$$tmp_status" "$$$$status"
endef
$(foreach profile,$(BOUNDARY_OPT_PROFILES),$(foreach app,$(BOUNDARY_APP_NAMES),$(eval $(call BOUNDARY_OPT_SIM_template,$(profile),$(app)))))

boundary_opt_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_BOUNDARY_OPT_LOG)"; failed=0; total_pass=0; total_partial=0; \
	echo "[BOUNDARY OPT] Correctness matrix: $(words $(BOUNDARY_OPT_PROFILES)) profiles x $(words $(BOUNDARY_APP_NAMES)) apps" | tee -a "$(PPA_BOUNDARY_OPT_LOG)"; \
	echo "[BOUNDARY OPT] Correctness method: program self-check + testbench assertions + complete-program Spike commit differential" | tee -a "$(PPA_BOUNDARY_OPT_LOG)"; \
	for profile in $(BOUNDARY_OPT_PROFILES); do \
		for status in $$(find "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" -maxdepth 1 -name '*.status' -type f 2>/dev/null | sort); do \
			line=$$(cat "$$status"); echo "$$line" | tee -a "$(PPA_BOUNDARY_OPT_LOG)"; \
			if echo "$$line" | grep -q '\[FAIL\]'; then \
				failed=1; name=$$(basename "$$status" .status); \
				tail -40 "$(BOUNDARY_OPT_RESULT_DIR)/$$profile/$$name.log"; \
			fi; \
		done; \
	done; \
	count=0; for profile in $(BOUNDARY_OPT_PROFILES); do \
		profile_count=$$(find "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" -maxdepth 1 -name '*.status' -type f 2>/dev/null | wc -l); \
		count=$$((count + profile_count)); \
	done; \
	if [ "$$count" -ne "$(words $(BOUNDARY_OPT_SIM_TARGETS))" ]; then \
		echo "[BOUNDARY OPT] Missing status files: expected $(words $(BOUNDARY_OPT_SIM_TARGETS)), got $$count"; failed=1; \
	fi; \
	for profile in $(BOUNDARY_OPT_PROFILES); do \
		pass=$$(grep -rl '\[PASS\]' "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" --include='*.status' 2>/dev/null | wc -l); \
		partial=$$(grep -rl '\[PARTIAL\]' "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" --include='*.status' 2>/dev/null | wc -l); \
		fail=$$(grep -rl '\[FAIL\]' "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" --include='*.status' 2>/dev/null | wc -l); \
		total_pass=$$((total_pass + pass)); total_partial=$$((total_partial + partial)); result=PASS; \
		if [ "$$fail" -ne 0 ]; then result=FAIL; failed=1; elif [ "$$partial" -ne 0 ]; then result=PARTIAL; fi; \
		flags=$$(tr '\n' ' ' < "$(BOUNDARY_OPT_APP_ROOT)/$$profile/flags.txt"); \
		echo "[BOUNDARY OPT][$$profile] CORRECTNESS=$$result passed=$$pass partial=$$partial failed=$$fail total=$(words $(BOUNDARY_APP_NAMES)) $$flags" | tee -a "$(PPA_BOUNDARY_OPT_LOG)"; \
	done; \
	overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; elif [ "$$total_partial" -ne 0 ]; then overall=PARTIAL; fi; \
	echo "[BOUNDARY OPT] CORRECTNESS=$$overall passed=$$total_pass partial=$$total_partial total=$(words $(BOUNDARY_OPT_SIM_TARGETS))" | tee -a "$(PPA_BOUNDARY_OPT_LOG)"; \
	echo "[PPA] Boundary optimization report: $(PPA_BOUNDARY_OPT_LOG)"; exit $$failed

boundary_opt_clean:
	@rm -rf "$(BOUNDARY_OPT_APP_ROOT)" "$(BOUNDARY_OPT_RESULT_DIR)" "$(BOUNDARY_OPT_RUN_DIR)" "$(HW_TRACE_OUT_DIR)/boundary-opt"

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

$(COE_M3_ITCM): $(IROM_COE) $(COE_TO_MEM)
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" "$<" "$@"

$(COE_M3_ITCM_BIN): $(IROM_COE) $(COE_TO_MEM)
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" --binary "$<" "$@"

$(COE_M3_DTCM) $(COE_LOOP2_DTCM) $(COE_LOOP5_DTCM) $(COE_LOOP_LINA_DTCM): $(DRAM_COE) $(COE_TO_MEM)
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" "$<" "$@"

$(COE_LOOP2_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_PATCH)
	perl "$(COE_LOOP_PATCH)" "$<" "$@" 1

$(COE_LOOP2_ITCM): $(COE_LOOP2_ITCM_BIN)
	od -An -t x4 -w4 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_LOOP5_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_PATCH)
	perl "$(COE_LOOP_PATCH)" "$<" "$@" 4

$(COE_LOOP5_ITCM): $(COE_LOOP5_ITCM_BIN)
	od -An -t x4 -w4 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_LOOP5_DUMP): $(COE_LOOP5_ITCM_BIN)
	$(OBJDUMP) -D -b binary -m riscv:rv32 "$<" > "$@"

$(COE_LOOP_LINA_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_LINA_PATCH)
	perl "$(COE_LOOP_LINA_PATCH)" "$<" "$@" "$(COE_LOOP_LINA_SCALE)"

$(COE_LOOP_LINA_ITCM): $(COE_LOOP_LINA_ITCM_BIN)
	od -An -t x4 -w4 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_LOOP_LINA_DUMP): $(COE_LOOP_LINA_ITCM_BIN)
	$(OBJDUMP) -D -b binary -m riscv:rv32 "$<" > "$@"

$(COE_MFLINA_SOURCE_ITCM_BIN): $(COE_MFLINA_IROM_SOURCE) $(COE_TO_MEM)
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" --binary "$<" "$@"

$(COE_MFLINA_ITCM_BIN): $(COE_MFLINA_SOURCE_ITCM_BIN) $(COE_MFLINA_PATCH)
	perl "$(COE_MFLINA_PATCH)" "$<" "$@" \
		"$(COE_MFLINA_MATRIX_ITERATIONS)" "$(COE_MFLINA_OUTER_ITERATIONS)" \
		"$(COE_MFLINA_SORT_LENGTH)" "$(COE_MFLINA_SORT_OUTER_ITERATIONS)" \
		"$(COE_MFLINA_PRIME_LIMIT)" "$(COE_MFLINA_RANDOM_OUTER_ITERATIONS)" \
		"$(COE_MFLINA_CRC_LENGTH)" "$(COE_MFLINA_CRC_OUTER_ITERATIONS)"

$(COE_MFLINA_ITCM): $(COE_MFLINA_ITCM_BIN)
	od -An -t x4 -w4 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_MFLINA_DTCM): $(COE_MFLINA_DRAM_SOURCE) $(COE_TO_MEM)
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" "$<" "$@"

$(COE_MFLINA_DUMP): $(COE_MFLINA_ITCM_BIN)
	$(OBJDUMP) -D -b binary -m riscv:rv32 "$<" > "$@"

coe_loop2_gen: $(COE_M3_ITCM) $(COE_M3_ITCM_BIN) $(COE_M3_DTCM) \
		$(COE_LOOP2_ITCM_BIN) $(COE_LOOP2_ITCM) $(COE_LOOP2_DTCM)

coe_simple: comp $(COE_SIMPLE_ITCM) $(COE_SIMPLE_DTCM)
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
	if [ -n "$(COE_EXPECT_SEG)" ] && ! grep -q "SEG write $(COE_EXPECT_SEG)" "$$log"; then \
		echo "[COE_SIMPLE] Expected SEG write $(COE_EXPECT_SEG) not found"; \
		ok=0; \
	fi; \
	if [ -n "$(COE_EXPECT_SEG_REGEX)" ] && ! grep -Eq "SEG write $(COE_EXPECT_SEG_REGEX)" "$$log"; then \
		echo "[COE_SIMPLE] Expected SEG pattern $(COE_EXPECT_SEG_REGEX) not found"; \
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
	if [ "$(COE_REQUIRE_CNT_READ)" = "1" ] && ! grep -q "CNT read" "$$log"; then \
		echo "[COE_SIMPLE] Expected CNT read not found"; \
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

coe_loop5_gen: $(COE_LOOP5_ITCM_BIN) $(COE_LOOP5_ITCM) $(COE_LOOP5_DTCM) $(COE_LOOP5_DUMP)

coe_loop5: coe_loop5_gen
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_loop5 \
		COE_SIMPLE_ITCM=$(COE_LOOP5_ITCM) \
		COE_SIMPLE_DTCM=$(COE_LOOP5_DTCM) \
		COE_EXPECT_CNT_READ=0x00000001 \
		COE_EXPECT_SEG=0x37800001

coe_loop_lina_gen: $(COE_LOOP_LINA_ITCM_BIN) $(COE_LOOP_LINA_ITCM) \
		$(COE_LOOP_LINA_DTCM) $(COE_LOOP_LINA_DUMP)

coe_loop_lina: coe_loop_lina_gen
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_loop_lina \
		COE_SIMPLE_ITCM=$(COE_LOOP_LINA_ITCM) \
		COE_SIMPLE_DTCM=$(COE_LOOP_LINA_DTCM) \
		COE_SIM_TIMEOUT=$(COE_LOOP_LINA_SIM_TIMEOUT) \
		COE_SIMPLE_SIM_EXTRA_DEFINES="$(COE_LOOP_LINA_SIM_EXTRA_DEFINES)" \
		COE_EXPECT_CNT_READ= \
		COE_REQUIRE_CNT_READ=1 \
		COE_EXPECT_SEG= \
		COE_EXPECT_SEG_REGEX='0x3780[0-9a-fA-F]{4}'

loop_lina: coe_loop_lina

coe_MFlina_gen: $(COE_MFLINA_SOURCE_ITCM_BIN) $(COE_MFLINA_ITCM_BIN) \
		$(COE_MFLINA_ITCM) $(COE_MFLINA_DTCM) $(COE_MFLINA_DUMP)

coe_MFlina: coe_MFlina_gen
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_MFlina \
		COE_SIMPLE_ITCM=$(COE_MFLINA_ITCM) \
		COE_SIMPLE_DTCM=$(COE_MFLINA_DTCM) \
		COE_SIM_TIMEOUT=$(COE_MFLINA_SIM_TIMEOUT) \
		COE_SIMPLE_SIM_EXTRA_DEFINES="$(COE_MFLINA_SIM_EXTRA_DEFINES)" \
		COE_EXPECT_CNT_READ= \
		COE_REQUIRE_CNT_READ=1 \
		COE_EXPECT_SEG= \
		COE_EXPECT_SEG_REGEX='0x3780[0-9a-fA-F]{4}'

coe_mflina_gen: coe_MFlina_gen
coe_mflina: coe_MFlina

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
	@$(MAKE) ydrasil_test_all YDRASIL_TEST_REUSE_MODEL=1
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
	@set +e; env $(SPIKE_RUN_ENV) $(SPIKE) $(SPIKE_FLAGS) $(spike_stepout) $(spike_extension) $(abspath $(COMPARE_ELF)) \
		> $(COMPARE_SPIKE_LOG) 2>&1; rc=$$?; echo "SPIKE_EXIT_CODE=$$rc" >> $(COMPARE_SPIKE_LOG); exit 0
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_SPIKE_LOG) --csv $(COMPARE_SPIKE_CSV) --source spike $(if $(filter 1,$(COMPARE_COMPLETE_PROGRAM)),--complete-program,)
	@echo "[SIM] Spike CSV: $(COMPARE_SPIKE_CSV)"
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(abspath $(COMPARE_ITCM)) \
		DTCM_FILE=$(abspath $(COMPARE_DTCM)) \
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_DEFINES) $(if $(filter 1,$(VERILATOR_COVERAGE)),+coverage_file=$(abspath $(COMPARE_COVERAGE_FILE)),)" \
		> $(COMPARE_HW_LOG) 2>&1
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_HW_LOG) --csv $(COMPARE_HW_CSV) --source ydrasil $(if $(filter 1,$(COMPARE_COMPLETE_PROGRAM)),--complete-program,)
	@echo "[SIM] HW CSV: $(COMPARE_HW_CSV)"
	@set +e; \
	$(PYTHON) $(TRACE_COMPARE) --mode csv \
		--hw-csv $(COMPARE_HW_CSV) \
		--spike-csv $(COMPARE_SPIKE_CSV) \
		--compare-csv-fields $(TRACE_COMPARE_FIELDS) \
		$(if $(filter 1,$(COMPARE_ALLOW_HW_TAIL)),--allow-hw-tail,) \
		$(if $(filter 1,$(COMPARE_ALLOW_SPIKE_TAIL)),--allow-spike-tail --max-spike-tail $(COMPARE_MAX_SPIKE_TAIL),) \
		--gpr-ignore-mask $(COMPARE_GPR_IGNORE_MASK) \
		--max-mismatches $(SIM_COMPARE_MAX_MISMATCHES) \
		--context-lines 10 \
		> $(COMPARE_LOG) 2>&1; \
	rc=$$?; spike_rc=$$(sed -n 's/^SPIKE_EXIT_CODE=//p' $(COMPARE_SPIKE_LOG) | tail -1); \
	cat $(COMPARE_LOG); \
	if [ "$${spike_rc:-1}" -ne 0 ]; then echo "[SIM] Spike exited with code $$spike_rc"; rc=1; fi; \
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
