# 200 MHz 时序恢复与双发射 IQ 架构建议

## 结论

当前 `ss2/rebuild` 的问题不是“表不够大”，而是 issue、EX、LSU、ROB 和前端握手共享了同一拍的宽组合网络。建议以 **小型 banked IQ + 注册唤醒/credit + 局部旁路 + 独立 FU 输入寄存器** 为主线，先关闭 200 MHz，再做表的 FF/LUTRAM A/B。不能用 false path、软件回环或 benchmark 特例作为修复。

推荐的数据通路语义为：

```text
IF -> decode skid -> rename/dispatch q -> banked IQ ingress
   -> registered grant token -> context_addr_q -> context RAM -> context_q
   -> independent FU input q -> local execute/bypass -> result_q/wakeup_q
   -> in-order ROB retire
```

其中 grant 只根据已登记的 IQ 状态产生；completion、ROB head、LSU busy/idle 和 context RAM 输出都不能回到同一拍 grant 的 D 端。

## 1. 当前证据

### 1.1 时序和资源

数据来自 `build/syn/pll200m/reports` 的同一份 routed design，时钟周期为 5.000 ns：

| 指标 | 当前值 |
|---|---:|
| WNS | -1.436 ns |
| TNS | -6052.150 ns |
| setup 失败端点 | 11091 |
| unconstrained endpoint | 0 |
| LUT / FF | 21311 / 11159 |
| RAMB36 / RAMB18 / DSP | 82 / 4 / 4 |
| LUTRAM | 0 |

主要层级为 `u_ctrl 5097 LUT/2049 FF`、`u_ydrasil_issue_stage 5658 LUT/640 FF`、`u_ydrasil_if_stage 4567 LUT/2380 FF`。这说明首要矛盾是控制网络和物理扇出，而不是 FF 数量。

### 1.2 路径族

`cpu200_timing_paths.csv` 和 `cpu200_timing_groups.md` 给出的代表路径：

| 路径 | 延迟/特点 | RTL 根因 | 架构切点 |
|---|---|---|---|
| `issue_ex_q -> u_ctrl/alu_result_q` | 6.125 ns，route 84.9% | 宽 issue packet 穿过 EX/完成网络回到 producer table | `grant_q`、FU 输入 q、result/wakeup q 分开 |
| DTCM BRAM -> LSU result -> `issue_ex_q` | 约 6.16 ns，逻辑深度 | BRAM 输出、load merge/align、completion mux 同拍进入 issue operand | `dtcm_resp_q`，固定延迟 token，本地旁路 |
| `fetchq_count_q -> issue_pipe_q -> latest/branch RAT` | 5.96--6.25 ns，route 约 88% | 前端 count/消费和 rename/RAT CE 组合闭环 | decode skid、registered dispatch credit |
| BTB -> pending redirect/PC CE | 约 5.94 ns | predictor 输出直接参与 pending redirect 控制 | `btb_meta_q`、registered correction/redirect |

### 1.3 RTL 对照

- `ydrasil_issue_stage.sv:51-119` 的 `completion_hit()`/`source_ready()` 直接读 completion bus；`source_data()` 也直接从 ROB source result 或 completion 取数。
- `ydrasil_issue_stage.sv:122-145` 的 stall/advance 直接读 LSU busy/idle 和 ROB-head 许可。
- `ydrasil_issue_stage.sv:253-350` 构造一个包含两 lane、LSU、FPU、branch、CSR 等字段的共享 `issue_ex_pkt`。
- `ydrasil_core.sv:485-536` 将该 bundle 同时扇出到 ALU、BRU、LSU、MUL、CSR、dual ALU、FPU。
- `ydrasil_ctrl.sv:144-158` 做 producer table 的动态 lookup；`ydrasil_ctrl.sv:228` 组合生成 dispatch packet；`ydrasil_ctrl.sv:272-275` 将 producer 状态暴露给 issue。
- `ydrasil_ex_block.sv:594-601` 用原始 ALU/bit/CSR 结果驱动 completion；`ydrasil_load_store_unit.sv:230-250` 用 BRAM/load merge 结果直接驱动 completion。

