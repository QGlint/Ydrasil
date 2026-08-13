include config.mk

SHELL := /bin/bash
# 硬件verilator编译 VERILATOR_IGNORE_ALL=0 不忽略所有语法检查
# --- 自动化测试相关定义 ---
VERIF_DIR ?= $(BUILD_DIR)/verif
VERIF_STATS_DIR ?= $(VERIF_DIR)/stats
VERIF_COVERAGE_DIR ?= $(VERIF_DIR)/coverage
RESULT_DIR := $(VERIF_DIR)/test_results
PPA_DIR ?= $(BUILD_DIR)/PPA
PPA_COREMARK_LOG ?= $(PPA_DIR)/coremark_summary.log
VERIF_RVTEST_LOG ?= $(VERIF_STATS_DIR)/test_all_summary.log
BUS_IRQ_OBJ_DIR ?= $(BUILD_DIR)/ydrasil_bus_irq_tb$(if $(filter 1,$(VERILATOR_COVERAGE)),-coverage,)
BUS_IRQ_COVERAGE_FILE ?= $(COVERAGE_DATA_DIR)/bus_irq.dat
BUS_IRQ_TIMEOUT ?= 5000
SORT_APP_DIR := $(PROJECT_ROOT)/verif/tests/sw_tests/sort
SORT_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(SORT_APP_DIR)/*.c))))
SORT_SIM_TARGETS := $(addprefix sort_sim_,$(SORT_APP_NAMES))
SORT_RESULT_DIR ?= $(RESULT_DIR)/sort
BOUNDARY_APP_DIR := $(PROJECT_ROOT)/verif/tests/sw_tests/boundary
BOUNDARY_APP_NAMES := $(sort $(basename $(notdir $(wildcard $(BOUNDARY_APP_DIR)/*.c))))
BOUNDARY_SIM_TARGETS := $(addprefix boundary_sim_,$(BOUNDARY_APP_NAMES))
BOUNDARY_RESULT_DIR ?= $(RESULT_DIR)/boundary
VERIF_BOUNDARY_LOG ?= $(VERIF_STATS_DIR)/boundary_summary.log
BOUNDARY_OPT_PROFILES ?= O0 O1 O2 O3 Os Og O2_noinline O3_app_unroll
BOUNDARY_OPT_JOBS ?= $(shell nproc)
BOUNDARY_OPT_APP_ROOT ?= $(BUILD_DIR)/app/boundary-opt
BOUNDARY_OPT_RESULT_DIR ?= $(RESULT_DIR)/boundary-opt
BOUNDARY_OPT_RUN_DIR ?= $(BUILD_DIR)/boundary-opt-run
VERIF_BOUNDARY_OPT_LOG ?= $(VERIF_STATS_DIR)/boundary_opt_summary.log
APP_OPT_PROFILES ?= O0 O1 O2 O3 Os Og O2_noinline O3_app_unroll
APP_OPT_JOBS ?= $(shell nproc)
APP_OPT_ITCM_BYTES ?= 131072
APP_OPT_EXPANDED_ITCM_BYTES ?= 131072
APP_OPT_EXPANDED_ITCM_KIB ?= 128
APP_OPT_EXPANDED_ITCM_ADDR_WIDTH ?= 15
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
# Keep application tuning orthogonal to the BSP so compiler groups can be
# re-swept after microarchitectural changes.
COREMARK_SWOPT_BASE_CFLAGS ?= -O3 -funroll-loops
COREMARK_SWOPT_CFLAGS_inline = \
	-finline-functions -finline-small-functions \
	-findirect-inlining -finline-functions-called-once \
	--param=max-inline-insns-auto=4000 \
	--param=large-function-insns=4000 \
	--param=large-function-growth=4000 \
	--param=inline-unit-growth=4000 \
	-finline-limit=4000
COREMARK_SWOPT_CFLAGS_register = \
	-frename-registers -fweb -fomit-frame-pointer -fno-caller-saves
COREMARK_SWOPT_CFLAGS_loop_shape = \
	-fno-tree-loop-distribute-patterns \
	-fno-tree-loop-vectorize -fno-tree-slp-vectorize \
	-fno-peel-loops -fno-split-loops
COREMARK_SWOPT_CFLAGS_control_shape = \
	-fno-branch-count-reg -fno-crossjumping \
	-fno-if-conversion -fno-if-conversion2 -fno-code-hoisting
COREMARK_SWOPT_CFLAGS_tree_shape = \
	-fno-tree-dse -fno-section-anchors \
	-fno-tree-forwprop -fno-tree-partial-pre
COREMARK_SWOPT_CFLAGS_unroll_all = -funroll-all-loops
COREMARK_SWOPT_CFLAGS_no_strict_alias = -fno-strict-aliasing
COREMARK_SWOPT_CFLAGS_lto = -flto
COREMARK_SWOPT_CFLAGS_mtune_s7 = -mtune=sifive-7-series
COREMARK_SWOPT_CFLAGS_mtune_ydrasil = -mtune=ydrasil
COREMARK_SWOPT_CFLAGS_branch_cost_2 = -mbranch-cost=2
COREMARK_SWOPT_CFLAGS_branch_cost_3 = -mbranch-cost=3
COREMARK_SWOPT_CFLAGS_branch_cost_5 = -mbranch-cost=5
COREMARK_SWOPT_AVAILABLE_GROUPS := inline register loop_shape control_shape tree_shape unroll_all no_strict_alias lto mtune_s7 mtune_ydrasil branch_cost_2 branch_cost_3 branch_cost_5
COREMARK_SWOPT_DEFAULT_GROUPS ?= inline register loop_shape control_shape tree_shape
COREMARK_SWOPT_GROUPS ?= $(COREMARK_SWOPT_DEFAULT_GROUPS)
COREMARK_SWOPT_UNKNOWN_GROUPS := $(filter-out $(COREMARK_SWOPT_AVAILABLE_GROUPS),$(COREMARK_SWOPT_GROUPS))
ifneq ($(strip $(COREMARK_SWOPT_UNKNOWN_GROUPS)),)
$(error Unknown COREMARK_SWOPT_GROUPS: $(COREMARK_SWOPT_UNKNOWN_GROUPS). Available: $(COREMARK_SWOPT_AVAILABLE_GROUPS))
endif
COREMARK_SWOPT_SELECTED_CFLAGS = $(strip $(foreach group,$(COREMARK_SWOPT_GROUPS),$(COREMARK_SWOPT_CFLAGS_$(group))))
COREMARK_SWOPT_ALIGN_BYTES ?= 8
COREMARK_SWOPT_ALIGN_CFLAGS = \
	-falign-functions=$(COREMARK_SWOPT_ALIGN_BYTES) \
	-falign-jumps=$(COREMARK_SWOPT_ALIGN_BYTES) \
	-falign-labels=$(COREMARK_SWOPT_ALIGN_BYTES) \
	-falign-loops=$(COREMARK_SWOPT_ALIGN_BYTES)
COREMARK_OPT_APP_CFLAGS_O3_app_unroll ?= $(COREMARK_SWOPT_BASE_CFLAGS) $(COREMARK_SWOPT_SELECTED_CFLAGS)
COREMARK_PROFILE ?= O3_app_unroll
COREMARK_BSP_CFLAGS ?= $(if $(COREMARK_OPT_BSP_CFLAGS_$(COREMARK_PROFILE)),$(COREMARK_OPT_BSP_CFLAGS_$(COREMARK_PROFILE)),$(APP_OPT_CFLAGS_$(COREMARK_PROFILE)))
COREMARK_APP_CFLAGS ?= $(COREMARK_OPT_APP_CFLAGS_$(COREMARK_PROFILE))
COREMARK_LINKER ?= $(APP_OPT_EXPANDED_LINKER)
COREMARK_SIM_ITCM_ADDR_WIDTH ?= $(APP_OPT_EXPANDED_ITCM_ADDR_WIDTH)
COREMARK_SIM_OBJ_DIR ?= $(BUILD_DIR)/ydrasil_core_tb-coremark
COREMARK_SIM_LOG_DIR ?= $(BUILD_DIR)/log/coremark
COREMARK_VERILATOR_IGNORE_FULL ?= 1
SORT_OPT_BSP_CFLAGS_O3_app_unroll ?= -Os
SORT_OPT_APP_CFLAGS_O3_app_unroll ?= -O3 -funroll-loops
COREMARK_OPT_ROOT ?= $(BUILD_DIR)/app/coremark-opt
COREMARK_OPT_RESULT_DIR ?= $(RESULT_DIR)/coremark-opt
PPA_COREMARK_OPT_LOG ?= $(PPA_DIR)/coremark_opt_summary.log
RTTHREAD_COREMARK_PROFILES ?= Os O2 O3
RTTHREAD_CPU_FREQ_HZ ?= 150000000
RTTHREAD_COREMARK_PROFILE_BUILD_TARGETS := $(addprefix rtthread-coremark-build-,$(RTTHREAD_COREMARK_PROFILES))
RTTHREAD_COREMARK_PROFILE_SIM_TARGETS := $(addprefix rtthread-coremark-sim-,$(RTTHREAD_COREMARK_PROFILES))
COREMARK_OPT_TIMEOUT ?= 2000000
COREMARK_OPT_TIMEOUT_O0 ?= 5000000
SORT_OPT_ROOT ?= $(BUILD_DIR)/app/sort-opt
SORT_OPT_RESULT_DIR ?= $(RESULT_DIR)/sort-opt
VERIF_SORT_OPT_LOG ?= $(VERIF_STATS_DIR)/sort_opt_summary.log
SORT_SIM_TIMEOUT ?= 20000000
SORT_OPT_TIMEOUT ?= 20000000
SORT_OPT_TIMEOUT_O0 ?= 50000000
COREMARK_OPT_BUILD_TARGETS := $(addprefix coremark_opt_build_,$(APP_OPT_PROFILES))
COREMARK_OPT_SIM_TARGETS := $(addprefix coremark_opt_sim_,$(APP_OPT_PROFILES))
SORT_OPT_BUILD_TARGETS := $(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),sort_opt_build_$(profile)_$(app)))
SORT_OPT_SIM_TARGETS := $(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),sort_opt_sim_$(profile)_$(app)))
COVERAGE_QUICK_COREMARK_PROFILE ?= $(COREMARK_PROFILE)
COVERAGE_QUICK_COREMARK_TARGET ?= coremark_opt_sim_$(COVERAGE_QUICK_COREMARK_PROFILE)
COVERAGE_QUICK_TARGETS ?= boundary_all test_all $(COVERAGE_QUICK_COREMARK_TARGET)
VERIF_COVERAGE_QUICK_SUMMARY ?= $(VERIF_COVERAGE_DIR)/coverage_quick_summary.log
COVERAGE_CLOSURE_DIR ?= $(VERIF_COVERAGE_DIR)/closure
COVERAGE_CLOSURE_DATA ?= $(COVERAGE_CLOSURE_DIR)/data/boundary_coverage_closure_edges.dat
COVERAGE_CLOSURE_MERGED ?= $(COVERAGE_CLOSURE_DIR)/merged.dat
COVERAGE_CLOSURE_INFO ?= $(COVERAGE_CLOSURE_DIR)/coverage.info
COVERAGE_CLOSURE_ANNOTATED ?= $(COVERAGE_CLOSURE_DIR)/annotated
COVERAGE_CLOSURE_BASES ?=
REGRESSION_TARGETS ?= coverage_all regression_sort regression_sort_opt riscv_dv_random
REGRESSION_SUMMARY ?= $(VERIF_STATS_DIR)/regression_summary.log
REGRESSION_STATUS_REPORT ?= $(VERIF_STATS_DIR)/regression_status.log
REGRESSION_LOG_DIR ?= $(VERIF_DIR)/regression
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
REGRESSION_TOTAL_COVERAGE_DIR ?= $(VERIF_COVERAGE_DIR)/total
REGRESSION_TOTAL_COVERAGE_DATA ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/merged.dat
REGRESSION_TOTAL_COVERAGE_INFO ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/coverage.info
REGRESSION_TOTAL_COVERAGE_ANNOTATED ?= $(REGRESSION_TOTAL_COVERAGE_DIR)/annotated
REGRESSION_TOTAL_COVERAGE_SUMMARY ?= $(VERIF_COVERAGE_DIR)/regression_coverage_summary.log
REGRESSION_TOTAL_COVERAGE_UNCOVERED ?= $(VERIF_COVERAGE_DIR)/regression_coverage_uncovered.log
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
RISCV_DV_SUMMARY ?= $(VERIF_STATS_DIR)/riscv_dv_summary.log
RISCV_DV_ARCH ?= rv32im_zicsr_zifencei
RISCV_DV_ABI ?= ilp32
override RISCV_DV_GCC := $(RISCV_TOOLCHAIN_PREFIX)-gcc
override RISCV_DV_OBJCOPY := $(RISCV_TOOLCHAIN_PREFIX)-objcopy
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
BOUNDARY_OPT_SPIKE_SKIP_APPS ?= csr_counter_edges coverage_closure_edges completion_broadcast_edges mmio_dtcm_order_edges
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
VERIF_SORT_LOG ?= $(VERIF_STATS_DIR)/sort_summary.log
SORT_EXPECT_CASES ?= 91
SORT_EXPECT_CHECKS ?= 455
SORT_EXPECT_SIGNATURE ?= c02bdfa9
VERIF_COE_LOG ?= $(VERIF_STATS_DIR)/$(COE_SIMPLE_NAME)_summary.log
COE_M3_DIR ?= $(BUILD_DIR)/fpga_coe_m3
COE_TO_MEM ?= $(PROJECT_ROOT)/verif/tools/coe_to_mem.pl
COE_LOOP_PATCH ?= $(PROJECT_ROOT)/verif/tools/make_m3_loop_variant.pl
COE_LOOP_LINA_PATCH ?= $(PROJECT_ROOT)/verif/tools/make_m3_loop_lina.pl
COE_M3_IROM_SOURCE ?= $(PROJECT_ROOT)/FPGA/coe/irom_M3.coe
COE_M3_DRAM_SOURCE ?= $(PROJECT_ROOT)/FPGA/coe/dram_M.coe
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
COE_MFLINA_PATCH ?= $(PROJECT_ROOT)/verif/tools/make_mf_lina.pl
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

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD COVERAGE VERILATOR_COVERAGE UVM USE_BENDER BENDER DIV_IMPL YDRASIL_PRODUCER_NUM YDRASIL_ENABLE_I2C LSU_IMPL MEMS_IMPL ARCH ABI RISCV_PREFIX RISCV_TOOLCHAIN_ROOT RISCV_TOOLCHAIN_BIN RISCV_TOOLCHAIN_TRIPLE RISCV_TOOLCHAIN_PREFIX CC OBJCOPY OBJDUMP NM GDB QEMU TRACE_TO_CSV TRACE_COMPARE

SYN_DIR ?= $(PROJECT_ROOT)/syn
SYN_BUILD_DIR ?= $(BUILD_DIR)/syn
SYN_VENV ?= $(SYN_BUILD_DIR)/.venv
SYN_PYTHON ?= $(SYN_VENV)/bin/python
SYN_PLL_FREQ_MHZ ?= 150
SYN_PLL_SUPPORTED_FREQS := 150 200 225 240 250 260 270 275 280 290.625 300
SYN_PLL_FREQ_TAG = pll$(subst .,p,$(SYN_PLL_FREQ_MHZ))m
SYN_PLL_DEFINE = SYN_PLL_FREQ_$(subst .,P,$(SYN_PLL_FREQ_MHZ))
SYN_PLL_FREQ_HZ = $(shell awk 'BEGIN { printf "%.0f", $(SYN_PLL_FREQ_MHZ) * 1000000 }')
SYN_TOP ?= ydrasil_soc
SYN_PART ?= xc7k325tffg900-2
SYN_BENDER_DIR ?= $(PROJECT_ROOT)/hw/ip/ydrasil_soc
SYN_XPM_MMI ?= 0
SYN_RTL_DEFINES = $(SYN_PLL_DEFINE)
SYN_RTL_DEFINES += SYNTHESIS
SYN_RTL_DEFINES += $(if $(filter 1,$(SYN_XPM_MMI)),YDRASIL_XPM_MMI)
SYN_RTL_DEFINES += YDRASIL_PRODUCER_NUM=$(YDRASIL_PRODUCER_NUM)
SYN_RTL_DEFINES += $(if $(filter 1,$(YDRASIL_ENABLE_I2C)),YDRASIL_ENABLE_I2C)
SYN_RTL_DEFINES += $(if $(filter custom-board,$(SYN_PROFILE)),YDRASIL_LED_ACTIVE_LOW)
SYN_PROFILE ?= official
SYN_PROFILE_SUFFIX = $(if $(filter official,$(SYN_PROFILE)),,-$(SYN_PROFILE))$(if $(filter 1,$(SYN_XPM_MMI)),-mmi)
SYN_ENABLE_ILA ?= 0
SYN_REPLACE_CONSTRAINTS ?= 1
SYN_RTL_DEFINES += $(if $(filter 1,$(SYN_ENABLE_ILA)),SYN_BOARD_ILA)
ifeq ($(DIV_IMPL),lzc)
SYN_RTL_DEFINES += YDRASIL_DIV_IMPL_LZC
else
$(error Unsupported DIV_IMPL '$(DIV_IMPL)'. Use DIV_IMPL=lzc)
endif
SYN_DEFINE_ARGS = $(foreach define,$(SYN_RTL_DEFINES),--define $(define))
SYN_FREQ_BUILD_DIR ?= $(SYN_BUILD_DIR)/$(SYN_PLL_FREQ_TAG)$(SYN_PROFILE_SUFFIX)
SYN_STAGE_ROOT ?= $(SYN_FREQ_BUILD_DIR)/project
SYN_STAGE_FPGA_DIR ?= $(SYN_STAGE_ROOT)/FPGA
SYN_STAGE_SOURCE_DIR ?= $(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.srcs/sources_1
SYN_STAGE_CONSTR_DIR ?= $(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.srcs/constrs_1
SYN_STAGE_MEMORY_DIR ?= $(SYN_STAGE_SOURCE_DIR)/memory
SYN_PREPROJECT_DIR ?= $(SYN_STAGE_FPGA_DIR)/staging
SYN_PREPROJECT_SOURCE_DIR ?= $(SYN_PREPROJECT_DIR)/sources_1
SYN_PREPROJECT_CONSTR_DIR ?= $(SYN_PREPROJECT_DIR)/constrs_1
SYN_PREPROJECT_MEMORY_DIR ?= $(SYN_PREPROJECT_SOURCE_DIR)/memory
SYN_XPR ?= $(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.xpr
SYN_SOURCES_TCL ?= $(SYN_STAGE_FPGA_DIR)/vivado_sources.tcl
SYN_CONSTR_DIR ?= $(PROJECT_ROOT)/FPGA/constrs
SYN_DEFAULT_XDC ?= $(SYN_STAGE_CONSTR_DIR)/digital_twin.xdc
SYN_BOARD_XDC ?= $(SYN_DEFAULT_XDC)
SYN_REPORT_DIR ?= $(SYN_FREQ_BUILD_DIR)/reports
SYN_LOG_DIR ?= $(SYN_FREQ_BUILD_DIR)/log
SYN_ARTIFACT_DIR ?= $(SYN_FREQ_BUILD_DIR)/artifacts
SYN_BIT_DIR ?= $(SYN_FREQ_BUILD_DIR)/bit
SYN_CHECKPOINT_DIR ?= $(SYN_FREQ_BUILD_DIR)/checkpoints
# The profile controls RT-Thread, monitor, and sensor code. CoreMark sources
# retain their separate RTTHREAD_COREMARK_CORE_CFLAGS optimization setting.
SYN_MSH_PROFILE ?= O2
SYN_MSH_IMAGE_DIR ?= $(BUILD_DIR)/app/rtthread-coremark/$(SYN_MSH_PROFILE)
SYN_MSH_ITCM ?= $(SYN_MSH_IMAGE_DIR)/rtthread_coremark.itcm
SYN_MSH_DTCM ?= $(SYN_MSH_IMAGE_DIR)/rtthread_coremark.dtcm
SYN_STAGED_ITCM_MEM ?= $(SYN_STAGE_MEMORY_DIR)/itcm.mem
SYN_STAGED_DTCM_MEM ?= $(SYN_STAGE_MEMORY_DIR)/dtcm.mem
SYN_STAGED_ITCM_COE ?= $(SYN_STAGE_MEMORY_DIR)/itcm.coe
SYN_STAGED_DTCM_COE ?= $(SYN_STAGE_MEMORY_DIR)/dtcm.coe
SYN_PREPROJECT_ITCM_MEM ?= $(SYN_PREPROJECT_MEMORY_DIR)/itcm.mem
SYN_PREPROJECT_DTCM_MEM ?= $(SYN_PREPROJECT_MEMORY_DIR)/dtcm.mem
SYN_PREPROJECT_ITCM_COE ?= $(SYN_PREPROJECT_MEMORY_DIR)/itcm.coe
SYN_PREPROJECT_DTCM_COE ?= $(SYN_PREPROJECT_MEMORY_DIR)/dtcm.coe
SYN_ITCM_WORDS ?= 16384
SYN_DTCM_WORDS ?= 16384
SYN_ITCM_WIDTH ?= 64
SYN_DTCM_WIDTH ?= 32
SYN_TIMING_SUMMARY_MAX_PATHS ?= 5000
SYN_TIMING_PATH_MAX_PATHS ?= 5000
SYN_TIMING_NWORST ?= 1
SYN_WAY ?= 0
SYN_VALID_WAYS := 0 1 2 3 4 full
ifeq ($(filter $(SYN_WAY),$(SYN_VALID_WAYS)),)
$(error Unsupported SYN_WAY=$(SYN_WAY); supported values: $(SYN_VALID_WAYS))
endif
ifeq ($(HOSTNAME),servera437)
SYN_JOBS ?= $(if $(filter full,$(SYN_WAY)),40,16)
SYN_IMPL_RUNS ?= $(if $(filter full,$(SYN_WAY)),4,1)
SYN_THREADS_PER_RUN ?= $(if $(filter full,$(SYN_WAY)),10,16)
else ifeq ($(HOSTNAME),QGlint-Ar)
SYN_JOBS ?= 16
SYN_IMPL_RUNS ?= 1
SYN_THREADS_PER_RUN ?= 16
else
SYN_JOBS ?= $(shell nproc)
SYN_IMPL_RUNS ?= 1
SYN_THREADS_PER_RUN ?= $(shell nproc)
endif
SYN_IMPL_MODE ?= $(if $(filter 4,$(SYN_WAY)),extreme,sweep)
SYN_SYNTH_STRATEGY ?= Flow_PerfOptimized_high
SYN_RUN_TO ?= route
SYN_FORCE ?= 1
SYN_SYNC_SOURCES ?= 1
SYN_REUSE_STAGE ?= 0
SYN_REUSE_SYNTH ?= 0
SYN_RESET_IMPL ?= 0
SYN_REPORT_SYNTH ?= 1
SYN_FULL_REPORTS ?= 0
SYN_POST_ROUTE_PHYSOPT ?= 0
SYN_SWEEP_POST_ROUTE_PHYSOPT ?= 0
VIVADO ?= vivado
ifeq ($(HOSTNAME),servera437)
VIVADO_SETTINGS ?= /opt/Xilinx/Vitis/2024.2/settings64.sh
else
VIVADO_SETTINGS ?=
endif
VIVADO_LICENSE_FILE ?= $(firstword $(wildcard $(HOME)/opt/vivado_2037.lic $(HOME)/*.lic $(HOME)/.Xilinx/*.lic))
BENDER_INSTALL_URL ?= https://github.com/pulp-platform/bender/releases/download/v0.32.1/bender-installer.sh

ifneq ($(VIVADO_LICENSE_FILE),)
export XILINXD_LICENSE_FILE := $(VIVADO_LICENSE_FILE)
endif

ifeq ($(filter $(SYN_PLL_FREQ_MHZ),$(SYN_PLL_SUPPORTED_FREQS)),)
$(error Unsupported SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ); supported values: $(SYN_PLL_SUPPORTED_FREQS))
endif

.PHONY: all comp sim clean wave resim test_all rvtest rvtest_wave rvtest_clean run_all_tests regression regression_all regression_status regression_stop regression_clean regression_sort regression_sort_opt regression_suite_coverage_merge regression_coverage_report init install-bender get_spike download_and_extract_spike check_spike_prebuilt_abi build_spike_from_source check_deps spike spike_wave_to_csv sim_compare commit_check commit_spike_csv commit_hw_trace commit_hw_csv commit_compare rv_test_comp_genmem ppa_rvtest_report ppa_perf_report coe_simple coe_smoke coe_smoke_led coe_isa_probes coverage_all coverage_all_run coverage_quick coverage_closure coverage_closure_merge coverage_clean coverage_report bus_irq_test bus_irq_coverage sw_boundary_test sw_coverage sw_coverage_clean sw_run_mode sw_coverage_report driver_sim_test
.PHONY: coremark coremark_sim coremark_run coremark_result coremark-rebuild coremark-clean coremark-clean-all coremark-clean-elf coremark-clean-bin coremark-clean-dump coremark-clean-mem coremark-clean-map coremark_swopt_show coremark_opt_all coremark_opt_build_all coremark_opt_sim_all coremark_opt_report coremark_opt_clean $(COREMARK_OPT_BUILD_TARGETS) $(COREMARK_OPT_SIM_TARGETS) sort_app sort_all sort_sim_all sort_report sort_app_sim sort_app-rebuild sort_app-clean sort_opt_all sort_opt_build_all sort_opt_sim_all sort_opt_report sort_opt_clean $(SORT_OPT_BUILD_TARGETS) $(SORT_OPT_SIM_TARGETS) boundary_app boundary_all boundary_sim_all boundary_report boundary_app-rebuild boundary_app-clean boundary_opt_all boundary_opt_build_all boundary_opt_sim_all boundary_opt_report boundary_opt_clean $(BOUNDARY_OPT_BUILD_TARGETS) $(BOUNDARY_OPT_SIM_TARGETS) coe_m3_force coe_loop2_gen coe_loop5 coe_loop5_gen coe_loop_lina coe_loop_lina_gen loop_lina coe_MFlina coe_MFlina_gen coe_mflina coe_mflina_gen rtthread rtthread-build rtthread-clean rtthread-coremark rtthread-coremark-build rtthread-coremark-build-all rtthread-coremark-sim rtthread-coremark-sim-all rtthread-coremark-report rtthread-coremark-compare rtthread-coremark-clean rtthread-utest rtthread-utest-build rtthread-utest-sim rtthread-utest-report rtthread-utest-clean $(RTTHREAD_COREMARK_PROFILE_BUILD_TARGETS) $(RTTHREAD_COREMARK_PROFILE_SIM_TARGETS)
.PHONY: riscv_dv_venv riscv_dv_model riscv_dv_prepare riscv_dv_run riscv_dv_random riscv_dv_random_status riscv_dv_regression riscv_dv_count riscv_dv_repro riscv_dv_estimate riscv_dv_stop riscv_dv_coverage_report riscv_dv_cleanup riscv_dv_distclean
.PHONY: syn synf syn225 syn240 syn250 syn260 syn270 syn275 syn280 syn290 syn290625 syn300 syn-board synf-board syn-extreme syn-reports syn-dedup syn-lowmem-synth syn-lowmem-impl syn-venv syn-prep syn-stage-xpr syn-stage-memory syn-reuse-stage-check syn-vivado syn-analyze syn-clean
.PHONY: rtl-quickcheck rtl-strict rtl-xml rtl-structure-report rtl-structure rtl-vivado-compare rtl-vivado-cross-validate rtl-vivado-archive verilator-strict verilator-xml slang-ast
.PHONY: yosys-slang yosys-slang-gate yosys-slang-baseline yosys-slang-quick vivado-ooc vivado-ooc-synth vivado-ooc-issue

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
	@mkdir -p "$(VERIF_STATS_DIR)"
	@"$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" run $(RISCV_DV_COMMON_ARGS); rc=$$?; \
	summary=$$(find "$(RISCV_DV_WORK_ROOT)/runs" -mindepth 2 -maxdepth 2 -name summary.log -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); \
	if [ -n "$$summary" ]; then cp "$$summary" "$(RISCV_DV_SUMMARY)"; echo "[RISCV-DV] Summary: $$summary"; fi; \
	exit $$rc

riscv_dv_random: riscv_dv_venv riscv_dv_model get_spike
	@mkdir -p "$(VERIF_STATS_DIR)"
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
	@mkdir -p "$(VERIF_COVERAGE_DIR)"; \
	data=$$("$(RISCV_DV_PYTHON)" "$(RISCV_DV_DRIVER)" coverage-path $(RISCV_DV_COMMON_ARGS)); \
	if [ -z "$$data" ]; then echo "[RISCV-DV] No merged coverage database found"; exit 2; fi; \
	cov_dir="$${data%/*}"; info="$$cov_dir/coverage.info"; annotated="$$cov_dir/annotated"; \
	summary="$(VERIF_COVERAGE_DIR)/riscv_dv_coverage_summary.log"; uncovered="$(VERIF_COVERAGE_DIR)/riscv_dv_uncovered.log"; \
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
		--state "$$state" --artifact "$$merged" --artifact "$(VERIF_SORT_LOG)" --artifact "$(SORT_RESULT_DIR)"; then \
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
		--artifact "$$merged" --artifact "$(VERIF_SORT_LOG)" --artifact "$(SORT_RESULT_DIR)"

regression_sort_opt:
	@set -e; state="$(REGRESSION_CACHE_DIR)/sort_opt.json"; merged="$(REGRESSION_SORT_OPT_COVERAGE_DIR)/merged.dat"; \
	if $(PYTHON) "$(REGRESSION_CACHE_TOOL)" check --project-root "$(PROJECT_ROOT)" --scope sort_opt \
		--state "$$state" --artifact "$$merged" --artifact "$(VERIF_SORT_OPT_LOG)" --artifact "$(SORT_OPT_RESULT_DIR)"; then \
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
		--artifact "$$merged" --artifact "$(VERIF_SORT_OPT_LOG)" --artifact "$(SORT_OPT_RESULT_DIR)"

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
	rm -rf "$(REGRESSION_TOTAL_COVERAGE_DIR)"; mkdir -p "$(REGRESSION_TOTAL_COVERAGE_DIR)" "$(VERIF_COVERAGE_DIR)"; \
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
	run_dir="$(REGRESSION_LOG_DIR)/$$run_id"; mkdir -p "$$run_dir" "$(VERIF_STATS_DIR)" "$(REGRESSION_CONTROL_DIR)"; \
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
	@set -e; mkdir -p "$(VERIF_STATS_DIR)"; report="$(REGRESSION_STATUS_REPORT)"; tmp="$$report.tmp.$$$$"; \
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
	@$(MAKE) bus_irq_coverage VERILATOR_TRACE=0
	@$(MAKE) boundary_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) boundary_opt_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coremark_opt_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) test_all VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coremark_sim VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@$(MAKE) coverage_report
	@$(MAKE) ppa_perf_report

bus_irq_test:
	@mkdir -p "$(COVERAGE_DATA_DIR)"
	@$(MAKE) -C hw/dv comp TOP=ydrasil_bus_irq_tb \
		OBJ_DIR="$(BUS_IRQ_OBJ_DIR)" VERILATOR_TRACE=0 \
		VERILATOR_MOD=sv VERILATOR_COVERAGE=$(VERILATOR_COVERAGE)
	@$(MAKE) -C hw/dv sim TOP=ydrasil_bus_irq_tb \
		OBJ_DIR="$(BUS_IRQ_OBJ_DIR)" VERILATOR_TRACE=0 \
		VERILATOR_MOD=sv LOG_OUTPUT=1 VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) \
		SIM_EXTRA_DEFINES="+cpp_timeout=$(BUS_IRQ_TIMEOUT) $(if $(filter 1,$(VERILATOR_COVERAGE)),+coverage_file=$(abspath $(BUS_IRQ_COVERAGE_FILE)),)"
	@grep -q "BUS_IRQ_TEST_PASS" "$(LOG_DIR)/ydrasil_bus_irq_tb.ver.sim.log"

bus_irq_coverage:
	@$(MAKE) --no-print-directory bus_irq_test VERILATOR_COVERAGE=1

driver_sim_test:
	@$(MAKE) --no-print-directory -C verif/sw/driver test \
		CC=cc BUILD_DIR="$(BUILD_DIR)/verif/sw/driver"

coverage_quick: coverage_clean
	@mkdir -p "$(COVERAGE_DATA_DIR)" "$(VERIF_COVERAGE_DIR)"
	@$(MAKE) comp VERILATOR_COVERAGE=1 VERILATOR_TRACE=0
	@set +e; failed=0; rm -f "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
	echo "[COVERAGE QUICK] Targets: $(COVERAGE_QUICK_TARGETS)" | tee "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
	for target in $(COVERAGE_QUICK_TARGETS); do \
		measured=0; minimum=$(COVERAGE_QUICK_TIMEOUT); \
		if [ -s "$(PPA_DIR)/perf_stats.csv" ]; then \
			case "$$target" in \
				boundary_all) pattern='^boundary(-opt)?/'; minimum=$(COVERAGE_QUICK_BOUNDARY_MIN) ;; \
				test_all) pattern='^rv32'; minimum=$(COVERAGE_QUICK_ISA_MIN) ;; \
				$(COVERAGE_QUICK_COREMARK_TARGET)) pattern='^coremark-opt/$(COVERAGE_QUICK_COREMARK_PROFILE)$$'; minimum=$(COVERAGE_QUICK_COREMARK_MIN) ;; \
				*) pattern='a^' ;; \
			esac; \
			measured=$$(awk -F, -v p="$$pattern" 'NR>1 && $$1 ~ p && $$2 ~ /^[0-9]+$$/ && $$2>m {m=$$2} END{print m+0}' "$(PPA_DIR)/perf_stats.csv"); \
		else \
			case "$$target" in \
				boundary_all) minimum=$(COVERAGE_QUICK_BOUNDARY_MIN) ;; \
				test_all) minimum=$(COVERAGE_QUICK_ISA_MIN) ;; \
				$(COVERAGE_QUICK_COREMARK_TARGET)) minimum=$(COVERAGE_QUICK_COREMARK_MIN) ;; \
			esac; \
		fi; \
		budget=$$(( (measured * $(COVERAGE_QUICK_TICKS_PER_CYCLE) * (100 + $(COVERAGE_QUICK_MARGIN_PERCENT)) + 99) / 100 + $(COVERAGE_QUICK_TIMEOUT_PAD) )); \
		if [ "$$budget" -lt "$$minimum" ]; then budget=$$minimum; fi; \
		echo "[COVERAGE QUICK] RUN  $$target timeout=$$budget measured_cycles=$$measured" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
		prepare_ok=1; \
		if [ "$$target" = "$(COVERAGE_QUICK_COREMARK_TARGET)" ]; then \
			if ! $(MAKE) --no-print-directory "coremark_opt_build_$(COVERAGE_QUICK_COREMARK_PROFILE)"; then \
				prepare_ok=0; \
			else \
				build_state=$$(sed -n 's/^STATE=\([^ ]*\).*/\1/p' \
					"$(COREMARK_OPT_ROOT)/$(COVERAGE_QUICK_COREMARK_PROFILE)/build.status"); \
				case "$$build_state" in \
					READY|READY_EXPANDED) \
						$(MAKE) --no-print-directory app_opt_comp_expanded_if_needed \
							APP_OPT_STATUS_ROOTS="$(COREMARK_OPT_ROOT)/$(COVERAGE_QUICK_COREMARK_PROFILE)" \
							VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 || prepare_ok=0 ;; \
					*) echo "[COVERAGE QUICK] Invalid $(COVERAGE_QUICK_COREMARK_PROFILE) build state: $${build_state:-MISSING}"; prepare_ok=0 ;; \
				esac; \
			fi; \
		fi; \
		target_result=FAIL; \
		if [ "$$prepare_ok" -eq 1 ] && $(MAKE) --no-print-directory "$$target" VERILATOR_COVERAGE=1 VERILATOR_TRACE=0 \
			SIM_COMPARE_TIMEOUT="$$budget" \
			BOUNDARY_SIM_TIMEOUT="$$budget" \
			COREMARK_SIM_TIMEOUT="$$budget" \
			COREMARK_OPT_TIMEOUT_$(COVERAGE_QUICK_COREMARK_PROFILE)="$$budget" \
			COE_SIM_TIMEOUT="$$budget"; then target_result=PASS; fi; \
		if [ "$$target" = "$(COVERAGE_QUICK_COREMARK_TARGET)" ] && \
			! grep -q '\[PASS\]' "$(COREMARK_OPT_RESULT_DIR)/$(COVERAGE_QUICK_COREMARK_PROFILE).status" 2>/dev/null; then \
			target_result=FAIL; \
		fi; \
		if [ "$$target_result" = PASS ]; then \
			echo "[COVERAGE QUICK] PASS $$target" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
		else \
			echo "[COVERAGE QUICK] FAIL $$target" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; failed=1; \
		fi; \
	done; \
	if $(MAKE) --no-print-directory coverage_report; then \
		echo "[COVERAGE QUICK] PASS coverage_report" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
		grep '^\[COVERAGE\] LCOV source-line coverage:' "$(COVERAGE_SUMMARY)" | tail -1 | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
	else \
		echo "[COVERAGE QUICK] FAIL coverage_report" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; failed=1; \
	fi; \
	dat_count=$$(find "$(COVERAGE_DATA_DIR)" -type f -name '*.dat' | wc -l); \
	overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[COVERAGE QUICK] CORRECTNESS=$$overall coverage_databases=$$dat_count" | tee -a "$(VERIF_COVERAGE_QUICK_SUMMARY)"; \
	echo "[COVERAGE QUICK] Summary: $(VERIF_COVERAGE_QUICK_SUMMARY)"; \
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
	mkdir -p "$(REGRESSION_TOTAL_COVERAGE_DIR)" "$(VERIF_COVERAGE_DIR)"; \
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

