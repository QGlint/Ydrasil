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

BSP_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.abspath(os.getenv(
    'RTT_OUTPUT_DIR', os.path.join(BSP_DIR, '..', '..', '..', 'build', 'app', 'rtthread')))
OUTPUT_BASENAME = os.getenv('RTT_OUTPUT_BASENAME', 'rtthread')
TARGET = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '.elf')
DUMP = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '.dump')
MAP = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '.map')
ITCM_BIN = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '_itcm.bin')
DTCM_BIN = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '_dtcm.bin')
ITCM = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '.itcm')
DTCM = os.path.join(OUTPUT_DIR, OUTPUT_BASENAME + '.dtcm')

DEVICE = ' -march=rv32im_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs -mabi=ilp32 -mcmodel=medany'
# The current simulation path has a known branch-loop issue during early BSS
# clearing. Load zero-initialized objects from DTCM instead so reset can skip it.
COMMON = DEVICE + ' --specs=picolibc.specs -ffunction-sections -fdata-sections -fno-common -fno-zero-initialized-in-bss'

OPTIMIZATION = os.getenv('RTT_OPT', '-Os')
LINK_SCRIPT = os.path.abspath(os.getenv('RTT_LINKER', '../link.lds'))

CFLAGS = COMMON + ' ' + OPTIMIZATION + ' -g -Wall -Wno-unused-function -fno-builtin'
if os.getenv('RTT_APP') == 'rtthread-coremark' or os.getenv('RTT_COREMARK') == '1':
    CFLAGS += ' -DRTT_COREMARK_BUILD=1'
AFLAGS = COMMON + ' -x assembler-with-cpp -DRTOS_RTTHREAD'
CXXFLAGS = CFLAGS + ' -fno-exceptions -fno-rtti'
LFLAGS = DEVICE + ' --specs=picolibc.specs -nostartfiles -static -Wl,--gc-sections -Wl,-Map=' + MAP
LFLAGS += ' -T ' + LINK_SCRIPT + ' -Wl,--start-group -lc -lgcc -Wl,--end-group'

POST_ACTION = SIZE + ' $TARGET\n'
POST_ACTION += OBJDUMP + ' -d -S $TARGET > "' + DUMP + '"\n'
POST_ACTION += OBJCPY + ' -O binary --gap-fill=0 --only-section=.init --only-section=.text $TARGET "' + ITCM_BIN + '"\n'
POST_ACTION += OBJCPY + ' -O binary --gap-fill=0 --only-section=.data --only-section=.bss '
POST_ACTION += '--set-section-flags .bss=alloc,load,contents $TARGET "' + DTCM_BIN + '"\n'
POST_ACTION += "od -An -t x4 -w4 -v \"" + ITCM_BIN + "\" | tr -d ' \\t' | sed '/^$/d' > \"" + ITCM + "\"\n"
POST_ACTION += "od -An -t x4 -w4 -v \"" + DTCM_BIN + "\" | tr -d ' \\t' | sed '/^$/d' > \"" + DTCM + "\"\n"
