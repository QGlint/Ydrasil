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
LSU_IMPL ?= legacy
MEMS_IMPL ?= new
PYTHON ?= python3
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
SPIKE_LIMIT_ARG ?= --steps=$(SPIKE_MAXSTEPS)
SPIKE_TRACE_LOG ?= $(SPIKE_OUT_DIR)/$(SPIKE_LOG).log
SPIKE_TRACE_CSV ?= $(SPIKE_OUT_DIR)/$(SPIKE_LOG).csv
SPIKE_MEM_BASE ?= $(patsubst %/elf/,%/mem/,$(dir $(SPIKE_ELF)))$(basename $(notdir $(SPIKE_ELF)))
HW_TRACE_OUT_DIR ?= $(SIM_OUT_DIR)/hw
HW_TRACE_LOG ?= $(HW_TRACE_OUT_DIR)/$(SPIKE_LOG)/hw.log
HW_TRACE_CSV ?= $(HW_TRACE_OUT_DIR)/$(SPIKE_LOG)/hw.csv
TRACE_COMPARE_FIELDS ?= pc,binary,gpr
SIM_COMPARE ?= csv
SIM_COMPARE_MAX_MISMATCHES ?= 20
SIM_COMPARE_MAX_ROWS ?= 0
SIM_COMPARE_TIMEOUT ?= 1000000
SIM_COMPARE_DIR ?= $(SIM_OUT_DIR)/compare
COMPARE_NAME ?= $(SPIKE_LOG)
COMPARE_ELF ?= $(SPIKE_ELF)
COMPARE_ITCM ?= $(SPIKE_MEM_BASE).itcm
COMPARE_DTCM ?= $(SPIKE_MEM_BASE).dtcm
COMPARE_OUT_DIR ?= $(SIM_COMPARE_DIR)/$(COMPARE_NAME)
COMPARE_HW_OUT_DIR ?= $(HW_TRACE_OUT_DIR)/$(COMPARE_NAME)
COMPARE_HW_LOG ?= $(COMPARE_HW_OUT_DIR)/hw.log
COMPARE_SPIKE_LOG ?= $(SPIKE_OUT_DIR)/$(COMPARE_NAME).log
COMPARE_HW_CSV ?= $(COMPARE_HW_OUT_DIR)/hw.csv
COMPARE_SPIKE_CSV ?= $(SPIKE_OUT_DIR)/$(COMPARE_NAME).csv
COMPARE_LOG ?= $(COMPARE_OUT_DIR)/compare.log
COMPARE_SIM_EXTRA_DEFINES ?= +cpp_timeout=$(SIM_COMPARE_TIMEOUT) +sv_timeout=$(SIM_COMPARE_TIMEOUT)

ifneq ($(steps),)
  spike_stepout = --steps=$(steps)
endif

ifeq ($(PKG_KIND),arch)
TOOLS ?= verilator gtkwave riscv64-elf-gcc riscv64-elf-newlib riscv64-elf-gdb qemu-system-riscv
SPIKE_BUILD_TOOLS ?= autoconf automake gcc make dtc boost
PKG_EXISTS ?= pacman -Qs -q
PKG_MANAGER ?= sudo pacman -S --needed
PKG_UPDATE ?= true
RISCV_PREFIX ?= riscv64-elf
GDB ?= $(RISCV_PREFIX)-gdb
QEMU ?= qemu-system-riscv
else ifeq ($(PKG_KIND),ubuntu)
TOOLS ?= verilator gtkwave gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf gdb-multiarch qemu-system-misc
SPIKE_BUILD_TOOLS ?= autoconf automake gcc g++ make device-tree-compiler libboost-dev libboost-regex-dev
PKG_EXISTS ?= dpkg -l
PKG_MANAGER ?= sudo apt-get install -y
PKG_UPDATE ?= sudo apt-get update
RISCV_PREFIX ?= riscv64-unknown-elf
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
RISCV_PREFIX ?= riscv64-elf
GDB ?= $(RISCV_PREFIX)-gdb
QEMU ?= qemu-system-riscv
SPIKE_BUILD_TOOLS ?= autoconf automake gcc g++ make device-tree-compiler boost
endif


#------------------------------------------
# toolchain
#------------------------------------------

ifeq ($(origin CC),default)
CC := $(RISCV_PREFIX)-gcc
else
CC ?= $(RISCV_PREFIX)-gcc
endif
OBJCOPY ?= $(RISCV_PREFIX)-objcopy
OBJDUMP ?= $(RISCV_PREFIX)-objdump

ARCH := rv32im_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs
ABI  := ilp32
PRIV := m

RISCV_CFLAGS := \
    -march=$(ARCH) \
    -mabi=$(ABI) \
    -nostdlib \
    -nostartfiles \
    -static \
    -mcmodel=medany

RVTESTS_TYPE := rv32ui rv32um rv32uzba rv32uzbb rv32uzbc rv32uzbkb rv32uzbkx rv32uzbs
RVTESTS_EXCLUDE ?= rv32ui/ma_data

RVTESTS_OUT_ROOT := $(BUILD_DIR)/riscv_tests

RVTESTS_RESULT_DIR := $(BUILD_DIR)/rvtest_results

SPIKE_FLAGS := \
	--isa=$(ARCH) \
	--log-commits \
	$(SPIKE_LIMIT_ARG) \
	--priv=$(PRIV) \
	-l


.SECONDEXPANSION:

RVTESTS_SIM_EXCLUDE_TARGETS = $(addprefix rv_sim_%_,$(subst /,_,$(RVTESTS_EXCLUDE)))
RVTESTS_SIM_DISCOVERED_TARGETS = $(foreach typ,$(RVTESTS_TYPE),$(addprefix rv_sim_$(typ)_, $(patsubst $(typ)_%,%,$(basename $(notdir $(wildcard $(RVTESTS_OUT_ROOT)/$(typ)/mem/*.itcm))))))
RVTESTS_SIM_TARGETS = $(filter-out $(RVTESTS_SIM_EXCLUDE_TARGETS),$(RVTESTS_SIM_DISCOVERED_TARGETS))
RVTESTS_SUMMARY_TARGETS = $(addprefix rv_summary_,$(RVTESTS_TYPE))
RVTESTS_REPORT_TARGETS = $(addprefix rv_report_,$(RVTESTS_TYPE))
