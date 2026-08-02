# Ydrasil

Ydrasil 是一个 RV32 处理器/FPGA 工程仓库，包含 RTL、FPGA Vivado 工程、仿真验证、RISC-V 测试生成、软件链接脚本，以及服务器上的 batch 综合布线和时序分析脚本。

## 可配置 RV32F 扩展

浮点扩展由公开构建变量 `FPU` 控制，默认关闭。FPGA 顶层端口和板级约束不随配置变化。

| 配置 | ISA/ABI | 浮点行为 |
| --- | --- | --- |
| `FPU=0`（默认） | `rv32im...` / `ilp32` | 不编译、例化浮点链路，浮点指令触发 illegal-instruction。 |
| `FPU=1` | `rv32imf...` / `ilp32f` | 启用完整 RV32F、32×32 FPR、`fflags/frm/fcsr`、`mstatus.FS` 和 `misa.F`。 |

`FPU=1` 支持 `FLW/FSW`、四类 FMA、加减乘除、开方、符号注入、min/max、比较、分类、整数/浮点转换和搬运；支持 RNE、RTZ、RDN、RUP、RMM 及动态舍入，并累计 NV、DZ、OF、UF、NX 异常标志。任意时刻最多一条 FP/FLSU 指令在途，浮点指令只从 slot0 发射，无关整数指令仍可继续执行。FP→GPR 与整数 MUL 共用已有 slow-result 通道，MUL 同拍优先。

FPU 基于 FPnew v0.8.1，子模块固定在 commit `79e453139072df42c9ec8f697132ba485d74e23d`。首次使用先初始化依赖：

```sh
git submodule update --init hw/vendor/cvfpu
git -C hw/vendor/cvfpu submodule update --init src/common_cells
```

常用验证与综合命令如下。快速验收只运行 `coverage_quick`，不要用完整 `regression` 代替：

```sh
make coverage_quick FPU=0
make coverage_quick FPU=1
make synf FPU=1
```

FPU 综合产物与默认基线隔离，位于 `build/syn/pll200m-fpu/`；200MHz 验收报告为 `build/syn/pll200m-fpu/reports/cpu200_timing_summary.rpt`。

## 仓库构成

| 路径 | 内容 |
| --- | --- |
| `hw/ip/ydrasil_core` | 处理器核心 RTL，包含取指、译码、执行、寄存器堆、CSR、分支预测、bitmanip 等模块。该目录使用 Bender 管理源码顺序。 |
| `hw/ip/ydrmem` | 通用存储器封装 RTL。 |
| `hw/ip/jyd_fpga` | FPGA 顶层相关 RTL 和 Bender 工程入口。 |
| `hw/ip/Xilinx_ip_wrapper` | 面向 Vivado/IP 的 Xilinx wrapper RTL，例如 IROM、DTCM 相关封装。 |
| `hw/dv` | RTL 仿真入口，按仿真器拆分为 Verilator、Icarus Verilog、VCS 配置。 |
| `FPGA` | Vivado 工程 `Ydrasil_FPGA.xpr`、约束、COE、IP 输出和实现结果。 |
| `syn` | Linux 服务器上的 Vivado batch 综合、布线、报告生成和 timing path 预处理脚本。 |
| `sw` | 裸机/测试软件相关 linker script 和 include。 |
| `verif` | RISC-V 测试、Spike/trace 辅助脚本、仿真结果处理脚本。 |
| `doc` | 架构或 ISA 相关资料。 |
| `build` | 构建输出目录，包括仿真产物、波形、RISC-V 测试输出、Vivado batch 报告。 |
| `Makefile` | 仓库顶层常用任务入口。 |
| `config.mk` | 工具链、仿真、RISC-V ISA、测试集合、Spike 路径等默认配置。 |

## 文档入口

