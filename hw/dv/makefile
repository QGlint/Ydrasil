##################################
# Load IP Description
##################################

IP_DIR := $(PROJECT_ROOT)/hw/ip/$(IP)
include $(PROJECT_ROOT)/hw/ip/Makefile

##################################
# Options
##################################

SIM_TOOL ?= verilator
TOP ?= $(IP)_tb
RANDOM_SEED ?= 42

##################################
# Paths
##################################

OBJ_DIR := $(BUILD_DIR)/$(TOP)
TB_SRCS := $(wildcard $(IP_DIR)/dv/*.sv)
INC_DIRS += $(PROJECT_ROOT)/hw/include

##################################
# Defines
##################################

DEFINES := RANDOM_SEED=$(RANDOM_SEED)
ifeq ($(USE_WINDOW_68_80_GEARBOX),1)
DEFINES += USE_WINDOW_68_80_GEARBOX
endif
ifeq ($(USE_WINDOW_80_68_GEARBOX),1)
DEFINES += USE_WINDOW_80_68_GEARBOX
endif

##################################
# Timestamp
##################################

TIME_TAG := $(shell date +%Y%m%d_%H%M%S)

##################################
# Dispatch
##################################

ifeq ($(SIM_TOOL),verilator)
include verilator/verilator.mk
endif

ifeq ($(SIM_TOOL),vcs)
include vcs/vcs.mk
endif

ifeq ($(SIM_TOOL),iverilog)
include iverilog/iverilog.mk
endif

clean:
	rm -rf $(OBJ_DIR)
