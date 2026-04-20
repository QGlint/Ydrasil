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
USE_BENDER ?= 1
BENDER ?= bender
BENDER_INCLUDE_TB ?= 1
BENDER_TB_TARGET ?= ip_tb

BENDER_TARGET_ARGS := -t $(SIM_TOOL)
ifeq ($(BENDER_INCLUDE_TB),1)
BENDER_TARGET_ARGS += -t $(BENDER_TB_TARGET)
endif

##################################
# Paths
##################################

OBJ_DIR := $(BUILD_DIR)/$(TOP)
TB_SRCS := $(wildcard $(IP_DIR)/dv/*.sv)
INC_DIRS += $(PROJECT_ROOT)/hw/include

ifeq ($(USE_BENDER),1)
FLIST_DIR := $(OBJ_DIR)/flist
FLIST_FILE := $(FLIST_DIR)/$(IP)_$(SIM_TOOL).f
endif

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
