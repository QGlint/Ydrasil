# SW 边界测试逐轮记录

本文档记录项目自有 SW 定向测试的逐轮新增项、适用 LSU、验证结果和覆盖率变化。

## 失败清单

### F-001：legacy LSU 中相关 mul/div 与 fence.i 交织导致除法结果丢失

- 复现测试：[sw_fence_div_repro.S](verif/tests/ydrasil-tests/rv32ui/sw_fence_div_repro.S)。
- 首次发现：第 4 轮；测试源保留在仓库中，但没有加入 `SW_ALIGNED_TESTS`，不参与正式覆盖率数据库。
- 运行配置：legacy LSU、HW-only 仿真；new LSU 未将该失败作为正式失败结论。
- 最小指令序列：

  ```asm
  li    t0, 0x1111
  li    t1, 3
  mul   t2, t0, t1       # 期望 t2 = 0x00003333
  fence.i
  sw    t2, 0(s0)
  divu  t3, t2, t1       # 期望 t3 = 0x00001111
  fence.i
  sw    t3, 4(s0)
  ```

- 失败证据：`testnum = 7`；第一次 SW 的 `t2` 结果正确，第二次除法结果实际为 `t3 = 0x00000000`，而不是 `0x00001111`。
- 日志：[hw.log](build/sw_boundary/iter4-failures/sw_fence_div_repro/hw.log)；反汇编和复现源保存在同目录。
- 影响：若加入正式清单，`make sw_boundary_test`、`make sw_coverage` 会出现 `TEST_FAIL`，不再满足正式矩阵全部 PASS 的验收条件。
- 处理：仅保留失败日志、`testnum`、反汇编和最小复现；不修改 RTL、testbench，也不通过修改测试期望值规避问题。

## 记录约定

- `aligned`：legacy/new LSU 均运行，并进入默认 `test_all`。
- `new-only`：只在 new LSU 运行，不验证 legacy 非对齐行为。
- 覆盖率数据库数量包含 legacy/new 各自运行的官方 `rv32ui_sw`。
- `通过`：所有加入正式测试清单的新增测试均通过。
- `部分通过`：正式测试通过，但本轮另保留了未加入清单的硬件失败最小复现。
- 第 1、2 轮的提交标题沿用当时格式；从第 3 轮开始采用
  `新增测试_（序号），通过与否，（新增测试数量/全部测试数量）`。

## 第 1 轮

- 提交：`f2f4bca 新增测试_1，全部通过`
- 结果：全部通过。
- 新增测试：
  - `sw_data_boundary.S`（aligned）：0、全 1、符号边界、交替位以及 walking-one/zero 数据模式。
  - `sw_immediate_boundary.S`（aligned）：`-2048/-1/0/1/2047` S 型立即数和基址进位组合。
  - `sw_address_boundary.S`（aligned）：DTCM 首字、末字、相邻保护字以及写后恢复。
  - `sw_dependency_boundary.S`（aligned）：连续同址/异址写、ALU/load 到 SW 的数据相关和 `x0` 数据源。
  - `sw_stress.S`（aligned）：连续地址和确定性位模式压力。
  - `sw_misaligned_boundary.S`（new-only）：地址低位 `01/10/11` 的跨字 SW 和两侧 guard。
- 其他测试支持：新增 `sw_test_macros.h` 自检查宏和首版覆盖率执行接口。

## 第 2 轮

