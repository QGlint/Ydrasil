# NaxRiscv 设计要点与 Ydrasil 优化参考

本文记录对 `/media/proj_tmp/alkaid_simulator_ooo/NaxRiscv` 的结构性审计结果，作为当前 Ydrasil 重构的设计约束。重点是把高扇出查表、宽组合选择和不可控的反压路径拆成有界、可流水化的状态机；它不是 NaxRiscv 源码的逐行翻译。

## 1. 总体原则

NaxRiscv 的高频实现依赖几个一致的边界：

1. **容量有界的 issue/重命名队列**。分配、唤醒、发射和提交都由明确的 head/tail/count 管理，队列满时只阻止分配，不把长组合链传回前端。
2. **按结果类型划分的 wakeup**。LSU、乘除法和简单 ALU 使用独立的完成通道；消费者只比较自己所属类型的 tag，避免每个源对所有完成总线做全交叉比较。
3. **分级 context mux**。先在 bank/lane 内选择候选，再在少量候选之间选择最终操作数；不要用一个覆盖所有 producer、lane 和旁路来源的大优先级 mux。
4. **存储体分 bank**。连续条目按奇偶或低位 bank 交错，使双发射读写可以映射到多个单端/简单双口 BRAM，而不是依赖 LUT RAM 或复制出高扇出读端口。
5. **提交与冲刷是唯一的年龄边界**。redirect/flush 通过 generation/tag 或显式保留掩码使年轻状态失效；完成数据不能绕过年龄检查直接写回架构状态。

## 2. 有界队列和发射

### 2.1 Queue contract

每个可重命名项至少保存：`valid`、generation-tag、目的寄存器、结果类型、ready/done、结果值和必要的 PC/异常元数据。推荐的时序契约如下：

```text
dispatch (cycle N) -> queue entry allocated
issue    (cycle N+k) -> operands captured into EX input register
complete (later)    -> typed wakeup and entry result update
retire   (head only) -> architectural write/side effects
```

`issue` 的 grant 只依赖已注册的 queue metadata 和本地 ready 位。完成总线可以在下一个周期更新 ready，但不应作为同一周期 grant 的深组合输入。这样做会增加一个周期的可见延迟，却能切断 `completion -> CAM -> grant -> decode/IF` 的关键路径。

### 2.2 双发射

双发射应先做静态 lane capability 筛选，再做动态资源/操作数检查：

- lane A/B 的能力矩阵在 decode 阶段生成并随 uop 保存；
- 每个 lane 只检查自己允许的执行类型；
- slot 1 被阻塞时可 replay/保留，不得让 slot 0 的已发射项重复执行；
- branch、CSR、fence、LSU 等有副作用操作需要显式的序列化或年龄检查；
- `ex_mul_stall`、redirect 和 tag generation 必须参与接受条件。

不要通过把所有候选项并行比较再 OR 回一个 grant 来“提高利用率”。这类逻辑通常比增加一个队列条目更伤害 200 MHz 时序。

## 3. Typed wakeup 和旁路

### 3.1 Tag 语义

一个源描述应同时携带：

- architectural register index；
- producer tag（含 generation/epoch）；
- producer result class；
- `used` 和 `tag_valid`。

`tag_valid` 为假或寄存器为 `x0` 时，源直接就绪。tag 命中必须同时满足 `valid && producer_tracked && class && addr && generation`，不能仅比较物理槽位或寄存器号。

### 3.2 旁路分层

建议顺序：

1. 当前执行单元的本地、固定延迟旁路（只覆盖无副作用简单 ALU/MDU 结果）；
2. 已注册的 typed completion；
3. 已完成 ROB/producer entry 的结果；
4. 架构寄存器文件。

每一级都应携带同一 producer identity。尤其不能把 BRAM 的原始 Q 输出直接反馈给发射 grant；可采用 speculative reservation + replay/hold：命中时在 EX holding register 中消费，未命中时保留 uop 并重试。

### 3.3 关键路径切分

把以下边界注册化通常收益最大：

```text
completion bus -> completion snapshot -> wakeup/ready
issue grant     -> issue/EX input register -> execution unit
fetch response  -> response skid/queue   -> decode
```

注册 payload 不等于清零整个宽总线。无效项只需要清 `valid`/`producer_tracked`，其余 payload 可保持，以免 grant/occupancy 信号扇出到每一根数据线。

## 4. 面向 Ydrasil 的 BRAM banking

