PROJECT_ROOT := $(abspath $(CURDIR))
BUILD_DIR := $(PROJECT_ROOT)/build
WAVE_DIR  := $(BUILD_DIR)/wave
LOG_DIR   := $(BUILD_DIR)/log

SIM_TOOL ?= verilator
IP   ?= ydrasil_core
VERILATOR_MOD ?= cc
UVM ?= 0
USE_BENDER ?= 1
BENDER ?= bender
VERILATOR_TRACE ?= 1
DIV_IMPL ?= lzc
YDRASIL_PRODUCER_NUM ?= 12
PYTHON ?= python3
export PYTHONPYCACHEPREFIX ?= $(BUILD_DIR)/pycache
TRACE_TO_CSV ?= $(PROJECT_ROOT)/verif/sim/riscv_trace_csv.py
TRACE_COMPARE ?= $(PROJECT_ROOT)/verif/sim/ydrasil_sim.py

HOSTNAME := $(shell hostname)

ifeq ($(origin PKG_KIND),undefined)
PKG_KIND := $(shell \
	if [ -r /etc/os-release ]; then \
		. /etc/os-release; \
		if [ "$$ID" = "arch" ]; then \
			echo "arch"; exit 0; \
		elif [ "$$ID" = "ubuntu" ]; then \
			echo "ubuntu"; exit 0; \
		elif printf '%s\n' "$$ID_LIKE" | grep -qw debian; then \
			echo "ubuntu"; exit 0; \
		fi; \
	fi; \
	if command -v pacman >/dev/null 2>&1; then \
		echo "arch"; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "ubuntu"; \
	else \
		echo "unknown"; \
	fi)
endif

SPIKE_TAR_URL ?= https://bitbucket.org/qglint/tool_tar/downloads/spike-1.1.1-log.tar.xz
SPIKE_SRC_DIR ?= $(PROJECT_ROOT)/verif/tools/riscv-isa-sim
SPIKE_SRC_BUILD_DIR ?= $(BUILD_DIR)/spike-src
SPIKE_BUILD_JOBS ?= $(shell nproc)
SPIKE_HOST_CC ?= gcc
SPIKE_HOST_CXX ?= g++
SPIKE_HOST_AR ?= ar
SPIKE_HOST_RANLIB ?= ranlib

CURL ?= curl
SPIKE_SYSTEM_INSTALL_DIR ?= /opt/spike
SPIKE_LOCAL_INSTALL_DIR ?= $(PROJECT_ROOT)/tools/spike
SPIKE_PREBUILT_BOOST_REGEX ?= libboost_regex.so.1.91.0

ifeq ($(PKG_KIND),ubuntu)
ifeq ($(HOSTNAME),servera437)
SPIKE_INSTALL_DIR ?= $(SPIKE_SYSTEM_INSTALL_DIR)
SPIKE_DEPLOY_MODE ?= source-sudo
else
SPIKE_INSTALL_DIR ?= $(SPIKE_LOCAL_INSTALL_DIR)
SPIKE_DEPLOY_MODE ?= source
endif
else
SPIKE_INSTALL_DIR ?= $(SPIKE_LOCAL_INSTALL_DIR)
SPIKE_DEPLOY_MODE ?= prebuilt
endif

