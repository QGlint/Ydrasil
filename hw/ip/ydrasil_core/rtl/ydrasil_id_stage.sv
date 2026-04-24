`include "define_decode.svh"

module ydrasil_id_stage #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          stall_id_i,
    input  logic                          flush_id_i,

    // IF/ID input
    input  logic [DATA_WIDTH-1:0]         if_id_pc_i,
    input  logic [DATA_WIDTH-1:0]         if_id_instr_i,

    // Register file read ports
    output logic [4:0]                    rf_rs1_addr_o,
    output logic [4:0]                    rf_rs2_addr_o,
    input  logic [DATA_WIDTH-1:0]         rf_rs1_rdata_i,
    input  logic [DATA_WIDTH-1:0]         rf_rs2_rdata_i,

    // Dispatch to EX
    output logic                          alu_valid_o,
    output logic [DATA_WIDTH-1:0]         operand_a_o,
    output logic [DATA_WIDTH-1:0]         operand_b_o,
    output logic [`OPERATOR_WIDTH-1:0]    operator_o, // 统一的ALU操作信息信号

    output logic [DATA_WIDTH-1:0]         bt_a_operand_o,
    output logic [DATA_WIDTH-1:0]         bt_b_operand_o,

    output logic [`OP_LSU_INFO_WIDTH-1:0] operator_lsu_o,



    // Generic writeback information
    output logic                          rd_wen_o,
    output logic [4:0]                    rd_addr_o,


);

    logic [4:0]                           rf_waddr_rd;
    logic [4:0]                           rf_raddr_rs1;
    logic [4:0]                           rf_raddr_rs2;
    logic                                 rf_ren_rs1;
    logic                                 rf_ren_rs2;

    logic [DATA_WIDTH-1:0]                imm_i;
    logic                                 operand_b_rs_sel;
    logic                                 operand_a_pc_sel;
    logic                                 bt_a_rs_sel;


    logic [`OPERATOR_TYPE_WIDTH-1:0]      operator_type;

    logic                                 valid_n;
    logic [DATA_WIDTH-1:0]                operand_a;
    logic [DATA_WIDTH-1:0]                operand_b;

    logic                                 rd_wen;
    logic [4:0]                           rd_addr;


    logic                                 valid_ff;
    logic [DATA_WIDTH-1:0]                operand_a_ff;
    logic [DATA_WIDTH-1:0]                operand_b_ff;
    logic [`OPERATOR_WIDTH-1:0]           operator_ff;

    logic                                 rd_wen_ff;
    logic [4:0]                           rd_addr_ff;

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
        .imm_i_o            (imm_i),
        .operand_b_rs_sel_o (operand_b_rs_sel),
        .operand_a_pc_sel_o (operand_a_pc_sel),
        .bt_a_rs_sel_o      (bt_a_rs_sel),
        .operator_o         (operator),
        .operator_lsu_o     (operator_lsu),
        .operator_type_o    (operator_type)
    );

    assign rf_rs1_addr_o = rf_raddr_rs1;
    assign rf_rs2_addr_o = rf_raddr_rs2;

    // Keep ALU source selection consistent with decoder control outputs.
    assign operand_a     = operand_a_pc_sel ? if_id_pc_i : rf_rs1_rdata_i;
    assign operand_b     = operand_b_rs_sel ? rf_rs2_rdata_i : DATA_WIDTH'(imm_i);

    assign bt_a_operand_o = bt_a_rs_sel ? rf_rs1_rdata_i : if_id_pc_i;
    assign bt_b_operand_o = imm_i;


    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            operand_a_ff    <= '0;
            operand_b_ff    <= '0;
            operator_ff     <= '0;
            rd_wen_ff       <= '0;
            rd_addr_ff      <= '0;
            operator_lsu_ff <= '0;
        end
        else if (flush_id_i) begin
            operand_a_ff    <= '0;
            operand_b_ff    <= '0;
            operator_ff     <= '0;
            rd_wen_ff       <= '0;
            rd_addr_ff      <= '0;
            operator_lsu_ff <= '0;
        end
        else if (!stall_id_i) begin
            operand_a_ff    <= operand_a;
            operand_b_ff    <= operand_b;
            operator_ff     <= operator_o;
            rd_wen_ff       <= rf_wen_rd;
            rd_addr_ff      <= rf_waddr_rd;
            operator_lsu_ff <= operator_lsu;
        end
    end

    assign operand_a_0 <= operand_a_ff;
    assign operand_b_0 <= operand_b_ff;
    assign operator_0  <= operator_ff;
    assign rd_wen_0    <= rd_wen_ff;
    assign rd_addr_0   <= rd_addr_ff;
    assign operator_lsu_0 <= operator_lsu_ff;

endmodule