Nax 的表项分层和端口约束可以迁移到 Ydrasil；在当前 Vivado 目标中，具体存储体应拆成独立的 bank 和 metadata，并显式要求同步 BRAM：

- payload（指令、队列项、结果）放入 `(* ram_style = "block" *)` 的同步 RAM；
- valid/tag/epoch 等小而频繁更新的 metadata 保持 FF 或小型寄存器阵列；
- 双读端需求用奇偶 bank 或复制的只读 bank 满足，避免综合推断 LUTRAM；
- 明确 read-during-write 行为，空队列 refill 时使用输入 payload bypass；
- BRAM 输出后加寄存器，避免地址译码和宽 mux 直接进入核心控制。

对于 32-bit 指令/数据，优先使用现有 `ydrmem_1r1w_ram`/BRAM wrapper；不要把深度很小的表自动改成 LUTRAM 来追求零延迟，除非该表不在时序关键路径且项目约束明确允许。

## 5. Flush、redirect 和 retire

冲刷必须同时覆盖：

- IF/ID/FIFO 中的年轻指令；
- issue queue 和 producer/RAT 项；
- 尚未完成的执行单元请求；
- branch predictor 的 speculative metadata。

推荐使用 generation bit 或 recovery keep mask。完成/写回到达时，先检查 tag generation，再更新 producer entry；失效项的完成包必须被丢弃。提交只从 ROB head 开始，双提交的第二项必须依赖第一项已提交且两项都 ready。

预测表的训练应在真实 EX resolve 后进行。预测命中不能改变年龄顺序，也不能直接释放未验证的 side effect。redirect 的目标和 flush 资格应在寄存器边界锁存，避免预测表数据回路影响前端 ready。

## 6. 对当前 Ydrasil 的落地映射

当前代码中对应的优先级如下：

| 结构 | 目标实现 | 主要验收点 |
| --- | --- | --- |
| `ydrasil_ctrl` 的 latest/RAT lookup | 按寄存器号的窄查表，metadata 与结果存储分离 | 不出现全表比较链；tag generation 正确 |
| `ydrasil_issue_stage` completion/wakeup | typed snapshot + 本地旁路 | grant 不直接依赖原始 completion bus |
| DTCM load-use | 单周期 speculative reservation，miss 时 holding/replay | 不把 BRAM Q 接回 grant；无错误消费旧数据 |
| IF fetch queue | 奇偶 bank BRAM、response skid | 双取指无端口冲突，redirect 丢弃年轻响应 |
| branch target/L0 表 | 小 metadata FF + payload bank；训练仅在 resolve | 无 LUTRAM 关键路径和错误命中 |
| ROB/producer table | bounded head/tail/count，提交按年龄 | flush 后旧 completion 不可写回 |

## 7. 时序和功能验收清单

每次结构修改后至少检查：

1. Vivado synthesis/implementation：`WNS >= 0`、`TNS = 0`、无 unconstrained endpoint，且报告中的 LUTRAM 数量为 0（允许明确豁免的非关键小表需单独记录）。
2. Verilator 定向测试：ALU->ALU、load->ALU、load->branch、mul/div->use、双发射 slot-1 replay、redirect 后旧完成包、x0 和 tag wraparound。
3. CoreMark 使用 `/media/proj_tmp/alkaid_simulator/deps/software-level/bin/gcc_open` 构建，并记录实际 `-O` 等级、cycles、IPC 和 CoreMark 分数。
4. 项目验证保持 Spike 关闭时，至少保留 RTL 自检、CoreMark 校验和以及 flush/retire 断言；关闭 Spike 不应关闭硬件一致性检查。

目标分数 `450.788943` 需要同时降低前端 `MEM_RESPONSE` 停顿和 load-use/branch 等数据相关停顿；单独扩大 ALU bypass 通常不足以达到该目标。

## 8. 事实边界与源码证据

本节区分 NaxRiscv 的实际实现和面向 Ydrasil 的迁移建议，避免把目标器件上的改造误认为 Nax 的默认配置。