SPIKE_SRC_INSTALL_DIR ?= $(SPIKE_INSTALL_DIR)
SPIKE_INSTALL_SUDO ?= $(if $(filter source-sudo,$(SPIKE_DEPLOY_MODE)),sudo,)
SPIKE_TAR_FILE ?= $(BUILD_DIR)/downloads/spike.tar.xz
SPIKE ?= $(SPIKE_INSTALL_DIR)/bin/spike
SPIKE_RUN_ENV ?= LD_LIBRARY_PATH=$(SPIKE_INSTALL_DIR)/lib:$(LD_LIBRARY_PATH)
SPIKE_CHECK_ARGS ?= --help
SPIKE_ELF ?= $(RVTESTS_OUT_ROOT)/rv32ui/elf/rv32ui_lh.elf
SIM_OUT_DIR ?= $(BUILD_DIR)/sim
SPIKE_OUT_DIR ?= $(SIM_OUT_DIR)/spike
SPIKE_LOG ?= rv32ui_lh
SPIKE_MAXSTEPS ?= 1000000
SPIKE_LIMIT_ARG ?= --instructions=$(SPIKE_MAXSTEPS)
# Match RTL reset state; Spike's boot ROM otherwise leaves a DTB pointer in a1.
SPIKE_RESET_PC ?= 0x80000000
SPIKE_TRACE_LOG ?= $(SPIKE_OUT_DIR)/$(SPIKE_LOG).log
SPIKE_TRACE_CSV ?= $(SPIKE_OUT_DIR)/$(SPIKE_LOG).csv
SPIKE_MEM_BASE ?= $(patsubst %/elf/,%/mem/,$(dir $(SPIKE_ELF)))$(basename $(notdir $(SPIKE_ELF)))
HW_TRACE_OUT_DIR ?= $(SIM_OUT_DIR)/hw
HW_TRACE_LOG ?= $(HW_TRACE_OUT_DIR)/$(SPIKE_LOG)/hw.log
HW_TRACE_CSV ?= $(HW_TRACE_OUT_DIR)/$(SPIKE_LOG)/hw.csv
VERIF_DIR ?= $(BUILD_DIR)/verif
COVERAGE_DIR ?= $(VERIF_DIR)/coverage
COVERAGE_DATA_DIR ?= $(COVERAGE_DIR)/data
COVERAGE_MERGED ?= $(COVERAGE_DIR)/merged.dat
COVERAGE_INFO ?= $(COVERAGE_DIR)/coverage.info
COVERAGE_SUMMARY ?= $(COVERAGE_DIR)/summary.log
COVERAGE_ANNOTATE_DIR ?= $(COVERAGE_DIR)/annotated
COVERAGE ?= 0
VERILATOR_COVERAGE ?= $(COVERAGE)
SW_TEST_OUT_ROOT ?= $(BUILD_DIR)/sw_tests
SW_BOUNDARY_DIR ?= $(BUILD_DIR)/sw_boundary
SW_COVERAGE_DIR ?= $(VERIF_DIR)/sw_coverage
SW_COVERAGE_DATA_DIR ?= $(SW_COVERAGE_DIR)/data
SW_COVERAGE_MERGED ?= $(SW_COVERAGE_DIR)/merged.dat
SW_COVERAGE_INFO ?= $(SW_COVERAGE_DIR)/coverage.info
SW_COVERAGE_SUMMARY ?= $(SW_COVERAGE_DIR)/summary.log
SW_COVERAGE_ANNOTATE_DIR ?= $(SW_COVERAGE_DIR)/annotated
SW_COVERAGE_UNCOVERED ?= $(SW_COVERAGE_DIR)/uncovered_sw_path.log
TRACE_COMPARE_FIELDS ?= pc,binary,gpr
SIM_COMPARE ?= csv
SIM_COMPARE_MAX_MISMATCHES ?= 20
SIM_COMPARE_TIMEOUT ?= 1000000
SIM_COMPARE_DIR ?= $(SIM_OUT_DIR)/compare
COMPARE_NAME ?= $(SPIKE_LOG)
COMPARE_ELF ?= $(SPIKE_ELF)
COMPARE_ITCM ?= $(SPIKE_MEM_BASE).itcm
COMPARE_DTCM ?= $(SPIKE_MEM_BASE).dtcm
COMPARE_OUT_DIR ?= $(SIM_COMPARE_DIR)/$(COMPARE_NAME)
COMPARE_COVERAGE_FILE ?= $(COVERAGE_DATA_DIR)/$(subst /,_,$(COMPARE_NAME)).dat
COMPARE_HW_OUT_DIR ?= $(HW_TRACE_OUT_DIR)/$(COMPARE_NAME)
COMPARE_HW_LOG ?= $(COMPARE_HW_OUT_DIR)/hw.log
COMPARE_SPIKE_LOG ?= $(SPIKE_OUT_DIR)/$(COMPARE_NAME).log
COMPARE_HW_CSV ?= $(COMPARE_HW_OUT_DIR)/hw.csv
COMPARE_SPIKE_CSV ?= $(SPIKE_OUT_DIR)/$(COMPARE_NAME).csv
COMPARE_LOG ?= $(COMPARE_OUT_DIR)/compare.log
COMPARE_ALLOW_HW_TAIL ?= 0
COMPARE_ALLOW_SPIKE_TAIL ?= 0
COMPARE_MAX_SPIKE_TAIL ?= 0
COMPARE_COMPLETE_PROGRAM ?= 0
COMPARE_GPR_IGNORE_MASK ?= 0
COMPARE_SIM_EXTRA_DEFINES ?= +cpp_timeout=$(SIM_COMPARE_TIMEOUT) +sv_timeout=$(SIM_COMPARE_TIMEOUT)

