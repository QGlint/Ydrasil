`timescale 1ns/1ps

module if_tb;

    logic        clk;
    logic        rst_n;

    logic        i_stall_if;
    logic        i_stall_id;
    logic        i_flush_if_id;

    logic        i_redirect_valid;
    logic [31:0] i_redirect_pc;

    logic        o_imem_req;
    logic [31:0] o_imem_addr;
    logic [31:0] i_imem_rdata;
    logic        i_imem_valid;

    logic [31:0] o_if_id_pc;
    logic [31:0] o_if_id_pc4;
    logic [31:0] o_if_id_instr;
    logic        o_if_id_valid;

    logic [31:0] o_if_pc;

    logic tb_done;

    localparam logic [31:0] RESET_PC  = 32'h0000_1000;
    localparam logic [31:0] RV32I_NOP = 32'h0000_0013;

    // DUT
    if_stage #(
        .RESET_PC(RESET_PC)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_stall_if(i_stall_if),
        .i_stall_id(i_stall_id),
        .i_flush_if_id(i_flush_if_id),
        .i_redirect_valid(i_redirect_valid),
        .i_redirect_pc(i_redirect_pc),
        .o_imem_req(o_imem_req),
        .o_imem_addr(o_imem_addr),
        .i_imem_rdata(i_imem_rdata),
        .i_imem_valid(i_imem_valid),
        .o_if_id_pc(o_if_id_pc),
        .o_if_id_pc4(o_if_id_pc4),
        .o_if_id_instr(o_if_id_instr),
        .o_if_id_valid(o_if_id_valid),
        .o_if_pc(o_if_pc)
    );

    // 10ns 时钟
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 用取指地址构造确定性的伪指令数据，便于检查
    always_comb begin
        i_imem_rdata = 32'hA000_0000 | (o_imem_addr >> 2);
    end

    task automatic step_and_check(
        input logic [31:0] exp_pc,
        input logic [31:0] exp_instr,
        input logic        exp_valid,
        input string       tag
    );
    begin
        @(posedge clk);
        #1;
        if (o_if_id_pc !== exp_pc) begin
            $error("[%s] o_if_id_pc mismatch: exp=%h got=%h", tag, exp_pc, o_if_id_pc);
            $fatal(1);
        end
        if (o_if_id_instr !== exp_instr) begin
            $error("[%s] o_if_id_instr mismatch: exp=%h got=%h", tag, exp_instr, o_if_id_instr);
            $fatal(1);
        end
        if (o_if_id_valid !== exp_valid) begin
            $error("[%s] o_if_id_valid mismatch: exp=%0d got=%0d", tag, exp_valid, o_if_id_valid);
            $fatal(1);
        end
    end
    endtask

    initial begin
        tb_done = 1'b0;

        // 默认输入
        rst_n             = 1'b0;
        i_stall_if        = 1'b0;
        i_stall_id        = 1'b0;
        i_flush_if_id     = 1'b0;
        i_redirect_valid  = 1'b0;
        i_redirect_pc     = 32'h0;
        i_imem_valid      = 1'b1;

        // 保持复位两个周期
        repeat (2) @(posedge clk);
        #1;
        if (o_if_id_valid !== 1'b0 || o_if_id_instr !== RV32I_NOP) begin
            $error("Reset state mismatch");
            $fatal(1);
        end

        // 释放复位
        rst_n = 1'b1;

        // Case 1: 顺序取指
        step_and_check(RESET_PC,      32'hA000_0000 | (RESET_PC >> 2),      1'b1, "seq0");
        step_and_check(RESET_PC+32'd4,32'hA000_0000 | ((RESET_PC+32'd4)>>2),1'b1, "seq1");

        // Case 2: IF 停顿，PC 和 IF/ID 应保持
        i_stall_if = 1'b1;
        step_and_check(RESET_PC+32'd8,32'hA000_0000 | ((RESET_PC+32'd8)>>2),1'b1, "stall_if_hold0");
        step_and_check(RESET_PC+32'd8,32'hA000_0000 | ((RESET_PC+32'd8)>>2),1'b1, "stall_if_hold1");
        i_stall_if = 1'b0;

        // Case 3: ID 停顿，IF/ID 保持，但 PC 继续前进
        i_stall_id = 1'b1;
        step_and_check(RESET_PC+32'd8,32'hA000_0000 | ((RESET_PC+32'd8)>>2),1'b1, "stall_id_hold0");
        step_and_check(RESET_PC+32'd8,32'hA000_0000 | ((RESET_PC+32'd8)>>2),1'b1, "stall_id_hold1");
        i_stall_id = 1'b0;

        // Case 4: 冲刷，输出应为 NOP + invalid
        i_flush_if_id = 1'b1;
        step_and_check(o_if_pc, RV32I_NOP, 1'b0, "flush");
        i_flush_if_id = 1'b0;

        // Case 5: 重定向，下个周期 IF/ID 注入气泡，再下个周期开始取新地址
        i_redirect_valid = 1'b1;
        i_redirect_pc    = 32'h0000_1080;
        @(posedge clk);
        #1;
        if (o_if_id_instr !== RV32I_NOP || o_if_id_valid !== 1'b0) begin
            $error("[redirect_bubble] expected bubble after redirect");
            $fatal(1);
        end
        i_redirect_valid = 1'b0;

        step_and_check(32'h0000_1080, 32'hA000_0000 | (32'h0000_1080 >> 2), 1'b1, "redirect_target");

        $display("IF stage TB PASSED");
        tb_done = 1'b1;
        #20;
        $finish;
    end

endmodule
