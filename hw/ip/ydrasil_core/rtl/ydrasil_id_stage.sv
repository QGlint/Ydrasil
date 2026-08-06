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
    wire [OPERATOR_WIDTH-1:0] operator_info;
    wire [OP_LSU_INFO_WIDTH-1:0] operator_lsu;
    wire [OPERATOR_TYPE_WIDTH-1:0] operator_type;
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

		decode_pkt_o.illegal_instr = illegal_instr;
		if (illegal_instr) begin
			decode_pkt_o.rs1_addr = '0;
			decode_pkt_o.rs2_addr = '0;
			decode_pkt_o.rd_addr = '0;
			decode_pkt_o.rs1_ren = 1'b0;
			decode_pkt_o.rs2_ren = 1'b0;
			decode_pkt_o.rd_wen = 1'b0;
			decode_pkt_o.imm = '0;
			decode_pkt_o.operator_info = '0;
			decode_pkt_o.operator_lsu = '0;
			decode_pkt_o.operator_type = '0;
		end

		// Resource ownership is decoded once and travels with the packed packet.
		// ALU has two copies; all other resources are lane0/port exclusive.
		decode_pkt_o.resources = '0;
		decode_pkt_o.resources[RESOURCE_ALU] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_ALU] ||
			decode_pkt_o.operator_type[OPERATOR_TYPE_BITMANIP];
		decode_pkt_o.resources[RESOURCE_FULL_BITMANIP] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_BITMANIP] &&
			!(decode_pkt_o.operator_info[OP_B_SH1ADD] |
			  decode_pkt_o.operator_info[OP_B_SH2ADD] |
			  decode_pkt_o.operator_info[OP_B_SH3ADD] |
			  decode_pkt_o.operator_info[OP_B_ANDN]   |
			  decode_pkt_o.operator_info[OP_B_ORN]    |
			  decode_pkt_o.operator_info[OP_B_XNOR]   |
			  decode_pkt_o.operator_info[OP_B_MIN]    |
			  decode_pkt_o.operator_info[OP_B_MAX]    |
			  decode_pkt_o.operator_info[OP_B_MINU]   |
			  decode_pkt_o.operator_info[OP_B_MAXU]   |
			  decode_pkt_o.operator_info[OP_B_REV8]   |
			  decode_pkt_o.operator_info[OP_B_SEXT_B] |
			  decode_pkt_o.operator_info[OP_B_SEXT_H] |
			  decode_pkt_o.operator_info[OP_B_ZEXT_H]);
		decode_pkt_o.resources[RESOURCE_BRU] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_BJP];
		decode_pkt_o.resources[RESOURCE_LSU] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_LOAD] ||
			decode_pkt_o.operator_type[OPERATOR_TYPE_STORE];
		decode_pkt_o.resources[RESOURCE_MULDIV] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_MUL];
		decode_pkt_o.resources[RESOURCE_SERIAL] =
			decode_pkt_o.operator_type[OPERATOR_TYPE_CSR] ||
			decode_pkt_o.operator_type[OPERATOR_TYPE_SYS] ||
			decode_pkt_o.illegal_instr || decode_pkt_o.fence_i;
    end
endmodule

