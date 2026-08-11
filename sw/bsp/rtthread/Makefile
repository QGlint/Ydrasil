SHELL := /bin/bash

ROOT := $(abspath ../../..)
SW_DIR := $(ROOT)/sw
SCONS ?= scons
PROFILES ?= Os O2 O3
JOBS ?= 4
ITERATIONS ?= 1

OUT_ROOT ?= $(ROOT)/build/app/rtthread-coremark
RESULT_ROOT ?= $(ROOT)/build/log/test_results/rtthread-coremark
MODEL_DIR ?= $(ROOT)/build/ydrasil_core_tb-rtthread-128k
MODEL_LOG_DIR ?= $(ROOT)/build/log/rtthread-128k
ITCM_BYTES ?= 131072
ITCM_ADDR_WIDTH ?= 15
LINKER ?= $(ROOT)/sw/bsp/link.lds
PPA_DIR ?= $(ROOT)/build/PPA
COREMARK_PPA_LOG ?= $(PPA_DIR)/coremark_opt_summary.log
COREMARK_REPORT_SCRIPT ?= $(ROOT)/sw/bsp/rtthread/coremark_report.sh

UTEST_OUT_ROOT ?= $(ROOT)/build/app/rtthread-utest
UTEST_RESULT_ROOT ?= $(ROOT)/build/log/test_results/rtthread-utest
UTEST_MODEL_DIR ?= $(ROOT)/build/ydrasil_core_tb-rtthread-utest-128k
UTEST_MODEL_LOG_DIR ?= $(ROOT)/build/log/rtthread-utest-128k
UTEST_ITCM_BYTES ?= 131072
UTEST_ITCM_ADDR_WIDTH ?= 15
UTEST_LINKER ?= $(ROOT)/sw/bsp/link.lds
UTEST_PPA_LOG ?= $(PPA_DIR)/rtthread_utest_summary.log

OPT_Os := -Os
OPT_O2 := -O2
OPT_O3 := -O3

.PHONY: all coremark coremark-build coremark-build-all coremark-sim coremark-sim-all \
        coremark-model baremetal-coremark coremark-report coremark-compare \
        utest rtthread-utest utest-build utest-sim utest-model utest-report \
        utest-clean clean

all: coremark-compare

coremark: coremark-build

coremark-build: coremark-build-all

coremark-build-all:
	@set -e; for profile in $(PROFILES); do $(MAKE) --no-print-directory coremark-build-$$profile; done

define COREMARK_BUILD_template
.PHONY: coremark-build-$(1)
coremark-build-$(1): $(LINKER)
	@$(MAKE) --no-print-directory -C "$(SW_DIR)" \
		RTTHREAD_SCONS="$(SCONS)" \
		RTTHREAD_JOBS=$(JOBS) \
		RTTHREAD_COREMARK_OUTPUT_ROOT="$(OUT_ROOT)" \
		RTTHREAD_COREMARK_LINKER="$(LINKER)" \
		RTTHREAD_COREMARK_ITERATIONS=$(ITERATIONS) \
		rtthread-coremark-build-$(1)
endef
$(foreach profile,$(PROFILES),$(eval $(call COREMARK_BUILD_template,$(profile))))

coremark-model:
	@mkdir -p "$(MODEL_DIR)" "$(MODEL_LOG_DIR)"
	@$(MAKE) -C "$(ROOT)" --no-print-directory comp FPU=0 \
		OBJ_DIR="$(MODEL_DIR)" LOG_DIR="$(MODEL_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(ITCM_ADDR_WIDTH) VERILATOR_TRACE=0

coremark-sim: coremark-sim-all

coremark-sim-all: coremark-model coremark-build-all
	@set -e; for profile in $(PROFILES); do $(MAKE) --no-print-directory coremark-sim-$$profile; done

