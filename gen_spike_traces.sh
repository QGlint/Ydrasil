#!/bin/bash

# 1. 定义目录
SRC_DIR=/mnt/c/Users/zsir_/Desktop/risc-v/Ydrasil/hw/dv/test_data
LOG_DIR=$SRC_DIR/spike_logs

# 2. 创建存放日志的文件夹
mkdir -p $LOG_DIR

echo "正在生成 Spike 标准运行日志..."

# 3. 遍历所有的 rv32ui-p 开头的测试文件
for file in ~/riscv-tests/isa/rv32ui-p-*; do
    # 确保是文件且不是已经生成的 .txt 或 .mem
    if [[ -f "$file" && ! "$file" == *.* ]]; then
        name=$(basename $file)
        echo "正在追踪: $name"

        # 运行 Spike 并开启日志模式
        # --isa=rv32ui 确保模拟器处于 RV32 基础指令集模式
        # -l 参数会让 spike 把每一步执行的指令和寄存器变化写到 stderr
        # 我们用 2>&1 把错误输出转到标准输出，然后保存
        spike -l --isa=rv32i $file > $LOG_DIR/${name}_trace.log 2>&1
    fi
done

echo "-----------------------------------------------"
echo "全部生成完毕！日志存放在: $LOG_DIR"
echo "你可以运行 'head -n 50 $LOG_DIR/rv32ui-p-add_trace.log' 查看内容。"