ifneq ($(steps),)
  spike_stepout = --steps=$(steps)
endif

ifeq ($(PKG_KIND),arch)
RISCV_TOOLCHAIN_PACKAGES ?= riscv64-elf-gcc riscv64-elf-newlib
TOOLS ?= verilator gtkwave $(RISCV_TOOLCHAIN_PACKAGES) riscv64-elf-gdb qemu-system-riscv
SPIKE_BUILD_TOOLS ?= autoconf automake gcc make dtc boost
PKG_EXISTS ?= pacman -Qs -q
PKG_MANAGER ?= sudo pacman -S --needed
PKG_UPDATE ?= true
GDB ?= gdb-multiarch
QEMU ?= qemu-system-riscv
else ifeq ($(PKG_KIND),ubuntu)
RISCV_TOOLCHAIN_PACKAGES ?= gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf
TOOLS ?= verilator gtkwave $(RISCV_TOOLCHAIN_PACKAGES) gdb-multiarch qemu-system-misc
SPIKE_BUILD_TOOLS ?= autoconf automake gcc g++ make device-tree-compiler libboost-dev libboost-regex-dev
PKG_EXISTS ?= dpkg -l
PKG_MANAGER ?= sudo apt-get install -y
PKG_UPDATE ?= sudo apt-get update
GDB ?= gdb-multiarch
QEMU ?= qemu-system-riscv64
else
PKG_EXISTS := $(shell \
	if command -v pacman >/dev/null 2>&1; then \
		echo "pacman -Qs -q"; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "dpkg -l"; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "dnf list installed"; \
	elif command -v yum >/dev/null 2>&1; then \
		echo "yum list installed"; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "brew list"; \
	else \
		echo "unknown"; \
	fi)

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
PKG_UPDATE ?= true
GDB ?= gdb-multiarch
QEMU ?= qemu-system-riscv
SPIKE_BUILD_TOOLS ?= autoconf automake gcc g++ make device-tree-compiler boost
RISCV_TOOLCHAIN_PACKAGES ?=
endif


#------------------------------------------
# toolchain
#------------------------------------------

# RISC-V software must use the repository toolchain. Linked worktrees share
# the primary worktree's tool directory instead of duplicating it.
GIT_COMMON_DIR := $(shell git -C "$(PROJECT_ROOT)" rev-parse \
	--path-format=absolute --git-common-dir 2>/dev/null)
PRIMARY_WORKTREE_ROOT := $(patsubst %/.git,%,$(GIT_COMMON_DIR))
LOCAL_RISCV_TOOLCHAIN := $(PROJECT_ROOT)/tools/riscv
PRIMARY_RISCV_TOOLCHAIN := $(PRIMARY_WORKTREE_ROOT)/tools/riscv
RISCV_TOOLCHAIN_ROOT ?= $(if $(wildcard $(LOCAL_RISCV_TOOLCHAIN)/bin/riscv64-unknown-elf-gcc),$(LOCAL_RISCV_TOOLCHAIN),$(PRIMARY_RISCV_TOOLCHAIN))
RISCV_TOOLCHAIN_BIN ?= $(RISCV_TOOLCHAIN_ROOT)/bin
RISCV_TOOLCHAIN_TRIPLE ?= riscv64-unknown-elf
override RISCV_PREFIX := $(RISCV_TOOLCHAIN_TRIPLE)
RISCV_TOOLCHAIN_PREFIX := $(RISCV_TOOLCHAIN_BIN)/$(RISCV_TOOLCHAIN_TRIPLE)
RISCV_TOOLCHAIN_TOOLS := gcc g++ ar objcopy objdump size
RISCV_TOOLCHAIN_MISSING := $(strip $(shell \
	for tool in $(RISCV_TOOLCHAIN_TOOLS); do \
		path="$(RISCV_TOOLCHAIN_PREFIX)-$$tool"; \
		if [ ! -x "$$path" ]; then printf '%s ' "$$path"; fi; \
	done))