define COREMARK_SIM_template
.PHONY: coremark-sim-$(1)
coremark-sim-$(1): coremark-build-$(1) coremark-model
	@mkdir -p "$(RESULT_ROOT)"; set +e; \
	$(MAKE) -C "$(ROOT)" --no-print-directory sim_compare FPU=0 SIM_COMPARE=none \
		COMPARE_NAME="rtthread-coremark/$(1)" \
		COMPARE_ELF="$(OUT_ROOT)/$(1)/rtthread_coremark.elf" \
		COMPARE_ITCM="$(OUT_ROOT)/$(1)/rtthread_coremark.itcm" \
		COMPARE_DTCM="$(OUT_ROOT)/$(1)/rtthread_coremark.dtcm" \
		OBJ_DIR="$(MODEL_DIR)" LOG_DIR="$(MODEL_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(ITCM_ADDR_WIDTH) \
		COMPARE_SIM_EXTRA_DEFINES="+cpp_timeout=3000000 +sv_timeout=3000000" \
		> "$(RESULT_ROOT)/$(1).run.log" 2>&1; rc=$$$$?; set -e; \
	hw_log="$(ROOT)/build/sim/hw/rtthread-coremark/$(1)/hw.log"; \
	cycles=$$$$(grep -o 'CYCLES=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	insts=$$$$(grep -o 'INSTS=[0-9]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	ipc=$$$$(grep -o 'IPC=[0-9.]*' "$$$$hw_log" 2>/dev/null | tail -1 | cut -d= -f2); \
	score=$$$$(sed -n 's/^CoreMark 1\.0 : *\([0-9.]*\).*/\1/p' "$$$$hw_log" 2>/dev/null | tail -1); \
	result=FAIL; if [ "$$$$rc" -eq 0 ] && grep -q 'Correct operation validated' "$$$$hw_log" && grep -q 'COREMARK DONE' "$$$$hw_log"; then result=PASS; fi; \
	echo "[$(1)] [$$$$result] cycles=$$$${cycles:-N/A} insts=$$$${insts:-N/A} ipc=$$$${ipc:-N/A} score=$$$${score:-N/A}" | tee "$(RESULT_ROOT)/$(1).status"; \
	exit "$$$$rc"
endef
$(foreach profile,$(PROFILES),$(eval $(call COREMARK_SIM_template,$(profile))))

baremetal-coremark:
	@$(MAKE) -C "$(ROOT)" --no-print-directory coremark_opt_all FPU=0 \
		APP_OPT_PROFILES="$(PROFILES)" APP_OPT_JOBS=1 \
		COREMARK_OPT_TIMEOUT=3000000

coremark-compare: coremark-sim-all baremetal-coremark
	@$(MAKE) --no-print-directory coremark-report
	@echo ""
	@echo "CoreMark single-iteration comparison (FPU=0)"
	@printf '%-8s %-55s %-55s\n' profile baremetal rtthread
	@for profile in $(PROFILES); do \
		bare="$(ROOT)/build/log/test_results/coremark-opt/$$profile.status"; \
		rtt="$(RESULT_ROOT)/$$profile.status"; \
		printf '%-8s %-55s %-55s\n' "$$profile" "$$(cat "$$bare" 2>/dev/null || echo MISSING)" "$$(cat "$$rtt" 2>/dev/null || echo MISSING)"; \
		done

coremark-report:
	@mkdir -p "$(PPA_DIR)"
	@$(COREMARK_REPORT_SCRIPT) "$(COREMARK_PPA_LOG)" \
		"$(ROOT)/build/log/test_results/coremark-opt" \
		"$(RESULT_ROOT)" $(PROFILES)

utest rtthread-utest: utest-sim

utest-build: $(UTEST_LINKER)
	@$(MAKE) --no-print-directory -C "$(SW_DIR)" \
		RTTHREAD_UTEST_OUTPUT_ROOT="$(UTEST_OUT_ROOT)" \
		RTTHREAD_UTEST_LINKER="$(UTEST_LINKER)" \
		rtthread-utest-build