PERF_STATS_SCOPE ?= coremark

ppa_perf_report:
	@bash verif/tools/collect_perf_stats.sh "$(HW_TRACE_OUT_DIR)" "$(PPA_DIR)" "$(PERF_STATS_SCOPE)"

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
ifeq ($(HOSTNAME),QGlint-Ar)
synf: SYN_JOBS := 16
synf: SYN_IMPL_RUNS := 1
synf: SYN_THREADS_PER_RUN := 16
else ifneq ($(HOSTNAME),servera437)
synf: SYN_IMPL_MODE := extreme
synf: SYN_JOBS := 8
synf: SYN_IMPL_RUNS := 1
synf: SYN_THREADS_PER_RUN := 8
endif
synf: syn-vivado
	@src="$(SYN_ARTIFACT_DIR)/$(SYN_TOP).bit"; \
	if [ ! -f "$$src" ]; then \
		echo "Error: best bitstream not found: $$src"; \
		exit 1; \
	fi; \
	mkdir -p "$(SYN_BIT_DIR)"; \
	timestamp=$$(date '+%Y%m%d_%H%M'); \
	dst="$(SYN_BIT_DIR)/$(SYN_TOP)$${timestamp}.bit"; \
	cp "$$src" "$$dst"; \
	ltx_src="$(SYN_ARTIFACT_DIR)/$(SYN_TOP).ltx"; \
	if [ -f "$$ltx_src" ]; then \
		ltx_dst="$${dst%.bit}.ltx"; cp "$$ltx_src" "$$ltx_dst"; \
		echo "[SYN] ILA probes: $$ltx_dst"; \
	fi; \
	echo "[SYN] Best bitstream: $$dst"
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE=$(SYN_PROFILE)