| 主题 | 文档位置 |
| --- | --- |
| Vivado batch 综合、布线、150MHz 时序报告、timing path 合并分析 | [`syn/README.md`](syn/README.md) |
| RISC-V 官方测试子模块说明 | [`verif/tests/riscv-tests/README.md`](verif/tests/riscv-tests/README.md) |
| Spike/RISC-V ISA simulator 子模块说明 | [`verif/tools/riscv-isa-sim/README.md`](verif/tools/riscv-isa-sim/README.md) |
| 顶层 make 目标和工程默认变量 | [`Makefile`](Makefile)、[`config.mk`](config.mk) |
| FPGA 工程文件、约束、IP 输出 | `FPGA/` 目录，目前没有独立 README |
| RTL 架构细节 | `hw/ip/ydrasil_core/rtl/` 目录，目前没有独立 README |
| 仿真环境细节 | `hw/dv/` 和 `verif/` 目录，目前没有独立 README |

## 常用命令

初始化子模块：

```sh
make init
```

编译并运行默认 CPU 仿真：

```sh
make comp
make sim
```

生成并运行 RISC-V 指令集回归：

```sh
make run_all_tests
```

在当前 RTL 上持续累积 coverage 的长期回归：

```sh
make regression
```

修改 RTL 后清空旧 coverage，再运行长期回归：

```sh
make regression_clean
```

从原始 M3 COE 生成并运行保持 `80:10` 循环比例的快速性能指标：

```sh
make coe_loop_lina
```

`loop_lina` 默认把12个80轮维度缩为16轮、最外层10轮缩为2轮；
生成物位于 `build/fpga_coe_m3/`，结果会被 `make ppa_perf_report` 收集。

从 MF COE 生成极短 lina 版本并运行 Verilator 仿真：

```sh
make coe_MFlina
```

该目标将矩阵、排序、素数筛、随机压力和CRC压力循环分别缩短至少约
1000倍；随机压力段的硬编码checksum也会按新循环精确重算，其他测试
继续执行原有动态结果比较。所有中间产物均位于
`build/fpga_coe_mflina/`，不会在 `FPGA/coe/` 中生成新 COE。

225MHz、240MHz 和 250MHz 超频综合入口：

```sh
make syn225
make syn240
make syn250
```

三个入口都会执行 Vivado batch flow，完成综合、实现、生成 bitstream 和时序分析；结果分别写到
`build/syn/pll225m/`、`build/syn/pll240m/` 和 `build/syn/pll250m/`。
也可以通过通用 `syn` 入口指定支持的频率（150、200、225、240 或 250MHz）：

```sh
make syn SYN_PLL_FREQ_MHZ=240
```

200MHz bitstream 入口仍然保留：

```sh
make synf
```

如果需要板级 ILA 版本，可以继续使用：

```sh
make synf-board
```

通过 `IROM_COE` 和 `DRAM_COE` 指定自定义 COE 文件；该写法适用于三个超频入口：

```sh
make syn225 IROM_COE=/path/to/irom.coe DRAM_COE=/path/to/dram.coe
make syn240 IROM_COE=/path/to/irom.coe DRAM_COE=/path/to/dram.coe
make syn250 IROM_COE=/path/to/irom.coe DRAM_COE=/path/to/dram.coe
```

综合前会检查文件是否存在，并将它们复制到对应频率构建目录的 `memory/` 下。若只需把
COE 转成文本或二进制内存文件，可使用：

```sh
perl sw/coe_to_mem.pl input.coe output.mem
perl sw/coe_to_mem.pl --binary input.coe output.bin
```

`sw/coe_to_mem.pl` 只接受 `memory_initialization_radix=16` 的 COE 文件，初始化向量里的每个字都必须是 1 到 8 位十六进制数。

长期回归目标由 `REGRESSION_TARGETS` 控制，默认包含完整 sort 与优化矩阵，
可继续追加随机指令测试目标。完整 sort 不再属于 `coverage_all`，
`coverage_quick` 也保持原有快速套件。

无 GUI 跑 Vivado 综合、实现到 route，并生成时序分析：

```sh
make syn SYN_JOBS=40
```

使用 RTL MMCM 切换 CPU clock 到 200MHz，综合、实现并生成 bitstream：

```sh
make synf
```

使用超频入口综合、实现并生成 bitstream：

```sh
make syn225
make syn240
make syn250
```

自定义 COE 文件并运行综合：

```sh
make syn240 IROM_COE=/path/to/irom.coe DRAM_COE=/path/to/dram.coe
```

