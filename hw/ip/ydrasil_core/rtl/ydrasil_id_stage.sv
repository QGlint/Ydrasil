module ydrasil_decode_slot
import ydrasil_pkg::*;
(
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire        pred_hit_i,
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,
    input  wire [1:0]  pred_counter_i,
    input  bp_bht_index_t pred_bht_index_i,
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
	logic [UOP_CLASS_WIDTH-1:0] op_class;
	logic [UOP_SUBOP_WIDTH-1:0] subop;
	logic [UOP_LSU_SUBOP_WIDTH-1:0] lsu_subop;
	wire full_bitmanip;
	wire divrem;
	wire illegal_instr = (instr_i[6:0] == 7'b0000111) ||
		(instr_i[6:0] == 7'b0100111) ||
		(instr_i[6:0] == 7'b1000011) ||
		(instr_i[6:0] == 7'b1000111) ||
		(instr_i[6:0] == 7'b1001011) ||
		(instr_i[6:0] == 7'b1001111) ||
		(instr_i[6:0] == 7'b1010011);

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
		.uop_class_o(op_class),
		.uop_subop_o(subop),
		.uop_lsu_subop_o(lsu_subop),
		.full_bitmanip_o(full_bitmanip),
		.divrem_o(divrem)
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
		decode_pkt_o.op_class = op_class;
		decode_pkt_o.subop = subop;
		decode_pkt_o.lsu_subop = lsu_subop;
		decode_pkt_o.full_bitmanip = full_bitmanip;
		decode_pkt_o.divrem = divrem;
        decode_pkt_o.csr_raddr = csr_raddr;
        decode_pkt_o.csr_waddr = csr_waddr;
        decode_pkt_o.csr_op_info = csr_op_info;
        decode_pkt_o.sys_op_info = sys_op_info;
        decode_pkt_o.fence_i = (instr_i[6:0] == RV32I_INS_FENCE) &&
            (instr_i[14:12] == 3'b001);

		decode_pkt_o.illegal_instr = illegal_instr;
		if (illegal_instr) begin
			decode_pkt_o.rs1_addr = '0;
			decode_pkt_o.rs2_addr = '0;
			decode_pkt_o.rd_addr = '0;
			decode_pkt_o.rs1_ren = 1'b0;
			decode_pkt_o.rs2_ren = 1'b0;
			decode_pkt_o.rd_wen = 1'b0;
			decode_pkt_o.imm = '0;
			decode_pkt_o.op_class = UOP_CLASS_SYS;
			decode_pkt_o.subop = '0;
			decode_pkt_o.lsu_subop = '0;
			decode_pkt_o.full_bitmanip = 1'b0;
			decode_pkt_o.divrem = 1'b0;
		end
    end
endmodule

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
    input  bp_bht_index_t        if_id_pred_bht_index_i,
    input  wire                  if_id_valid_i,
    input  wire [31:0]           if_id1_pc_i,
    input  wire [31:0]           if_id1_instr_i,
    input  wire                  if_id1_pred_hit_i,
    input  wire                  if_id1_pred_taken_i,
    input  wire [31:0]           if_id1_pred_target_i,
    input  wire [1:0]            if_id1_pred_counter_i,
    input  bp_bht_index_t        if_id1_pred_bht_index_i,
    input  wire                  if_id1_valid_i,
    output wire                  if_id_ready_o,
    output wire                  if_id_consume_two_o,
    output ydrasil_issue_pkt_t   issue_pkt_o,
    output ydrasil_issue_pkt_t   issue_pkt1_o
);
    ydrasil_decode_pkt_t decoded0;
    ydrasil_decode_pkt_t decoded1;
    ydrasil_issue_pkt_t incoming_pkt0;
    ydrasil_issue_pkt_t incoming_pkt1;
    ydrasil_issue_pkt_t id_queue_q0;
    ydrasil_issue_pkt_t id_queue_q1;
    ydrasil_issue_pkt_t id_queue_q2;
    ydrasil_issue_pkt_t id_queue_q3;
    reg [2:0] id_queue_count_q;
    reg [1:0] id_queue_head_q;
    reg [1:0] id_queue_tail_q;
    reg [3:0] id_queue_valid_q;
    reg id_ready_q;
    reg id_two_room_q;

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

    wire decode_valid = if_id_valid_i;
    wire decoded0_memory = (decoded0.op_class == UOP_CLASS_LOAD) ||
        (decoded0.op_class == UOP_CLASS_STORE);
    wire decoded1_memory = (decoded1.op_class == UOP_CLASS_LOAD) ||
        (decoded1.op_class == UOP_CLASS_STORE);
    wire decoded0_serial = (decoded0.op_class == UOP_CLASS_CSR) ||
        (decoded0.op_class == UOP_CLASS_SYS) || decoded0.fence_i ||
        decoded0.illegal_instr;
    wire decoded1_serial = (decoded1.op_class == UOP_CLASS_CSR) ||
        (decoded1.op_class == UOP_CLASS_SYS) || decoded1.fence_i ||
        decoded1.illegal_instr;
    wire decode_valid1 = if_id1_valid_i;
    wire slot0_writes = (decoded0.rd_addr != '0) &&
		(decoded0.rd_wen || (decoded0.op_class == UOP_CLASS_LOAD));
    wire slot1_writes = (decoded1.rd_addr != '0) &&
		(decoded1.rd_wen || (decoded1.op_class == UOP_CLASS_LOAD));
    // Lane A resolves control flow; lane B owns memory and MDU. This lets the
    // much more frequent branch/LSU combinations use both execution lanes.
    wire slot0_a_capable = (decoded0.op_class != UOP_CLASS_MUL) &&
        !decoded0_memory;
    wire slot0_b_capable = (decoded0.op_class != UOP_CLASS_BJP) &&
        !decoded0.full_bitmanip && !decoded0_serial;
    wire slot1_a_capable = (decoded1.op_class != UOP_CLASS_MUL) &&
        !decoded1_memory;
    wire slot1_b_capable = (decoded1.op_class != UOP_CLASS_BJP) &&
        !decoded1.full_bitmanip && !decoded1_serial;
    // Entrance credit depends only on registered occupancy. The extra pair of
    // storage absorbs one cycle of downstream backpressure without exposing
    // Issue/CTRL ready to FetchQ.
    wire id_queue_push = !flush_i && id_ready_q && if_id_valid_i;
    wire id_queue_push_two = id_queue_push && id_two_room_q &&
        if_id1_valid_i;
    wire [1:0] id_queue_push_count = id_queue_push ?
        (id_queue_push_two ? 2'd2 : 2'd1) : 2'd0;
    wire id_queue_pop = !flush_i && issue_ready_i && issue_pkt_o.valid;
    wire id_queue_pop_two = id_queue_pop && issue_pkt1_o.valid;
    wire [1:0] id_queue_pop_count = id_queue_pop ?
        (id_queue_pop_two ? 2'd2 : 2'd1) : 2'd0;
    wire [2:0] id_queue_count_next = id_queue_count_q +
        id_queue_push_count - id_queue_pop_count;

    // IF already qualifies these registered credits with its own valid and
    // flush state. Keeping the boundary credit-only avoids a combinational
    // FetchQ -> Decode -> FetchQ control loop.
    assign if_id_ready_o = id_ready_q;
    assign if_id_consume_two_o = id_two_room_q;

    function automatic ydrasil_issue_decode_pkt_t issue_decode_payload(
        input ydrasil_decode_pkt_t decoded
    );
        begin
            issue_decode_payload = '0;
            issue_decode_payload.pc = decoded.pc;
            issue_decode_payload.instr = decoded.instr;
            issue_decode_payload.pred_hit = decoded.pred_hit;
            issue_decode_payload.pred_taken = decoded.pred_taken;
            issue_decode_payload.pred_target = decoded.pred_target;
            issue_decode_payload.pred_counter = decoded.pred_counter;
            issue_decode_payload.pred_bht_index = decoded.pred_bht_index;
            issue_decode_payload.imm = decoded.imm;
            issue_decode_payload.operand_b_rs_sel = decoded.operand_b_rs_sel;
            issue_decode_payload.operand_a_pc_sel = decoded.operand_a_pc_sel;
            issue_decode_payload.operand_a_imm_sel = decoded.operand_a_imm_sel;
            issue_decode_payload.bt_a_rs_sel = decoded.bt_a_rs_sel;
            issue_decode_payload.operand_b_jump_sel = decoded.operand_b_jump_sel;
            issue_decode_payload.csr_raddr = decoded.csr_raddr;
            issue_decode_payload.csr_waddr = decoded.csr_waddr;
            issue_decode_payload.csr_op_info = decoded.csr_op_info;
            issue_decode_payload.sys_op_info = decoded.sys_op_info;
            issue_decode_payload.fence_i = decoded.fence_i;
            issue_decode_payload.illegal_instr = decoded.illegal_instr;
        end
    endfunction

    always_comb begin
        incoming_pkt0 = '0;
        incoming_pkt0.valid = decode_valid;
        incoming_pkt0.decode = issue_decode_payload(decoded0);
        incoming_pkt0.uop_class = decoded0.op_class;
        incoming_pkt0.uop_subop = decoded0.subop;
        incoming_pkt0.uop_lsu_subop = decoded0.lsu_subop;
        incoming_pkt0.lane_mask = {slot0_b_capable, slot0_a_capable};
        incoming_pkt0.src0.used = decode_valid && decoded0.rs1_ren;
        incoming_pkt0.src0.arch_addr = decoded0.rs1_addr;
        incoming_pkt0.src1.used = decode_valid &&
			(decoded0.rs2_ren || (decoded0.op_class == UOP_CLASS_STORE));
        incoming_pkt0.src1.arch_addr = decoded0.rs2_addr;
        incoming_pkt0.dst.writes_gpr = decode_valid && slot0_writes;
        incoming_pkt0.dst.rd_addr = decoded0.rd_addr;
        // Issue/CTRL only consumes this serialization bit from the ID
        // control bundle.  Validity is carried by id_queue_valid_q and the
        // other decoded control mirrors are reconstructed from src/dst/uop.
        incoming_pkt0.ctrl.serialize_before = decode_valid && decoded0_serial;

        incoming_pkt1 = '0;
        incoming_pkt1.valid = decode_valid1;
        incoming_pkt1.decode = issue_decode_payload(decoded1);
        incoming_pkt1.uop_class = decoded1.op_class;
        incoming_pkt1.uop_subop = decoded1.subop;
        incoming_pkt1.uop_lsu_subop = decoded1.lsu_subop;
        incoming_pkt1.lane_mask = {slot1_b_capable, slot1_a_capable};
        incoming_pkt1.src0.used = decode_valid1 && decoded1.rs1_ren;
        incoming_pkt1.src0.arch_addr = decoded1.rs1_addr;
        incoming_pkt1.src1.used = decode_valid1 &&
			(decoded1.rs2_ren || (decoded1.op_class == UOP_CLASS_STORE));
        incoming_pkt1.src1.arch_addr = decoded1.rs2_addr;
        incoming_pkt1.dst.writes_gpr = decode_valid1 && slot1_writes;
        incoming_pkt1.dst.rd_addr = decoded1.rd_addr;
        // See lane A: only serialize_before crosses the elastic boundary.
        incoming_pkt1.ctrl.serialize_before = decode_valid1 && decoded1_serial;
    end

    always_comb begin
        unique case (id_queue_head_q)
            2'd0: begin
                issue_pkt_o = id_queue_q0;
                issue_pkt1_o = id_queue_q1;
                issue_pkt_o.valid = id_queue_valid_q[0];
                issue_pkt1_o.valid = id_queue_valid_q[1];
            end
            2'd1: begin
                issue_pkt_o = id_queue_q1;
                issue_pkt1_o = id_queue_q2;
                issue_pkt_o.valid = id_queue_valid_q[1];
                issue_pkt1_o.valid = id_queue_valid_q[2];
            end
            2'd2: begin
                issue_pkt_o = id_queue_q2;
                issue_pkt1_o = id_queue_q3;
                issue_pkt_o.valid = id_queue_valid_q[2];
                issue_pkt1_o.valid = id_queue_valid_q[3];
            end
            default: begin
                issue_pkt_o = id_queue_q3;
                issue_pkt1_o = id_queue_q0;
                issue_pkt_o.valid = id_queue_valid_q[3];
                issue_pkt1_o.valid = id_queue_valid_q[0];
            end
        endcase
        if (!issue_pkt_o.valid) begin
            issue_pkt_o.valid = 1'b0;
            issue_pkt_o.lane_mask = '0;
        end
        if (!issue_pkt1_o.valid || issue_pkt_o.ctrl.serialize_before) begin
            issue_pkt1_o.valid = 1'b0;
            issue_pkt1_o.lane_mask = '0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_queue_count_q <= '0;
            id_queue_head_q <= '0;
            id_queue_tail_q <= '0;
            id_queue_valid_q <= '0;
            id_ready_q <= 1'b1;
            id_two_room_q <= 1'b1;
        end else if (flush_i) begin
            id_queue_count_q <= '0;
            id_queue_head_q <= '0;
            id_queue_tail_q <= '0;
            id_queue_valid_q <= '0;
            id_ready_q <= 1'b1;
            id_two_room_q <= 1'b1;
        end else begin
            if (id_queue_pop) begin
                unique case (id_queue_head_q)
                    2'd0: begin
                        id_queue_valid_q[0] <= 1'b0;
                        if (id_queue_pop_two)
                            id_queue_valid_q[1] <= 1'b0;
                    end
                    2'd1: begin
                        id_queue_valid_q[1] <= 1'b0;
                        if (id_queue_pop_two)
                            id_queue_valid_q[2] <= 1'b0;
                    end
                    2'd2: begin
                        id_queue_valid_q[2] <= 1'b0;
                        if (id_queue_pop_two)
                            id_queue_valid_q[3] <= 1'b0;
                    end
                    default: begin
                        id_queue_valid_q[3] <= 1'b0;
                        if (id_queue_pop_two)
                            id_queue_valid_q[0] <= 1'b0;
                    end
                endcase
            end
            if (id_queue_push) begin
                unique case (id_queue_tail_q)
                    2'd0: begin
                        id_queue_q0 <= incoming_pkt0;
                        id_queue_valid_q[0] <= 1'b1;
                        if (id_queue_push_two)
                            id_queue_q1 <= incoming_pkt1;
                        if (id_queue_push_two)
                            id_queue_valid_q[1] <= 1'b1;
                    end
                    2'd1: begin
                        id_queue_q1 <= incoming_pkt0;
                        id_queue_valid_q[1] <= 1'b1;
                        if (id_queue_push_two)
                            id_queue_q2 <= incoming_pkt1;
                        if (id_queue_push_two)
                            id_queue_valid_q[2] <= 1'b1;
                    end
                    2'd2: begin
                        id_queue_q2 <= incoming_pkt0;
                        id_queue_valid_q[2] <= 1'b1;
                        if (id_queue_push_two)
                            id_queue_q3 <= incoming_pkt1;
                        if (id_queue_push_two)
                            id_queue_valid_q[3] <= 1'b1;
                    end
                    default: begin
                        id_queue_q3 <= incoming_pkt0;
                        id_queue_valid_q[3] <= 1'b1;
                        if (id_queue_push_two)
                            id_queue_q0 <= incoming_pkt1;
                        if (id_queue_push_two)
                            id_queue_valid_q[0] <= 1'b1;
                    end
                endcase
            end
            id_queue_head_q <= id_queue_head_q + 2'(id_queue_pop_count);
            id_queue_tail_q <= id_queue_tail_q + 2'(id_queue_push_count);
            id_queue_count_q <= id_queue_count_next;
            id_ready_q <= id_queue_count_next < 3'd4;
            id_two_room_q <= id_queue_count_next <= 3'd2;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n)
            assert (id_queue_count_q <= 3'd4)
                else $fatal(1, "ID elastic queue occupancy overflow");
    end
`endif
endmodule