严格 Verilator 检查目前仍因 69 个 warning 退出，主要是宽度扩展/截断、IF 数组索引、LSU `byte_scan` 多驱动和 `CASEINCOMPLETE`。这些必须先修正或逐项证明，不得全局关闭，否则结构检查和性能比较不可信。

`build/PPA/coremark_current`、`coremark_O2_current` 和根目录 `perf_stats.csv` 的生成日期早于当前 `ss2/rebuild`，其中仍引用旧的 `entry_valid_q/issue_window` 信号；它们只能用于解释“依赖、producer full、前端积压”等机制，不能作为当前 IPC 0.82 的数值门槛。正式比较必须用同一 RTL commit、同一 COE、同一统计区间重新生成。

## 2. 推荐的 IQ/发射架构

### 2.1 小型 banked IQ

第一版使用 8 或 12 个 station，4 个 bank，每 bank 2--3 项；不要一开始扩展到 16/32/48 项。每项只保留以下状态：

```text
valid, epoch, age token, resource token, serial token
src0/src1 producer tag, src0/src1 ready, src0/src1 value
operator class/control summary, rd/ROB metadata, context index
```

完整 decode packet 和大块派生控制只在必要的 context 存储中保存。每个 bank 先产生一个 oldest-ready 候选；第二级只在最多四个候选之间做二发配对。pair legality 只比较窄 token：资源冲突、RAW/WAW、序列化和 lane 兼容，不扫描整个 payload。

### 2.2 grant 和唤醒边界

`grant_q.D` 允许的输入只能是：

```text
entry_valid_q, src_ready_q, age_q, resource_credit_q,
serial_token_q, epoch_q, bank candidate q
```

禁止以下信号直接或经组合别名进入 grant：

```text
ROB head/output, LSU status/busy/idle, completion bus/event/data,
producer table raw result, context RAM output, EX result combinational net
```

completion 的唯一全局路径是：

```text
completion_event -> typed wakeup_q -> station ready/value next-state
```

wakeup 在下一个周期改变 `src_ready_q/src_value_q`，不参与本周期选择。ROB head 通过 `serial_token_q` 或固定顺序许可传递；LSU 通过 `lsu_credit_q` 和请求 FIFO 传递。这样可以满足硬切断，同时避免把整个 issue 变成单发射 oldest-only 的全局停顿。

### 2.3 双发射语义

双发射不是把两个指令再塞进一个宽 bundle，而是两个独立 lane：

1. lane 0 和 lane 1 各自从不同 bank 取得 registered grant；lane 1 被资源或序列化条件阻塞时，lane 0 仍可发射。
2. 默认要求二发候选来自不同 bank；同 bank 只有在已有局部双端口实现且静态证明无竞争时才允许。
3. 配对先比较窄 token，再在 lane 输入寄存器中展开数据；不把完整 packet 的比较和重排放到一个组合级。
4. 二发射消耗和 dispatch credit 分开寄存。不能用本拍 `selected_remove` 直接生成前端 `ready/CE`；回收的 credit 下拍可用。
5. 维护 lane-specific `alu/bit/bru/agu/csr` 输入寄存器，例如 `alu0_in_q`、`bit0_in_q`、`bru0_in_q`、`agu0_in_q`、`csr0_in_q` 以及 lane 1 对应寄存器，另设 `mul_in_q`、`fpu_in_q`。禁止重新引入共享 `issue_ex_pkt` 作为 FU 输入边界。

### 2.4 前后端积压与 elastic 语义

当前性能计数显示双发射已经有实际贡献，用户给出的最新 CoreMark 方向性结果约为 IPC 0.82；旧日志还显示 producer full、scoreboard 和前端 refill 共同存在。因此需要用积压吸收寄存器边界带来的延迟：

