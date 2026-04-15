PROJECT_ROOT := $(abspath $(CURDIR))

BUILD_DIR := $(PROJECT_ROOT)/build
WAVE_DIR  := $(BUILD_DIR)/wave
LOG_DIR   := $(BUILD_DIR)/log

SIM_TOOL ?= verilator
IP  ?= rate_adapter
VERILATOR_MOD ?= sv
UVM ?= 0

USE_WINDOW_68_80_GEARBOX ?= 1
USE_WINDOW_80_68_GEARBOX ?= 1

export PROJECT_ROOT BUILD_DIR WAVE_DIR LOG_DIR SIM_TOOL IP VERILATOR_MOD UVM USE_WINDOW_68_80_GEARBOX USE_WINDOW_80_68_GEARBOX

.PHONY: all sim clean wave resim

all: sim wave


sim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv sim

resim:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(LOG_DIR)
	@$(MAKE) -C hw/dv resim

wave:
	@$(MAKE) -C hw/dv wave

clean:
	rm -rf $(BUILD_DIR)