只从已有 routed checkpoint 重新生成报告：

```sh
make syn-vivado SYN_RUN_TO=reports SYN_FORCE=0 SYN_SYNC_SOURCES=0 SYN_JOBS=40
make syn-analyze
```

## RTL 架构快速检查

下面的目标都只在 `build/` 下生成文件，不会复用仿真编译中的宽度忽略或 `-Wno-fatal`：

```sh
# 独立严格门禁：UNOPTFLAT、LATCH、MULTIDRIVEN、WIDTH 等警告会使目标失败
make rtl-strict

# Verilator 展开树（Verilator 5.048 没有 XML 时自动使用 tree JSON）和结构报告
make rtl-structure

# Vivado pin-free OOC；主线综合检查，使用 Xilinx wrapper，不读取 hw/ip/ydrmem 仿真模型
make vivado-ooc

# 需要时再跑 Yosys/Slang 作为可选交叉检查
make yosys-slang
make yosys-slang-gate YOSYS_BASELINE_STAT=build/yosys-slang/base/stat.json
```

`rtl-quickcheck` 现在默认串起 `rtl-strict`、`rtl-structure` 和 `vivado-ooc`。
Yosys 目标仍保留为可选交叉检查，可通过 `YOSYS_TOP`、`YOSYS_BENDER_DIR`、`YOSYS_RUN`
和 `YOSYS_WITH_WRAPPERS` 覆盖。
Vivado OOC 默认器件为 `xc7k325tffg900-2`，可用 `VIVADO_OOC_PART` 覆盖。

## Vivado 环境

服务器上的 Vivado 入口应使用 batch 模式，不启动 GUI。顶层 Makefile 默认在 Vivado 目标中局部 source：

```sh
/opt/Xilinx/Vitis/2024.2/settings64.sh
```

如果环境不同，可以覆盖变量：

```sh
make syn VIVADO_SETTINGS=/path/to/settings64.sh VIVADO=/path/to/vivado
```

## 构建输出

`build/` 和 Vivado run 目录是生成产物目录。常见输出包括：

| 路径 | 内容 |
| --- | --- |
| `build/wave` | 仿真波形。 |
| `build/log` | 仿真日志。 |
| `build/riscv_tests` | RISC-V 测试编译输出。 |
| `build/rvtest_results` | 回归测试结果。 |
| `build/syn/pll150m/reports` | 默认 150MHz Vivado batch 报告和 timing path 合并结果。 |
| `build/syn/pll150m/checkpoints` | 默认 150MHz batch flow 保存的 Vivado checkpoint。 |
| `build/syn/pll200m/artifacts` | 200MHz bitstream、checkpoint 副本和 manifest，使用 `make synf` 生成。 |
| `build/syn/pll225m/artifacts` | 225MHz bitstream、checkpoint 副本和 manifest，使用 `make syn225` 生成。 |
| `build/syn/pll240m/artifacts` | 240MHz bitstream、checkpoint 副本和 manifest，使用 `make syn240` 生成。 |
| `build/syn/pll250m/artifacts` | 250MHz bitstream、checkpoint 副本和 manifest，使用 `make syn250` 生成。 |

## 备注

- Bender 管理的 RTL 顺序主要用于 `hw/ip/jyd_fpga` 及其依赖的 core/mem 源码。
- FPGA 综合脚本会保留 `hw/ip/Xilinx_ip_wrapper/rtl` 中的 FPGA wrapper，并跳过与 wrapper 同名的通用 RTL，避免 Vivado 里出现重复模块定义。
- `xpm_lutram_1r1w.sv` 来自 `ss2/Bifurcus` 分支，Xilinx 分支固定使用 distributed RAM，非 Xilinx 分支内置仿真模型；Vivado source list 会排除全部 `hw/ip/ydrmem/rtl` 文件。
- `FPGA/Ydrasil_FPGA.xpr` 保持 150MHz 基线；`syn` 流程会按 `SYN_PLL_FREQ_MHZ` 复制 staged 工程到 `build/syn/pllXXXm/project`，通过对应的 `SYN_PLL_FREQ_XXX` 宏选择 `ydrasil_clocking.sv` 中的 MMCM 参数。
