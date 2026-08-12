一、最重要的总体原则：先认识 FPGA 的“硬件经济学”

ASIC 的基本思维通常是：

晶体管便宜，连线和高性能逻辑可以针对具体需求优化，因此可以用大量 mux、CAM、复杂旁路、宽 issue、复杂 scheduler 换性能。

FPGA 则完全不同。

FPGA 的核心资源是已经制造好的：

LUT
FF
BRAM
DSP
固定 carry chain
固定 routing fabric

因此你不是在“设计晶体管”，而是在“拼装 FPGA 已经提供的结构”。

文件给出的一个非常重要的数据是：

结构	FPGA 相对 ASIC/custom CMOS 的延迟差异	面积差异
Processor	18–26×	17–27×
SRAM	7–10×	2–5×
Multiport SRAM	9–15×	12–179×
CAM	~14×	100–210×
Multiplier	17–22×	4.5–7×
Adder	15–20×	4.5–7×
Mux	20–75×	>100×
Pipeline latch	12–19×	—
Routing	9–20×	—

这张表其实就是整份资料最值得记住的东西。

FPGA 不是“所有东西都比 ASIC 慢 20 倍”

真正的区别是：

某些结构在 FPGA 上非常便宜，而某些结构极其昂贵。

尤其：

便宜 / 应该积极利用：

BRAM
DSP
Carry chain
普通 FF
FPGA 原生 RAM

昂贵 / 应该尽量避免：

大量 mux
大型 CAM
高端口 RAM
巨大的 bypass network
高 associativity cache
过度复杂的 scheduler

所以 FPGA CPU 的设计目标不能是：

“怎样把 ASIC CPU 做得更小/更快？”

而应该变成：

“怎样让 CPU 的计算尽可能落到 FPGA 的便宜资源上，同时减少 FPGA 最讨厌的结构？”

这是整个设计方法的核心。

二、第一原则：面积不是“附带指标”，而是微架构一级指标

文件明确认为 FPGA 中面积往往是主要约束，而且不同结构的面积 ratio 差异达到约 2–200×，远大于 delay ratio 的 7–75×。因此 FPGA 微架构中，面积应该比 ASIC 更早进入设计决策。

这意味着你设计 CPU 时不能只问：

“这个结构能不能提高 IPC？”

而必须同时问：

“它提高 0.05 IPC，需要多少 LUT / BRAM / routing？”

例如：

方案 A：
+0.05 IPC
+500 LUT

和

方案 B：
+0.05 IPC
+3000 LUT
+大量 mux
+严重 routing congestion

在 ASIC 思维中，两者可能都值得。

在 FPGA 中，B 很可能是坏设计。

因此 FPGA CPU 应该采用一种：

Performance Gain/FPGA Resource Cost

的思维。

三、第二原则：优先把结构映射到 FPGA Hard Block

这是非常关键的一点。

文件发现 FPGA SRAM 的面积效率远好于用 LUT/FF 自己构造 RAM；adder 和 multiplier 也因为有专用硬件而具有明显优势。

因此：

RAM → 尽量 BRAM

例如：

register file
cache
queue
ROB
predictor
TLB
buffer

只要结构允许，优先考虑 BRAM。

特别是：

宁愿调整数据结构让它符合 BRAM 的尺寸和端口形式，也不要轻易用大量 LUT 搭 RAM。

文件特别指出 FPGA BRAM 有固定容量，较小 RAM 会出现浪费，但总体 density 仍然明显优于 LUT/FF 实现。

这和你现在的 ITCM / DTCM / BTB / BHT 设计直接相关。

例如你的 BHT：

如果一个 BRAM18 只用了很少的 bit，而通过改变组织方式可以让更多 prediction entries 填进去，那么：

“增加容量”在 FPGA 上可能几乎是免费的。

这就是典型 FPGA thinking。

四、第三原则：不要害怕增加 pipeline

这一点对你现在冲 250 MHz 特别重要。

文件给出的结论是：

FPGA soft processor 应该比对应的 ASIC processor 使用稍微更深的 pipeline。

原因不是简单的“FPGA 逻辑慢”。

而是：

T
cycle
	​

=T
logic
	​

+T
register
	​


FPGA 中 register/latch 本身相对于 ASIC 的 penalty 没有逻辑整体 penalty 那么严重。

资料给出的结果是：

processor delay ratio ≈ 22×
pipeline latch delay ratio ≈ 15×

因此：

T
latch,FPGA
	​

T
logic,FPGA
	​

	​


相对 ASIC 变得更大。

于是增加 pipeline stage 的收益更明显。

文件估计，等价微架构下 FPGA pipeline depth 可以大约增加：

15
22
	​

≈1.47

最终考虑其他因素后，建议大约 20% 更深。

文件原文的核心结论是：

soft processor 应该使用稍深于 equivalent hard processor 的 pipeline。

但这里有一个非常重要的限制：

不是无限加 pipeline

因为每一级都会产生：