- Nax 的项目说明将参考 FPGA 实现描述为 **distributed RAM**，并明确目标是较小面积和较高频率（`NaxRiscv/README.md`）。`Config.plugins()` 的默认参数 `withDistributedRam = true`；该开关会使取指/数据 cache tag 使用异步读、IssueQueue context 的 `robIdAt` 取值为 1，并让 ROB 使用 `completionWithReg = false`（`src/main/scala/naxriscv/Gen.scala`）。因此，本文要求 Ydrasil “不使用 LUT RAM、优先 BRAM”是针对当前 Vivado 目标的迁移约束，不是对 Nax 默认存储实现的复述。
- 将 `withDistributedRam` 置为 `false` 时，Nax 已提供同步 RAM/BRAM 推断方向：`robIdAt` 提前到 0，completion 增加寄存器边界，cache tag 读延迟也相应调整。这个配置开关和显式的 pipeline latency 参数，是 Ydrasil 做 BRAM 化时应保留的结构化思路。
- `src/main/scala/naxriscv/frontend/IssueQueue.scala` 展示了核心调度机制：固定容量、按 way 推入，push 时压紧（compact）有效项；`triggers` 保存等待事件，schedule 只从 ready slot 产生 one-hot 选择。它是“有界状态 + 局部选择 + 注册执行入口”的具体实现依据。
- `src/main/scala/naxriscv/frontend/RfTranslationPlugin.scala` 中 `TranslatorWithRollback` 将 speculative translation 和 committed translation 分开存储，并在 reschedule 时清除 speculative 状态；`RfDependencyPlugin.scala` 则用物理寄存器到 ROB 的依赖表产生 wakeup。这两者共同构成重命名、回滚和年龄检查的基础。
- `src/main/scala/naxriscv/misc/RobPlugin.scala` 将 ROB metadata 按 line/bank 组织，并为 completion、异步读取和提交提供独立端口；`src/main/scala/naxriscv/misc/CommitPlugin.scala` 负责按 ROB head 的年龄顺序提交和 reschedule。
- `src/main/scala/naxriscv/lsu/DataCache.scala`、`DataCachePlugin.scala` 实现非阻塞 cache 的 refill/writeback slot、load/store 端口和 redo/fault 响应；`src/main/scala/naxriscv/lsu/LsuPlugin.scala` 保存 load/store queue 的年龄与内存依赖检查。Ydrasil 的查表和 LSU 流水化应优先借鉴这些边界，而不是复制其异步 RAM 选择。
- `src/main/scala/naxriscv/prediction/BtbPlugin.scala`、`GSharePlugin.scala` 和 `BranchContextPlugin.scala` 分别体现 BTB、全局历史预测和 resolve 后训练；预测表命中只产生 speculative jump，最终年龄和副作用仍由提交/冲刷路径裁决。

建议在每次结构修改的评审记录中同时注明：采用了哪一条 Nax 边界、为 BRAM 化增加了多少周期、以及对应的 valid/epoch/flush 验证项。这样可以把“借鉴设计思想”和“保持当前实现语义”分开验收。

## 9. Nax 特有机制与迁移取舍

### 9.1 前端到执行单元

`src/main/scala/naxriscv/frontend/FrontendPlugin.scala` 将前端固定为
`aligned -> decompressed -> decoded -> serialized -> allocated -> dispatch`；
`FetchPlugin.scala` 根据各插件声明的最小延迟补齐 fetch stages。`ExecutionUnitBase.scala`
再为每个 EU 建立独立的 context/read/execute/writeback pipeline。`DispatchPlugin.scala`
从 issue queue 的 schedule 产生 one-hot event，先在小组内做 context mux，再在后续 stage
注册 ROB ID、物理目的寄存器和 EU context；静态延迟使用 history mask，动态完成使用
`WakeRobService`/`WakeRegFileService` 的 typed event。

可迁移的重点是“接口 payload 随 uop 保存、选择结果在 EU 入口注册、wakeup 按结果类型分流”。
Ydrasil 不应把所有 producer 的原始 completion、查表 Q 值和 lane context 合并到一个组合
grant；增加一级 holding/issue register 通常比复制整张表更容易达到 200 MHz。

### 9.2 重命名、依赖和提交

- `RfAllocationPlugin.scala` 的多端口 allocator 在 dispatch 分配物理寄存器，在 commit/free
  端口归还旧物理寄存器；满时只阻塞 allocated stage。
- `RfTranslationPlugin.scala` 的 `TranslatorWithRollback` 分开保存 speculative 和
  committed arch-to-phys 映射，并用 `location.updated` 选择新旧副本；reschedule 时清除
  speculative 位置。一个 dispatch group 内还做了 slot-to-slot 的同拍 bypass。
- `RfDependencyPlugin.scala` 用 `physToRob` 加 busy bit 记录“物理寄存器由哪个 ROB 项产生”，
  commit 清除 busy，读取时返回 ROB ID，因而不需要对所有架构寄存器做全表比较。
