RVTESTS_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests
RVTESTSISA_DIR := $(RVTESTS_DIR)/isa

RVTESTS_ALL := $(foreach t,$(RVTESTS_TYPE), \
               $(addprefix $(t)/,$(basename $(notdir $(wildcard $(RVTESTSISA_DIR)/$(t)/*.S)))) )

# 为每个测试生成唯一目标名（替换 / 为 _）
RVTESTS_TARGETS := $(addprefix rv_comp_,$(subst /,_,$(RVTESTS_ALL)))

RVTESTS_INCLUDES := -I$(PROJECT_ROOT)/sw/include -I$(RVTESTS_DIR)/env -I$(RVTESTS_DIR)/isa/macros/scalar

RVBENCH_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests/benchmarks
RVBENCH_COMMON := $(RVBENCH_DIR)/common

RVBENCH_LIST := \
    median \
    qsort \
    rsort \
    towers \
    vvadd \
    memcpy \
    multiply \
    mm \
    dhrystone \
    spmv \
    mt-vvadd \
    mt-matmul \
    mt-memcpy \
    pmp \
    vec-memcpy \
    vec-daxpy \
    vec-sgemm \
    vec-strcmp

RVBENCH_TARGETS := $(addprefix rv_bench_,$(RVBENCH_LIST))

RVBENCH_INCLUDES := -I$(RVBENCH_DIR)/../env -I$(RVBENCH_COMMON) $(addprefix -I$(RVBENCH_DIR)/,$(RVBENCH_LIST))
RVBENCH_LDSCRIPT := $(RVBENCH_COMMON)/test.ld
RVBENCH_CFLAGS := -U_FORTIFY_SOURCE -DPREALLOCATE=1 -std=gnu99 -O2 
RVBENCH_CFLAGS += -ffast-math
RVBENCH_CFLAGS +=  -fno-common -fno-builtin-printf -fno-tree-loop-distribute-patterns 
RVBENCH_CFLAGS += -Wno-implicit-int -Wno-implicit-function-declaration

rv_test_comp_genmem: $(RVTESTS_TARGETS)

rv_test_comp_genmem_rebuild:
	@$(MAKE) rv_test_comp_genmem REBUILD=1

rv_bench_comp_genmem: $(RVBENCH_TARGETS)

rv_bench_comp_genmem_rebuild:
	@$(MAKE) rv_bench_comp_genmem REBUILD=1

rv_comp_%:
	@name=$*; \
	group=$${name%%_*}; \
	base=$${name#*_}; \
	type=$$group; \
	echo ">>> Building $$group/$$base"; \
	$(MAKE) -C sw rv_comp_genmem \
		NAME=$$name \
		SRC=$(RVTESTSISA_DIR)/$$group/$$base.S \
		OUT_DIR=$(RVTESTS_OUT_ROOT)/$$type \
		COMP_MODE=rvtest \
		INCLUDES="$(RVTESTS_INCLUDES)"

rv_bench_%:
	@name=$*; \
	echo ">>> Building benchmark $$name"; \
	$(MAKE) -C sw rv_comp_genmem \
		NAME=$$name \
		SRC="$(wildcard $(RVBENCH_DIR)/$$name/*.c) $(wildcard $(RVBENCH_DIR)/$$name/*.S) $(wildcard $(RVBENCH_COMMON)/*.c) $(wildcard $(RVBENCH_COMMON)/*.S)" \
		OUT_DIR=$(RVTESTS_OUT_ROOT)/benchmark \
		COMP_MODE=bench \
		INCLUDES="$(RVBENCH_INCLUDES)" \
		LDSCRIPT=$(RVBENCH_LDSCRIPT) \
		RV_CFLAGS="$(RISCV_CFLAGS) $(RVBENCH_CFLAGS)" \
		LDFLAGS="-lm -lgcc"


rv_test_sim_all: $$(RVTESTS_SIM_TARGETS)

rv_sim_%:
	@name=$*; \
	typ=$${name%%_*}; \
	base=$${name#*_}; \
	mem_dir=$(RVTESTS_OUT_ROOT)/$$typ/mem; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	mkdir -p $$result_dir; \
	$(MAKE) LOG_OUTPUT=0 Compile_optimization=0 sim \
		ITCM_FILE=$$mem_dir/$$base.itcm \
		DTCM_FILE=$$mem_dir/$$base.dtcm \
		> $$result_dir/$$base.log 2>&1; \
	cycles=$$(grep -o "CYCLES=[0-9]*" $$result_dir/$$base.log | cut -d= -f2); \
	insts=$$(grep -o "INSTS=[0-9]*" $$result_dir/$$base.log | cut -d= -f2); \
	ipc=$$(grep -o "IPC=[0-9.]*" $$result_dir/$$base.log | cut -d= -f2); \
	if grep -q "TEST_PASS" $$result_dir/$$base.log; then \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ PASSED ]" >> $$result_dir/$$base.log; \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ PASSED ]" > $$result_dir/$$base.status; \
	else \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ FAILED ]" >> $$result_dir/$$base.log; \
		echo "[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc] [ FAILED ]" > $$result_dir/$$base.status; \
	fi

rv_test_report_all: $(RVTESTS_REPORT_TARGETS)

rv_report_%:
	@typ=$*; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	echo "========== $$typ =========="; \
	for f in $$(ls $$result_dir/*.status 2>/dev/null | sort); do \
		line=$$(cat $$f); \
		left=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\1/'); \
		mid=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\2/'); \
		tag=$$(echo "$$line" | sed 's/\(.*\)\(\[Cycles:.*\]\)\( \[ [A-Z]* \]\)/\3/'); \
		if echo "$$tag" | grep -q "\[ PASSED \]"; then \
			echo -e "$$left\033[34m$$mid\033[0m \033[32m$$tag\033[0m"; \
		else \
			echo -e "$$left\033[34m$$mid\033[0m \033[31m$$tag\033[0m"; \
		fi; \
	done

rv_test_summary_all: $(RVTESTS_SUMMARY_TARGETS)

rv_summary_%:
	@typ=$*; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	summary_file=$(RVTESTS_RESULT_DIR)/$${typ}_summary.log; \
	rm -f $$summary_file; \
	for log in $$result_dir/*.log; do \
		[ -e "$$log" ] || continue; \
		base=$$(basename $$log .log); \
		if grep -q "TEST_PASS" $$log; then \
			echo "$$base: PASS" >> $$summary_file; \
		else \
			echo "$$base: FAIL" >> $$summary_file; \
		fi; \
	done; \
	echo "Summary: $$summary_file"