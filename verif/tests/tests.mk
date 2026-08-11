RVTESTS_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests
RVTESTSISA_DIR := $(RVTESTS_DIR)/isa

TESTS += coremark

RVTESTS_EXCLUDE ?= rv32ui/ma_data

RVTESTS_DISCOVERED := $(foreach t,$(filter-out rv32mi,$(RVTESTS_TYPE)), \
               $(addprefix $(t)/,$(basename $(notdir $(wildcard $(RVTESTSISA_DIR)/$(t)/*.S)))) )
RVTESTS_DISCOVERED += $(addprefix rv32mi/,$(RV32MI_TESTS))

RVTESTS_ALL := $(filter-out $(RVTESTS_EXCLUDE),$(RVTESTS_DISCOVERED))

# 为每个测试生成唯一目标名（替换 / 为 _）
RVTESTS_TARGETS := $(addprefix rv_comp_,$(subst /,_,$(RVTESTS_ALL)))

RVTESTS_INCLUDES := -I$(PROJECT_ROOT)/sw/include -I$(RVTESTS_DIR)/env -I$(RVTESTS_DIR)/isa/macros/scalar

YDRASIL_TESTS_DIR := $(PROJECT_ROOT)/verif/tests/ydrasil-tests/rv32ui
SW_ALIGNED_TESTS := \
    sw_data_boundary \
    sw_immediate_boundary \
    sw_address_boundary \
    sw_dependency_boundary \
    sw_stress \
    sw_register_matrix \
    sw_forwarding_alu \
    sw_forwarding_load \
    sw_forwarding_mul_div \
    sw_immediate_matrix \
    sw_endian_readback \
    sw_address_alias \
    sw_control_sequence \
    sw_dense_stress \
    sw_self_modify_exec \
    sw_producer_window \
    sw_load_interlock \
    sw_load_bypass_operands \
    sw_fence_stall \
    sw_fence_div_repro \
    sw_subword_readback_matrix \
    sw_div_fence_independent \
    sw_forwarding_bitmanip \
    sw_bitmanip_address_data \
    sw_bitmanip_immediate \
    sw_forwarding_alu_extended \
    sw_unsigned_branch_jalr \
    sw_jalr_lui_bypass \
    sw_forwarding_csr \
    sw_mul_div_edge_results
SW_ALIGNED_TESTS += sw_dual_issue
SW_NEW_ONLY_TESTS := \
    sw_misaligned_boundary \
    sw_misaligned_negative \
    sw_misaligned_overlap \
    sw_misaligned_boundaries \
    sw_misaligned_loadback \
    sw_misaligned_half_readback \
    sw_misaligned_forwarding_mix
SW_FORMAL_TESTS := $(SW_ALIGNED_TESTS) $(SW_NEW_ONLY_TESTS)
# Compatibility alias for callers that used the old combined-list name.
SW_ALL_TESTS := $(SW_FORMAL_TESTS)
YDRASIL_TEST_EXCLUDE ?= $(SW_NEW_ONLY_TESTS)
YDRASIL_TESTS := $(filter-out $(YDRASIL_TEST_EXCLUDE),\
    $(sort $(basename $(notdir $(wildcard $(YDRASIL_TESTS_DIR)/*.S)))))
YDRASIL_TEST_SPIKE_SKIP_TESTS := $(filter $(SW_NEW_ONLY_TESTS),$(YDRASIL_TESTS))
YDRASIL_TEST_SIM_TARGETS := $(addprefix ydrasil_test_sim_,$(YDRASIL_TESTS))
YDRASIL_TEST_RESULT_DIR ?= $(RESULT_DIR)/ydrasil-tests
YDRASIL_TEST_TIMEOUT ?= 100000
YDRASIL_TEST_JOBS ?= $(shell nproc)
YDRASIL_TEST_REUSE_MODEL ?= 0
VERIF_YDRASIL_TEST_LOG ?= $(VERIF_STATS_DIR)/ydrasil_tests_summary.log
SW_TEST_TARGETS := $(addprefix sw_comp_,$(SW_FORMAL_TESTS))
SW_TEST_INCLUDES := $(RVTESTS_INCLUDES) -I$(YDRASIL_TESTS_DIR)
SW_SINGLE_DB_COUNT := $(shell expr 1 + $(words $(SW_FORMAL_TESTS)))

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

sw_test_comp_aligned: $(addprefix sw_comp_,$(SW_ALIGNED_TESTS))

sw_test_comp_all: $(SW_TEST_TARGETS)

.PHONY: ydrasil_test_all ydrasil_test_build_all ydrasil_test_sim_all ydrasil_test_report ydrasil_test_clean

ydrasil_test_all:
	@$(MAKE) ydrasil_test_clean
	@$(MAKE) -j$(YDRASIL_TEST_JOBS) ydrasil_test_build_all REBUILD=1
	@if [ "$(YDRASIL_TEST_REUSE_MODEL)" != "1" ]; then \
		$(MAKE) comp VERILATOR_COVERAGE=$(VERILATOR_COVERAGE) VERILATOR_TRACE=0; \
	fi
	@$(MAKE) -j$(YDRASIL_TEST_JOBS) ydrasil_test_sim_all
	@$(MAKE) ydrasil_test_report

ydrasil_test_build_all: $(addprefix sw_comp_,$(YDRASIL_TESTS))

ydrasil_test_sim_all: $(YDRASIL_TEST_SIM_TARGETS)

ydrasil_test_sim_%:
	@name=$*; result_dir="$(YDRASIL_TEST_RESULT_DIR)"; mkdir -p "$$result_dir"; \
	status="$$result_dir/$$name.status"; run_log="$$result_dir/$$name.log"; \
	elf="$(SW_TEST_OUT_ROOT)/elf/$$name.elf"; itcm="$(SW_TEST_OUT_ROOT)/mem/$$name.itcm"; dtcm="$(SW_TEST_OUT_ROOT)/mem/$$name.dtcm"; \
	finish_pc=$$($(NM) -n "$$elf" 2>/dev/null | awk '$$3 == "write_tohost" { print "0x" $$1; exit }'); \
	finish_define=; if [ -n "$$finish_pc" ]; then finish_define="+finish_pc=$$finish_pc"; fi; \
	compare_mode=csv; spike_status=MISMATCH; trace_rows=N/A; \
	case " $(YDRASIL_TEST_SPIKE_SKIP_TESTS) " in *" $$name "*) compare_mode=none; spike_status=POLICY_SKIP;; esac; \
	set +e; $(MAKE) --no-print-directory sim_compare SIM_COMPARE="$$compare_mode" \
		COMPARE_NAME="ydrasil-tests/$$name" COMPARE_ELF="$$elf" \
		COMPARE_ITCM="$$itcm" COMPARE_DTCM="$$dtcm" \
		COMPARE_SIM_EXTRA_DEFINES="$$finish_define +cpp_timeout=$(YDRASIL_TEST_TIMEOUT) +sv_timeout=$(YDRASIL_TEST_TIMEOUT)" \
		SIM_COMPARE_MAX_MISMATCHES=3 >"$$run_log" 2>&1; rc=$$?; set -e; \
	hw_log="$(HW_TRACE_OUT_DIR)/ydrasil-tests/$$name/hw.log"; compare_log="$(SIM_COMPARE_DIR)/ydrasil-tests/$$name/compare.log"; \
	if [ "$$compare_mode" = csv ] && [ "$$rc" -eq 0 ] && grep -q '^MATCH: YES' "$$compare_log"; then \
		spike_status=MATCH; \
		trace_rows=$$(sed -n 's/^CSV compare PASS: \([0-9]*\) HW rows, \([0-9]*\) Spike rows.*/\1\/\2/p' "$$compare_log" | tail -1); \
	fi; \
	self_status=FAIL; if grep -q 'TEST_PASS' "$$hw_log" 2>/dev/null && \
		! grep -Eq 'TEST_FAIL|timeout reached|\$$readmem file not found' "$$hw_log"; then self_status=PASS; fi; \
	cycles=$$(sed -n 's/^PERF_METRIC:.*CYCLES= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	insts=$$(sed -n 's/^PERF_METRIC:.*INSTS= *\([0-9]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	ipc=$$(sed -n 's/^PERF_METRIC:.*IPC= *\([0-9.]*\).*/\1/p' "$$hw_log" 2>/dev/null | tail -1); \
	result=FAIL; if [ "$$self_status" = PASS ] && { [ "$$spike_status" = MATCH ] || [ "$$spike_status" = POLICY_SKIP ]; }; then result=PASS; fi; \
	echo "[ydrasil-tests/$$name] [SPIKE=$$spike_status] [SELF=$$self_status] [cycles=$${cycles:-N/A} insts=$${insts:-N/A} ipc=$${ipc:-N/A}] [trace_rows=$$trace_rows] [$$result]" > "$$status"

ydrasil_test_report:
	@mkdir -p "$(VERIF_STATS_DIR)"; rm -f "$(VERIF_YDRASIL_TEST_LOG)"; \
	failed=0; passed=0; matched=0; policy_skip=0; self_pass=0; total=$(words $(YDRASIL_TESTS)); \
	echo "[YDRASIL TESTS] EXCLUDED=$(YDRASIL_TEST_EXCLUDE) reason=unsupported misaligned accesses" | tee "$(VERIF_YDRASIL_TEST_LOG)"; \
	for name in $(YDRASIL_TESTS); do status="$(YDRASIL_TEST_RESULT_DIR)/$$name.status"; \
		if [ ! -s "$$status" ]; then line="[ydrasil-tests/$$name] [FAIL missing status]"; failed=1; \
		else line=$$(cat "$$status"); fi; \
		echo "$$line" | tee -a "$(VERIF_YDRASIL_TEST_LOG)"; \
		if echo "$$line" | grep -q '\[SPIKE=MATCH\]'; then matched=$$((matched+1)); fi; \
		if echo "$$line" | grep -q '\[SPIKE=POLICY_SKIP\]'; then policy_skip=$$((policy_skip+1)); fi; \
		if echo "$$line" | grep -q '\[SELF=PASS\]'; then self_pass=$$((self_pass+1)); fi; \
		if echo "$$line" | grep -q '\[PASS\]$$'; then passed=$$((passed+1)); else \
			failed=1; echo "[YDRASIL TESTS] Failure detail: $(YDRASIL_TEST_RESULT_DIR)/$$name.log"; \
			tail -40 "$(YDRASIL_TEST_RESULT_DIR)/$$name.log" 2>/dev/null || \
				tail -40 "$(SIM_COMPARE_DIR)/ydrasil-tests/$$name/compare.log" 2>/dev/null || true; \
		fi; \
	done; overall=PASS; if [ "$$failed" -ne 0 ]; then overall=FAIL; fi; \
	echo "[YDRASIL TESTS] CORRECTNESS=$$overall passed=$$passed spike_match=$$matched spike_policy_skip=$$policy_skip self_pass=$$self_pass total=$$total" | tee -a "$(VERIF_YDRASIL_TEST_LOG)"; \
	echo "[VERIF] Ydrasil tests report: $(VERIF_YDRASIL_TEST_LOG)"; exit $$failed

ydrasil_test_clean:
	@rm -rf "$(YDRASIL_TEST_RESULT_DIR)" "$(HW_TRACE_OUT_DIR)/ydrasil-tests" \
		"$(SIM_COMPARE_DIR)/ydrasil-tests" "$(SPIKE_OUT_DIR)/ydrasil-tests"

sw_comp_%:
	@echo ">>> Building Ydrasil SW test $*"
	@$(MAKE) -C sw rv_comp_genmem \
		ARCH=$(ARCH) \
		ABI=$(ABI) \
		NAME=$* \
		SRC=$(firstword $(wildcard $(YDRASIL_TESTS_DIR)/$*.S)) \
		OUT_DIR=$(SW_TEST_OUT_ROOT) \
		COMP_MODE=rvtest \
		INCLUDES="$(SW_TEST_INCLUDES)"

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
	finish_pc=$$($(NM) -n "$$elf_dir/$$base.elf" 2>/dev/null | awk '$$3 == "write_tohost" { print "0x" $$1; exit }'); \
	finish_define=; if [ -n "$$finish_pc" ]; then finish_define="+finish_pc=$$finish_pc"; fi; \
	mkdir -p $$result_dir; \
	if $(MAKE) --no-print-directory sim_compare \
		COMPARE_NAME=$$typ/$$base \
		COMPARE_ELF=$$elf_dir/$$base.elf \
		COMPARE_ITCM=$$mem_dir/$$base.itcm \
		COMPARE_DTCM=$$mem_dir/$$base.dtcm \
		COMPARE_OUT_DIR=$$compare_dir \
		COMPARE_SIM_EXTRA_DEFINES="$$finish_define" \
		> $$result_dir/$$base.log 2>&1; then \
		match_status=MATCH; \
	else \
		match_status=MISMATCH; \
	fi; \
	hw_log=$(HW_TRACE_OUT_DIR)/$$typ/$$base/hw.log; \
	[ -f "$$hw_log" ] || hw_log=$$result_dir/$$base.log; \
	perf_metric=$$(grep -m1 "^PERF_METRIC:" "$$hw_log"); \
	cycles=$$(printf '%s\n' "$$perf_metric" | sed -n 's/.*CYCLES=\([0-9]*\).*/\1/p'); \
	insts=$$(printf '%s\n' "$$perf_metric" | sed -n 's/.*INSTS=\([0-9]*\).*/\1/p'); \
	ipc=$$(printf '%s\n' "$$perf_metric" | sed -n 's/.*IPC=\([0-9.]*\).*/\1/p'); \
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

ppa_rvtest_report:
	@mkdir -p "$(VERIF_STATS_DIR)"; \
	rm -f "$(VERIF_RVTEST_LOG)"; \
	for typ in $(RVTESTS_TYPE); do \
		result_dir=$(RVTESTS_RESULT_DIR)/$$typ; \
		[ -d "$$result_dir" ] || continue; \
		echo "========== $$typ ==========" >> "$(VERIF_RVTEST_LOG)"; \
		for f in $$(ls $$result_dir/*.status 2>/dev/null | sort); do \
			awk -f "$(PROJECT_ROOT)/verif/tests/fix_test_all_summary.awk" "$$f" >> "$(VERIF_RVTEST_LOG)"; \
		done; \
	done; \
	echo "[VERIF] RV test report: $(VERIF_RVTEST_LOG)"

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