RISCV_TOOLCHAIN_FREE_GOALS := init check_deps install-bender get_spike \
	download_and_extract_spike check_spike_prebuilt_abi build_spike_from_source
RISCV_TOOLCHAIN_REQUIRED_GOALS := $(filter-out $(RISCV_TOOLCHAIN_FREE_GOALS),$(MAKECMDGOALS))
RISCV_TOOLCHAIN_CHECK ?= $(if $(or $(RISCV_TOOLCHAIN_REQUIRED_GOALS),$(if $(MAKECMDGOALS),,1)),1,0)
ifeq ($(RISCV_TOOLCHAIN_CHECK),1)
ifneq ($(RISCV_TOOLCHAIN_MISSING),)
$(error Required RISC-V toolchain is missing or not executable: $(RISCV_TOOLCHAIN_MISSING). Expected tools under $(RISCV_TOOLCHAIN_BIN); refusing to use a system compiler)
endif
endif

override CC := $(RISCV_TOOLCHAIN_PREFIX)-gcc
override OBJCOPY := $(RISCV_TOOLCHAIN_PREFIX)-objcopy
override OBJDUMP := $(RISCV_TOOLCHAIN_PREFIX)-objdump

# -----------------------------------------------------------------------------
# RTL architecture quick-checks
# -----------------------------------------------------------------------------
# All quick-check artifacts stay below BUILD_DIR.  Tool paths and policy knobs
# live here so the top-level Makefile only contains target recipes.
fre ?= 200
RTL_QC_SUPPORTED_FREQS ?= 200 250
RTL_QC_FREQ_MHZ ?= $(fre)
ifeq ($(filter $(RTL_QC_FREQ_MHZ),$(RTL_QC_SUPPORTED_FREQS)),)
$(error Unsupported rtl-structure fre=$(RTL_QC_FREQ_MHZ); supported values: $(RTL_QC_SUPPORTED_FREQS))
endif
RTL_QC_FREQ_TAG := pll$(subst .,p,$(RTL_QC_FREQ_MHZ))m
RTL_QC_FREQ_FILE_TAG := $(subst .,p,$(RTL_QC_FREQ_MHZ))
RTL_QC_BASE_DIR ?= $(BUILD_DIR)/rtl-quickcheck
# Preserve the established default output paths.  Non-default frequencies get
# isolated trees/reports so alternating quick checks cannot reuse stale JSON.
RTL_QC_DIR ?= $(if $(filter 200,$(RTL_QC_FREQ_MHZ)),$(RTL_QC_BASE_DIR),$(RTL_QC_BASE_DIR)/$(RTL_QC_FREQ_TAG))
RTL_QC_TOP ?= ydrasil_core
RTL_QC_BENDER_DIR ?= $(PROJECT_ROOT)/hw/ip/ydrasil_core
RTL_QC_BENDER_TARGETS ?= verilator
RTL_QC_WRAPPER_DIR ?= $(PROJECT_ROOT)/hw/ip/Xilinx_ip_wrapper/rtl
RTL_QC_DEFINES ?= SYNTHESIS YDRASIL_PRODUCER_NUM=$(YDRASIL_PRODUCER_NUM)
RTL_QC_SOURCE_DEPS ?= $(shell find $(PROJECT_ROOT)/hw/ip -type f \( -name '*.sv' -o -name '*.svh' -o -name 'Bender.yml' -o -name 'Bender.yaml' -o -name 'Bender.lock' \) 2>/dev/null)
RTL_QC_FLIST ?= $(RTL_QC_DIR)/$(RTL_QC_TOP).f
RTL_QC_METADATA ?= $(RTL_QC_DIR)/$(RTL_QC_TOP).sources.json
RTL_QC_TREE_DIR ?= $(RTL_QC_DIR)/verilator-tree
RTL_QC_TREE_JSON ?= $(RTL_QC_TREE_DIR)/final.tree.json
RTL_QC_STRUCTURE_JSON ?= $(RTL_QC_DIR)/$(RTL_QC_TOP).structure.json
RTL_QC_VIVADO_REPORT_DIR ?= $(BUILD_DIR)/syn/$(RTL_QC_FREQ_TAG)/reports
RTL_QC_VIVADO_UTILIZATION ?= $(RTL_QC_VIVADO_REPORT_DIR)/synth_utilization_hier.rpt
RTL_QC_VIVADO_TIMING ?= $(RTL_QC_VIVADO_REPORT_DIR)/synth_timing_summary.rpt
RTL_QC_VIVADO_POST_ROUTE_TIMING ?= $(RTL_QC_VIVADO_REPORT_DIR)/post_route_timing_summary.rpt
RTL_QC_VIVADO_TIMING_PATHS_CSV ?= $(RTL_QC_VIVADO_REPORT_DIR)/cpu$(RTL_QC_FREQ_FILE_TAG)_timing_paths.csv
RTL_QC_VIVADO_COMPARE_JSON ?= $(RTL_QC_DIR)/$(RTL_QC_TOP).vivado-compare.json
RTL_QC_RELIABILITY_SUMMARY ?= $(RTL_QC_DIR)/reliability-summary.txt
RTL_QC_CROSS_VALIDATE_JSON ?= $(RTL_QC_DIR)/archive-cross-validation.json
RTL_QC_CROSS_VALIDATE_SUMMARY ?= $(RTL_QC_DIR)/archive-cross-validation.txt
RTL_QC_CALIBRATION_BASE ?= $(BUILD_DIR)/rtl-calibration
RTL_QC_CALIBRATION_ROOT ?= $(if $(filter 200,$(RTL_QC_FREQ_MHZ)),$(RTL_QC_CALIBRATION_BASE),$(RTL_QC_CALIBRATION_BASE)/$(RTL_QC_FREQ_TAG))
RTL_QC_CALIBRATION_HISTORY ?= $(RTL_QC_CALIBRATION_ROOT)
RTL_QC_GIT_SHORT := $(shell git -C $(PROJECT_ROOT) rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
RTL_QC_CALIBRATION_TIMESTAMP := $(shell date -u +%Y%m%d-%H%M%S)
RTL_QC_CALIBRATION_TAG ?= $(RTL_QC_GIT_SHORT)-$(RTL_QC_FREQ_TAG)-$(RTL_QC_CALIBRATION_TIMESTAMP)
RTL_QC_CALIBRATION_DIR ?= $(RTL_QC_CALIBRATION_ROOT)/$(RTL_QC_CALIBRATION_TAG)
RTL_QC_ARCHIVE_SCRIPT ?= $(SYN_DIR)/archive_rtl_calibration.py
RTL_QC_CROSS_VALIDATE_SCRIPT ?= $(SYN_DIR)/cross_validate_rtl_timing.py
RTL_QC_CV_MIN_AGGREGATE_PATH_RECALL ?= 0.95
RTL_QC_CV_MIN_AGGREGATE_FAMILY_RECALL ?= 0.80
RTL_QC_CV_MIN_HOLDOUT_PATH_RECALL ?= 0.90
RTL_QC_CV_MIN_HOLDOUT_SCORED_PATHS ?= 100
RTL_QC_CV_MIN_ERROR_PRECISION ?= 0.90
RTL_QC_CV_MIN_ERROR_TRUE_FAMILIES ?= 5
RTL_QC_ERROR_LIMIT ?= 50
# Frequency-specific policy calibrated against the xc7 post-route reports.
# At 200 MHz, depth 33 closes timing and depth 34 remains the zero-false-positive
# severe boundary across the archive.  At 250 MHz, the current depth-33 fetch
# path fails at -0.846 ns, so it is an ERROR while 3.6 ns remains the warning
# margin.  With the BRAM launch penalty included, the weighted limit 1000 sits
# above the archived passing maximum (975) while the current failing design is
# 1301.  This also covers the short-logic BRAM paths seen in routed violations.
# BRAM clock-to-out is device-specific and remains unchanged.
RTL_QC_TARGET_PERIOD_NS_200 ?= 5.0
RTL_QC_WARNING_PERIOD_NS_200 ?= 4.5
RTL_QC_TIMING_POSSIBLE_DEPTH_200 ?= 9
RTL_QC_TIMING_DEFINITE_DEPTH_200 ?= 34
RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT_200 ?= 1000
RTL_QC_LUTRAM_POSSIBLE_DEPTH_200 ?= 6
RTL_QC_TARGET_PERIOD_NS_250 ?= 4.0
RTL_QC_WARNING_PERIOD_NS_250 ?= 3.6
RTL_QC_TIMING_POSSIBLE_DEPTH_250 ?= 7
RTL_QC_TIMING_DEFINITE_DEPTH_250 ?= 33
RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT_250 ?= 1000
RTL_QC_LUTRAM_POSSIBLE_DEPTH_250 ?= 5
RTL_QC_TARGET_PERIOD_NS ?= $(RTL_QC_TARGET_PERIOD_NS_$(RTL_QC_FREQ_MHZ))
RTL_QC_WARNING_PERIOD_NS ?= $(RTL_QC_WARNING_PERIOD_NS_$(RTL_QC_FREQ_MHZ))
RTL_QC_TIMING_POSSIBLE_DEPTH ?= $(RTL_QC_TIMING_POSSIBLE_DEPTH_$(RTL_QC_FREQ_MHZ))
RTL_QC_TIMING_DEFINITE_DEPTH ?= $(RTL_QC_TIMING_DEFINITE_DEPTH_$(RTL_QC_FREQ_MHZ))
RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT ?= $(RTL_QC_TIMING_WEIGHTED_VIOLATION_LIMIT_$(RTL_QC_FREQ_MHZ))
RTL_QC_LUTRAM_POSSIBLE_DEPTH ?= $(RTL_QC_LUTRAM_POSSIBLE_DEPTH_$(RTL_QC_FREQ_MHZ))
RTL_QC_FANOUT_TIMING_MIN_DEPTH ?= 3
RTL_QC_BRAM_LAUNCH_PENALTY_DEPTH ?= 6
RTL_QC_BRAM_CLOCK_TO_OUT_NS ?= 2.45
RTL_QC_LUTRAM_ARC_NS ?= 0.06
RTL_QC_ROUTE_DOMINATED_FRACTION ?= 0.65
VERILATOR_STRICT ?= verilator
VERILATOR_STRICT_FLAGS ?= --lint-only --sv -Wall --report-unoptflat --error-limit $(RTL_QC_ERROR_LIMIT)
# The RTL strict pass remains fatal for width, loop, latch and timing-shape
# diagnostics. These categories are pre-existing compatibility-only signals
# (DV observability pins and package constants) that do not enter synthesized
# logic; keep the list explicit rather than using the
# broad VERILATOR_IGNORE_FULL escape hatch.
VERILATOR_STRICT_WNO ?= DECLFILENAME PINCONNECTEMPTY UNUSEDSIGNAL UNUSEDPARAM SYMRSVDWORD SYNCASYNCNET
# Keep structural diagnostics in the same log as the elaborated tree.  The
# target remains non-fatal so the JSON is still available for post-analysis.
VERILATOR_XML_FLAGS ?= --lint-only --dump-tree-json --report-unoptflat --error-limit $(RTL_QC_ERROR_LIMIT) -Wno-fatal

YOSYS ?= yosys
YOSYS_TOP ?= $(RTL_QC_TOP)
YOSYS_BENDER_DIR ?= $(RTL_QC_BENDER_DIR)
YOSYS_BENDER_TARGETS ?= $(RTL_QC_BENDER_TARGETS)
YOSYS_FAMILY ?= xc7
YOSYS_RUN ?= coarse:map_luts
# Yosys can use the same FPGA-side memory wrappers as Vivado. Pure RTL
# simulation uses the technology-independent hw/ip/ydrasil_sim models.
YOSYS_WITH_WRAPPERS ?= 1
YOSYS_DEFINES ?= SYNTHESIS TARGET_SYNTHESIS YDRASIL_PRODUCER_NUM=$(YDRASIL_PRODUCER_NUM)
YOSYS_DIR ?= $(BUILD_DIR)/yosys-slang/$(YOSYS_TOP)
YOSYS_FLIST ?= $(YOSYS_DIR)/$(YOSYS_TOP).f
YOSYS_METADATA ?= $(YOSYS_DIR)/sources.json
YOSYS_SCRIPT ?= $(YOSYS_DIR)/run.ys
YOSYS_STAT_JSON ?= $(YOSYS_DIR)/stat.json
YOSYS_NETLIST_JSON ?= $(YOSYS_DIR)/netlist.json
YOSYS_LOG ?= $(YOSYS_DIR)/yosys.log
YOSYS_BASELINE_STAT ?=
YOSYS_LUT_GROWTH_LIMIT_PERCENT ?= 15
YOSYS_LTP_GROWTH_LIMIT_PERCENT ?= 20

VIVADO_OOC ?= vivado
VIVADO_OOC_SETTINGS ?= $(VIVADO_SETTINGS)
VIVADO_OOC_TOP ?= $(YOSYS_TOP)
VIVADO_OOC_PART ?= xc7k325tffg900-2
VIVADO_OOC_DIR ?= $(BUILD_DIR)/vivado-ooc/$(VIVADO_OOC_TOP)
VIVADO_OOC_FLIST ?= $(VIVADO_OOC_DIR)/$(VIVADO_OOC_TOP).f
VIVADO_OOC_METADATA ?= $(VIVADO_OOC_DIR)/sources.json
VIVADO_OOC_LOG ?= $(VIVADO_OOC_DIR)/vivado.log
VIVADO_OOC_PERIOD_NS ?= 5.0
VIVADO_OOC_SYNTH_DIRECTIVE ?= PerformanceOptimized
VIVADO_OOC_WITH_WRAPPERS ?= 1
VIVADO_OOC_DEFINES ?= SYNTHESIS TARGET_SYNTHESIS TARGET_VIVADO TARGET_XILINX
# Issue pipeline OOC is intentionally split by top.  Keep this list
# configurable because a focused run may only need one stage.
VIVADO_OOC_ISSUE_MODULES ?= ydrasil_id_stage ydrasil_issue_stage ydrasil_ctrl ydrasil_ex_block
VIVADO_OOC_ISSUE_DIR ?= $(BUILD_DIR)/vivado-ooc/issue

ARCH := rv32im_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs
ABI  := ilp32
PRIV := m

RISCV_CFLAGS := \
    -march=$(ARCH) \
    -mabi=$(ABI) \
    -nostdlib \
    -nostartfiles \
    -static \
    -mcmodel=medany \
    -falign-functions=8 \
    -falign-jumps=8 \
    -falign-labels=8 \
    -falign-loops=8

RVTESTS_TYPE := rv32ui rv32um rv32uzba rv32uzbb rv32uzbc rv32uzbkb rv32uzbkx rv32uzbs rv32mi
RV32MI_TESTS ?= csr mcsr
RVTESTS_EXCLUDE ?= rv32ui/ma_data

RVTESTS_OUT_ROOT := $(BUILD_DIR)/riscv_tests

RVTESTS_RESULT_DIR := $(VERIF_DIR)/rvtest_results

SPIKE_FLAGS := \
	--isa=$(ARCH) \
	--log-commits \
	$(SPIKE_LIMIT_ARG) \
	--priv=$(PRIV) \
	--disable-dtb \
	--pc=$(SPIKE_RESET_PC) \
	-l


.SECONDEXPANSION:

RVTESTS_SIM_EXCLUDE_TARGETS = $(addprefix rv_sim_%_,$(subst /,_,$(RVTESTS_EXCLUDE)))
RVTESTS_SIM_DISCOVERED_TARGETS = $(foreach typ,$(RVTESTS_TYPE),$(addprefix rv_sim_$(typ)_, $(basename $(notdir $(wildcard $(RVTESTS_OUT_ROOT)/$(typ)/mem/*.itcm)))))
RVTESTS_SIM_TARGETS = $(filter-out $(RVTESTS_SIM_EXCLUDE_TARGETS),$(RVTESTS_SIM_DISCOVERED_TARGETS))
RVTESTS_SUMMARY_TARGETS = $(addprefix rv_summary_,$(RVTESTS_TYPE))
RVTESTS_REPORT_TARGETS = $(addprefix rv_report_,$(RVTESTS_TYPE))