syn225: SYN_PLL_FREQ_MHZ := 225
syn240: SYN_PLL_FREQ_MHZ := 240
syn250: SYN_PLL_FREQ_MHZ := 250
syn260: SYN_PLL_FREQ_MHZ := 260
syn270: SYN_PLL_FREQ_MHZ := 270
syn275: SYN_PLL_FREQ_MHZ := 275
syn280: SYN_PLL_FREQ_MHZ := 280
syn290 syn290625: SYN_PLL_FREQ_MHZ := 290.625
syn300: SYN_PLL_FREQ_MHZ := 300
SYN_OVERCLOCK_TARGETS := syn225 syn240 syn250 syn260 syn270 syn275 syn280 syn290 syn290625 syn300
$(SYN_OVERCLOCK_TARGETS): SYN_RUN_TO := bitstream
ifeq ($(HOSTNAME),QGlint-Ar)
$(SYN_OVERCLOCK_TARGETS): SYN_JOBS := 16
$(SYN_OVERCLOCK_TARGETS): SYN_IMPL_RUNS := 1
$(SYN_OVERCLOCK_TARGETS): SYN_THREADS_PER_RUN := 16
else ifneq ($(HOSTNAME),servera437)
$(SYN_OVERCLOCK_TARGETS): SYN_JOBS := 8
$(SYN_OVERCLOCK_TARGETS): SYN_IMPL_RUNS := 1
$(SYN_OVERCLOCK_TARGETS): SYN_THREADS_PER_RUN := 8
endif
$(SYN_OVERCLOCK_TARGETS): syn-vivado
	@src="$(SYN_ARTIFACT_DIR)/$(SYN_TOP).bit"; \
	if [ ! -f "$$src" ]; then \
		echo "Error: best bitstream not found: $$src"; \
		exit 1; \
	fi; \
	mkdir -p "$(SYN_BIT_DIR)"; \
	timestamp=$$(date '+%Y%m%d_%H%M'); \
	dst="$(SYN_BIT_DIR)/$(SYN_TOP)$${timestamp}.bit"; \
	cp "$$src" "$$dst"; \
	ltx_src="$(SYN_ARTIFACT_DIR)/$(SYN_TOP).ltx"; \
	if [ -f "$$ltx_src" ]; then \
		ltx_dst="$${dst%.bit}.ltx"; cp "$$ltx_src" "$$ltx_dst"; \
		echo "[SYN] ILA probes: $$ltx_dst"; \
	fi; \
	echo "[SYN] Best bitstream: $$dst"
	@$(MAKE) syn-analyze SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE=$(SYN_PROFILE)