module ydrasil_id_stage
import ydrasil_pkg::*;
(
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
    wire decode_valid1 = if_id1_valid_i;
    wire slot0_writes = (decoded0.rd_addr != '0) &&
		(decoded0.rd_wen || decoded0.operator_type[OPERATOR_TYPE_LOAD]);
    wire slot1_writes = (decoded1.rd_addr != '0) &&
		(decoded1.rd_wen || decoded1.operator_type[OPERATOR_TYPE_LOAD]);
    wire pair_raw = slot0_writes &&
        ((decoded1.rs1_ren && (decoded1.rs1_addr == decoded0.rd_addr)) ||
		 ((decoded1.rs2_ren || decoded1.operator_type[OPERATOR_TYPE_STORE]) &&
          (decoded1.rs2_addr == decoded0.rd_addr)));
    wire pair_waw = slot0_writes && slot1_writes &&
        (decoded0.rd_addr == decoded1.rd_addr);
    wire pair_resource_conflict =
        |(decoded0.resources & decoded1.resources & RESOURCE_EXCLUSIVE_MASK);
    wire pair_serialize = decoded0.resources[RESOURCE_SERIAL] ||
        decoded1.resources[RESOURCE_SERIAL];
    wire pair_control_memory =
        decoded0.resources[RESOURCE_BRU] && decoded1.resources[RESOURCE_LSU];
    wire pair_mul_memory =
        (decoded0.resources[RESOURCE_MULDIV] &&
         decoded1.resources[RESOURCE_LSU]) ||
        (decoded0.resources[RESOURCE_LSU] &&
         decoded1.resources[RESOURCE_MULDIV]);
    wire slot0_a_capable = !decoded0.resources[RESOURCE_BRU] &&
        !decoded0.resources[RESOURCE_LSU];
    wire slot0_b_capable = !decoded0.resources[RESOURCE_MULDIV] &&
        !decoded0.resources[RESOURCE_FULL_BITMANIP] &&
		!decoded0.resources[RESOURCE_SERIAL];
    wire slot1_a_capable = !decoded1.resources[RESOURCE_BRU] &&
        !decoded1.resources[RESOURCE_LSU];
    wire slot1_b_capable = !decoded1.resources[RESOURCE_MULDIV] &&
        !decoded1.resources[RESOURCE_FULL_BITMANIP] &&
		!decoded1.resources[RESOURCE_SERIAL];
    wire pair_lane_assignable =
        (slot0_a_capable && slot1_b_capable) ||
        (slot0_b_capable && slot1_a_capable);
    wire pair_eligible = decode_valid && decode_valid1 && pair_lane_assignable &&
        !pair_resource_conflict && !pair_raw && !pair_waw && !pair_serialize &&
	        !pair_control_memory && !pair_mul_memory;

    assign if_id_ready_o = issue_ready_i;
    assign if_id_consume_two_o = issue_ready_i && pair_eligible;

    always_comb begin
        issue_pkt_o = '0;
        issue_pkt_o.valid = decode_valid;
        issue_pkt_o.decode = decoded0;
        issue_pkt_o.dual_capable = decode_valid &&
            (slot0_a_capable || slot0_b_capable);
        issue_pkt_o.pair_eligible = pair_eligible;
        issue_pkt_o.static_pair = pair_eligible;
        issue_pkt_o.lane_mask = {slot0_b_capable, slot0_a_capable};
        issue_pkt_o.memory_op = decode_valid &&
            (decoded0.operator_type[OPERATOR_TYPE_LOAD] ||
             decoded0.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.target = decoded0.pc + decoded0.imm;
        issue_pkt_o.next_pc = decoded0.pc + 32'd4;
        issue_pkt_o.src0.used = decode_valid && decoded0.rs1_ren;
        issue_pkt_o.src0.arch_addr = decoded0.rs1_addr;
        issue_pkt_o.src1.used = decode_valid &&
			(decoded0.rs2_ren || decoded0.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.src1.arch_addr = decoded0.rs2_addr;
        issue_pkt_o.dst.writes_gpr = decode_valid && slot0_writes;
        issue_pkt_o.dst.rd_addr = decoded0.rd_addr;
        issue_pkt_o.ctrl.rs1_addr = decoded0.rs1_addr;
        issue_pkt_o.ctrl.valid = decode_valid;
        issue_pkt_o.ctrl.rs2_addr = decoded0.rs2_addr;
        issue_pkt_o.ctrl.rd_addr = decoded0.rd_addr;
        issue_pkt_o.ctrl.rs1_ren = decode_valid && decoded0.rs1_ren;
        issue_pkt_o.ctrl.rs2_ren = decode_valid &&
			(decoded0.rs2_ren || decoded0.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.ctrl.rd_wen = decode_valid && slot0_writes;
        issue_pkt_o.ctrl.lsu_req = decode_valid &&
            (decoded0.operator_type[OPERATOR_TYPE_LOAD] ||
             decoded0.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.ctrl.store_req = decode_valid &&
            decoded0.operator_type[OPERATOR_TYPE_STORE];
        issue_pkt_o.ctrl.serialize_before = decode_valid &&
            (decoded0.operator_type[OPERATOR_TYPE_CSR] ||
             decoded0.operator_type[OPERATOR_TYPE_SYS] || decoded0.fence_i);
        issue_pkt_o.ctrl.checkpoint_req = decode_valid &&
            decoded0.operator_type[OPERATOR_TYPE_BJP];

        issue_pkt1_o = '0;
        issue_pkt1_o.valid = decode_valid1;
        issue_pkt1_o.lane1 = 1'b1;
        issue_pkt1_o.decode = decoded1;
        issue_pkt1_o.dual_capable = decode_valid1 &&
            (slot1_a_capable || slot1_b_capable);
        issue_pkt1_o.lane_mask = {slot1_b_capable, slot1_a_capable};
        issue_pkt1_o.memory_op = decode_valid1 &&
            (decoded1.operator_type[OPERATOR_TYPE_LOAD] ||
             decoded1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.target = decoded1.pc + decoded1.imm;
        issue_pkt1_o.next_pc = decoded1.pc + 32'd4;
        issue_pkt1_o.src0.used = decode_valid1 && decoded1.rs1_ren;
        issue_pkt1_o.src0.arch_addr = decoded1.rs1_addr;
        issue_pkt1_o.src1.used = decode_valid1 &&
			(decoded1.rs2_ren || decoded1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.src1.arch_addr = decoded1.rs2_addr;
        issue_pkt1_o.dst.writes_gpr = decode_valid1 && slot1_writes;
        issue_pkt1_o.dst.rd_addr = decoded1.rd_addr;
        issue_pkt1_o.ctrl.rs1_addr = decoded1.rs1_addr;
        issue_pkt1_o.ctrl.valid = decode_valid1;
        issue_pkt1_o.ctrl.rs2_addr = decoded1.rs2_addr;
        issue_pkt1_o.ctrl.rd_addr = decoded1.rd_addr;
        issue_pkt1_o.ctrl.rs1_ren = decode_valid1 && decoded1.rs1_ren;
        issue_pkt1_o.ctrl.rs2_ren = decode_valid1 &&
			(decoded1.rs2_ren || decoded1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.ctrl.rd_wen = decode_valid1 && slot1_writes;
        issue_pkt1_o.ctrl.lsu_req = decode_valid1 &&
            (decoded1.operator_type[OPERATOR_TYPE_LOAD] ||
             decoded1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.ctrl.store_req = decode_valid1 &&
            decoded1.operator_type[OPERATOR_TYPE_STORE];
        issue_pkt1_o.ctrl.serialize_before = decode_valid1 &&
            (decoded1.operator_type[OPERATOR_TYPE_CSR] ||
             decoded1.operator_type[OPERATOR_TYPE_SYS] || decoded1.fence_i);
        issue_pkt1_o.ctrl.checkpoint_req = decode_valid1 &&
            decoded1.operator_type[OPERATOR_TYPE_BJP];
    end

    wire unused = &{1'b0, clk, rst_n, flush_i, issue_consume_two_i};
endmodule