utest-model:
	@mkdir -p "$(UTEST_MODEL_DIR)" "$(UTEST_MODEL_LOG_DIR)"
	@$(MAKE) -C "$(ROOT)" --no-print-directory comp FPU=0 \
		OBJ_DIR="$(UTEST_MODEL_DIR)" LOG_DIR="$(UTEST_MODEL_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(UTEST_ITCM_ADDR_WIDTH) VERILATOR_TRACE=0

utest-sim: utest-model utest-build
	@mkdir -p "$(UTEST_RESULT_ROOT)"; set +e; \
	$(MAKE) -C "$(ROOT)" --no-print-directory sim_compare FPU=0 SIM_COMPARE=none \
		COMPARE_NAME="rtthread-utest" \
		COMPARE_ELF="$(UTEST_OUT_ROOT)/rtthread_utest.elf" \
		COMPARE_ITCM="$(UTEST_OUT_ROOT)/rtthread_utest.itcm" \
		COMPARE_DTCM="$(UTEST_OUT_ROOT)/rtthread_utest.dtcm" \
		OBJ_DIR="$(UTEST_MODEL_DIR)" LOG_DIR="$(UTEST_MODEL_LOG_DIR)" \
		ITCM_ADDR_WIDTH_OVERRIDE=$(UTEST_ITCM_ADDR_WIDTH) \
		COMPARE_SIM_EXTRA_DEFINES="+cpp_timeout=3000000 +sv_timeout=3000000 +no_finish_on_tohost" \
		> "$(UTEST_RESULT_ROOT)/run.log" 2>&1; rc=$$?; set -e; \
	hw_log="$(ROOT)/build/sim/hw/rtthread-utest/hw.log"; \
	result=FAIL; marker=""; \
	if [ "$$rc" -eq 0 ] && [ -f "$$hw_log" ] && grep -q 'RT_UTEST PASS' "$$hw_log"; then result=PASS; marker=$$(grep 'RT_UTEST PASS' "$$hw_log" | tail -1); fi; \
	if [ -z "$$marker" ] && [ -f "$$hw_log" ]; then marker=$$(grep 'RT_UTEST ' "$$hw_log" | tail -1 || true); fi; \
	echo "[RTTHREAD UTEST] [$$result] $${marker:-no PASS marker}" | tee "$(UTEST_RESULT_ROOT)/status"; \
	if [ "$$result" = PASS ]; then exit 0; else exit 1; fi

utest-report:
	@mkdir -p "$(PPA_DIR)"; status="$(UTEST_RESULT_ROOT)/status"; \
	if [ ! -f "$$status" ]; then echo "[RTTHREAD UTEST] [FAIL] missing status" > "$(UTEST_PPA_LOG)"; cat "$(UTEST_PPA_LOG)"; exit 1; fi; \
	cat "$$status" > "$(UTEST_PPA_LOG)"; cat "$(UTEST_PPA_LOG)"; \
	grep -q '\[PASS\]' "$(UTEST_PPA_LOG)"

utest-clean:
	@rm -rf "$(UTEST_OUT_ROOT)" "$(UTEST_RESULT_ROOT)" "$(UTEST_MODEL_DIR)" \
		"$(UTEST_MODEL_LOG_DIR)" "$(UTEST_LINKER)" "$(UTEST_PPA_LOG)"

clean:
	@rm -rf "$(OUT_ROOT)" "$(RESULT_ROOT)" "$(MODEL_DIR)" "$(MODEL_LOG_DIR)" "$(LINKER)" \
		"$(UTEST_OUT_ROOT)" "$(UTEST_RESULT_ROOT)" "$(UTEST_MODEL_DIR)" \
		"$(UTEST_MODEL_LOG_DIR)" "$(UTEST_LINKER)" "$(UTEST_PPA_LOG)"