syn-board: SYN_PROFILE := custom-board
syn-board: SYN_BOARD_XDC = $(SYN_STAGE_CONSTR_DIR)/board_ag10_ah10.xdc
syn-board: synf

BOARD_TURE ?= 0

ifeq ($(BOARD_TURE),1)
SYN_PROFILE := custom-board
SYN_BOARD_XDC = $(SYN_STAGE_CONSTR_DIR)/board_ag10_ah10.xdc
endif

synf-board: syn-board

syn-extreme: SYN_WAY := 4
syn-extreme: SYN_PLL_FREQ_MHZ := 200
syn-extreme: SYN_RUN_TO := bitstream
syn-extreme: SYN_IMPL_MODE := extreme
syn-extreme: SYN_IMPL_RUNS := 1
ifeq ($(HOSTNAME),servera437)
syn-extreme: SYN_JOBS := 16
syn-extreme: SYN_THREADS_PER_RUN := 16
else
syn-extreme: SYN_JOBS := 8
syn-extreme: SYN_THREADS_PER_RUN := 8
endif
syn-extreme: syn-vivado
	@$(MAKE) syn-analyze SYN_IMPL_MODE=extreme SYN_IMPL_RUNS=1

# Regenerate Vivado reports from routed checkpoints without launching synthesis,
# placement, or routing. syn-dedup only rebuilds the derived CSV/Markdown files.
syn-reports: SYN_PLL_FREQ_MHZ := 200
syn-reports:
	@$(MAKE) --no-print-directory syn-vivado \
		SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE="$(SYN_PROFILE)" \
		SYN_RUN_TO=reports SYN_REUSE_STAGE=1 SYN_REUSE_SYNTH=1 \
		SYN_SYNC_SOURCES=0 SYN_FORCE=0 SYN_REPORT_SYNTH=0
	@$(MAKE) --no-print-directory syn-analyze \
		SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE="$(SYN_PROFILE)"

syn-dedup: SYN_PLL_FREQ_MHZ := 200
syn-dedup:
	@$(MAKE) --no-print-directory syn-analyze \
		SYN_PLL_FREQ_MHZ=$(SYN_PLL_FREQ_MHZ) SYN_PROFILE="$(SYN_PROFILE)"

# Split the peak-memory operations into separate Vivado processes.  Phase one
# creates a current top-level DCP with the low-memory synthesis strategy.
# Phase two keeps that staged project intact, releases the opened synth design
# before implementation, then runs the highest stable per-step implementation
# directives serially.
syn-lowmem-synth:
	@$(MAKE) syn-vivado \
		SYN_PLL_FREQ_MHZ=200 SYN_RUN_TO=synth SYN_FORCE=1 \
		SYN_IMPL_MODE=extreme SYN_IMPL_RUNS=1 SYN_JOBS=8 SYN_THREADS_PER_RUN=8 \
		SYN_SYNTH_STRATEGY=Flow_RuntimeOptimized SYN_SYNC_SOURCES=1 \
		SYN_REUSE_STAGE=0 SYN_REUSE_SYNTH=0 SYN_RESET_IMPL=0 \
		SYN_REPORT_SYNTH=0 SYN_FULL_REPORTS=0 SYN_POST_ROUTE_PHYSOPT=0 \
		SYN_SWEEP_POST_ROUTE_PHYSOPT=0

syn-lowmem-impl:
	@$(MAKE) syn-vivado \
		SYN_PLL_FREQ_MHZ=200 SYN_RUN_TO=route SYN_FORCE=0 \
		SYN_IMPL_MODE=extreme SYN_IMPL_RUNS=1 SYN_JOBS=8 SYN_THREADS_PER_RUN=8 \
		SYN_SYNC_SOURCES=0 SYN_REUSE_STAGE=1 SYN_REUSE_SYNTH=1 SYN_RESET_IMPL=1 \
		SYN_REPORT_SYNTH=0 SYN_FULL_REPORTS=0 SYN_POST_ROUTE_PHYSOPT=0 \
		SYN_SWEEP_POST_ROUTE_PHYSOPT=0

syn-venv: $(SYN_VENV)/.stamp

$(SYN_VENV)/.stamp:
	@mkdir -p $(SYN_BUILD_DIR)
	$(PYTHON) -m venv $(SYN_VENV)
	@touch $@

syn-prep: syn-venv syn-stage-memory
	@mkdir -p $(SYN_FREQ_BUILD_DIR)
	$(SYN_PYTHON) $(SYN_DIR)/prep_vivado_sources.py \
		--repo-root $(PROJECT_ROOT) \
		--bender $(BENDER) \
		--bender-dir $(SYN_BENDER_DIR) \
		--wrapper-dir $(PROJECT_ROOT)/hw/ip/Xilinx_ip_wrapper/rtl \
		--itcm-init-file $(SYN_PREPROJECT_ITCM_MEM) \
		--dtcm-init-file $(SYN_PREPROJECT_DTCM_MEM) \
		--stage-sources-dir $(SYN_PREPROJECT_SOURCE_DIR) \
		$(SYN_DEFINE_ARGS) \
		--out $(SYN_SOURCES_TCL)

syn-stage-xpr:
	@test -f "$(SYN_CONSTR_DIR)/digital_twin.xdc" || { echo "Error: official XDC not found"; exit 1; }
	@test -f "$(SYN_CONSTR_DIR)/board_ag10_ah10.xdc" || { echo "Error: board XDC not found"; exit 1; }
	rm -rf "$(SYN_STAGE_FPGA_DIR)"
	@mkdir -p "$(SYN_PREPROJECT_SOURCE_DIR)" "$(SYN_PREPROJECT_CONSTR_DIR)"
	cp "$(SYN_CONSTR_DIR)/digital_twin.xdc" "$(SYN_PREPROJECT_CONSTR_DIR)/digital_twin.xdc"
	cp "$(SYN_CONSTR_DIR)/board_ag10_ah10.xdc" "$(SYN_PREPROJECT_CONSTR_DIR)/board_ag10_ah10.xdc"

syn-stage-memory: RTTHREAD_CPU_FREQ_HZ = $(SYN_PLL_FREQ_HZ)
syn-stage-memory: syn-stage-xpr rtthread-coremark-build-$(SYN_MSH_PROFILE)
	@test -f "$(SYN_MSH_ITCM)" || { echo "Error: msh ITCM image not found: $(SYN_MSH_ITCM)"; exit 1; }
	@test -f "$(SYN_MSH_DTCM)" || { echo "Error: msh DTCM image not found: $(SYN_MSH_DTCM)"; exit 1; }
	@mkdir -p "$(SYN_PREPROJECT_MEMORY_DIR)"
	$(PYTHON) "$(SYN_DIR)/prepare_memory_init.py" \
		--input "$(SYN_MSH_ITCM)" --width $(SYN_ITCM_WIDTH) --depth $(SYN_ITCM_WORDS) \
		--mem "$(SYN_PREPROJECT_ITCM_MEM)" --coe "$(SYN_PREPROJECT_ITCM_COE)"
	$(PYTHON) "$(SYN_DIR)/prepare_memory_init.py" \
		--input "$(SYN_MSH_DTCM)" --width $(SYN_DTCM_WIDTH) --depth $(SYN_DTCM_WORDS) \
		--mem "$(SYN_PREPROJECT_DTCM_MEM)" --coe "$(SYN_PREPROJECT_DTCM_COE)"
	@printf 'image=rtthread_coremark\nprofile=%s\ncpu_freq_hz=%s\nitcm_width=%s\ndtcm_width=%s\nitcm_words=%s\ndtcm_words=%s\n' \
		"$(SYN_MSH_PROFILE)" "$(RTTHREAD_CPU_FREQ_HZ)" "$(SYN_ITCM_WIDTH)" "$(SYN_DTCM_WIDTH)" "$(SYN_ITCM_WORDS)" "$(SYN_DTCM_WORDS)" \
		> "$(SYN_PREPROJECT_MEMORY_DIR)/manifest.txt"

