PROJECT_ROOT := $(abspath $(CURDIR))

BUILD_DIR := $(PROJECT_ROOT)/build
WAVE_DIR  := $(BUILD_DIR)/wave
LOG_DIR   := $(BUILD_DIR)/log

SIM_TOOL ?= verilator
IP  ?= ydrasil_core
VERILATOR_MOD ?= sv
UVM ?= 0
USE_BENDER ?= 1
BENDER ?= bender
ITCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem/irom0.mem
DTCM_MEM ?= $(PROJECT_ROOT)/hw/dv/test_data/mem/dram0.mem


export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_BENDER BENDER ITCM_MEM DTCM_MEM

.PHONY: all sim clean wave resim sim_jyd_fpga resim_jyd_fpga

all: sim wave


sim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile sim

resim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv -f Makefile resim

wave:
	@$(MAKE) -C hw/dv -f Makefile wave

clean:
	rm -rf $(BUILD_DIR)