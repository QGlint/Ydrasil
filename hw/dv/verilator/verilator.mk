VERILATOR ?= verilator


##################################
# Paths
##################################

BIN := $(OBJ_DIR)/$(TOP)
OBJ_DIR_SIM := $(OBJ_DIR)/verilator

ifeq ($(VERILATOR_MOD),cc)
SIM_C_DIR := $(PROJECT_ROOT)/hw/dv/verilator
SIM_CSRCS := $(SIM_C_DIR)/sim.cpp
endif
##################################
# Base Flags
##################################

VERILATOR_FLAGS :=
ifeq ($(VERILATOR_MOD) ,cc)
VERILATOR_FLAGS += -cc --exe --timing
VERILATOR_FLAGS += -DVERILATOR_CC
VERILATOR_FLAGS += -CFLAGS "-DVERILATOR_CC"
else
VERILATOR_FLAGS += --binary --timing --exe
VERILATOR_FLAGS += -DVERILATOR_SV
endif

VERILATOR_FLAGS += -MAKEFLAGS "-j$(shell nproc)"

VERILATOR_FLAGS += --sv
VERILATOR_FLAGS += --Mdir $(OBJ_DIR_SIM)
VERILATOR_FLAGS += -x-assign fast
VERILATOR_FLAGS += --build -o $(abspath $(BIN))

VERILATOR_FLAGS += -Wno-fatal -Wno-TIMESCALEMOD 

# VERILATOR_FLAGS += \
#  -Wno-INITIALDLY \
#  -Wno-WIDTHTRUNC \
#  -Wno-WIDTHCONCAT \
#  -Wno-WIDTHEXPAND \
#  -Wno-UNOPTFLAT \
#  -Wno-PINMISSING \
#  -Wno-UNSIGNED 

VERILATOR_FLAGS += --trace --trace-structs --trace-params --trace-max-array 1024
VERILATOR_FLAGS += --prof-cfuncs -CFLAGS -DVL_DEBUG
VERILATOR_FLAGS += -j  $(shell nproc)
VERILATOR_FLAGS += --top-module $(TOP)

VERILATOR_FLAGS += $(addprefix -I,$(INC_DIRS))
VERILATOR_FLAGS += $(addprefix -D,$(DEFINES))
VERILATOR_FLAGS += -CFLAGS "-DTB_NAME=$(TOP)"




##################################
# Target
##################################


sim:
	@mkdir -p $(OBJ_DIR) $(LOG_DIR) $(WAVE_DIR) $(OBJ_DIR_SIM) 

	@echo "[VERILATOR COMPILE]"
	$(VERILATOR) $(VERILATOR_FLAGS) \
	    $(RTL_SRCS) \
	    $(TB_SRCS) \
	    $(SIM_CSRCS)\
	    >$(LOG_DIR)/$(TOP).ver.comp_$(TIME_TAG).log 2>$(LOG_DIR)/$(TOP).ver.comp.err_$(TIME_TAG).log

	@echo "[VERILATOR RUN]"
	cd $(OBJ_DIR_SIM) && $(BIN) +trace \
	    >$(LOG_DIR)/$(TOP).ver.sim_$(TIME_TAG).log 2>$(LOG_DIR)/$(TOP).ver.sim.err_$(TIME_TAG).log
	@echo "[MOVE WAVE]"
	@if ls $(OBJ_DIR_SIM)/*.vcd 1>/dev/null 2>&1; then \
	    mv $(OBJ_DIR_SIM)/*.vcd \
	       $(WAVE_DIR)/$(TOP)_$(TIME_TAG).vcd ; \
	fi

	@if ls $(OBJ_DIR_SIM)/*.fst 1>/dev/null 2>&1; then \
	    mv $(OBJ_DIR_SIM)/*.fst \
	       $(WAVE_DIR)/$(TOP)_$(TIME_TAG).fst ; \
	fi
	
	@echo "[CLEAN EMPTY LOG]"
	@find $(LOG_DIR) -type f -size 0 -delete
	@find $(LOG_DIR) -type f -size 0 -print -delete

resim:
	@echo "[CLEAN OBJ_DIR_SIM]"
	@rm -rf $(OBJ_DIR_SIM)/*;  
	$(MAKE) sim

wave:
	gtkwave $$(ls -t $(WAVE_DIR)/$(TOP)_*.vcd | head -n 1) &