ifeq ($(SYN_REUSE_STAGE),1)
SYN_VIVADO_PREREQS := syn-reuse-stage-check
else
SYN_VIVADO_PREREQS := syn-prep
endif

syn-reuse-stage-check:
	@test -f "$(SYN_XPR)" || { echo "Error: staged XPR not found: $(SYN_XPR)"; exit 1; }
	@test -f "$(SYN_STAGE_FPGA_DIR)/Ydrasil_FPGA.runs/synth_1/$(SYN_TOP).dcp" || { echo "Error: completed top synthesis DCP not found in staged project"; exit 1; }

syn-vivado: $(SYN_VIVADO_PREREQS)
	@mkdir -p $(SYN_REPORT_DIR) $(SYN_LOG_DIR) $(SYN_ARTIFACT_DIR)
	@if [ -n "$(VIVADO_SETTINGS)" ]; then \
		test -f "$(VIVADO_SETTINGS)" || { echo "Error: VIVADO_SETTINGS not found: $(VIVADO_SETTINGS)" >&2; exit 2; }; \
		. "$(VIVADO_SETTINGS)"; \
	fi; \
	$(VIVADO) -mode batch -nojournal -log $(SYN_LOG_DIR)/vivado.log \
		-source $(SYN_DIR)/run_vivado.tcl \
		-tclargs \
		-xpr $(SYN_XPR) \
		-part $(SYN_PART) \
		-staging_dir $(SYN_PREPROJECT_DIR) \
		-sources_tcl $(SYN_SOURCES_TCL) \
		-top $(SYN_TOP) \
		-report_dir $(SYN_REPORT_DIR) \
		-checkpoint_dir $(SYN_CHECKPOINT_DIR) \
		-artifact_dir $(SYN_ARTIFACT_DIR) \
		-jobs $(SYN_JOBS) \
		-threads_per_run $(SYN_THREADS_PER_RUN) \
		-impl_runs $(SYN_IMPL_RUNS) \
		-impl_mode $(SYN_IMPL_MODE) \
		-impl_way $(SYN_WAY) \
		-synth_strategy "$(SYN_SYNTH_STRATEGY)" \
		-run_to $(SYN_RUN_TO) \
		-sync_sources $(SYN_SYNC_SOURCES) \
		-reuse_synth $(SYN_REUSE_SYNTH) \
		-reset_impl $(SYN_RESET_IMPL) \
		-report_synth $(SYN_REPORT_SYNTH) \
		-pll_freq_mhz $(SYN_PLL_FREQ_MHZ) \
		-board_xdc "$(SYN_BOARD_XDC)" \
		-replace_constraints $(SYN_REPLACE_CONSTRAINTS) \
		-enable_ila $(SYN_ENABLE_ILA) \
		-itcm_mem "$(SYN_STAGED_ITCM_MEM)" \
		-dtcm_mem "$(SYN_STAGED_DTCM_MEM)" \
		-timing_summary_max_paths $(SYN_TIMING_SUMMARY_MAX_PATHS) \
		-timing_path_max_paths $(SYN_TIMING_PATH_MAX_PATHS) \
		-timing_nworst $(SYN_TIMING_NWORST) \
		-full_reports $(SYN_FULL_REPORTS) \
		-post_route_physopt $(SYN_POST_ROUTE_PHYSOPT) \
		-sweep_post_route_physopt $(SYN_SWEEP_POST_ROUTE_PHYSOPT) \
		-force $(SYN_FORCE)

syn-analyze: syn-venv
	$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py \
		--report-dir $(SYN_REPORT_DIR) \
		--violation-report $(SYN_REPORT_DIR)/post_route_timing_violations.rpt
	@if [ -f "$(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_violations.rpt" ]; then \
		$(SYN_PYTHON) $(SYN_DIR)/analyze_timing.py \
			--report-dir $(SYN_REPORT_DIR) \
				--timing-report $(SYN_REPORT_DIR)/post_route_timing_summary.rpt \
				--violation-report $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_violations.rpt \
				--path-group cpu_clk_mmcm \
			--csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_groups.csv \
			--paths-csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_paths.csv \
			--violations-csv $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_violations.csv \
			--md $(SYN_REPORT_DIR)/cpu$(subst .,p,$(SYN_PLL_FREQ_MHZ))_timing_groups.md; \
	fi

syn-clean:
	rm -rf $(SYN_BUILD_DIR)

# -----------------------------------------------------------------------------
# Architecture quick-checks
# -----------------------------------------------------------------------------

rtl-quickcheck: rtl-strict rtl-structure vivado-ooc

rtl-strict: $(RTL_QC_FLIST)
	@mkdir -p "$(RTL_QC_DIR)"
	@echo "[RTL] Verilator strict lint: top=$(RTL_QC_TOP)"
	$(VERILATOR_STRICT) $(VERILATOR_STRICT_FLAGS) $(addprefix -Wno-,$(VERILATOR_STRICT_WNO)) \
		--top-module "$(RTL_QC_TOP)" -f "$(RTL_QC_FLIST)" \
		>"$(RTL_QC_DIR)/verilator-strict.log" 2>&1

rtl-xml: $(RTL_QC_FLIST)
	@mkdir -p "$(RTL_QC_TREE_DIR)"
	@echo "[RTL] Verilator elaboration tree: top=$(RTL_QC_TOP)"
	@set +e; $(VERILATOR_STRICT) $(VERILATOR_XML_FLAGS) --top-module "$(RTL_QC_TOP)" \
		-f "$(RTL_QC_FLIST)" --Mdir "$(RTL_QC_TREE_DIR)" \
		>"$(RTL_QC_DIR)/verilator-tree.log" 2>&1; rc=$$?; \
		final=$$(find "$(RTL_QC_TREE_DIR)" -type f -name '*_990_final.tree.json' -print -quit); \
		module_count=$$(grep -Eo '"type"[[:space:]]*:[[:space:]]*"MODULE"' "$$final" 2>/dev/null | wc -l); \
		if [ -n "$$final" ] && [ "$$module_count" -lt 10 ]; then \
			for candidate in $$(find "$(RTL_QC_TREE_DIR)" -type f -name 'V*.tree.json' | sort -Vr); do \
				module_count=$$(grep -Eo '"type"[[:space:]]*:[[:space:]]*"MODULE"' "$$candidate" 2>/dev/null | wc -l); \
				if [ "$$module_count" -ge 10 ]; then final="$$candidate"; break; fi; \
			done; \
		fi; \
		if [ -z "$$final" ]; then echo "Verilator did not produce a tree JSON (rc=$$rc)" >&2; exit $$rc; fi; \
		cp "$$final" "$(RTL_QC_TREE_JSON)"; \
		echo "[RTL] tree JSON: $(RTL_QC_TREE_JSON)"; exit 0

rtl-structure-report: rtl-xml
	@echo "[RTL] structure timing policy: fre=$(RTL_QC_FREQ_MHZ)MHz warning=$(RTL_QC_WARNING_PERIOD_NS)ns target=$(RTL_QC_TARGET_PERIOD_NS)ns weighted-limit=$(RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT) bram-penalty=$(RTL_QC_BRAM_LAUNCH_PENALTY_DEPTH)"
	$(PYTHON) "$(SYN_DIR)/analyze_rtl_structure.py" \
		--input "$(RTL_QC_TREE_JSON)" --output "$(RTL_QC_STRUCTURE_JSON)" --top "$(RTL_QC_TOP)" \
		--source-metadata "$(RTL_QC_METADATA)" \
		--calibration-history "$(RTL_QC_CALIBRATION_HISTORY)" \
		--target-period-ns "$(RTL_QC_TARGET_PERIOD_NS)" \
		--warning-period-ns "$(RTL_QC_WARNING_PERIOD_NS)" \
		--timing-possible-depth "$(RTL_QC_TIMING_POSSIBLE_DEPTH)" \
		--timing-definite-depth "$(RTL_QC_TIMING_DEFINITE_DEPTH)" \
		--timing-path-weighted-violation-limit "$(RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT)" \
		--lutram-possible-depth "$(RTL_QC_LUTRAM_POSSIBLE_DEPTH)" \
		--fanout-timing-min-depth "$(RTL_QC_FANOUT_TIMING_MIN_DEPTH)" \
		--bram-launch-penalty-depth "$(RTL_QC_BRAM_LAUNCH_PENALTY_DEPTH)" \
		--bram-clock-to-out-ns "$(RTL_QC_BRAM_CLOCK_TO_OUT_NS)" \
		--lutram-arc-ns "$(RTL_QC_LUTRAM_ARC_NS)"

rtl-structure: rtl-structure-report
	$(PYTHON) "$(SYN_DIR)/analyze_rtl_structure.py" \
		--check-output "$(RTL_QC_STRUCTURE_JSON)"

rtl-vivado-compare: rtl-structure-report
	@test -f "$(RTL_QC_VIVADO_UTILIZATION)" || { echo "Vivado utilization report not found: $(RTL_QC_VIVADO_UTILIZATION)" >&2; exit 2; }
	$(PYTHON) "$(SYN_DIR)/compare_rtl_vivado.py" \
		--structure "$(RTL_QC_STRUCTURE_JSON)" \
		--utilization "$(RTL_QC_VIVADO_UTILIZATION)" \
		--timing "$(RTL_QC_VIVADO_TIMING)" \
		--timing "$(RTL_QC_VIVADO_POST_ROUTE_TIMING)" \
		$(if $(wildcard $(RTL_QC_VIVADO_TIMING_PATHS_CSV)),--timing-csv "$(RTL_QC_VIVADO_TIMING_PATHS_CSV)",) \
		--route-dominated-fraction "$(RTL_QC_ROUTE_DOMINATED_FRACTION)" \
		--history-root "$(RTL_QC_CALIBRATION_HISTORY)" \
		--output "$(RTL_QC_VIVADO_COMPARE_JSON)" \
		--summary-output "$(RTL_QC_RELIABILITY_SUMMARY)"

rtl-vivado-cross-validate:
	$(PYTHON) "$(RTL_QC_CROSS_VALIDATE_SCRIPT)" \
		--archive-root "$(RTL_QC_CALIBRATION_HISTORY)" \
		--target-period-ns "$(RTL_QC_TARGET_PERIOD_NS)" \
		--warning-period-ns "$(RTL_QC_WARNING_PERIOD_NS)" \
		--definite-depth "$(RTL_QC_TIMING_DEFINITE_DEPTH)" \
		--min-aggregate-path-recall "$(RTL_QC_CV_MIN_AGGREGATE_PATH_RECALL)" \
		--min-aggregate-family-recall "$(RTL_QC_CV_MIN_AGGREGATE_FAMILY_RECALL)" \
		--min-holdout-path-recall "$(RTL_QC_CV_MIN_HOLDOUT_PATH_RECALL)" \
		--min-holdout-scored-paths "$(RTL_QC_CV_MIN_HOLDOUT_SCORED_PATHS)" \
		--min-error-precision "$(RTL_QC_CV_MIN_ERROR_PRECISION)" \
		--min-error-true-families "$(RTL_QC_CV_MIN_ERROR_TRUE_FAMILIES)" \
		--output "$(RTL_QC_CROSS_VALIDATE_JSON)" \
		--summary-output "$(RTL_QC_CROSS_VALIDATE_SUMMARY)"

rtl-vivado-archive: rtl-vivado-compare
	$(PYTHON) "$(RTL_QC_ARCHIVE_SCRIPT)" \
		--repo-root "$(PROJECT_ROOT)" \
		--build-root "$(BUILD_DIR)" \
		--frequency-mhz "$(RTL_QC_FREQ_MHZ)" \
		--archive-dir "$(RTL_QC_CALIBRATION_DIR)" \
		--reports "$(RTL_QC_VIVADO_REPORT_DIR)" \
		--structure "$(RTL_QC_STRUCTURE_JSON)" \
		--source-metadata "$(RTL_QC_METADATA)" \
		--filelist "$(RTL_QC_FLIST)" \
		--comparison "$(RTL_QC_VIVADO_COMPARE_JSON)" \
		--summary "$(RTL_QC_RELIABILITY_SUMMARY)"

