VERILATOR ?= verilator
VERILATOR_TRACE ?= 1
VERILATOR_MOD ?= cc
VERILATOR_IGNORE_ALL ?= 0
Compile_optimization ?= 0
mutil_run ?= 0
LOG_OUTPUT ?= 1 
##################################
# Paths
##################################

BIN := $(OBJ_DIR)/$(TOP)
OBJ_DIR_SIM := $(OBJ_DIR)/verilator


ifeq ($(VERILATOR_MOD),cc)
SIM_C_DIR := $(PROJECT_ROOT)/hw/dv/verilator
SIM_CSRCS := $(SIM_C_DIR)/sim.cpp
endif

SIM_CMDS := $(BIN)
SIM_FLAGS := 
VERILATOR_FLAGS :=

##################################
# Base Flags
##################################


ifeq ($(VERILATOR_MOD) ,cc)
VERILATOR_FLAGS += -cc --exe
VERILATOR_FLAGS += -DVERILATOR_CC
# VERILATOR_FLAGS += -CFLAGS "-DVERILATOR_CC"
else
VERILATOR_FLAGS += --binary --timing --exe
VERILATOR_FLAGS += -DVERILATOR_SV
endif

ifeq ($(mutil_run),1)
VERILATOR_FLAGS += --threads 16
endif

VERILATOR_FLAGS += -MAKEFLAGS "-j$(shell nproc)"

VERILATOR_FLAGS += --sv
VERILATOR_FLAGS += --Mdir $(OBJ_DIR_SIM)
VERILATOR_FLAGS += -x-assign fast
VERILATOR_FLAGS += --build -o $(abspath $(BIN))

VERILATOR_FLAGS += -j  $(shell nproc)
VERILATOR_FLAGS += --top-module $(TOP)

VERILATOR_FLAGS += $(addprefix -I,$(INC_DIRS))
VERILATOR_FLAGS += $(addprefix -D,$(DEFINES))
VERILATOR_FLAGS += -CFLAGS "-DTB_NAME=$(TOP)"


VERILATOR_FLAGS += -Wno-fatal -Wno-TIMESCALEMOD 

ifeq ($(VERILATOR_IGNORE_ALL),1)
VERILATOR_FLAGS +=  -Wno-INITIALDLY 
VERILATOR_FLAGS += -Wno-WIDTHTRUNC 
VERILATOR_FLAGS += -Wno-WIDTHCONCAT 
VERILATOR_FLAGS += -Wno-WIDTHEXPAND 
VERILATOR_FLAGS += -Wno-UNOPTFLAT 
VERILATOR_FLAGS += -Wno-PINMISSING 
VERILATOR_FLAGS += -Wno-UNSIGNED
endif

ifeq ($(Compile_optimization),1)
VERILATOR_FLAGS += -O3
VERILATOR_FLAGS += --no-assert
VERILATOR_FLAGS += -CFLAGS "-O3 -march=native -DNDEBUG"
endif

ifeq ($(VERILATOR_TRACE),1)
# VERILATOR_FLAGS += --trace --trace-depth 2
VERILATOR_FLAGS +=--trace  --trace-structs --trace-params --trace-max-array 1024
VERILATOR_FLAGS += -CFLAGS "-DVERILATOR_TRACE"
SIM_FLAGS += +trace
endif

SIM_FLAGS += $(SIM_DEFINES)

ifeq ($(USE_BENDER),1)
VERILATOR_FLAGS += -f $(FLIST_FILE)
endif

##################################
# Target
##################################


comp:
	@mkdir -p $(OBJ_DIR) $(LOG_DIR) $(WAVE_DIR) $(OBJ_DIR_SIM) 

ifeq ($(USE_BENDER),1)
	@mkdir -p $(FLIST_DIR)
	@echo "[BENDER FLIST]"
	@if [ -f $(IP_DIR)/Bender.yml ] || [ -f $(IP_DIR)/Bender.yaml ]; then \
		cd $(IP_DIR) && $(BENDER) script flist-plus $(BENDER_TARGET_ARGS) | sed '/^+define+/d' > $(FLIST_FILE); \
	else \
		echo "ERROR: USE_BENDER=1 but Bender.yml/Bender.yaml not found at $(IP_DIR)"; \
		exit 1; \
	fi
endif

	@echo "[VERILATOR COMPILE]"
	$(VERILATOR) $(VERILATOR_FLAGS) \
	    $(if $(filter 1,$(USE_BENDER)),,$(RTL_SRCS)) \
	    $(if $(and $(filter 1,$(USE_BENDER)),$(filter 1,$(BENDER_INCLUDE_TB))),,$(TB_SRCS)) \
	    $(SIM_CSRCS)\
	    >$(LOG_DIR)/$(TOP).ver.comp.log 2>$(LOG_DIR)/$(TOP).ver.comp.err.log

	@echo "[CLEAN EMPTY LOG]"
	@find $(LOG_DIR) -type f -size 0 -delete
	@find $(LOG_DIR) -type f -size 0 -print -delete

sim:
	@echo "[VERILATOR RUN]"
ifeq ($(LOG_OUTPUT),1) 
	cd $(OBJ_DIR_SIM) && $(SIM_CMDS) $(SIM_FLAGS) \
		>$(LOG_DIR)/$(TOP).ver.sim.log 2>$(LOG_DIR)/$(TOP).ver.sim.err.log
else
	cd $(OBJ_DIR_SIM) && $(SIM_CMDS) $(SIM_FLAGS) 
endif


ifeq ($(VERILATOR_TRACE),1)
	@echo "[MOVE WAVE]"
	@if ls $(OBJ_DIR_SIM)/*.vcd 1>/dev/null 2>&1; then \
	    mv -f $(OBJ_DIR_SIM)/*.vcd \
	       $(WAVE_DIR)/$(TOP).vcd ; \
	fi

	@if ls $(OBJ_DIR_SIM)/*.fst 1>/dev/null 2>&1; then \
	    mv -f $(OBJ_DIR_SIM)/*.fst \
	       $(WAVE_DIR)/$(TOP).fst ; \
	fi
endif

	@echo "[CLEAN EMPTY LOG]"
	@find $(LOG_DIR) -type f -size 0 -delete
	@find $(LOG_DIR) -type f -size 0 -print -delete

recomp:
	@echo "[CLEAN OBJ_DIR_SIM]"
	@rm -rf $(OBJ_DIR_SIM)/*;  
	$(MAKE) comp

wave:
ifeq ($(VERILATOR_TRACE),1)
	gtkwave $$(ls -t $(WAVE_DIR)/$(TOP).vcd | head -n 1) &
endif