- `RobPlugin.scala` 将 completion 和 metadata 按 ROB line/bank 存储；`CommitPlugin.scala`
  维护 alloc/commit/free 三个年龄指针，提交 mask 可 retime，并在多个 reschedule 请求同时
  到达时按 ROB age 选择最老请求。

对应 Ydrasil 的实现应把 `valid + epoch/generation + producer id` 作为同一个事务边界；
流水化查表后，旧 completion 必须在 epoch 检查失败时丢弃，不能仅依赖物理槽位回绕。

### 9.3 分支预测和恢复

`BranchContextPlugin.scala` 为在-flight 分支分配有界 branch ID，分别保存 early/final
context；分支提交后释放 ID，reschedule 时把分配指针恢复到已提交位置。`HistoryPlugin.scala`
同时维护 fetch-side speculative history 和 commit-side architectural history；恢复事件从
ROB 读出该指令的历史与真实 taken 位后重建 fetch history。`BranchPlugin.scala` 将 taken/fall-through
两个目标并行计算，并用 `KeepAttribute` 防止综合把比较器和两个加法器串成一条长路径。
`PcPlugin.scala` 对不同优先级的 jump source 做统一仲裁。

迁移到 Ydrasil 时，应在 redirect 产生处锁存 `{target, epoch, branch metadata}`，先冲刷年轻
fetch/issue/LSU 状态，再训练预测表；预测表命中只能提出 speculative redirect，不能绕过 ROB
年龄顺序释放副作用。

### 9.4 LSU 和非阻塞 cache

`src/main/scala/naxriscv/lsu/LsuPlugin.scala` 用独立的环形 LQ/SQ 指针保存地址、ROB、物理
寄存器和等待原因。load pipeline 选择最老 ready LQ 项，按配置在 cache 命令前加入 bypass 或
pipeline stage，随后检查 older store mask；cache 响应可以先按 hit-prediction 唤醒 ROB/RF，
但 `redo`、fault 或 store-to-load alias 会触发 replay/reschedule。store pipeline 只按年龄推进
到 writeback，检查 younger load 后才允许释放；redo 时翻转 generation，避免旧 cache response
再次消费。LQ/SQ 在 commit reschedule 时清空年轻项，同时保留已提交 store 的必要状态。

`DataCache.scala` 将数据按 way 分 bank，bank 数据读是同步 RAM；tag/status/PLRU 默认可异步读，
也可通过 `tagsReadAsync=false` 改为同步读。refill 和 writeback 各自使用有界 slot，reservation
仲裁同一拍的 tag/status 写入，bank busy、refill hit、line lock 等条件统一编码为 `REDO`，并以
`refillCompletions` 唤醒等待项。这个结构说明 Nax 的高 IPC 来自“非阻塞 + 预测 + replay”，而
不是假设 cache 永远单周期命中。

对 Ydrasil 的直接建议：

1. 保留 LQ/SQ 的 head/tail/age 和 younger/older mask 语义；只把查表 payload 拆到同步 BRAM，
   将 valid、epoch、等待原因放在窄 metadata 中。
2. 在 DTCM launch 同拍 snapshot store-buffer/LQ 状态，forward mask/data、completion、producer
   ID 和 reservation 一起延迟；下一拍不要重新扫描已改变的环形表。
3. BRAM 未命中或 bank hazard 时使用 holding/replay，沿用 `redo` 优先于 fault 的响应规则；
   任何新增流水级都必须同步 kill/flush 和错误响应。

### 9.5 取舍表

| Nax 的选择 | 收益 | 代价 | Ydrasil 迁移策略 |
| --- | --- | --- | --- |
| distributed/async tag 与 context 读 | 低延迟、较少寄存器 | LUTRAM、宽 mux 和高扇出 | 使用同步 BRAM，增加明确的读响应级 |
| speculative load-hit predictor | 约 3-cycle load-use | redo、年龄检查和错误恢复复杂 | reservation + holding/replay + epoch kill |
| push 时 compact issue queue | 空槽少、选择局部化 | push 周期有搬移逻辑 | 分 bank/分段队列，限制搬移扇出 |
| 多 refill/writeback slot | 隐藏 cache miss | bank/line hazard 状态多 | 保留 slot reservation 和 completion mask |
| 插件化、按配置生成 pipeline | 易调 latency 和资源 | 依赖边界分散，易形成组合回路 | 固化模块接口，跨模块 payload 注册化 |