verilator-strict: rtl-strict
verilator-xml: rtl-xml
slang-ast: rtl-structure

$(RTL_QC_FLIST): $(PROJECT_ROOT)/Makefile $(PROJECT_ROOT)/config.mk $(SYN_DIR)/prepare_rtl_sources.py $(RTL_QC_SOURCE_DEPS)
	$(PYTHON) "$(SYN_DIR)/prepare_rtl_sources.py" \
		--repo-root "$(PROJECT_ROOT)" --bender "$(BENDER)" \
		--bender-dir "$(RTL_QC_BENDER_DIR)" \
		$(foreach target,$(RTL_QC_BENDER_TARGETS),--target "$(target)") \
		$(foreach define,$(RTL_QC_DEFINES),--define "$(define)") \
		--wrapper-dir "$(RTL_QC_WRAPPER_DIR)" --out "$@" \
		--metadata "$(RTL_QC_METADATA)"

yosys-slang: $(YOSYS_SCRIPT)
	@command -v "$(YOSYS)" >/dev/null 2>&1 || { echo "Error: YOSYS=$(YOSYS) not found" >&2; exit 127; }
	@mkdir -p "$(YOSYS_DIR)"
	@echo "[YOSYS-SLANG] top=$(YOSYS_TOP) family=$(YOSYS_FAMILY)"
	@set -o pipefail; "$(YOSYS)" -s "$(YOSYS_SCRIPT)" 2>&1 | tee "$(YOSYS_LOG)"
	$(PYTHON) "$(SYN_DIR)/extract_yosys_stats.py" --log "$(YOSYS_LOG)" \
		--output "$(YOSYS_STAT_JSON)" --top "$(YOSYS_TOP)"

yosys-slang-quick: yosys-slang

yosys-slang-gate: yosys-slang
	@if [ -z "$(YOSYS_BASELINE_STAT)" ]; then \
		echo "[YOSYS-SLANG] no YOSYS_BASELINE_STAT supplied; relative gate skipped"; \
	else \
		$(PYTHON) "$(SYN_DIR)/compare_yosys_stats.py" \
			--baseline "$(YOSYS_BASELINE_STAT)" --candidate "$(YOSYS_STAT_JSON)" \
			--top "$(YOSYS_TOP)" \
			--lut-limit "$(YOSYS_LUT_GROWTH_LIMIT_PERCENT)" \
			--ltp-limit "$(YOSYS_LTP_GROWTH_LIMIT_PERCENT)"; \
	fi

yosys-slang-baseline: yosys-slang
	@test -n "$(YOSYS_BASELINE_STAT)" || { echo "Set YOSYS_BASELINE_STAT=/path/to/base/stat.json" >&2; exit 2; }
	mkdir -p "$$(dirname "$(YOSYS_BASELINE_STAT)")"
	cp "$(YOSYS_STAT_JSON)" "$(YOSYS_BASELINE_STAT)"

$(YOSYS_FLIST): $(PROJECT_ROOT)/Makefile $(PROJECT_ROOT)/config.mk $(SYN_DIR)/prepare_rtl_sources.py $(RTL_QC_SOURCE_DEPS)
	$(PYTHON) "$(SYN_DIR)/prepare_rtl_sources.py" \
		--repo-root "$(PROJECT_ROOT)" --bender "$(BENDER)" \
		--bender-dir "$(YOSYS_BENDER_DIR)" \
		$(foreach target,$(YOSYS_BENDER_TARGETS),--target "$(target)") \
		$(foreach define,$(YOSYS_DEFINES),--define "$(define)") \
		$(if $(filter 1,$(YOSYS_WITH_WRAPPERS)),--with-wrappers,) \
		--wrapper-dir "$(RTL_QC_WRAPPER_DIR)" --out "$@" --metadata "$(YOSYS_METADATA)"

$(YOSYS_SCRIPT): $(PROJECT_ROOT)/Makefile $(PROJECT_ROOT)/config.mk $(SYN_DIR)/prepare_yosys_slang.py $(YOSYS_FLIST)
	$(PYTHON) "$(SYN_DIR)/prepare_yosys_slang.py" \
		--flist "$(YOSYS_FLIST)" --top "$(YOSYS_TOP)" --family "$(YOSYS_FAMILY)" --run "$(YOSYS_RUN)" \
		--out "$@" --stat-json "$(YOSYS_STAT_JSON)" --netlist-json "$(YOSYS_NETLIST_JSON)"

vivado-ooc: $(VIVADO_OOC_FLIST)
	@command -v "$(VIVADO_OOC)" >/dev/null 2>&1 || { echo "Error: VIVADO_OOC=$(VIVADO_OOC) not found" >&2; exit 127; }
	@mkdir -p "$(VIVADO_OOC_DIR)"
	@echo "[VIVADO-OOC] top=$(VIVADO_OOC_TOP) part=$(VIVADO_OOC_PART) (no pins/XDC)"
	@if [ -n "$(VIVADO_OOC_SETTINGS)" ] && [ -f "$(VIVADO_OOC_SETTINGS)" ]; then \
		. "$(VIVADO_OOC_SETTINGS)"; \
		"$(VIVADO_OOC)" -mode batch -nojournal -nolog -source "$(SYN_DIR)/run_vivado_ooc.tcl" \
			-tclargs -flist "$(VIVADO_OOC_FLIST)" -top "$(VIVADO_OOC_TOP)" \
			-part "$(VIVADO_OOC_PART)" -out_dir "$(VIVADO_OOC_DIR)" \
			-period_ns "$(VIVADO_OOC_PERIOD_NS)" -synth_directive "$(VIVADO_OOC_SYNTH_DIRECTIVE)" \
			>"$(VIVADO_OOC_LOG)" 2>&1; \
	else \
		"$(VIVADO_OOC)" -mode batch -nojournal -nolog -source "$(SYN_DIR)/run_vivado_ooc.tcl" \
			-tclargs -flist "$(VIVADO_OOC_FLIST)" -top "$(VIVADO_OOC_TOP)" \
			-part "$(VIVADO_OOC_PART)" -out_dir "$(VIVADO_OOC_DIR)" \
			-period_ns "$(VIVADO_OOC_PERIOD_NS)" -synth_directive "$(VIVADO_OOC_SYNTH_DIRECTIVE)" \
			>"$(VIVADO_OOC_LOG)" 2>&1; \
	fi
	@tail -20 "$(VIVADO_OOC_LOG)"

vivado-ooc-synth: vivado-ooc

# Run the current issue pipeline one top at a time.  Recursive invocations are
# deliberate: each one gets its own generated file list and Vivado output
# directory, so reports and checkpoints cannot overwrite another module.
vivado-ooc-issue:
	@test -n "$(VIVADO_OOC_ISSUE_MODULES)" || { echo "VIVADO_OOC_ISSUE_MODULES is empty" >&2; exit 2; }
	@set -e; for module in $(VIVADO_OOC_ISSUE_MODULES); do \
		echo "[VIVADO-OOC] issue module=$$module output=$(VIVADO_OOC_ISSUE_DIR)/$$module"; \
		$(MAKE) --no-print-directory vivado-ooc \
			VIVADO_OOC_TOP="$$module" \
			VIVADO_OOC_DIR="$(VIVADO_OOC_ISSUE_DIR)/$$module"; \
	done

$(VIVADO_OOC_FLIST): $(PROJECT_ROOT)/Makefile $(PROJECT_ROOT)/config.mk $(SYN_DIR)/prepare_rtl_sources.py $(RTL_QC_SOURCE_DEPS)
	$(PYTHON) "$(SYN_DIR)/prepare_rtl_sources.py" \
		--repo-root "$(PROJECT_ROOT)" --bender "$(BENDER)" \
		--bender-dir "$(YOSYS_BENDER_DIR)" \
		$(foreach target,$(YOSYS_BENDER_TARGETS),--target "$(target)") \
		$(foreach define,$(VIVADO_OOC_DEFINES),--define "$(define)") \
		$(if $(filter 1,$(VIVADO_OOC_WITH_WRAPPERS)),--with-wrappers,) \
		--wrapper-dir "$(RTL_QC_WRAPPER_DIR)" --out "$@" --metadata "$(VIVADO_OOC_METADATA)"


# Set to 0 for RTL-only setup. Software build targets still require the
# repository RISC-V toolchain when they are invoked.
INIT_INSTALL_RISCV_TOOLCHAIN ?= 1
INIT_TOOLS := $(TOOLS)
ifeq ($(INIT_INSTALL_RISCV_TOOLCHAIN),0)
INIT_TOOLS := $(filter-out $(RISCV_TOOLCHAIN_PACKAGES),$(INIT_TOOLS))
endif

init:
	@$(MAKE) check_deps TOOLS="$(INIT_TOOLS)"
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
		ABI=$(ABI) \
		CONTROL_FLOW_ALIGN_CFLAGS="$(COREMARK_SWOPT_ALIGN_CFLAGS)"
COREMARK_SW_PROFILE_ARGS = \
		BSP_LINKER_SCRIPT="$(COREMARK_LINKER)" \
		COREMARK_EXTRA_CFLAGS="$(COREMARK_BSP_CFLAGS)" \
		COREMARK_APP_ONLY_CFLAGS="$(COREMARK_APP_CFLAGS)" \
		COREMARK_FLAGS_STR="$(COREMARK_PROFILE)"
SORT_APP_SW_MAKE_ARGS = \
		PROJECT_ROOT=$(PROJECT_ROOT) \
		RISCV_PREFIX=$(RISCV_PREFIX) \
		ARCH=rv32im_zicsr_zifencei \
		ABI=$(ABI)
BOUNDARY_APP_SW_MAKE_ARGS = $(COREMARK_SW_MAKE_ARGS)
BOUNDARY_APP_SW_MAKE_ARGS += BOUNDARY_EXTRA_CFLAGS="$(BOUNDARY_EXTRA_CFLAGS)"
COREMARK_RESULT_LOG ?= $(HW_TRACE_OUT_DIR)/coremark/hw.log
COREMARK_SIM_COMPARE ?= csv
COREMARK_DIFF_STOP_SYMBOL ?= stop_time

coremark_swopt_show:
	@printf 'COREMARK_SWOPT_AVAILABLE_GROUPS=%s\n' '$(COREMARK_SWOPT_AVAILABLE_GROUPS)'
	@printf 'COREMARK_SWOPT_GROUPS=%s\n' '$(COREMARK_SWOPT_GROUPS)'
	@printf 'COREMARK_SWOPT_ALIGN_BYTES=%s\n' '$(COREMARK_SWOPT_ALIGN_BYTES)'
	@printf 'COREMARK_OPT_APP_CFLAGS_O3_app_unroll=%s\n' '$(COREMARK_OPT_APP_CFLAGS_O3_app_unroll)'
COREMARK_DIFF_STOP_PC = $(shell $(NM) -n "$(BUILD_DIR)/app/coremark/coremark.elf" 2>/dev/null | awk '$$3 == "$(COREMARK_DIFF_STOP_SYMBOL)" { print "0x" $$1; exit }')
COMPARE_TRACE_DEFINES = $(if $(filter none,$(SIM_COMPARE)),,$(if $(findstring +commit_trace,$(COMPARE_SIM_EXTRA_DEFINES)),,+commit_trace))
COMPARE_SIM_DEFINES = $(strip $(COMPARE_SIM_EXTRA_DEFINES) $(COMPARE_TRACE_DEFINES))

coremark: $(COREMARK_LINKER)
	@$(MAKE) -C sw coremark-clean-all $(COREMARK_SW_MAKE_ARGS) $(COREMARK_SW_PROFILE_ARGS)
	@$(MAKE) -C sw coremark $(COREMARK_SW_MAKE_ARGS) $(COREMARK_SW_PROFILE_ARGS)

coremark-rebuild: coremark

rtthread:
	@$(MAKE) --no-print-directory -C sw rtthread \
		RTTHREAD_CPU_FREQ_HZ="$(RTTHREAD_CPU_FREQ_HZ)"

rtthread-build:
	@$(MAKE) --no-print-directory -C sw rtthread-build \
		RTTHREAD_CPU_FREQ_HZ="$(RTTHREAD_CPU_FREQ_HZ)"

