`include "define_decode.svh"

module ydrasil_id_stage #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  logic                            stall_id_i,
    input  logic                            flush_id_i,

    // IF/ID input  
    input  logic [DATA_WIDTH-1:0]           if_id_pc_i,
    input  logic [DATA_WIDTH-1:0]           if_id_instr_i,

    // Register file read ports 
    output logic [4:0]                      rf_addr_rs1_o,
    output logic [4:0]                      rf_addr_rs2_o,
    input  logic [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  logic [DATA_WIDTH-1:0]           rf_rdata_rs2_i,

    // Dispatch to EX   
    // output logic                            alu_valid_o,
    output logic [DATA_WIDTH-1:0]           operand_a_o,
    output logic [DATA_WIDTH-1:0]           operand_b_o,
    output logic [`OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output logic [DATA_WIDTH-1:0]           bt_a_operand_o,
    output logic [DATA_WIDTH-1:0]           bt_b_operand_o,

    output logic [`OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output logic [DATA_WIDTH-1:0]           id_lsu_rs2_data_o, // 操作类型信号

    output logic [`OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    // Generic writeback information
    output logic                            id_alu_rf_wen_rd_o,
    output logic [4:0]                      id_rf_waddr_rd_o


);


    logic [4:0]                           rf_raddr_rs1;
    logic [4:0]                           rf_raddr_rs2;
    logic                                 rf_ren_rs1;
    logic                                 rf_ren_rs2;

    logic [4:0]                           rf_waddr_rd;
    logic                                 rf_wen_rd;
    logic [4:0]                           rf_waddr_rd_ff;
    logic                                 rf_wen_rd_ff;

    logic [DATA_WIDTH-1:0]                imm_i;
    logic                                 operand_b_rs_sel;
    logic                                 operand_a_pc_sel;
    logic                                 bt_a_rs_sel;

    logic [DATA_WIDTH-1:0]                id_lsu_rs2_data_ff;

    logic [`OPERATOR_TYPE_WIDTH-1:0]      operator_type;
    logic [`OPERATOR_TYPE_WIDTH-1:0]      operator_type_ff;

    logic [DATA_WIDTH-1:0]                operand_a;
    logic [DATA_WIDTH-1:0]                operand_b;
    logic [`OPERATOR_WIDTH-1:0]           operator;


    logic [DATA_WIDTH-1:0]                operand_a_ff;
    logic [DATA_WIDTH-1:0]                operand_b_ff;
    logic [`OPERATOR_WIDTH-1:0]           operator_ff;

    logic [`OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
    logic [`OP_LSU_INFO_WIDTH-1:0]        operator_lsu_ff;


    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
        .instr_i            (if_id_instr_i),
        .rf_waddr_rd_o      (rf_waddr_rd),
        .rf_raddr_rs1_o     (rf_raddr_rs1),
        .rf_raddr_rs2_o     (rf_raddr_rs2),
        .rf_ren_rs1_o       (rf_ren_rs1),
        .rf_ren_rs2_o       (rf_ren_rs2),
        .rf_wen_rd_o        (rf_wen_rd),
        .imm_i_o            (imm_i),
        .operand_b_rs_sel_o (operand_b_rs_sel),
        .operand_a_pc_sel_o (operand_a_pc_sel),
        .bt_a_rs_sel_o      (bt_a_rs_sel),
        .operator_o         (operator),
        .operator_lsu_o     (operator_lsu),
        .operator_type_o    (operator_type)
    );

    assign rf_addr_rs1_o = rf_raddr_rs1;
    assign rf_addr_rs2_o = rf_raddr_rs2;

    // Keep ALU source selection consistent with decoder control outputs.
    assign operand_a     = operand_a_pc_sel ? if_id_pc_i : rf_rdata_rs1_i;
    assign operand_b     = operand_b_rs_sel ? rf_rdata_rs2_i : DATA_WIDTH'(imm_i);

    assign bt_a_operand_o = bt_a_rs_sel ? rf_rdata_rs1_i : if_id_pc_i;
    assign bt_b_operand_o = imm_i;


    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
        end
        else if (flush_id_i) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
        end
        else if (!stall_id_i) begin
            operand_a_ff        <= operand_a;
            operand_b_ff        <= operand_b;
            operator_ff         <= operator;
            operator_type_ff    <= operator_type;
            rf_wen_rd_ff        <= rf_wen_rd;
            rf_waddr_rd_ff      <= rf_waddr_rd;
            operator_lsu_ff     <= operator_lsu;
            id_lsu_rs2_data_ff  <= rf_rdata_rs2_i; // 直接传递寄存器数据，供LSU使用
        end
    end

    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign operator_lsu_o       = operator_lsu_ff;
    assign operator_type_o      = operator_type_ff;
    assign id_lsu_rs2_data_o    = id_lsu_rs2_data_ff; // 直接传递寄存器数据，供LSU使用

endmodule
