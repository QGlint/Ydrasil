module ydrasil_decode_slot
import ydrasil_pkg::*;
(
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire        pred_hit_i,
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,
    input  wire [1:0]  pred_counter_i,
    input  wire [31:0] pred_bht_index_i,
    output ydrasil_decode_pkt_t decode_pkt_o
);
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [4:0] rd_addr;
    wire rs1_ren;
    wire rs2_ren;
    wire rd_wen;
    wire [31:0] imm;
    wire operand_b_rs_sel;
    wire operand_a_pc_sel;
    wire operand_a_imm_sel;
    wire bt_a_rs_sel;
    wire operand_b_jump_sel;
    wire [CSR_ADDR_WIDTH-1:0] csr_raddr;
    wire [CSR_ADDR_WIDTH-1:0] csr_waddr;
    wire [OP_CSR_INFO_WIDTH-1:0] csr_op_info;
    wire [OP_SYS_INFO_WIDTH-1:0] sys_op_info;
    wire [OPERATOR_WIDTH-1:0] operator_info;
    wire [OP_LSU_INFO_WIDTH-1:0] operator_lsu;
    wire [OPERATOR_TYPE_WIDTH-1:0] operator_type;

    ydrasil_ins_decoder u_decoder (
        .instr_i(instr_i),
        .rf_waddr_rd_o(rd_addr),
        .rf_raddr_rs1_o(rs1_addr),
        .rf_raddr_rs2_o(rs2_addr),
        .rf_ren_rs1_o(rs1_ren),
        .rf_ren_rs2_o(rs2_ren),
        .rf_wen_rd_o(rd_wen),
        .imm_i_o(imm),
        .operand_b_rs_sel_o(operand_b_rs_sel),
        .operand_a_pc_sel_o(operand_a_pc_sel),
        .operand_a_imm_sel_o(operand_a_imm_sel),
        .bt_a_rs_sel_o(bt_a_rs_sel),
        .operand_b_jump_sel_o(operand_b_jump_sel),
        .csr_reg_raddr_o(csr_raddr),
        .csr_ex_waddr_o(csr_waddr),
        .csr_op_info_o(csr_op_info),
        .sys_op_info_o(sys_op_info),
        .operator_o(operator_info),
        .operator_lsu_o(operator_lsu),
        .operator_type_o(operator_type)
    );

    always_comb begin
        decode_pkt_o = '0;
        decode_pkt_o.pc = pc_i;
        decode_pkt_o.instr = instr_i;
        decode_pkt_o.pred_hit = pred_hit_i;
        decode_pkt_o.pred_taken = pred_taken_i;
        decode_pkt_o.pred_target = pred_target_i;
        decode_pkt_o.pred_counter = pred_counter_i;
        decode_pkt_o.pred_bht_index = pred_bht_index_i;
        decode_pkt_o.rs1_addr = rs1_addr;
        decode_pkt_o.rs2_addr = rs2_addr;
        decode_pkt_o.rd_addr = rd_addr;
        decode_pkt_o.rs1_ren = rs1_ren;
        decode_pkt_o.rs2_ren = rs2_ren;
        decode_pkt_o.rd_wen = rd_wen;
        decode_pkt_o.imm = imm;
        decode_pkt_o.operand_b_rs_sel = operand_b_rs_sel;
        decode_pkt_o.operand_a_pc_sel = operand_a_pc_sel;
        decode_pkt_o.operand_a_imm_sel = operand_a_imm_sel;
        decode_pkt_o.bt_a_rs_sel = bt_a_rs_sel;
        decode_pkt_o.operand_b_jump_sel = operand_b_jump_sel;
        decode_pkt_o.operator_info = operator_info;
        decode_pkt_o.operator_lsu = operator_lsu;
        decode_pkt_o.operator_type = operator_type;
        decode_pkt_o.csr_raddr = csr_raddr;
        decode_pkt_o.csr_waddr = csr_waddr;
        decode_pkt_o.csr_op_info = csr_op_info;
        decode_pkt_o.sys_op_info = sys_op_info;
        decode_pkt_o.fence_i = (instr_i[6:0] == RV32I_INS_FENCE) &&
            (instr_i[14:12] == 3'b001);
    end
endmodule

module ydrasil_id_stage
import ydrasil_pkg::*;
#(
    parameter int DECODE_FIFO_DEPTH = 4
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush_i,
    input  wire                  issue_ready_i,
    input  wire                  issue_consume_two_i,
    input  wire [31:0]           if_id_pc_i,
    input  wire [31:0]           if_id_instr_i,
    input  wire                  if_id_pred_hit_i,
    input  wire                  if_id_pred_taken_i,
    input  wire [31:0]           if_id_pred_target_i,
    input  wire [1:0]            if_id_pred_counter_i,
    input  wire [31:0]           if_id_pred_bht_index_i,
    input  wire                  if_id_valid_i,
    input  wire [31:0]           if_id1_pc_i,
    input  wire [31:0]           if_id1_instr_i,
    input  wire                  if_id1_pred_hit_i,
    input  wire                  if_id1_pred_taken_i,
    input  wire [31:0]           if_id1_pred_target_i,
    input  wire [1:0]            if_id1_pred_counter_i,
    input  wire [31:0]           if_id1_pred_bht_index_i,
    input  wire                  if_id1_valid_i,
    output wire                  if_id_ready_o,
    output wire                  if_id_consume_two_o,
    output wire                  decode_valid_o,
    output wire                  decode_valid1_o,
    output ydrasil_decode_pkt_t  decode_pkt_o,
    output ydrasil_decode_pkt_t  decode_pkt1_o
);
    localparam int COUNT_WIDTH = $clog2(DECODE_FIFO_DEPTH + 1);
    localparam int PTR_WIDTH = $clog2(DECODE_FIFO_DEPTH);
    reg [COUNT_WIDTH-1:0] decode_count_q;
    (* max_fanout = 64 *) reg [PTR_WIDTH-1:0] decode_rptr_q;
    reg [PTR_WIDTH-1:0] decode_wptr_q;
    ydrasil_decode_pkt_t decode_fifo_q [0:DECODE_FIFO_DEPTH-1];
    ydrasil_decode_pkt_t decoded0;
    ydrasil_decode_pkt_t decoded1;

    ydrasil_decode_slot u_decode0 (
        .pc_i(if_id_pc_i), .instr_i(if_id_instr_i),
        .pred_hit_i(if_id_pred_hit_i), .pred_taken_i(if_id_pred_taken_i),
        .pred_target_i(if_id_pred_target_i), .pred_counter_i(if_id_pred_counter_i),
        .pred_bht_index_i(if_id_pred_bht_index_i), .decode_pkt_o(decoded0)
    );
    ydrasil_decode_slot u_decode1 (
        .pc_i(if_id1_pc_i), .instr_i(if_id1_instr_i),
        .pred_hit_i(if_id1_pred_hit_i), .pred_taken_i(if_id1_pred_taken_i),
        .pred_target_i(if_id1_pred_target_i), .pred_counter_i(if_id1_pred_counter_i),
        .pred_bht_index_i(if_id1_pred_bht_index_i), .decode_pkt_o(decoded1)
    );

    wire has_room_one = decode_count_q < COUNT_WIDTH'(DECODE_FIFO_DEPTH);
    wire has_room_two = decode_count_q <= COUNT_WIDTH'(DECODE_FIFO_DEPTH - 2);
    wire [1:0] pop_count = (issue_ready_i && decode_count_q != '0) ?
        ((issue_consume_two_i && decode_count_q > COUNT_WIDTH'(1)) ? 2'd2 : 2'd1) : 2'd0;
    wire push0 = if_id_valid_i && has_room_one;
    wire push1 = if_id1_valid_i && has_room_two;
    wire [1:0] push_count = push1 ? 2'd2 : (push0 ? 2'd1 : 2'd0);
    wire [COUNT_WIDTH-1:0] post_pop_count = decode_count_q - COUNT_WIDTH'(pop_count);
    wire [PTR_WIDTH-1:0] decode_rptr1 = decode_rptr_q + PTR_WIDTH'(1);
    wire [PTR_WIDTH-1:0] decode_wptr1 = decode_wptr_q + PTR_WIDTH'(1);

    assign if_id_ready_o = has_room_one;
    assign if_id_consume_two_o = push1;
    assign decode_valid_o = decode_count_q != '0;
    assign decode_valid1_o = decode_count_q > COUNT_WIDTH'(1);
    assign decode_pkt_o = decode_fifo_q[decode_rptr_q];
    assign decode_pkt1_o = decode_fifo_q[decode_rptr1];

    integer idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_count_q <= '0;
            decode_rptr_q <= '0;
            decode_wptr_q <= '0;
            for (idx = 0; idx < DECODE_FIFO_DEPTH; idx = idx + 1)
                decode_fifo_q[idx] <= '0;
        end else if (flush_i) begin
            decode_count_q <= '0;
            decode_rptr_q <= '0;
            decode_wptr_q <= '0;
        end else begin
            decode_rptr_q <= decode_rptr_q + PTR_WIDTH'(pop_count);
            decode_wptr_q <= decode_wptr_q + PTR_WIDTH'(push_count);
            if (push0)
                decode_fifo_q[decode_wptr_q] <= decoded0;
            if (push1)
                decode_fifo_q[decode_wptr1] <= decoded1;
            decode_count_q <= post_pop_count + COUNT_WIDTH'(push_count);
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && !flush_i)
            assert (post_pop_count + COUNT_WIDTH'(push_count) <= COUNT_WIDTH'(DECODE_FIFO_DEPTH))
                else $fatal(1, "decode FIFO overflow");
    end
`endif
endmodule
