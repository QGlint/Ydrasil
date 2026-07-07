# SystemVerilog RTL Coding Skill (No Function Version)

## 1. 目标

本 skill 用于约束 Codex/OpenCode 生成 SystemVerilog RTL，使其：

* 可综合
* 无隐式行为
* 无 function / task
* lint-clean
* 结构清晰（组合 / 时序严格分离）

所有设计必须显式展开逻辑，不允许抽象封装隐藏行为。

---

## 2. 强制禁止项（HARD RULE）

### ❌ 设计 RTL 中禁止使用：

* `function`
* `task`
* `automatic function/task`
* `import DPI-C function`
* `recursive function`
* `class method`

### 原则：

所有逻辑必须“显式展开在 always_comb / always_ff 中”。

---

## 3. 时序逻辑规范（MUST）

必须使用：

```systemverilog id="ff_tpl"
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    q <= RESET_VALUE;
  else if (en_i)
    q <= d_i;
end
```

规则：

* 只允许一个 clock
* 只允许 nonblocking `<=`
* 一个 always_ff 只能驱动一个寄存器组

---

## 4. 组合逻辑规范（MUST）

必须使用：

```systemverilog id="comb_tpl"
always_comb begin
  y = '0;
  if (sel_i)
    y = a_i;
  else
    y = b_i;
end
```

规则：

* 只允许 blocking `=`
* 必须 full assignment（防 latch）
* 禁止依赖隐式保持值

---

## 5. function 禁止带来的替代写法（关键）

所有 function 必须改写为 inline combinational logic。

### ❌ 禁止：

```systemverilog
function logic [7:0] add(input logic [7:0] a, b);
  return a + b;
endfunction
```

### ✅ 正确：

```systemverilog
always_comb begin
  add_res = a_i + b_i;
end
```

或直接 inline：

```systemverilog
assign add_res = a_i + b_i;
```

---

## 6. 设计结构强约束

### 6.1 逻辑必须显式展开

* 不允许隐藏中间逻辑封装
* 不允许抽象“计算函数层”

所有 datapath 必须在当前 module 内可见

---

### 6.2 组合/时序必须严格分离

标准结构：

```systemverilog id="split"
always_comb begin
  d = q;
  if (en_i)
    d = in_i;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    q <= '0;
  else
    q <= d;
end
```

---

## 7. FSM 规则

必须使用 enum：

```systemverilog id="fsm"
typedef enum logic [1:0] {
  ST_IDLE,
  ST_RUN,
  ST_DONE
} state_e;
```

禁止：

* function-based next-state logic
* encode/decode function

---

## 8. 位宽与类型规则

### 8.1 必须显式位宽

禁止：

```systemverilog
a + 1
```

必须：

```systemverilog
a + 8'd1
```

---

### 8.2 必须显式扩展

```systemverilog
sum = {1'b0, a_i} + {1'b0, b_i};
```

---

### 8.3 signed 规则

* 必须显式声明
* 禁止隐式混合运算

---

## 9. 组合逻辑安全规则

### 9.1 latch 禁止

必须：

* default assignment
* full case

---

### 9.2 case 规则

```systemverilog id="case"
always_comb begin
  y = '0;
  case (sel_i)
    2'd0: y = a_i;
    2'd1: y = b_i;
    default: y = '0;
  endcase
end
```

---

### 9.3 if 规则

* if = priority
* case = mux

---

## 10. 时钟 / reset 规则

### clock

禁止：

* gate clock
* logic derived clock

---

### reset

* async assert
* sync release
* centralized reset strategy

---

## 11. PPA 规则

优化顺序：

1. 架构
2. pipeline
3. bitwidth
4. mux reduction
5. sharing

禁止：

* 改协议
* 改 cycle semantics

---

## 12. RTL 禁止行为汇总

❌ forbidden：

* function / task
* latch
* multi-driver
* implicit net
* casex
* X/Z in RTL
* combinational loop
* gated clock

---

## 13. Codex 输出要求

每次生成 RTL 必须说明：

* combinational / sequential split
* bit-width reasoning
* FSM semantics
* overflow strategy
* CDC risk

---

## 14. Golden Patterns

### Register

```systemverilog id="reg"
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    q <= '0;
  else
    q <= d;
end
```

---

### Mux

```systemverilog id="mux"
always_comb begin
  y = '0;
  case (sel_i)
    0: y = a_i;
    1: y = b_i;
  endcase
end
```

---
