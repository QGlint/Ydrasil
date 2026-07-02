RVTESTS_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests
RVTESTSISA_DIR := $(RVTESTS_DIR)/isa

TESTS += coremark

RVTESTS_EXCLUDE ?= rv32ui/ma_data

RVTESTS_DISCOVERED := $(foreach t,$(RVTESTS_TYPE), \
               $(addprefix $(t)/,$(basename $(notdir $(wildcard $(RVTESTSISA_DIR)/$(t)/*.S)))) )

RVTESTS_ALL := $(filter-out $(RVTESTS_EXCLUDE),$(RVTESTS_DISCOVERED))

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
		ARCH=$(ARCH) \
		ABI=$(ABI) \
		NAME=$$name \
		SRC=$(RVTESTSISA_DIR)/$$group/$$base.S \
		OUT_DIR=$(RVTESTS_OUT_ROOT)/$$type \
		COMP_MODE=rvtest \
		INCLUDES="$(RVTESTS_INCLUDES)"

rv_bench_%:
	@name=$*; \
	echo ">>> Building benchmark $$name"; \
	$(MAKE) -C sw rv_comp_genmem \
		ARCH=$(ARCH) \
		ABI=$(ABI) \
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
	elf_dir=$(RVTESTS_OUT_ROOT)/$$typ/elf; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	compare_dir=$(SIM_COMPARE_DIR)/$$typ/$$base; \
	mkdir -p $$result_dir; \
	if $(MAKE) --no-print-directory sim_compare \
		COMPARE_NAME=$$typ/$$base \
		COMPARE_ELF=$$elf_dir/$$base.elf \
		COMPARE_ITCM=$$mem_dir/$$base.itcm \
		COMPARE_DTCM=$$mem_dir/$$base.dtcm \
		COMPARE_OUT_DIR=$$compare_dir \
		> $$result_dir/$$base.log 2>&1; then \
		match_status=MATCH; \
	else \
		match_status=MISMATCH; \
	fi; \
	hw_log=$(HW_TRACE_OUT_DIR)/$$typ/$$base/hw.log; \
	[ -f "$$hw_log" ] || hw_log=$$result_dir/$$base.log; \
	cycles=$$(grep -o "CYCLES=[0-9]*" $$hw_log | cut -d= -f2); \
	insts=$$(grep -o "INSTS=[0-9]*" $$hw_log | cut -d= -f2); \
	ipc=$$(grep -o "IPC=[0-9.]*" $$hw_log | cut -d= -f2); \
	bp_acc=$$(grep -m1 "^PERF_BP_ACC:" $$hw_log | sed -n 's/.*ACC=\([0-9.]*\).*/\1/p'); \
	if [ -z "$$bp_acc" ]; then \
		bp_acc=$$(grep -m1 "^PERF_BRANCH:" $$hw_log | sed -n 's/.*ACC=\([0-9.]*\).*/\1/p'); \
	fi; \
	[ -n "$$bp_acc" ] || bp_acc=N/A; \
	if [ "$(SIM_COMPARE)" = "none" ]; then \
		match_status=SKIP; \
	fi; \
	if grep -q "TEST_PASS" $$hw_log; then \
		pass_status=PASS; \
	else \
		pass_status=FAIL; \
	fi; \
	status_line="[$$typ/$$base] [Cycles: $$cycles | Insts: $$insts | IPC: $$ipc | BP Acc: $$bp_acc%] [$$match_status] [$$pass_status]"; \
	echo "$$status_line" >> $$result_dir/$$base.log; \
	echo "$$status_line" > $$result_dir/$$base.status

rv_test_report_all: $(RVTESTS_REPORT_TARGETS)

rv_report_%:
	@typ=$*; \
	result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
	echo "========== $$typ =========="; \
	for f in $$(ls $$result_dir/*.status 2>/dev/null | sort); do \
		line=$$(cat $$f); \
		colored=$$(printf '%s\n' "$$line" | sed \
			-e 's/\(\[Cycles:[^]]*\]\)/\\033[34m\1\\033[0m/' \
			-e 's/\[MISMATCH\]/\\033[31m[MISMATCH]\\033[0m/g' \
			-e 's/\[MATCH\]/\\033[32m[MATCH]\\033[0m/g' \
			-e 's/\[SKIP\]/\\033[34m[SKIP]\\033[0m/g' \
			-e 's/\[FAIL\]/\\033[31m[FAIL]\\033[0m/g' \
			-e 's/\[PASS\]/\\033[32m[PASS]\\033[0m/g'); \
		printf '%b\n' "$$colored"; \
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
		if grep -q "\[PASS\]" $$result_dir/$$base.status 2>/dev/null; then \
			echo "$$base: PASS" >> $$summary_file; \
		else \
			echo "$$base: FAIL" >> $$summary_file; \
		fi; \
	done; \
	echo "Summary: $$summary_file"
