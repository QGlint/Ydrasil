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
PYTHON ?= python3
TRACE_TO_CSV ?= $(PROJECT_ROOT)/verif/sim/riscv_trace_csv.py


SPIKE ?= ./tools/spike/bin/spike
SPIKE_ELF ?= $(RVTESTS_OUT_ROOT)/rv32ui/elf/rv32ui_lh.elf
SPIKE_LOG ?= $(BUILD_DIR)/sim/spike/rv32ui_lh
SPIKE_MAXSTEPS ?= 1000000

ifneq ($(steps),)
  spike_stepout = --steps=$(steps)
endif




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


#------------------------------------------
# toolchain
#------------------------------------------

RISCV_PREFIX := riscv64-elf
CC      := $(RISCV_PREFIX)-gcc
OBJCOPY := $(RISCV_PREFIX)-objcopy
OBJDUMP := $(RISCV_PREFIX)-objdump

ARCH := rv32im_zicsr
ABI  := ilp32
PRIV := m

RISCV_CFLAGS := \
    -march=$(ARCH) \
    -mabi=$(ABI) \
    -nostdlib \
    -nostartfiles \
    -static \
    -mcmodel=medany

RVTESTS_TYPE := rv32ui rv32um

RVTESTS_OUT_ROOT := $(BUILD_DIR)/riscv_tests

RVTESTS_RESULT_DIR := $(BUILD_DIR)/rvtest_results

SPIKE_FLAGS := \
	--isa=$(ARCH) \
	--log-commits \
	--steps=$(SPIKE_MAXSTEPS) \
	--priv=$(PRIV) \
	-l 


.SECONDEXPANSION:

RVTESTS_SIM_TARGETS = $(foreach typ,$(RVTESTS_TYPE),$(addprefix rv_sim_$(typ)_, $(basename $(notdir $(wildcard $(RVTESTS_OUT_ROOT)/$(typ)/mem/*.itcm)))))
RVTESTS_SUMMARY_TARGETS = $(addprefix rv_summary_,$(RVTESTS_TYPE))
RVTESTS_REPORT_TARGETS = $(addprefix rv_report_,$(RVTESTS_TYPE))