pipeline register
control/register overhead
branch penalty
dependency latency
forwarding complexity
flush penalty

所以应该把 pipeline 加到：

关键路径被切断，但 IPC 不明显下降的位置。

对于你现在的情况，我会把这个原则理解成：

250 MHz 不应该靠“硬顶 timing”，而应该主动把 critical combinational cone 拆开。

尤其是你最近一直在处理：

Select
producer
completion
bypass
LSU
BRU
MDU
ROB/scoreboard

这些结构之间的组合路径。

如果某个路径已经明显成为 200→250 MHz 的瓶颈，增加一级 pipeline 往往比继续优化几十个 LUT 更符合这份资料的设计思想。

五、第四原则：FPGA 特别讨厌大 MUX

这是我认为对你当前 Ydrasil 最有价值的一条。

文件测出来：

小型 mux 的 FPGA delay ratio 可以达到 40–75×，面积 ratio >100×。

所以 FPGA CPU 中有一个很容易犯的错误：

为了减少 ALU
       ↓
共享 ALU
       ↓
增加 operand mux
       ↓
增加 bypass mux
       ↓
增加 select mux
       ↓
增加 routing
       ↓
Fmax下降

ASIC 里：

多个 ALU vs 一个 ALU + mux

可能是很合理的 area/performance trade-off。

FPGA 中却未必。

因为：

复制一个 ALU 可能只需要少量 LUT/carry，而一个宽大的 mux + routing network 可能非常昂贵。

文件明确指出，FPGA functional unit 的面积 ratio 只有约 4.5–7×，但是 mux 可以 >100×。因此不能按照 ASIC 的思路大量共享 ALU。

六、这直接解释了为什么“少 bypass”是 FPGA 优化方向

文件专门讨论了 bypass network。

ASIC：

ALU0 ─┐
ALU1 ─┤
ALU2 ─┤→ 巨大 bypass mux → ALU
ALU3 ─┘

很常见。

FPGA：

这个网络非常昂贵。

因此更好的方式可能是：

ALU0 → local result
ALU1 → local result

或者：

cluster 0
  ALU
  local operands

cluster 1
  ALU
  local operands

又或者：

用更高的计算资源复制率换更小的 operand selection network。

资料甚至提出 fused ALU / instruction clustering 可以减少 operand shuffling，因此 FPGA 上可能比 ASIC 更有价值。

这与你之前问的：

“lane 1 MDU+BIT，lane 2 BRU+LSU，是否应该重新组合？”

实际上高度相关。

你不能只看：

Functional Unit Utilization

还必须看：

Operand MUX+Bypass+Routing

的成本。

所以对于你的双 lane 设计，我会特别建议你把：

“每增加一种 FU 后，需要增加多少选择路径？”

作为主要评价指标之一。

七、第五原则：CAM 是 FPGA 的大敌

这是文件中最明确的 FPGA-specific microarchitecture conclusion 之一。

CAM：

Area Ratio≈100−210×

而普通 SRAM：

Area Ratio≈2−5×

因此：

能用 RAM 就不要用 CAM。

但是这里有一个很有意思的结论：

OoO 并不是 FPGA 上不能做

文件专门研究了这个问题，发现 FPGA 上 OoO processor 并没有出现预期中的巨大面积恶化。

原因是：

CAM 虽然很贵，但 scheduler CAM 通常只是整个 CPU 的一部分。

所以：

FPGA 不排斥 OoO，FPGA 排斥“大 CAM”。

这两句话差别非常大。

八、第六原则：如果做 OoO，要“小 Scheduler + 大 RAM”

这是整份资料里最值得迁移到你自己的 CPU 的架构思想之一。

文件建议：

FPGA OoO 可以做，但 scheduler window 应该小。

因为：

BRAM 很便宜
CAM 很贵

因此：

Large ROB
Large PRF
Large queues
Small scheduler

是一个很合理的 FPGA 方向。

资料甚至明确提出：

FPGA 可以拥有较大的 ROB、register file 等 RAM-based structures，而 CAM 昂贵，因此 scheduler 应保持较小。

这非常值得你参考。

九、第七原则：PRF 架构非常适合 FPGA

文件特别推荐 Physical Register File organization。

原因是：

普通 scheduler 可能需要保存：

source operand 0 value
source operand 1 value
ready bits
tags
...

于是 CAM entry 很宽。

而 PRF 组织：

Scheduler:
    src_tag0
    src_tag1
    ready

PRF:
    actual operand values

这样：

CAM 只存 tag / ready 信息，而不是 operand value。

文件明确认为这样可以：

减小 CAM
减少 multiported structure
把数据存储交给 FPGA 更擅长的 RAM
降低 scheduler area

所以如果你未来把 Ydrasil 从现在的有限 OoO completion/producer scoreboard 向更完整 OoO 推进：

PRF + small non-data-capturing scheduler 是非常值得考虑的 FPGA-native OoO 方向。

