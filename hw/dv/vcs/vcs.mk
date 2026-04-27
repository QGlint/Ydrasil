##################################
# Tool
##################################

VCS ?= vcs
VERDI ?= verdi
UVM ?= 0

##################################
# Paths
OBJ_DIR_SIM := $(OBJ_DIR)/vcs

##################################
# VCS FLAGS
##################################

VFLAGS := -full64 -sverilog -timescale=1ns/1ps \
          -debug_access+all -kdb -lca \

VFLAGS += -j $(shell nproc)
VFLAGS += -Mupdate


DEFINES += VCS_FSDB SYNTHESIS

VFLAGS += $(addprefix +define+,$(DEFINES))
VFLAGS += $(addprefix +incdir+,$(INC_DIRS))


##################################
# UVM / VERDI
##################################
ifeq ($(UVM),1)
UVM_VER ?= -ntb_opts uvm-1.2
NOVAS_HOME ?= $(VERDI_HOME)

FSDB_PLI = -P $(NOVAS_HOME)/share/PLI/VCS/LINUX64/novas.tab \
           $(NOVAS_HOME)/share/PLI/VCS/LINUX64/pli.a

VFLAGS += $(UVM_VER) $(FSDB_PLI)
endif
##################################
# Output
##################################

SIMV := $(OBJ_DIR_SIM)/simv
FSDB := $(TOP).fsdb



##################################
# Simulation Options
##################################

SIM_OPTS := -lca 

##################################
# Targets
##################################

VERDIFLAGS := -dbdir $(OBJ_DIR_SIM)/simv.daidir/

all: comp sim wave

comp:
	@mkdir -p $(OBJ_DIR) $(LOG_DIR) $(WAVE_DIR) $(OBJ_DIR_SIM) 

ifeq ($(USE_BENDER),1)
	@mkdir -p $(FLIST_DIR)
	@echo "[BENDER FLIST]"
	@if [ -f $(IP_DIR)/Bender.yml ] || [ -f $(IP_DIR)/Bender.yaml ]; then \
		cd $(IP_DIR) && $(BENDER) script flist $(BENDER_TARGET_ARGS) > $(FLIST_FILE); \
	else \
		echo "ERROR: USE_BENDER=1 but Bender.yml/Bender.yaml not found at $(IP_DIR)"; \
		exit 1; \
	fi
endif

	@echo "[VCS COMPILE]"
	@cd $(OBJ_DIR_SIM) && $(VCS) $(VFLAGS) \
	    -o $(SIMV) \
	    $(if $(filter 1,$(USE_BENDER)),-f $(FLIST_FILE),$(RTL_SRCS)) $(if $(and $(filter 1,$(USE_BENDER)),$(filter 1,$(BENDER_INCLUDE_TB))),,$(TB_SRCS)) \
	    -top $(TOP) \
	    -l $(LOG_DIR)/$(TOP).vcs_compile_$(TIME_TAG).log 2>$(LOG_DIR)/$(TOP).vcs_compile.err_$(TIME_TAG).log

sim:
	@echo "[VCS RUN]"
	@cd $(OBJ_DIR_SIM) && $(SIMV) $(SIM_OPTS) +fsdb \
	    -l $(LOG_DIR)/$(TOP).vcs_sim_$(TIME_TAG).log 2>$(LOG_DIR)/$(TOP).vcs_sim.err_$(TIME_TAG).log
	@echo "[MOVE WAVE]"
	@if [ -f $(OBJ_DIR_SIM)/$(FSDB) ]; then \
	    mv $(OBJ_DIR_SIM)/$(FSDB) \
	       $(WAVE_DIR)/$(TOP)_$(TIME_TAG).fsdb ; \
	fi
	
	@echo "[CLEAN EMPTY LOG]"
	@find $(LOG_DIR) -type f -size 0 -delete
	@find $(LOG_DIR) -type f -size 0 -print -delete

resim:
	@echo "[clean OBJ_DIR_SIM]"
	@rm -rf $(OBJ_DIR_SIM)/*
	$(MAKE) sim

wave:
	@echo "[LAUNCH VERDI]"
	LATEST_FSDB=$(shell ls -t $(WAVE_DIR)/$(TOP)_*.fsdb 2>/dev/null | head -n1) ; \
	cd $(OBJ_DIR) && verdi $(VERDIFLAGS) -ssf $$LATEST_FSDB & 