| 边界 | 建议容量/状态 | 反压来源 |
|---|---|---|
| IF -> decode | 保持现有 fetch queue，修正索引宽度 | 只看 registered decode credit |
| decode -> IQ | 2-entry skid + 2-entry ingress credit | 不接 completion/ROB head |
| IQ -> FU | 每 lane 一个 grant/input holding register | 只看 FU registered accept |
| FU -> LSU | 2-entry request FIFO，独立 `lsu_credit_q` | 不把 LSU busy 组合回 IQ |
| LSU -> WB | `dtcm_resp_q/mmio_resp_q` 与 result FIFO | 只在 wakeup_q/WB q 更新 |

credit 采用 `available_q - reserved_q + released_q` 的寄存器语义。`released_q` 本拍产生、下拍加回；flush/epoch 取消未消费 token。这样可以形成类似 NaxRiscv 的 elastic/ready-valid 语义，但规模保持小，避免“大表+全局唤醒”的物理代价。

## 3. 性能不退的关键：typed reservation + 局部旁路

不能把所有 completion 都统一延迟一拍。旧 PPA 诊断中 ALU producer use 约占 scoreboard producer-use 的 94--95%，说明普通 ALU 链是 IPC 主体；当前/历史统计还显示预计划本地旁路和二发射对吞吐有实际贡献。

建议每个 producer 在 dispatch 时写入窄的固定延迟 token：

```text
producer_id, epoch, result_class, due_cycle, local_bypass_valid
```

- ALU/bit/BRU 和固定一拍 DTCM load：用预计划的 local bypass，实际数据只进入对应 FU input register 的 D 端；IQ ready 仍来自 token/`wakeup_q`，不是 raw completion。
- MUL/DIV/FPU、MMIO 和变量延迟 LSU：只使用 registered wakeup 和 station buffer。
- token 到期时若结果没有按期到达，清除 reservation、重新置 src ready=0 并 replay；不能把“预计会到”当作真实完成。
- DTCM 必须有 `dtcm_resp_q`；BRAM Q 不得直接驱动 `issue_ex_q` 或 grant。load-use 若要保持低损失，应由 `dtcm_resp_q + local_bypass_valid` 直接送本地 AGU/ALU 输入寄存器，而不是绕过寄存器回到 IQ。

这会增加少量执行延迟，但不会对所有依赖统一增加固定气泡；双发射和前后端 FIFO 可以在独立指令上隐藏该延迟。

## 4. 表拆分与 LUTRAM 选择

### 4.1 逻辑所有权

把当前混杂的 producer/rename/retire/checkpoint 状态分成：

```text
rename_meta_q:    valid, architectural/physical tag, class
producer_state_q: live, ready, value, epoch, result class
retire_meta_q:    rd, write-enable, ROB/PC, exception state
checkpoint_ctx:   branch recovery payload and branch epoch
```

每张表只有一个时序 owner；wakeup、retire、flush 通过事件队列更新 owner 的 next-state，禁止多处 always block 写同一个表。

### 4.2 LUTRAM 的安全候选

第一阶段先用 FF 关闭时序。通过后只 A/B 以下候选：

- branch checkpoint/context payload：约 4 行、约 224 bit/行，单读/单写，约 896 bit；
- `context_addr_q` 是唯一读地址寄存器；RAM 输出必须捕获进 `context_q`；定义读写同址时 read-first 或 write-first 语义；valid/epoch sideband 保留 FF 并可复位；payload 不要求逐位 reset。

不建议第一版 LUTRAM 化 latest RAT、producer result/wakeup table、整个 IQ payload 或 IF queue：它们需要多 lane 读写、并行唤醒/恢复或高 fanout，LUTRAM 的端口和同步读延迟会把问题重新变成组合/布线瓶颈。NaxRiscv 可借鉴“context 与执行单元局部化、静态 latency wake、elastic queue”的语义，不能照搬其规模；参考综合约 `-7.06 ns WNS` 和高 LUTRAM 用量，不是本设计的时序目标。

## 5. 必须切断的路径清单

