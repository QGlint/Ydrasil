##################################
# IP Description
##################################

IP_DIR := $(PROJECT_ROOT)/hw/ip/$(IP)

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
DIV_IMPL ?= new
LSU_IMPL ?= new
MEMS_IMPL ?= new

BENDER_TARGET_ARGS := -t $(SIM_TOOL)
ifeq ($(BENDER_INCLUDE_TB),1)
BENDER_TARGET_ARGS += -t $(BENDER_TB_TARGET)
endif

ifeq ($(USE_BENDER),0)
include $(PROJECT_ROOT)/hw/ip/Makefile
else
RTL_SRCS :=
endif

##################################
# Paths
##################################

OBJ_DIR ?= $(BUILD_DIR)/$(TOP)
TB_SRCS ?= $(wildcard $(IP_DIR)/dv/*.sv)
INC_DIRS += $(PROJECT_ROOT)/hw/include
INC_DIRS += $(IP_DIR)/rtl
INC_DIRS += $(IP_DIR)/include

ifeq ($(USE_BENDER),1)
BENDER_INCDIRS := $(shell \
	if [ -f $(IP_DIR)/Bender.yml ] || [ -f $(IP_DIR)/Bender.yaml ]; then \
		cd $(IP_DIR) && $(BENDER) script flist-plus $(BENDER_TARGET_ARGS) | sed -n 's/^+incdir+//p'; \
	fi)
INC_DIRS += $(BENDER_INCDIRS)
endif

INC_DIRS := $(sort $(INC_DIRS))

ifeq ($(USE_BENDER),1)
FLIST_DIR := $(OBJ_DIR)/flist
FLIST_FILE := $(FLIST_DIR)/$(IP)_$(SIM_TOOL).f
endif

##################################
# Defines
##################################

ITCM_FILE ?= 
DTCM_FILE ?=

ifneq ($(ITCM_FILE),)
SIM_DEFINES += +itcmfile=$(ITCM_FILE)
endif
ifneq ($(DTCM_FILE),)
SIM_DEFINES += +dtcmfile=$(DTCM_FILE)
endif

DEFINES := RANDOM_SEED=$(RANDOM_SEED)

ifeq ($(DIV_IMPL),new)
DEFINES += YDRASIL_DIV_IMPL_NEW
else ifeq ($(DIV_IMPL),legacy)
DEFINES += YDRASIL_DIV_IMPL_LEGACY
else
$(error Unsupported DIV_IMPL '$(DIV_IMPL)'. Use DIV_IMPL=new or DIV_IMPL=legacy)
endif

ifeq ($(LSU_IMPL),new)
DEFINES += YDRASIL_LSU_IMPL_NEW
else ifeq ($(LSU_IMPL),legacy)
DEFINES += YDRASIL_LSU_IMPL_LEGACY
else
$(error Unsupported LSU_IMPL '$(LSU_IMPL)'. Use LSU_IMPL=new or LSU_IMPL=legacy)
endif

ifeq ($(MEMS_IMPL),new)
DEFINES += YDRASIL_MEMS_IMPL_NEW
else ifeq ($(MEMS_IMPL),legacy)
DEFINES += YDRASIL_MEMS_IMPL_LEGACY
else
$(error Unsupported MEMS_IMPL '$(MEMS_IMPL)'. Use MEMS_IMPL=new or MEMS_IMPL=legacy)
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