- 提交：`b449c91 新增测试_2，全部通过`
- 结果：全部通过；34 个覆盖率数据库。
- 覆盖率：line 56.8%，toggle 61.0%，branch 83.3%，expr 76.4%，LCOV 84.5%。
- 新增测试：
  - `sw_register_matrix.S`（aligned）：rs1/rs2 寄存器矩阵、同寄存器和高编号寄存器。
  - `sw_forwarding_alu.S`（aligned）：ALU 到 SW 地址/数据的 0～3 间隔转发。
  - `sw_forwarding_load.S`（aligned）：load 到 store-data/base、WAW 和连续写读。
  - `sw_forwarding_mul_div.S`（aligned）：mul/div/rem 长延迟结果到 SW 数据和地址。
  - `sw_immediate_matrix.S`（aligned）：S 型立即数字段分界、2 的幂边界和低位进位。
  - `sw_endian_readback.S`（aligned）：SW 后使用 lb/lbu/lh/lhu/lw 验证小端顺序和符号扩展。
  - `sw_address_alias.S`（aligned）：bank/index 地址位翻转、同索引冲突和热点更新。
  - `sw_control_sequence.S`（aligned）：branch、jal/jalr、fence 和 bubble 周围的 SW。
  - `sw_dense_stress.S`（aligned）：多 seed、升降序、不同步长和重复覆盖压力。
  - `sw_misaligned_negative.S`（new-only）：负偏移和接近立即数极值的非对齐 SW。
  - `sw_misaligned_overlap.S`（new-only）：低位 `01/10/11` 连续重叠写和 last-writer-wins。
  - `sw_misaligned_boundaries.S`（new-only）：32/64 字节、4KB 和 DTCM 上边界内跨字写。

## 第 3 轮

- 提交：`d43cbce 新增测试_3，通过，（3/21）`
- 结果：通过；40 个覆盖率数据库。
- 覆盖率：line 57.4%，toggle 61.5%，branch 84.5%，expr 76.8%，LCOV 85.7%。
- 新增测试：
  - `sw_self_modify_exec.S`（aligned）：SW 写入 DTCM 指令、`fence.i` 后执行并再次改写验证。
  - `sw_producer_window.S`（aligned）：mul 到 SW 的 0～4 间隔和乘法生成 store base。
  - `sw_load_interlock.S`（aligned）：双 load producer、WAW load、热点地址 load→SW 链。

## 第 4 轮

- 提交：`0257d3d 新增测试_4，部分通过，（4/25）`
- 结果：3 个正式测试通过；1 个已知硬件失败复现被排除在正式清单外；45 个覆盖率数据库。
- 覆盖率：line 57.8%，toggle 61.9%，branch 84.9%，expr 77.3%，LCOV 86.2%。
- 新增测试：
  - `sw_load_bypass_operands.S`（aligned）：load 结果作为 ALU rs1/rs2，随后紧邻 SW。
  - `sw_fence_stall.S`（aligned）：mul 与 `fence/fence.i` 交织后的 SW。
  - `sw_misaligned_loadback.S`（new-only）：非对齐 SW 后使用跨字 LW 读回和重叠验证。
  - `sw_fence_div_repro.S`（不进入清单）：相关 mul/div 与 `fence.i` 交织导致除法结果丢失的最小复现，`testnum=7`，预期失败。

## 第 5 轮

- 提交：`eb5c8bb 新增测试_5，通过，（2/27）`
- 结果：通过；48 个覆盖率数据库。
- 覆盖率：line 57.8%，toggle 62.0%，branch 84.9%，expr 77.3%，LCOV 86.2%。
- 新增测试：
  - `sw_subword_readback_matrix.S`（aligned）：SW 后覆盖全部字节位的 lb/lbu 和两个半字位的 lh/lhu。
  - `sw_misaligned_half_readback.S`（new-only）：跨字 lh/lhu 后再次进行对齐/非对齐 SW 重叠写。

## 第 6 轮

- 提交：`89eb893 新增测试_6，通过，（1/28）`
- 结果：通过；50 个覆盖率数据库。
- 覆盖率：line 58.1%，toggle 62.8%，branch 85.4%，expr 77.5%，LCOV 86.4%。
- 新增测试：
  - `sw_div_fence_independent.S`（aligned）：无相关依赖的 div/rem、`fence.i` 和 SW 交织，覆盖纯乘除 stall 分支。

## 第 7 轮

- 提交：`63fcf4a 新增测试_7，通过，（1/29）`
- 结果：通过；52 个覆盖率数据库。
- 覆盖率：line 60.2%，toggle 64.0%，branch 85.9%，expr 79.3%，LCOV 87.5%。
- 新增测试：
  - `sw_forwarding_bitmanip.S`（aligned）：15 类 Bitmanip 结果紧邻作为 SW 数据源并逐字读回。

## 第 8 轮

