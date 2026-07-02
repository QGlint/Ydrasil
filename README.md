# Ydrasil

Ydrasil 是一个 RV32 处理器/FPGA 工程仓库，包含 RTL、FPGA Vivado 工程、仿真验证、RISC-V 测试生成、软件链接脚本，以及服务器上的 batch 综合布线和时序分析脚本。

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

编译并运行 CoreMark：

```sh
make coremark
make coremark_sim
```

CoreMark 默认只跑 HW 仿真，结果摘要写入 `build/PPA/coremark_summary.log`，完整 HW 日志在 `build/sim/hw/coremark/hw.log`。如果需要和 Spike 比较，使用专门的 `COREMARK_SIM_COMPARE` 变量：

```sh
make coremark_sim COREMARK_SIM_COMPARE=csv SIM_COMPARE_MAX_MISMATCHES=1
make coremark_sim COREMARK_SIM_COMPARE=realtime TRACE_COMPARE_FIELDS=pc,binary SIM_COMPARE_MAX_ROWS=240000 SIM_COMPARE_MAX_MISMATCHES=1
```

`csv` 模式会先生成完整 HW/Spike 日志再比较，适合保留上下文；`realtime` 模式会边跑边解析 commit trace，默认比较 `TRACE_COMPARE_FIELDS=pc,binary,gpr`，会自动跳过 make 输出、Spike warning 等非 trace 行，适合快速定位首个 mismatch。CoreMark 会读取 `mcycle` 并把计时值存入内存，和 Spike 的周期数不同，后续结果格式化阶段的控制流也可能不同；排查 benchmark 主体控制流时使用 `TRACE_COMPARE_FIELDS=pc,binary SIM_COMPARE_MAX_ROWS=<N>` 比较确定性前缀。CoreMark 仿真默认超时参数在顶层 `Makefile` 的 `coremark_sim` 目标中设置为 `+cpp_timeout=10000000 +sv_timeout=10000000`。

无 GUI 跑 Vivado 综合、实现到 route，并生成时序分析：

```sh
make syn SYN_JOBS=40
```

使用 RTL MMCM 切换 CPU clock 到 200MHz，综合、实现并生成 bitstream：

```sh
make synf
```

只从已有 routed checkpoint 重新生成报告：

```sh
make syn-vivado SYN_RUN_TO=reports SYN_FORCE=0 SYN_SYNC_SOURCES=0 SYN_JOBS=40
make syn-analyze
```

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

## 备注

- Bender 管理的 RTL 顺序主要用于 `hw/ip/jyd_fpga` 及其依赖的 core/mem 源码。
- FPGA 综合脚本会保留 `hw/ip/Xilinx_ip_wrapper/rtl` 中的 FPGA wrapper，并跳过与 wrapper 同名的通用 RTL，避免 Vivado 里出现重复模块定义。
- `FPGA/Ydrasil_FPGA.xpr` 保持 150MHz 基线；`syn` 流程会按 `SYN_PLL_FREQ_MHZ` 复制 staged 工程到 `build/syn/pllXXXm/project`，通过 `SYN_PLL_FREQ_150`/`SYN_PLL_FREQ_200` 宏选择 `ydrasil_clocking.sv` 中的 MMCM 参数。