| 现有跨块路径 | 目标边界 | 验收方式 |
|---|---|---|
| completion -> grant/ready | `completion -> wakeup_q -> ready_q` | netlist fan-in 无 completion raw pin |
| LSU busy/idle -> grant | `lsu_credit_q` + request FIFO | grant cone 只含 registered credit |
| ROB head -> grant | `serial_token_q` | 只允许 token 等级比较 |
| context RAM -> grant/FU | `context_addr_q -> RAM -> context_q` | structural checker 检查地址和输出寄存器 |
| DTCM BRAM -> issue operand | `dtcm_resp_q` + typed local bypass | timing path 起点为 response FF，不是 RAMB Q |
| fetchq count -> RAT CE | decode skid + `dispatch_credit_q` | count 不直接扇出到 ctrl CE |
| BTB -> redirect CE | `btb_meta_q` + registered redirect | BRAM Q 不直接驱动 pending CE |
| shared `issue_ex_pkt` -> FU | lane/FU input cells | 每个 FU 独立 input cell，静态 fanout 检查 |

这些是功能/架构边界，不是 `set_false_path` 的约束对象。跨时钟或真正异步信号才允许按 CDC 规则约束。

## 6. 实施顺序和性能闸门

按以下顺序逐步改，每一步都保留同一份功能镜像和统计区间：

1. 先修严格 Verilator 的宽度、数组索引、`byte_scan` 多驱动和不完整 case；warning 数必须为 0，或有逐项审查记录。
2. 先只实现 `wakeup_q/ready_q`、`lsu_credit_q`、`serial_token_q` 和 FU 独立输入寄存器，保持 IQ 表为 FF。
3. 再把现有 issue pipe 改成 4-bank、8/12-entry IQ ingress；二发射做 bank-local candidate + registered pair arbiter。
4. 最后对 checkpoint/context 做 LUTRAM A/B，并检查 `context_addr_q -> context_q` 读延迟与冲突语义。
5. 每个版本运行严格编译、ISA/随机/定向回归、同一 COE 的 IPC 统计、综合和 post-route。

建议的硬闸门：

| 闸门 | 目标 |
|---|---|
| 功能 | 全量定向/随机/Spike 差分无回退，CRC/签名一致 |
| 200 MHz | clock period 5.000 ns，WNS >= 0，TNS = 0，unconstrained = 0 |
| 性能 | 当前 IPC 0.82 为基线；第一版不得低于 0.80，目标 >= 0.82；dual-pair 计数不得明显下降 |
| 依赖 | ALU->ALU、ALU->branch、load->ALU/branch 定向测试通过；reservation miss/replay 有覆盖 |
| 结构 | grant/context/FU 三类静态检查全部通过，无共享宽 bundle 作为 FU 边界 |
| 资源 | 先记录 FF/LUT/RAMB；LUTRAM 版本必须在相同 timing/IPC 下比较，不能只看 LUT 数 |

如果插入寄存器后 IPC 下降到 0.5，优先检查是否错误地把所有 wakeup 改成全局一拍延迟、是否让 lane 1 阻塞 lane 0、是否让 dispatch 等待本拍释放 credit；这三种现象都不是本方案的预期语义。

## 7. 对 Bifurcus 和现有草案的判断

`ss2/Bifurcus@56c123d` 的 IPC 0.6/WNS -28 ns 被用户确认包含“只为功能绿灯”的软件方案，因此不能作为“大 IQ 必然失败”的证据。它可以作为反例说明：completion/ROB/LSU 原始状态参与组合选择、上下文宽读和全局 wakeup 同时存在时，物理时序会崩溃。现有“表/队列加大 + 全局唤醒”方向也不能直接复用；应先把事件和资源变成注册 token，再用小窗口和局部旁路恢复吞吐。

最终目标不是盲目复制 NaxRiscv，而是借鉴其拆分语义：执行单元拥有自己的 context、ready/valid 阶段有弹性、固定延迟 wakeup 是局部的、队列用 registered credit 隐藏后端延迟。规模、端口数和物理布局必须按当前 21k LUT/11k FF 的 Ydrasil 基线重新选择。
