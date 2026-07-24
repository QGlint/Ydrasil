import os

ARCH = 'risc-v'
CPU = 'ydrasil'
CROSS_TOOL = 'gcc'
PLATFORM = 'gcc'

EXEC_PATH = os.getenv('RTT_EXEC_PATH', '/usr/bin')
PREFIX = os.getenv('RTT_CC_PREFIX', 'riscv64-unknown-elf-')

CC = PREFIX + 'gcc'
CXX = PREFIX + 'g++'
AS = PREFIX + 'gcc'
AR = PREFIX + 'ar'
LINK = PREFIX + 'gcc'
TARGET_EXT = 'elf'
SIZE = PREFIX + 'size'
OBJDUMP = PREFIX + 'objdump'
OBJCPY = PREFIX + 'objcopy'

DEVICE = ' -march=rv32imf_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs -mabi=ilp32f -mcmodel=medany'
COMMON = DEVICE + ' --specs=picolibc.specs -ffunction-sections -fdata-sections -fno-common'

CFLAGS = COMMON + ' -Os -g -Wall -Wno-unused-function -fno-builtin'
AFLAGS = COMMON + ' -x assembler-with-cpp -DRTOS_RTTHREAD'
CXXFLAGS = CFLAGS + ' -fno-exceptions -fno-rtti'
LFLAGS = DEVICE + ' --specs=picolibc.specs -nostartfiles -static -Wl,--gc-sections -Wl,-Map=rtthread.map'
LFLAGS += ' -T ../link.lds -Wl,--start-group -lc -lgcc -Wl,--end-group'

POST_ACTION = SIZE + ' $TARGET\n'
POST_ACTION += OBJDUMP + ' -d -S $TARGET > rtthread.dump\n'
POST_ACTION += OBJCPY + ' -O binary --gap-fill=0 --only-section=.init --only-section=.text $TARGET rtthread_itcm.bin\n'
POST_ACTION += OBJCPY + ' -O binary --gap-fill=0 --only-section=.data --only-section=.bss '
POST_ACTION += '--set-section-flags .bss=alloc,load,contents $TARGET rtthread_dtcm.bin\n'
POST_ACTION += "od -An -t x4 -w4 -v rtthread_itcm.bin | tr -d ' \\t' | sed '/^$/d' > rtthread.itcm\n"
POST_ACTION += "od -An -t x4 -w4 -v rtthread_dtcm.bin | tr -d ' \\t' | sed '/^$/d' > rtthread.dtcm\n"
