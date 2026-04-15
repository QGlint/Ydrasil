IVERILOG ?= iverilog

OBJ_DIR_SIM := $(OBJ_DIR)/iverilog

VFLAGS := -g2012
VFLAGS += $(addprefix -D,$(DEFINES))
VFLAGS += $(addprefix -I,$(INC_DIRS))
VFLAGS += -Wall
VFLAGS += -D IVERILOG_VCD

sim:
	@mkdir -p $(OBJ_DIR) $(OBJ_DIR_SIM)
	@echo "[IVERILOG COMPILE]"
	cd $(OBJ_DIR_SIM) && $(IVERILOG) $(VFLAGS) \
	    -s $(TOP) \
	    $(RTL_SRCS) $(TB_SRCS) \
	    -o $(OBJ_DIR_SIM)/simv \
	    > $(LOG_DIR)/$(TOP).iv.comp_$(TIME_TAG).log 2> $(LOG_DIR)/$(TOP).iv.comp.err_$(TIME_TAG).log
	
	@echo "[RUN SIMULATION]"
	cd $(OBJ_DIR_SIM) && vvp simv \
	    > $(LOG_DIR)/$(TOP).iv.sim_$(TIME_TAG).log 2> $(LOG_DIR)/$(TOP).iv.sim.err_$(TIME_TAG).log
	@echo "[MOVE WAVE]"
	@if ls $(OBJ_DIR_SIM)/*.vcd 1>/dev/null 2>&1; then \
	    mv $(OBJ_DIR_SIM)/*.vcd \
	       $(WAVE_DIR)/$(TOP)_$(TIME_TAG).vcd ; \
	fi

	@echo "[CLEAN EMPTY LOG]"
	@find $(LOG_DIR) -type f -size 0 -delete
	@find $(LOG_DIR) -type f -size 0 -print -delete

resim:
	@rm -f $(OBJ_DIR_SIM)/*
	$(MAKE) sim

wave:
	gtkwave $$(ls -t $(WAVE_DIR)/$(TOP)_*.vcd | head -n 1) &