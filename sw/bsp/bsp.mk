ifndef SIM_ROOT_DIR
$(error SIM_ROOT_DIR is not set. Please pass SIM_ROOT_DIR from the main Makefile, e.g. 'make SIM_ROOT_DIR=/path/to/sim_root')
endif

include $(SIM_ROOT_DIR)/make.conf

BIN_TO_MEM    := $(BSP_DIR)/../../tools/BinToMem.py

BUILD_DIR ?= .

# 自动搜索汇编和C源文件
ASM_SRCS := $(wildcard $(BSP_DIR)/*.S)
C_SRCS := $(wildcard $(BSP_DIR)/lib/*.c)
ifdef C_SRC_DIR
C_SRCS += $(wildcard $(C_SRC_DIR)/*.c)
INCLUDES += -I$(C_SRC_DIR)
endif

LINKER_SCRIPT := $(BSP_DIR)/link.lds

INCLUDES += -I$(BSP_DIR)/include

# 目标文件和产物输出到BUILD_DIR
ASM_OBJS := $(patsubst %.S,${BUILD_DIR}/%.o,$(notdir $(ASM_SRCS)))
C_OBJS := $(patsubst %.c,${BUILD_DIR}/%.o,$(notdir $(C_SRCS)))

LINK_OBJS := $(ASM_OBJS) $(C_OBJS)
LINK_DEPS := $(LINKER_SCRIPT)

TARGET ?= ${BUILD_DIR}/main.elf

CLEAN_OBJS += $(TARGET) $(LINK_OBJS) ${BUILD_DIR}/main.dump ${BUILD_DIR}/main.bin ${BUILD_DIR}/main.hex ${BUILD_DIR}/main.mem

CFLAGS += --sysroot=$(RISCV_GCC_ROOT)/riscv64-unknown-elf
CFLAGS += -march=$(DEFAULT_RISCV_ARCH)
CFLAGS += -mabi=$(DEFAULT_RISCV_ABI)
CFLAGS += -mcmodel=$(DEFAULT_RISCV_MCMODEL) 
CFLAGS += -ffunction-sections -fdata-sections -fno-builtin-printf -fno-builtin-malloc
# CFLAGS += -O0
# CFLAGS += -DSIMULATION_XLSPIKE
CFLAGS += -DSDK_BANNER=1

# 禁用工具链自带的启动文件和标准库
LDFLAGS += -nostartfiles -nostdlib -T $(LINKER_SCRIPT)
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -march=$(DEFAULT_RISCV_ARCH)
LDFLAGS += -mabi=$(DEFAULT_RISCV_ABI)
# 添加32位库路径
LDFLAGS += -L$(RISCV_GCC_ROOT)/riscv64-unknown-elf/lib/rv32im/ilp32
LDFLAGS += -L$(RISCV_GCC_ROOT)/lib/gcc/riscv64-unknown-elf/12.2.0/rv32im/ilp32

.PHONY: all
all: $(TARGET)

$(TARGET): $(LINK_OBJS) $(LINK_DEPS) Makefile
	$(CC) $(CFLAGS) $(INCLUDES) $(LINK_OBJS) -o $@ $(LDFLAGS) -lc -lgcc
	$(OBJCOPY) -O binary $@ ${BUILD_DIR}/main.bin
	$(OBJDUMP) -d $@ > ${BUILD_DIR}/main.dump
	$(OBJCOPY) -O verilog $@ ${BUILD_DIR}/main.verilog
	@if [ -n "$${SIM_ROOT_DIR}" ]; then \
		${SIM_ROOT_DIR}/deps/tools/split_memory.sh ${BUILD_DIR}/main.verilog; \
	fi

${BUILD_DIR}/%.o: $(BSP_DIR)/%.S
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

${BUILD_DIR}/%.o: $(BSP_DIR)/lib/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

${BUILD_DIR}/%.o: $(C_SRC_DIR)/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<