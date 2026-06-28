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

SPIKE_TAR_URL ?= https://bitbucket.org/qglint/tool_tar/downloads/spike-1.1.1-log.tar.xz

CURL ?=  curl 


HOSTNAME := $(shell hostname)
ifeq ($(HOSTNAME),servera437)
SPIKE_INSTALL_DIR ?= /opt/spike
else
SPIKE_INSTALL_DIR ?= $(PROJECT_ROOT)/tools/spike
endif
SPIKE_TAR_FILE ?= $(BUILD_DIR)/downloads/spike.tar.xz
SPIKE ?= $(SPIKE_INSTALL_DIR)/bin/spike
SPIKE_ELF ?= $(RVTESTS_OUT_ROOT)/rv32ui/elf/rv32ui_lh.elf
SPIKE_OUT_DIR ?= $(BUILD_DIR)/sim/spike/
SPIKE_LOG ?= rv32ui_lh
SPIKE_MAXSTEPS ?= 1000000

ifneq ($(steps),)
  spike_stepout = --steps=$(steps)
endif


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

ifeq ($(PKG_KIND),arch)
TOOLS ?= verilator gtkwave riscv64-elf-gcc riscv64-elf-newlib riscv64-elf-gdb qemu-system-riscv
PKG_EXISTS ?= pacman -Qs -q
PKG_MANAGER ?= sudo pacman -S --needed
PKG_UPDATE ?= true
RISCV_PREFIX ?= riscv64-elf
GDB ?= $(RISCV_PREFIX)-gdb
QEMU ?= qemu-system-riscv
else ifeq ($(PKG_KIND),ubuntu)
TOOLS ?= verilator gtkwave gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf gdb-multiarch qemu-system-misc
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
	--steps=$(SPIKE_MAXSTEPS) \
	--priv=$(PRIV) \
	-l 


.SECONDEXPANSION:

RVTESTS_SIM_EXCLUDE_TARGETS = $(addprefix rv_sim_%_,$(subst /,_,$(RVTESTS_EXCLUDE)))
RVTESTS_SIM_DISCOVERED_TARGETS = $(foreach typ,$(RVTESTS_TYPE),$(addprefix rv_sim_$(typ)_, $(basename $(notdir $(wildcard $(RVTESTS_OUT_ROOT)/$(typ)/mem/*.itcm)))))
RVTESTS_SIM_TARGETS = $(filter-out $(RVTESTS_SIM_EXCLUDE_TARGETS),$(RVTESTS_SIM_DISCOVERED_TARGETS))
RVTESTS_SUMMARY_TARGETS = $(addprefix rv_summary_,$(RVTESTS_TYPE))
RVTESTS_REPORT_TARGETS = $(addprefix rv_report_,$(RVTESTS_TYPE))