rtthread-clean:
	@$(MAKE) --no-print-directory -C sw rtthread-clean

rtthread-coremark:
	@$(MAKE) --no-print-directory -C sw rtthread-coremark \
		RTTHREAD_CPU_FREQ_HZ="$(RTTHREAD_CPU_FREQ_HZ)"

rtthread-coremark-build:
	@$(MAKE) --no-print-directory -C sw rtthread-coremark-build \
		RTTHREAD_CPU_FREQ_HZ="$(RTTHREAD_CPU_FREQ_HZ)"

rtthread-coremark-build-all: rtthread-coremark-build

rtthread-coremark-sim:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread coremark-sim

rtthread-coremark-sim-all: rtthread-coremark-sim

rtthread-coremark-sim-%:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread coremark-sim-$*

rtthread-coremark-report:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread coremark-report \
		COREMARK_PPA_LOG="$(PPA_COREMARK_OPT_LOG)"

rtthread-coremark-compare:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread coremark-compare \
		COREMARK_PPA_LOG="$(PPA_COREMARK_OPT_LOG)"

rtthread-coremark-clean:
	@$(MAKE) --no-print-directory -C sw rtthread-coremark-clean

rtthread-utest:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread utest

rtthread-utest-build:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread utest-build

rtthread-utest-sim:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread utest-sim

rtthread-utest-report:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread utest-report

rtthread-utest-clean:
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread utest-clean

define RTTHREAD_COREMARK_PROFILE_template
rtthread-coremark-build-$(1):
	@$(MAKE) --no-print-directory -C sw rtthread-coremark-build-$(1) \
		RTTHREAD_CPU_FREQ_HZ="$$(RTTHREAD_CPU_FREQ_HZ)"

rtthread-coremark-sim-$(1):
	@$(MAKE) --no-print-directory -C sw/bsp/rtthread coremark-sim-$(1)
endef
$(foreach profile,$(RTTHREAD_COREMARK_PROFILES),$(eval $(call RTTHREAD_COREMARK_PROFILE_template,$(profile))))

