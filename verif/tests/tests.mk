RVTESTS_DIR := $(PROJECT_ROOT)/verif/tests/riscv-tests
RVTESTSISA_DIR := $(RVTESTS_DIR)/isa

RVTESTS_ALL := $(foreach t,$(RVTESTS_TYPE), \
               $(addprefix $(t)/,$(basename $(notdir $(wildcard $(RVTESTSISA_DIR)/$(t)/*.S)))) )

# 为每个测试生成唯一目标名（替换 / 为 _）
RVTESTS_TARGETS := $(addprefix rv_comp_,$(subst /,_,$(RVTESTS_ALL)))

RVTESTS_INCLUDES := -I$(RVTESTS_DIR)/env/p -I$(RVTESTS_DIR)/isa/macros/scalar

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
		OUT_DIR=$(PROJECT_ROOT)/build/riscv_tests/$$type \
		COMP_MODE=rvtest \
		INCLUDES="$(RVTESTS_INCLUDES)"

rv_bench_%:
	@name=$*; \
	echo ">>> Building benchmark $$name"; \
	$(MAKE) -C sw rv_comp_genmem \
		NAME=$$name \
		SRC="$(wildcard $(RVBENCH_DIR)/$$name/*.c) $(wildcard $(RVBENCH_DIR)/$$name/*.S) $(wildcard $(RVBENCH_COMMON)/*.c) $(wildcard $(RVBENCH_COMMON)/*.S)" \
		OUT_DIR=$(PROJECT_ROOT)/build/riscv_test/benchmark \
		COMP_MODE=bench \
		INCLUDES="$(RVBENCH_INCLUDES)" \
		LDSCRIPT=$(RVBENCH_LDSCRIPT) \
		RV_CFLAGS="$(RISCV_CFLAGS) $(RVBENCH_CFLAGS)" \
		LDFLAGS="-lm -lgcc"