- 提交：`cbcebf5 新增测试_8，通过，（1/30）`
- 结果：通过；54 个覆盖率数据库。
- 覆盖率：line 62.3%，toggle 64.8%，branch 85.9%，expr 79.3%，LCOV 88.0%。
- 新增测试：
  - `sw_bitmanip_address_data.S`（aligned）：Zba 生成 store base，Zbc/Zbkb/Zbkx 生成 store data。

## 第 9 轮

- 提交：`96560c1 新增测试_9，通过，（1/31）`
- 结果：通过；56 个覆盖率数据库。
- 覆盖率：line 64.1%，toggle 65.3%，branch 86.8%，expr 79.3%，LCOV 88.3%。
- 新增测试：
  - `sw_bitmanip_immediate.S`（aligned）：rori、bclri、bexti、binvi、bseti、brev8 和 min/max 结果到 SW。

## 第 10 轮

- 提交：`cc87ac2 新增测试_10，通过，（1/32）`
- 结果：通过；58 个覆盖率数据库。
- 覆盖率：line 64.1%，toggle 65.4%，branch 86.8%，expr 79.3%，LCOV 88.6%。
- 新增测试：
  - `sw_forwarding_alu_extended.S`（aligned）：RV32I 逻辑、比较、寄存器移位和立即数移位结果紧邻 SW。

## 第 11 轮

- 提交：`7c8c3a7 新增测试_11，通过，（1/33）`
- 结果：通过；60 个覆盖率数据库。
- 覆盖率：line 64.1%（211/329），toggle 65.4%（37273/56996），branch 86.8%（565/651），expr 79.3%（352/444），LCOV 88.8%（3581/4033）。
- 新增测试：
  - `sw_unsigned_branch_jalr.S`（aligned）：BLTU/BGEU taken/not-taken、ALU→JALR 紧邻依赖、目标和返回路径 SW。

## 第 12 轮

- 提交：`3f32013 新增测试_12，通过，（2/35）`
- 结果：通过；64 个覆盖率数据库。
- 覆盖率：line 64.4%（212/329），toggle 65.7%（37431/56996），branch 86.9%（566/651），expr 79.3%（352/444），LCOV 89.0%（3589/4033）。
- 新增测试：
  - `sw_jalr_lui_bypass.S`（aligned）：SW 生成 DTCM 指令，LUI 紧邻 JALR 后执行并检查返回值和 guard。
  - `sw_forwarding_csr.S`（aligned）：mscratch 的 csrrc/csrrsi/csrrci/csrrwi 旧值紧邻作为 SW 数据源，结束时恢复 CSR。

## 第 13 轮

- 提交：`00e84a3 新增测试_13，通过，（1/36）`
- 结果：通过；66 个覆盖率数据库。
- 覆盖率：line 65.0%（214/329），toggle 65.7%（37473/56996），branch 87.1%（567/651），expr 79.7%（354/444），LCOV 89.4%（3606/4033）。
- 新增测试：
  - `sw_mul_div_edge_results.S`（aligned）：mulh/mulhsu/mulhu、除零、`INT_MIN/-1` 溢出、较小和零被除数结果紧邻 SW。

## 第 14 轮

- 提交标题：`新增测试_14，通过，（1/37）`
- 结果：通过；67 个覆盖率数据库。
- 覆盖率：line 65.0%（214/329），toggle 65.9%（37553/56996），branch 87.1%（567/651），expr 79.7%（354/444），LCOV 89.4%（3606/4033）。
- 新增测试：
  - `sw_misaligned_forwarding_mix.S`（new-only）：非对齐跨字 SW 与 ALU、mul、load、CSR 数据/地址依赖组合，并检查逐字结果和两侧 guard。

## 当前汇总

- 项目自有 SW 测试源：37 个，其中 36 个进入正式清单，1 个为独立已知失败复现。
- 正式矩阵：legacy 30 个数据库，new 37 个数据库，共 67 个数据库。
- 默认 `test_all`：29 个 aligned 项目测试。
- 当前已知失败：仅 `sw_fence_div_repro.S`；不进入正式清单，不修改硬件规避。