coremark_sim: coremark
	@if [ "$(COREMARK_SIM_COMPARE)" != "none" ] && [ -z "$(COREMARK_DIFF_STOP_PC)" ]; then \
		echo "Unable to resolve CoreMark diff stop symbol: $(COREMARK_DIFF_STOP_SYMBOL)"; exit 2; \
	fi
	@$(MAKE) comp VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) VERILATOR_TRACE=0 \
		VERILATOR_IGNORE_FULL=$(COREMARK_VERILATOR_IGNORE_FULL) \
		OBJ_DIR="$(COREMARK_SIM_OBJ_DIR)" LOG_DIR="$(COREMARK_SIM_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(COREMARK_SIM_ITCM_ADDR_WIDTH)
	@set +e; \
	rm -f $(COREMARK_RESULT_LOG); \
	$(MAKE) sim_compare \
		COMPARE_NAME=coremark \
		COMPARE_ELF=$(BUILD_DIR)/app/coremark/coremark.elf \
		COMPARE_ITCM=$(BUILD_DIR)/app/coremark/coremark.itcm \
		COMPARE_DTCM=$(BUILD_DIR)/app/coremark/coremark.dtcm \
		SIM_COMPARE=$(COREMARK_SIM_COMPARE) \
		COMPARE_COMPLETE_PROGRAM=1 \
		COMPARE_TRACE_STOP_PC=$(COREMARK_DIFF_STOP_PC) \
		COMPARE_SIM_EXTRA_DEFINES="+no_finish_on_tohost +cpp_timeout=$(COREMARK_SIM_TIMEOUT) +sv_timeout=$(COREMARK_SIM_TIMEOUT)" \
		VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) \
		OBJ_DIR="$(COREMARK_SIM_OBJ_DIR)" LOG_DIR="$(COREMARK_SIM_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(COREMARK_SIM_ITCM_ADDR_WIDTH); \
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
		echo "[COREMARK OPT][$$$$profile] base ITCM capacity exceeded; rebuilding for $(APP_OPT_EXPANDED_ITCM_KIB) KiB simulation only"; set +e; \
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
	echo "STATE=$$$$state ITCM_BYTES=$$$$bytes ITCM_CAPACITY_BYTES=$$$$capacity EXPANDED_ITCM=$$$$expanded FLAGS=$(COREMARK_OPT_APP_CFLAGS_$(1))" | tee "$$$$out/build.status"

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
		COMPARE_SIM_EXTRA_DEFINES="+no_finish_on_tohost +cpp_timeout=$(if $(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT)) +sv_timeout=$(if $(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT_$(1)),$(COREMARK_OPT_TIMEOUT))" \
		$$$$model_args \
		>"$$$$run_log" 2>&1; rc=$$$$?; set -e; hw_log="$(HW_TRACE_OUT_DIR)/coremark-opt/$$$$profile/hw.log"; \
	result=FAIL; if [ "$$$$rc" -eq 0 ] && grep -q 'Correct operation validated' "$$$$hw_log" && \
		grep -q 'COREMARK DONE' "$$$$hw_log"; then result=PASS; fi; \
	cycles=$$$$(sed -n 's/^PERF_METRIC:.*CYCLES= *\([0-9]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	insts=$$$$(sed -n 's/^PERF_METRIC:.*INSTS= *\([0-9]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	ipc=$$$$(sed -n 's/^PERF_METRIC:.*IPC= *\([0-9.]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	score=$$$$(sed -n 's/^CoreMark 1\.0 : *\([0-9.]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	echo "[$$$$profile] [$$$$result] itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded cycles=$$$${cycles:-N/A} insts=$$$${insts:-N/A} ipc=$$$${ipc:-N/A} score=$$$${score:-N/A}" > "$$$$status"
endef
$(foreach profile,$(APP_OPT_PROFILES),$(eval $(call COREMARK_OPT_template,$(profile))))

coremark_opt_report:
	@mkdir -p "$(PPA_DIR)"; rm -f "$(PPA_COREMARK_OPT_LOG)"; failed=0; pass=0; skip=0; expanded_count=0; \
	for profile in $(APP_OPT_PROFILES); do status="$(COREMARK_OPT_RESULT_DIR)/$$profile.status"; \
		if [ ! -f "$$status" ]; then echo "[$$profile] [FAIL] missing status" | tee -a "$(PPA_COREMARK_OPT_LOG)"; failed=1; continue; fi; \
		line=$$(cat "$$status"); hw_log="$(HW_TRACE_OUT_DIR)/coremark-opt/$$profile/hw.log"; \
		if echo "$$line" | grep -q '\[PASS\]'; then \
			cycles=$$(sed -n 's/^PERF_METRIC:.*CYCLES= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
			insts=$$(sed -n 's/^PERF_METRIC:.*INSTS= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
			ipc=$$(sed -n 's/^PERF_METRIC:.*IPC= *\([0-9.]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
			if [ -n "$$cycles" ] && [ -n "$$insts" ] && [ -n "$$ipc" ]; then \
				line=$$(printf '%s\n' "$$line" | sed -E "s/cycles=[^ ]+ insts=[^ ]+ ipc=[^ ]+/cycles=$$cycles insts=$$insts ipc=$$ipc/"); \
			fi; \
		fi; \
		if ! echo "$$line" | grep -q ' score='; then \
			score=$$(sed -n 's/^CoreMark 1\.0 : *\([0-9.]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
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
	cycles=$$(sed -n 's/^PERF_METRIC:.*CYCLES= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	insts=$$(sed -n 's/^PERF_METRIC:.*INSTS= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	ipc=$$(sed -n 's/^PERF_METRIC:.*IPC= *\([0-9.]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	[ -n "$$cycles" ] || cycles=N/A; \
	[ -n "$$insts" ] || insts=N/A; \
	[ -n "$$ipc" ] || ipc=N/A; \
	echo "[$$name] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [$$result]" > "$$status"

sort_report:
	@mkdir -p "$(VERIF_STATS_DIR)"; \
	rm -f "$(VERIF_SORT_LOG)"; \
	failed=0; \
	for status in $$(find "$(SORT_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | sort); do \
		line=$$(cat "$$status"); \
		echo "$$line" | tee -a "$(VERIF_SORT_LOG)"; \
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
	echo "[VERIF] Sort report: $(VERIF_SORT_LOG)"; \
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
		echo "[SORT OPT][$$$$profile/$$$$name] base ITCM capacity exceeded; rebuilding for $(APP_OPT_EXPANDED_ITCM_KIB) KiB simulation only"; set +e; \
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
	cycles=$$$$(sed -n 's/^PERF_METRIC:.*CYCLES= *\([0-9]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	insts=$$$$(sed -n 's/^PERF_METRIC:.*INSTS= *\([0-9]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	ipc=$$$$(sed -n 's/^PERF_METRIC:.*IPC= *\([0-9.]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	echo "[$$$$profile/$$$$name] [$$$$result] itcm_bytes=$$$$bytes itcm_capacity=$$$$capacity expanded_itcm=$$$$expanded cycles=$$$${cycles:-N/A} insts=$$$${insts:-N/A} ipc=$$$${ipc:-N/A}" > "$$$$status"
endef
$(foreach profile,$(APP_OPT_PROFILES),$(foreach app,$(SORT_APP_NAMES),$(eval $(call SORT_OPT_template,$(profile),$(app)))))

sort_opt_report:
	@mkdir -p "$(VERIF_STATS_DIR)"; rm -f "$(VERIF_SORT_OPT_LOG)"; failed=0; pass=0; skip=0; expanded_count=0; total=$(words $(SORT_OPT_SIM_TARGETS)); \
	for profile in $(APP_OPT_PROFILES); do for name in $(SORT_APP_NAMES); do status="$(SORT_OPT_RESULT_DIR)/$$profile/$$name.status"; \
		if [ ! -f "$$status" ]; then echo "[$$profile/$$name] [FAIL] missing status" | tee -a "$(VERIF_SORT_OPT_LOG)"; failed=1; continue; fi; \
		line=$$(cat "$$status"); echo "$$line" | tee -a "$(VERIF_SORT_OPT_LOG)"; \
		if echo "$$line" | grep -q 'expanded_itcm=YES'; then expanded_count=$$((expanded_count+1)); fi; \
		if echo "$$line" | grep -q '\[PASS\]'; then pass=$$((pass+1)); elif echo "$$line" | grep -q '\[SKIP\]'; then skip=$$((skip+1)); else failed=1; fi; \
	done; done; overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[SORT OPT] ITCM original=$(APP_OPT_ITCM_BYTES) expanded=$(APP_OPT_EXPANDED_ITCM_BYTES) expanded_runs=$$expanded_count" | tee -a "$(VERIF_SORT_OPT_LOG)"; \
	echo "[SORT OPT] CORRECTNESS=$$overall passed=$$pass skipped=$$skip total=$$total" | tee -a "$(VERIF_SORT_OPT_LOG)"; exit $$failed

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
	if $(MAKE) --no-print-directory sim_compare SIM_COMPARE=none COMPARE_NAME="boundary/$$name" COMPARE_ELF="$(BUILD_DIR)/app/boundary/$$name.elf" COMPARE_ITCM="$(BUILD_DIR)/app/boundary/$$name.itcm" COMPARE_DTCM="$(BUILD_DIR)/app/boundary/$$name.dtcm" COMPARE_SIM_EXTRA_DEFINES="+no_finish_on_tohost +perip_debug +cpp_timeout=$(BOUNDARY_SIM_TIMEOUT) +sv_timeout=$(BOUNDARY_SIM_TIMEOUT)" >"$$run_log" 2>&1 && grep -q "BOUNDARY PASS name=$$name" "$$hw_log"; then result=PASS; else result=FAIL; fi; \
	echo "[$$name] [$$result]" > "$$status"

boundary_report:
	@mkdir -p "$(VERIF_STATS_DIR)"; rm -f "$(VERIF_BOUNDARY_LOG)"; failed=0; \
	for status in $$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | sort); do line=$$(cat "$$status"); echo "$$line" | tee -a "$(VERIF_BOUNDARY_LOG)"; if echo "$$line" | grep -q '\[FAIL\]'; then failed=1; name=$$(basename "$$status" .status); tail -40 "$(BOUNDARY_RESULT_DIR)/$$name.log"; fi; done; \
	count=$$(find "$(BOUNDARY_RESULT_DIR)" -maxdepth 1 -name '*.status' -type f | wc -l); \
	if [ "$$count" -ne "$(words $(BOUNDARY_APP_NAMES))" ]; then echo "[BOUNDARY] Missing status files: expected $(words $(BOUNDARY_APP_NAMES)), got $$count"; failed=1; fi; \
	echo "[VERIF] Boundary report: $(VERIF_BOUNDARY_LOG)"; exit $$failed

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
		COMPARE_SIM_EXTRA_DEFINES="+no_finish_on_tohost +perip_debug +cpp_timeout=$(BOUNDARY_SIM_TIMEOUT) +sv_timeout=$(BOUNDARY_SIM_TIMEOUT)" \
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
	@mkdir -p "$(VERIF_STATS_DIR)"; rm -f "$(VERIF_BOUNDARY_OPT_LOG)"; failed=0; total_pass=0; total_partial=0; \
	echo "[BOUNDARY OPT] Correctness matrix: $(words $(BOUNDARY_OPT_PROFILES)) profiles x $(words $(BOUNDARY_APP_NAMES)) apps" | tee -a "$(VERIF_BOUNDARY_OPT_LOG)"; \
	echo "[BOUNDARY OPT] Correctness method: program self-check + testbench assertions + complete-program Spike commit differential" | tee -a "$(VERIF_BOUNDARY_OPT_LOG)"; \
	for profile in $(BOUNDARY_OPT_PROFILES); do \
		for status in $$(find "$(BOUNDARY_OPT_RESULT_DIR)/$$profile" -maxdepth 1 -name '*.status' -type f 2>/dev/null | sort); do \
			line=$$(cat "$$status"); echo "$$line" | tee -a "$(VERIF_BOUNDARY_OPT_LOG)"; \
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
		echo "[BOUNDARY OPT][$$profile] CORRECTNESS=$$result passed=$$pass partial=$$partial failed=$$fail total=$(words $(BOUNDARY_APP_NAMES)) $$flags" | tee -a "$(VERIF_BOUNDARY_OPT_LOG)"; \
	done; \
	overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; elif [ "$$total_partial" -ne 0 ]; then overall=PARTIAL; fi; \
	echo "[BOUNDARY OPT] CORRECTNESS=$$overall passed=$$total_pass partial=$$total_partial total=$(words $(BOUNDARY_OPT_SIM_TARGETS))" | tee -a "$(VERIF_BOUNDARY_OPT_LOG)"; \
	echo "[VERIF] Boundary optimization report: $(VERIF_BOUNDARY_OPT_LOG)"; exit $$failed

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
			if (line ~ /^(PERF_METRIC:|PERF_APB_STDOUT_ACCOUNT:|PERF_SLOT_ACCOUNT:|PERF_EX_SLOT_STATE:|PERF_EX_EMPTY_CAUSE:|PERF_SLOT_REASON:|PERF_SLOT_LEAF:|PERF_SLOT_LOSS:|PERF_NOIF_SLOT_DETAIL:|PERF_ISSUE_SLOT_DETAIL:|PERF_SINGLE_BUNDLE_DETAIL:|PERF_SELECT_REFILL_DETAIL:|PERF_RS_DEPENDENCY_DETAIL2:|PERF_SINGLE_BUNDLE_OP:|PERF_SELECT_REFILL_SHAPE:|PERF_RS_DEPENDENCY_WAKE:|PERF_RS_DEPENDENCY_OP:|PERF_BANK_BLOCK_DETAIL:|PERF_P0_FULL_DETAIL:|PERF_CONTROL_DECOUPLE:|PERF_LOCAL_CONTROL:|PERF_WAKEUP:|PERF_ROB_OCCUPANCY:|PERF_RS_OCCUPANCY:|PERF_PIPE_FLOW:|PERF_ROB_HEAD_STATE:|PERF_BACKEND_LOSS:|PERF_OTHER_SLOT_DETAIL:|PERF_SELECT_CANDIDATES:|PERF_LSU_STB:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:)/) { \
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
			if grep -Eq '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_METRIC:|PERF_APB_STDOUT_ACCOUNT:|PERF_SLOT_ACCOUNT:|PERF_EX_SLOT_STATE:|PERF_EX_EMPTY_CAUSE:|PERF_SLOT_REASON:|PERF_SLOT_LEAF:|PERF_SLOT_LOSS:|PERF_NOIF_SLOT_DETAIL:|PERF_ISSUE_SLOT_DETAIL:|PERF_SINGLE_BUNDLE_DETAIL:|PERF_SELECT_REFILL_DETAIL:|PERF_RS_DEPENDENCY_DETAIL2:|PERF_SINGLE_BUNDLE_OP:|PERF_SELECT_REFILL_SHAPE:|PERF_RS_DEPENDENCY_WAKE:|PERF_RS_DEPENDENCY_OP:|PERF_BANK_BLOCK_DETAIL:|PERF_P0_FULL_DETAIL:|PERF_CONTROL_DECOUPLE:|PERF_LOCAL_CONTROL:|PERF_WAKEUP:|PERF_ROB_OCCUPANCY:|PERF_RS_OCCUPANCY:|PERF_PIPE_FLOW:|PERF_ROB_HEAD_STATE:|PERF_BACKEND_LOSS:|PERF_OTHER_SLOT_DETAIL:|PERF_SELECT_CANDIDATES:|PERF_LSU_STB:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:|\[[0-9]+\]crc)' "$$tmp"; then \
				grep -E '^(CoreMark Size|Total ticks|Total time \(secs\)|Iterations/Sec|Iterations       |Compiler version|Compiler flags|Memory location|seedcrc|Correct operation validated|CoreMark 1\.0 :|Errors detected|ERROR!|COREMARK DONE|PERF_METRIC:|PERF_APB_STDOUT_ACCOUNT:|PERF_SLOT_ACCOUNT:|PERF_EX_SLOT_STATE:|PERF_EX_EMPTY_CAUSE:|PERF_SLOT_REASON:|PERF_SLOT_LEAF:|PERF_SLOT_LOSS:|PERF_NOIF_SLOT_DETAIL:|PERF_ISSUE_SLOT_DETAIL:|PERF_SINGLE_BUNDLE_DETAIL:|PERF_SELECT_REFILL_DETAIL:|PERF_RS_DEPENDENCY_DETAIL2:|PERF_SINGLE_BUNDLE_OP:|PERF_SELECT_REFILL_SHAPE:|PERF_RS_DEPENDENCY_WAKE:|PERF_RS_DEPENDENCY_OP:|PERF_BANK_BLOCK_DETAIL:|PERF_P0_FULL_DETAIL:|PERF_CONTROL_DECOUPLE:|PERF_LOCAL_CONTROL:|PERF_WAKEUP:|PERF_ROB_OCCUPANCY:|PERF_RS_OCCUPANCY:|PERF_PIPE_FLOW:|PERF_ROB_HEAD_STATE:|PERF_BACKEND_LOSS:|PERF_OTHER_SLOT_DETAIL:|PERF_SELECT_CANDIDATES:|PERF_LSU_STB:|PERF_FRONTEND:|PERF_BRANCH:|PERF_BP_ACC:|PERF_BP_DETAIL:|\[[0-9]+\]crc)' "$$tmp" | tee -a "$(PPA_COREMARK_LOG)"; \
		else \
			echo "[COREMARK] No CoreMark result lines found in $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
		fi; \
		rm -f $$tmp; \
	else \
		echo "[COREMARK] HW log not found: $(COREMARK_RESULT_LOG)" | tee -a "$(PPA_COREMARK_LOG)"; \
	fi

coe_m3_force:

$(COE_M3_ITCM): $(COE_M3_ITCM_BIN)
	od -An -t x8 -w8 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_M3_ITCM_BIN): $(COE_M3_IROM_SOURCE) $(COE_TO_MEM) coe_m3_force
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" --binary "$<" "$@"

$(COE_M3_DTCM) $(COE_LOOP2_DTCM) $(COE_LOOP5_DTCM) $(COE_LOOP_LINA_DTCM): $(COE_M3_DRAM_SOURCE) $(COE_TO_MEM) coe_m3_force
	@mkdir -p "$(@D)"
	perl "$(COE_TO_MEM)" "$<" "$@"

$(COE_LOOP2_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_PATCH)
	perl "$(COE_LOOP_PATCH)" "$<" "$@" 1

$(COE_LOOP2_ITCM): $(COE_LOOP2_ITCM_BIN)
	od -An -t x8 -w8 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_LOOP5_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_PATCH)
	perl "$(COE_LOOP_PATCH)" "$<" "$@" 4

$(COE_LOOP5_ITCM): $(COE_LOOP5_ITCM_BIN)
	od -An -t x8 -w8 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

$(COE_LOOP5_DUMP): $(COE_LOOP5_ITCM_BIN)
	$(OBJDUMP) -D -b binary -m riscv:rv32 "$<" > "$@"

$(COE_LOOP_LINA_ITCM_BIN): $(COE_M3_ITCM_BIN) $(COE_LOOP_LINA_PATCH)
	perl "$(COE_LOOP_LINA_PATCH)" "$<" "$@" "$(COE_LOOP_LINA_SCALE)"

$(COE_LOOP_LINA_ITCM): $(COE_LOOP_LINA_ITCM_BIN)
	od -An -t x8 -w8 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

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
	od -An -t x8 -w8 -v "$<" | tr -d ' \t' | tr 'A-F' 'a-f' | sed '/^$$/d' > "$@"

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
	if [ "$(COE_SIMPLE_NAME)" = "coe_loop_lina" ]; then \
		rm -f "$(VERIF_COE_LOG)" "$(PPA_DIR)/$(COE_SIMPLE_NAME)_summary.log"; \
		echo "[COE_SIMPLE] PASS $(COE_SIMPLE_NAME) (included in aggregate performance statistics; no dedicated report)"; \
	else \
		mkdir -p "$(VERIF_STATS_DIR)"; \
		{ echo "[COE_SIMPLE] PASS $(COE_SIMPLE_NAME)"; \
		  grep -E "LED write|SEG write|CNT write|CNT read|PERF_" "$$log"; \
		} > "$(VERIF_COE_LOG)"; \
	fi; \
	echo "[COE_SIMPLE] PASS $(COE_SIMPLE_NAME)"; \
	grep -E "LED write|SEG write|CNT write|CNT read|PERF_|\\[PERIP\\]|\\[TB\\]|Simulation finished" "$$log" | tail -100

coe_loop5_gen: $(COE_LOOP5_ITCM_BIN) $(COE_LOOP5_ITCM) $(COE_LOOP5_DTCM) $(COE_LOOP5_DUMP)

coe_loop5: coe_loop5_gen
	@$(MAKE) coe_simple \
		COE_SIMPLE_NAME=coe_loop5 \
		COE_SIMPLE_ITCM=$(COE_LOOP5_ITCM) \
		COE_SIMPLE_DTCM=$(COE_LOOP5_DTCM) \
		COE_EXPECT_CNT_READ=0x00000000 \
		COE_EXPECT_SEG=0x37800000

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
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_SPIKE_LOG) --csv $(COMPARE_SPIKE_CSV) --source spike $(if $(filter 1,$(COMPARE_COMPLETE_PROGRAM)),--complete-program,) $(if $(strip $(COMPARE_TRACE_STOP_PC)),--stop-after-pc $(COMPARE_TRACE_STOP_PC),)
	@echo "[SIM] Spike CSV: $(COMPARE_SPIKE_CSV)"
	@$(MAKE) -C hw/dv sim \
		VERILATOR_TRACE=0 \
		LOG_OUTPUT=0 \
		ITCM_FILE=$(abspath $(COMPARE_ITCM)) \
		DTCM_FILE=$(abspath $(COMPARE_DTCM)) \
		SIM_EXTRA_DEFINES="$(COMPARE_SIM_DEFINES) $(if $(filter 1,$(VERILATOR_COVERAGE)),+coverage_file=$(abspath $(COMPARE_COVERAGE_FILE)),)" \
		> $(COMPARE_HW_LOG) 2>&1
	@$(PYTHON) $(TRACE_TO_CSV) --log $(COMPARE_HW_LOG) --csv $(COMPARE_HW_CSV) --source ydrasil $(if $(filter 1,$(COMPARE_COMPLETE_PROGRAM)),--complete-program,) $(if $(strip $(COMPARE_TRACE_STOP_PC)),--stop-after-pc $(COMPARE_TRACE_STOP_PC),)
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


SYN_TIME_DIR ?= pll200m

syn_time:
	@rg 'Implementation sweep:|Synthesis result:|status:.*elapsed=|Vivado flow elapsed:' \
		build/syn/$(SYN_TIME_DIR)/log/vivado.log