十、第八原则：Cache 应该“大容量、低 associativity”

这是 FPGA 和 ASIC 非常明显的区别。

ASIC：

高 associativity
↓
CAM tag
↓
快速查找

FPGA：

CAM 极其昂贵。

所以资料建议：

FPGA soft processor cache 应该降低 associativity，但是增加 capacity。

原因非常直接：

BRAM density≫CAM density

因此：

ASIC:
4-way / 8-way / 16-way

不一定适合 FPGA。

FPGA 更倾向：

2-way
4-way
较大的 cache

文件自己的实现就是：

L1：2-way
L2：4-way
TLB：2-way
TLB capacity：128 entries

这与你目前如果考虑 cache/TLB 架构非常相关。

十一、第九原则：FPGA 不一定需要像 ASIC 一样极端优化全局通信

这点比较反直觉。

ASIC 先进工艺：

transistor 越来越快，但是 global wire 越来越慢。

所以 ASIC 越来越需要：

cluster
partition
local scheduler
local register file
distributed execution units

但是资料发现：

FPGA 的长距离 routing 相对于整个 processor 的 penalty 没有 ASIC 那么严重。

短距离 routing 很差，但长距离 routing 的 ratio 反而相对较低。

因此：

不要因为 ASIC 的经验，就过早把 FPGA CPU 切成大量 cluster。

也就是说：

ASIC 思维：
global communication 很贵
        ↓
强制 partition

FPGA：

global communication
        ↓
先测 timing
        ↓
如果真的成为 critical path 再 partition

这对你现在的：

lane
ALU cluster
producer
LSU
BRU

之间的组织非常重要。

十二、第十原则：不要为了“资源共享”牺牲 FPGA timing

这份资料实际上推导出了一个非常重要的 FPGA CPU 设计哲学：

在 FPGA 上，“复制硬件”有时候比“共享硬件”更快、更省资源。

因为：

共享：
             ┌→ MUX → ALU
FU0 ─────────┤
FU1 ─────────┤
FU2 ─────────┘

可能产生巨大的 mux。

而：

FU0 → ALU0
FU1 → ALU1

可能只是增加一点 LUT/carry。

所以应该比较：

C
share
	​

=C
mux
	​

+C
routing
	​

+C
sharedFU
	​


和

C
replicate
	​

=C
FU0
	​

+C
FU1
	​


而不是简单比较：

C
ALU
	​

vs.C
MUX
	​


这对你之前的：

MDU / BIT / BRU / LSU / ALU 如何分 lane

非常关键。

十三、第十一原则：DSP / Carry Chain 不要“重新发明”

资料显示 FPGA multiplier 的面积 ratio 只有 4.5–7×，明显好于整个 processor。adder 也类似。

因此：

加法

优先：

+

让工具映射到 FPGA carry chain。

不要为了追求 ASIC 式 logarithmic adder，主动构造复杂 prefix adder。

资料明确指出 FPGA 的 hard carry chain 通常比用 LUT/routing 构造的快速 adder 更合适。

乘法

优先：

DSP

而不是 LUT multiplier。

但还有一个重要点：

如果 throughput 比 latency 更重要，可以把 multiplier pipeline 得更深。

这意味着你的 MDU 设计可以把：

latency

和

throughput

分开优化。

十四、第十二原则：不要机械地追求“更深 pipeline”，而是优化 stage balance

资料中的 pipeline 分析其实隐含了一个很重要的方法。

假设：

Stage 0 = 1.0 ns
Stage 1 = 2.5 ns
Stage 2 = 0.8 ns

那么简单增加 register：

Stage 0 = 1.0
Stage 1 = 1.2
Stage 2 = 1.3
Stage 3 = 0.8

收益很大。

但如果：

1.0
1.9
1.8
1.7

继续切分的收益就会逐渐降低。

而每个 register 自身又有 FPGA overhead。

所以真正应该优化的是：

i
max
	​

(T
logic,i
	​

)+T
reg
	​


而不是 pipeline stage 数量本身。

十五、第十三原则：先看 Critical Path 的“结构类型”，再决定怎么改

这份资料最适合形成一个 FPGA 优化流程。

不要：

WNS = -1 ns
↓
随便改 RTL
↓
重新综合
↓
看 WNS

而应该：

Critical Path
      ↓
是什么类型？
      ↓
├── LUT logic
├── MUX
├── carry chain
├── BRAM
├── register
├── routing
└── high fanout

然后根据 FPGA 的“经济学”选择方案。

例如：

如果是 MUX：

优先：

减少选择项
减少 bypass
复制 FU
localize operand
pipeline

而不是继续优化 LUT expression。

如果是 BRAM：

考虑：

改 memory organization
改宽度/深度
增加 pipeline
改 read/write mode
减少 port conflict
如果是 routing：

考虑：

减少 fanout
减少 cross-lane connection
local register
pipeline
duplicate control/data
physical placement
如果是 carry chain：

一般不要轻易破坏 carry chain。