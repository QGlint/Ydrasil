module ydrasil_id_stage
import ydrasil_pkg::*;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush_i,
    input  wire                  issue_ready_i,
    input  wire [31:0]           if_id_pc_i,
    input  wire [31:0]           if_id_instr_i,
    input  wire                  if_id_pred_hit_i,
    input  wire                  if_id_pred_taken_i,
    input  wire [31:0]           if_id_pred_target_i,
    input  wire [1:0]            if_id_pred_counter_i,
    input  wire [31:0]           if_id_pred_bht_index_i,
    input  wire                  if_id_valid_i,
    output wire                  if_id_ready_o,
    output wire                  decode_valid_o,
    output ydrasil_decode_pkt_t  decode_pkt_o
);

    logic [4:0] rf_waddr_rd;
    logic [4:0] rf_raddr_rs1;
    logic [4:0] rf_raddr_rs2;
    logic       rf_ren_rs1;
    logic       rf_ren_rs2;
    logic       rf_wen_rd;
    logic [31:0] imm;
    logic operand_b_rs_sel;
    logic operand_a_pc_sel;
    logic operand_a_imm_sel;
    logic bt_a_rs_sel;
    logic operand_b_jump_sel;
    logic [CSR_ADDR_WIDTH-1:0] csr_raddr;
    logic [CSR_ADDR_WIDTH-1:0] csr_waddr;
    logic [OP_CSR_INFO_WIDTH-1:0] csr_op_info;
    logic [OP_SYS_INFO_WIDTH-1:0] sys_op_info;
    logic [OPERATOR_WIDTH-1:0] operator_info;
    logic [OP_LSU_INFO_WIDTH-1:0] operator_lsu;
    logic [OPERATOR_TYPE_WIDTH-1:0] operator_type;
    localparam int DECODE_FIFO_DEPTH = 2;
    localparam int DECODE_FIFO_COUNT_WIDTH = $clog2(DECODE_FIFO_DEPTH + 1);
    logic [DECODE_FIFO_COUNT_WIDTH-1:0] decode_count_q;
    logic decode_head_q;
    logic decode_tail_q;
    ydrasil_decode_pkt_t decoded_pkt;
    (* max_fanout = 12 *) ydrasil_decode_pkt_t decode_fifo_q [0:DECODE_FIFO_DEPTH-1];
    wire decode_pop = (decode_count_q != '0) && issue_ready_i;
    wire decode_push = if_id_valid_i && if_id_ready_o;

    ydrasil_ins_decoder u_ydrasil_ins_decoder (
        .instr_i              (if_id_instr_i),
        .rf_waddr_rd_o        (rf_waddr_rd),
        .rf_raddr_rs1_o       (rf_raddr_rs1),
        .rf_raddr_rs2_o       (rf_raddr_rs2),
        .rf_ren_rs1_o         (rf_ren_rs1),
        .rf_ren_rs2_o         (rf_ren_rs2),
        .rf_wen_rd_o          (rf_wen_rd),
        .imm_i_o              (imm),
        .operand_b_rs_sel_o   (operand_b_rs_sel),
        .operand_a_pc_sel_o   (operand_a_pc_sel),
        .operand_a_imm_sel_o  (operand_a_imm_sel),
        .bt_a_rs_sel_o        (bt_a_rs_sel),
        .operand_b_jump_sel_o (operand_b_jump_sel),
        .csr_reg_raddr_o      (csr_raddr),
        .csr_ex_waddr_o       (csr_waddr),
        .csr_op_info_o        (csr_op_info),
        .sys_op_info_o        (sys_op_info),
        .operator_o           (operator_info),
        .operator_lsu_o       (operator_lsu),
        .operator_type_o      (operator_type)
    );

    // A conservative full-only ready breaks the backend-stall-to-IF
    // combinational path.  The second entry keeps Issue fed while full drains.
    assign if_id_ready_o =
        (decode_count_q != DECODE_FIFO_COUNT_WIDTH'(DECODE_FIFO_DEPTH));
    assign decode_valid_o = (decode_count_q != '0);
    assign decode_pkt_o = decode_head_q ? decode_fifo_q[1] : decode_fifo_q[0];

    always_comb begin
        decoded_pkt = '0;
        decoded_pkt.pc = if_id_pc_i;
        decoded_pkt.instr = if_id_instr_i;
        decoded_pkt.pred_hit = if_id_pred_hit_i;
        decoded_pkt.pred_taken = if_id_pred_taken_i;
        decoded_pkt.pred_target = if_id_pred_target_i;
        decoded_pkt.pred_counter = if_id_pred_counter_i;
        decoded_pkt.pred_bht_index = if_id_pred_bht_index_i;
        decoded_pkt.rs1_addr = rf_raddr_rs1;
        decoded_pkt.rs2_addr = rf_raddr_rs2;
        decoded_pkt.rd_addr = rf_waddr_rd;
        decoded_pkt.rs1_ren = rf_ren_rs1;
        decoded_pkt.rs2_ren = rf_ren_rs2;
        decoded_pkt.rd_wen = rf_wen_rd;
        decoded_pkt.imm = imm;
        decoded_pkt.operand_b_rs_sel = operand_b_rs_sel;
        decoded_pkt.operand_a_pc_sel = operand_a_pc_sel;
        decoded_pkt.operand_a_imm_sel = operand_a_imm_sel;
        decoded_pkt.bt_a_rs_sel = bt_a_rs_sel;
        decoded_pkt.operand_b_jump_sel = operand_b_jump_sel;
        decoded_pkt.operator_info = operator_info;
        decoded_pkt.operator_lsu = operator_lsu;
        decoded_pkt.operator_type = operator_type;
        decoded_pkt.csr_raddr = csr_raddr;
        decoded_pkt.csr_waddr = csr_waddr;
        decoded_pkt.csr_op_info = csr_op_info;
        decoded_pkt.sys_op_info = sys_op_info;
        decoded_pkt.fence_i =
            (if_id_instr_i[6:0] == RV32I_INS_FENCE) &&
            (if_id_instr_i[14:12] == 3'b001);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_count_q <= '0;
            decode_head_q <= 1'b0;
            decode_tail_q <= 1'b0;
            decode_fifo_q[0] <= '0;
            decode_fifo_q[1] <= '0;
        end else if (flush_i) begin
            decode_count_q <= '0;
            decode_head_q <= 1'b0;
            decode_tail_q <= 1'b0;
        end else begin
            if (decode_push) begin
                if (decode_tail_q)
                    decode_fifo_q[1] <= decoded_pkt;
                else
                    decode_fifo_q[0] <= decoded_pkt;
                decode_tail_q <= ~decode_tail_q;
            end
            if (decode_pop)
                decode_head_q <= ~decode_head_q;

            case ({decode_push, decode_pop})
                2'b10: decode_count_q <= decode_count_q + 1'b1;
                2'b01: decode_count_q <= decode_count_q - 1'b1;
                default: decode_count_q <= decode_count_q;
            endcase
        end
    end

`ifndef SYNTHESIS
    // The two-slot ring is empty/full when the pointers match and contains
    // one entry when they differ. Keep this invariant close to the state.
    always_ff @(posedge clk) begin
        if (rst_n && !flush_i) begin
            assert (decode_count_q <= DECODE_FIFO_COUNT_WIDTH'(DECODE_FIFO_DEPTH))
                else $fatal(1, "decode FIFO count overflow: %0d", decode_count_q);
            assert ((decode_head_q == decode_tail_q) ==
                    ((decode_count_q == '0) ||
                     (decode_count_q == DECODE_FIFO_COUNT_WIDTH'(DECODE_FIFO_DEPTH))))
                else $fatal(1, "decode FIFO pointer/count invariant failed");
        end
    end
`endif

endmodule
