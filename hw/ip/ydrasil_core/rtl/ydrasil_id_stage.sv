module ydrasil_decode_slot
import ydrasil_pkg::*;
(
    input  wire [31:0] pc_i,
    input  wire [31:0] instr_i,
    input  wire        pred_hit_i,
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,
    input  wire [1:0]  pred_counter_i,
    input  wire [1:0]  pred_global_counter_i,
    input  wire [1:0]  pred_local_counter_i,
    input  bp_bht_index_t pred_bht_index_i,
    output ydrasil_decode_pkt_t decode_pkt_o,
    output wire [REGS_ADDR_WIDTH-1:0] src0_arch_addr_o,
    output wire                         src0_used_o,
    output wire [REGS_ADDR_WIDTH-1:0] src1_arch_addr_o,
    output wire                         src1_used_o,
    output wire [REGS_ADDR_WIDTH-1:0] dst_arch_addr_o,
    output wire                         dst_writes_o
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
	logic [UOP_CLASS_WIDTH-1:0] op_class;
	logic [UOP_SUBOP_WIDTH-1:0] subop;
	logic [UOP_LSU_SUBOP_WIDTH-1:0] lsu_subop;
	wire full_bitmanip;
	wire divrem;
	wire fp_load = (instr_i[6:0] == 7'b0000111) &&
		((instr_i[14:12] == 3'b010) || (instr_i[14:12] == 3'b011));
	wire fp_store = (instr_i[6:0] == 7'b0100111) &&
		((instr_i[14:12] == 3'b010) || (instr_i[14:12] == 3'b011));
	wire fp_op = instr_i[6:0] == 7'b1010011;
	wire fp_fma = ((instr_i[6:0] == 7'b1000011) ||
		(instr_i[6:0] == 7'b1000111) ||
		(instr_i[6:0] == 7'b1001011) ||
		(instr_i[6:0] == 7'b1001111)) &&
		((instr_i[26:25] == 2'b00) || (instr_i[26:25] == 2'b01));
	wire fp_opcode = fp_load || fp_store || fp_fma || fp_op;
	wire fp_is_double = (fp_load || fp_store) ? (instr_i[14:12] == 3'b011) :
		fp_fma ? (instr_i[26:25] == 2'b01) : instr_i[25];
	wire fp_int_source = fp_op &&
		((instr_i[31:26] == 6'b110100) ||
		 (instr_i[31:26] == 6'b111100));
	wire fp_gpr_destination = fp_op &&
		((instr_i[31:26] == 6'b101000) ||
		 (instr_i[31:26] == 6'b111000) ||
		 (instr_i[31:26] == 6'b110000));
	wire fp_gpr_src0 = fp_load || fp_store || fp_int_source;
	wire fp_gpr_dst = fp_gpr_destination;
`ifdef YDRASIL_ENABLE_FPU
	wire illegal_instr = 1'b0;
`else
	wire illegal_instr = fp_opcode;
`endif
	logic fp_known;
	logic fp_rm_used;
	logic fp_double_enabled;
	logic [6:0] fp_funct7;
	logic [2:0] fp_funct3;
	logic [4:0] fp_rs2;
	logic fp_illegal;

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
		.operator_type_o(operator_type),
		.uop_class_o(op_class),
		.uop_subop_o(subop),
		.uop_lsu_subop_o(lsu_subop),
		.full_bitmanip_o(full_bitmanip),
		.divrem_o(divrem)
    );

    assign src0_arch_addr_o = rs1_addr;
    assign src0_used_o = illegal_instr ? 1'b0 :
`ifdef YDRASIL_ENABLE_FPU
        (fp_opcode ? fp_gpr_src0 : rs1_ren);
`else
        rs1_ren;
`endif
    assign src1_arch_addr_o = rs2_addr;
    assign src1_used_o = illegal_instr ? 1'b0 :
`ifdef YDRASIL_ENABLE_FPU
        (fp_opcode ? 1'b0 : rs2_ren);
`else
        rs2_ren;
`endif
    assign dst_arch_addr_o = rd_addr;
    assign dst_writes_o = illegal_instr ? 1'b0 :
`ifdef YDRASIL_ENABLE_FPU
        (fp_opcode ? fp_gpr_dst : rd_wen);
`else
        rd_wen;
`endif

    always_comb begin
		decode_pkt_o = '0;
        decode_pkt_o.pc = pc_i;
        decode_pkt_o.instr = instr_i;
        decode_pkt_o.pred_hit = pred_hit_i;
        decode_pkt_o.pred_taken = pred_taken_i;
        decode_pkt_o.pred_target = pred_target_i;
        decode_pkt_o.pred_counter = pred_counter_i;
        decode_pkt_o.pred_global_counter = pred_global_counter_i;
        decode_pkt_o.pred_local_counter = pred_local_counter_i;
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

		fp_funct7 = instr_i[31:25];
		fp_funct3 = instr_i[14:12];
		fp_rs2 = instr_i[24:20];
`ifdef YDRASIL_FPU_DOUBLE
		fp_double_enabled = 1'b1;
`else
		fp_double_enabled = 1'b0;
`endif
		fp_known = (fp_load || fp_store || fp_fma) &&
			(!fp_is_double || fp_double_enabled);
		fp_rm_used = 1'b0;
		decode_pkt_o.fp_op = FPU_OP_ADD;
		decode_pkt_o.fp_fmt = fp_is_double;
		decode_pkt_o.fp_dst_fmt = fp_is_double;
		if (fp_fma) begin
			fp_rm_used = 1'b1;
			case (instr_i[6:0])
				7'b1000011: decode_pkt_o.fp_op = FPU_OP_FMADD;
				7'b1000111: decode_pkt_o.fp_op = FPU_OP_FMSUB;
				7'b1001011: decode_pkt_o.fp_op = FPU_OP_FNMSUB;
				default:    decode_pkt_o.fp_op = FPU_OP_FNMADD;
			endcase
		end else if (fp_op) begin
			case (fp_funct7[6:1])
				6'b000000: begin fp_known = !fp_is_double || fp_double_enabled; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_ADD; end
				6'b000010: begin fp_known = !fp_is_double || fp_double_enabled; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_SUB; end
				6'b000100: begin fp_known = !fp_is_double || fp_double_enabled; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_MUL; end
				6'b000110: begin fp_known = !fp_is_double || fp_double_enabled; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_DIV; end
				6'b010110: begin fp_known = (fp_rs2 == 5'd0) && (!fp_is_double || fp_double_enabled); fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_SQRT; end
				6'b001000: begin
					fp_known = (fp_funct3 <= 3'b010) && (!fp_is_double || fp_double_enabled);
					case (fp_funct3)
						3'b000: decode_pkt_o.fp_op = FPU_OP_SGNJ;
						3'b001: decode_pkt_o.fp_op = FPU_OP_SGNJN;
						default: decode_pkt_o.fp_op = FPU_OP_SGNJX;
					endcase
				end
				6'b001010: begin
					fp_known = (fp_funct3 <= 3'b001) && (!fp_is_double || fp_double_enabled);
					decode_pkt_o.fp_op = fp_funct3[0] ? FPU_OP_MAX : FPU_OP_MIN;
				end
				6'b101000: begin
					fp_known = ((fp_funct3 == 3'b000) || (fp_funct3 == 3'b001) ||
						(fp_funct3 == 3'b010)) && (!fp_is_double || fp_double_enabled);
					case (fp_funct3)
						3'b010: decode_pkt_o.fp_op = FPU_OP_EQ;
						3'b001: decode_pkt_o.fp_op = FPU_OP_LT;
						default: decode_pkt_o.fp_op = FPU_OP_LE;
					endcase
				end
				6'b111000: begin
					fp_known = (fp_rs2 == 5'd0) &&
						(fp_funct3 == 3'b001 || (!fp_is_double && fp_funct3 == 3'b000)) &&
						(!fp_is_double || fp_double_enabled);
					decode_pkt_o.fp_op = fp_funct3[0] ? FPU_OP_CLASS : FPU_OP_MV_X_W;
				end
				6'b110000: begin
					fp_known = (fp_rs2 <= 5'd1) && (!fp_is_double || fp_double_enabled);
					fp_rm_used = 1'b1;
					if (fp_is_double)
						decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_WU_D : FPU_OP_CVT_W_D;
					else
						decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_WU_S : FPU_OP_CVT_W_S;
				end
				6'b110100: begin
					fp_known = (fp_rs2 <= 5'd1) && (!fp_is_double || fp_double_enabled);
					fp_rm_used = 1'b1;
					if (fp_is_double)
						decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_D_WU : FPU_OP_CVT_D_W;
					else
						decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_S_WU : FPU_OP_CVT_S_W;
				end
				6'b010000: begin
					fp_rm_used = 1'b1;
					if (!fp_funct7[0]) begin
						fp_known = fp_double_enabled && (fp_rs2 == 5'd1);
						decode_pkt_o.fp_op = FPU_OP_CVT_S_D;
						decode_pkt_o.fp_fmt = 1'b1;
						decode_pkt_o.fp_dst_fmt = 1'b0;
					end else begin
						fp_known = fp_double_enabled && (fp_rs2 == 5'd0);
						decode_pkt_o.fp_op = FPU_OP_CVT_D_S;
						decode_pkt_o.fp_fmt = 1'b0;
						decode_pkt_o.fp_dst_fmt = 1'b1;
					end
				end
				6'b111100: begin
					fp_known = !fp_is_double && (fp_rs2 == 5'd0) && (fp_funct3 == 3'b000);
					decode_pkt_o.fp_op = FPU_OP_MV_W_X;
				end
				default: fp_known = 1'b0;
			endcase
		end else if (fp_load) begin
			decode_pkt_o.fp_op = fp_is_double ? FPU_OP_FLD : FPU_OP_FLW;
		end else if (fp_store) begin
			decode_pkt_o.fp_op = fp_is_double ? FPU_OP_FSD : FPU_OP_FSW;
		end

		decode_pkt_o.fp_valid = fp_opcode;
		decode_pkt_o.fp_rm = fp_funct3;
		decode_pkt_o.fp_rs1_addr = instr_i[19:15];
		decode_pkt_o.fp_rs2_addr = instr_i[24:20];
		decode_pkt_o.fp_rs3_addr = instr_i[31:27];
		decode_pkt_o.fp_rd_addr = instr_i[11:7];
		decode_pkt_o.fp_rs1_fpr = fp_fma || (fp_op && !fp_int_source);
		decode_pkt_o.fp_rs2_fpr = fp_fma || fp_store || (fp_op &&
			((fp_funct7[6:1] == 6'b000000) || (fp_funct7[6:1] == 6'b000010) ||
			 (fp_funct7[6:1] == 6'b000100) || (fp_funct7[6:1] == 6'b000110) ||
			 (fp_funct7[6:1] == 6'b001000) || (fp_funct7[6:1] == 6'b001010) ||
			 (fp_funct7[6:1] == 6'b101000)));
		decode_pkt_o.fp_rs3_fpr = fp_fma;
		decode_pkt_o.fp_rd_gpr = fp_gpr_destination;
		decode_pkt_o.fp_rd_fpr = decode_pkt_o.fp_valid && !fp_store &&
			!decode_pkt_o.fp_rd_gpr;
		fp_illegal = fp_opcode && (!fp_known ||
			(fp_rm_used && (fp_funct3 > 3'b100) && (fp_funct3 != 3'b111)));
		decode_pkt_o.fp_illegal = fp_illegal;
		decode_pkt_o.illegal_instr = illegal_instr || fp_illegal;

`ifdef YDRASIL_ENABLE_FPU
		if (fp_opcode && !fp_illegal) begin
			decode_pkt_o.op_class = fp_load ? UOP_CLASS_LOAD :
				fp_store ? UOP_CLASS_STORE : UOP_CLASS_FPU;
			decode_pkt_o.lsu_subop = fp_load ?
				UOP_LSU_SUBOP_WIDTH'(OP_LSU_LW) : fp_store ?
				UOP_LSU_SUBOP_WIDTH'(OP_LSU_SW) : '0;
			decode_pkt_o.rs1_addr = instr_i[19:15];
			decode_pkt_o.rs2_addr = instr_i[24:20];
			decode_pkt_o.rd_addr = instr_i[11:7];
			decode_pkt_o.rs1_ren = fp_gpr_src0;
			decode_pkt_o.rs2_ren = 1'b0;
			decode_pkt_o.rd_wen = fp_gpr_dst;
			decode_pkt_o.imm = fp_load ? {{20{instr_i[31]}}, instr_i[31:20]} :
				fp_store ? {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]} : '0;
		end
`endif

		if (decode_pkt_o.illegal_instr) begin
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
    input  wire [1:0]            if_id_pred_global_counter_i,
    input  wire [1:0]            if_id_pred_local_counter_i,
    input  bp_bht_index_t        if_id_pred_bht_index_i,
    input  wire                  if_id_valid_i,
    input  wire                  if_id_serial_i,
    input  ydrasil_dispatch_domain_t if_id_domain_i,
    input  wire                  if_id_src0_used_i,
    input  wire                  if_id_src1_used_i,
    input  wire                  if_id_dst_writes_i,
    input  wire [31:0]           if_id1_pc_i,
    input  wire [31:0]           if_id1_instr_i,
    input  wire                  if_id1_pred_hit_i,
    input  wire                  if_id1_pred_taken_i,
    input  wire [31:0]           if_id1_pred_target_i,
    input  wire [1:0]            if_id1_pred_counter_i,
    input  wire [1:0]            if_id1_pred_global_counter_i,
    input  wire [1:0]            if_id1_pred_local_counter_i,
    input  bp_bht_index_t        if_id1_pred_bht_index_i,
    input  wire                  if_id1_valid_i,
    input  wire                  if_id1_serial_i,
    input  ydrasil_dispatch_domain_t if_id1_domain_i,
    input  wire                  if_id1_src0_used_i,
    input  wire                  if_id1_src1_used_i,
    input  wire                  if_id1_dst_writes_i,
    output wire                  if_id_ready_o,
    output wire                  if_id_consume_two_o,
    output ydrasil_issue_pkt_t   issue_pkt_o,
    output ydrasil_issue_pkt_t   issue_pkt1_o,
    output ydrasil_source_desc_t decode_src0_o,
    output ydrasil_source_desc_t decode_src1_o,
    output ydrasil_source_desc_t decode_src2_o,
    output ydrasil_source_desc_t decode_src3_o,
    output wire                    decode_dst0_writes_o,
    output wire [REGS_ADDR_WIDTH-1:0] decode_dst0_addr_o
);
    ydrasil_decode_pkt_t decoded0;
    ydrasil_decode_pkt_t decoded1;
    wire [REGS_ADDR_WIDTH-1:0] decoded0_src0_addr;
    wire [REGS_ADDR_WIDTH-1:0] decoded0_src1_addr;
    wire [REGS_ADDR_WIDTH-1:0] decoded1_src0_addr;
    wire [REGS_ADDR_WIDTH-1:0] decoded1_src1_addr;
    wire decoded0_src0_used;
    wire decoded0_src1_used;
    wire decoded1_src0_used;
    wire decoded1_src1_used;
    wire [REGS_ADDR_WIDTH-1:0] decoded0_dst_addr;
    wire [REGS_ADDR_WIDTH-1:0] decoded1_dst_addr;
    wire decoded0_dst_writes;
    wire decoded1_dst_writes;

    ydrasil_decode_slot u_decode0 (
        .pc_i(if_id_pc_i), .instr_i(if_id_instr_i),
        .pred_hit_i(if_id_pred_hit_i), .pred_taken_i(if_id_pred_taken_i),
        .pred_target_i(if_id_pred_target_i), .pred_counter_i(if_id_pred_counter_i),
        .pred_global_counter_i(if_id_pred_global_counter_i),
        .pred_local_counter_i(if_id_pred_local_counter_i),
        .pred_bht_index_i(if_id_pred_bht_index_i),
        .decode_pkt_o(decoded0),
        .src0_arch_addr_o(decoded0_src0_addr),
        .src0_used_o(decoded0_src0_used),
        .src1_arch_addr_o(decoded0_src1_addr),
        .src1_used_o(decoded0_src1_used),
        .dst_arch_addr_o(decoded0_dst_addr),
        .dst_writes_o(decoded0_dst_writes)
    );
    ydrasil_decode_slot u_decode1 (
        .pc_i(if_id1_pc_i), .instr_i(if_id1_instr_i),
        .pred_hit_i(if_id1_pred_hit_i), .pred_taken_i(if_id1_pred_taken_i),
        .pred_target_i(if_id1_pred_target_i), .pred_counter_i(if_id1_pred_counter_i),
        .pred_global_counter_i(if_id1_pred_global_counter_i),
        .pred_local_counter_i(if_id1_pred_local_counter_i),
        .pred_bht_index_i(if_id1_pred_bht_index_i),
        .decode_pkt_o(decoded1),
        .src0_arch_addr_o(decoded1_src0_addr),
        .src0_used_o(decoded1_src0_used),
        .src1_arch_addr_o(decoded1_src1_addr),
        .src1_used_o(decoded1_src1_used),
        .dst_arch_addr_o(decoded1_dst_addr),
        .dst_writes_o(decoded1_dst_writes)
    );

    wire decode_valid = if_id_valid_i;
    wire decoded0_memory = if_id_domain_i == DISPATCH_DOMAIN_P0;
    wire decoded1_memory = if_id1_domain_i == DISPATCH_DOMAIN_P0;
    wire decoded0_store = if_id_instr_i[6:0] == RV32I_INS_TYPE_S;
    wire decoded1_store = if_id1_instr_i[6:0] == RV32I_INS_TYPE_S;
    // A younger instruction must remain in FetchQ while slot 0 establishes a
    // serializing redirect or CSR boundary. This keeps FetchQ pop, Issue FIFO
    // push, and ROB allocation on the same one-entry transaction.
    wire decode_valid1 = if_id1_valid_i && !if_id_serial_i;
    wire slot0_writes = if_id_dst_writes_i &&
        (if_id_instr_i[11:7] != '0);
    wire slot1_writes = if_id1_dst_writes_i &&
        (if_id1_instr_i[11:7] != '0);
    // P0 owns ALU/LSU. P1 owns ALU/Zb/BRU/MDU/SERIAL. Keeping the two
    // capability bits class-local prevents payload-dependent lane assignment
    // from re-entering the Issue select cone, and keeps every Zb operation off
    // the main ALU datapath.
    wire slot0_a_capable = if_id_domain_i != DISPATCH_DOMAIN_P1;
    wire slot0_b_capable = if_id_domain_i != DISPATCH_DOMAIN_P0;
    wire slot1_a_capable = if_id1_domain_i != DISPATCH_DOMAIN_P1;
    wire slot1_b_capable = if_id1_domain_i != DISPATCH_DOMAIN_P0;
    assign if_id_ready_o = issue_ready_i;
    assign if_id_consume_two_o = issue_ready_i && decode_valid1;
    assign decode_dst0_addr_o = if_id_instr_i[11:7];
    assign decode_dst0_writes_o = decode_valid &&
        if_id_dst_writes_i && (if_id_instr_i[11:7] != '0);

    always_comb begin
        decode_src0_o = '0;
        decode_src0_o.used = decode_valid && if_id_src0_used_i;
        decode_src0_o.arch_addr = if_id_instr_i[19:15];
        decode_src1_o = '0;
        decode_src1_o.used = decode_valid && if_id_src1_used_i;
        decode_src1_o.arch_addr = if_id_instr_i[24:20];
        decode_src2_o = '0;
        decode_src2_o.used = decode_valid1 && if_id1_src0_used_i;
        decode_src2_o.arch_addr = if_id1_instr_i[19:15];
        decode_src3_o = '0;
        decode_src3_o.used = decode_valid1 && if_id1_src1_used_i;
        decode_src3_o.arch_addr = if_id1_instr_i[24:20];
    end

    always_comb begin
        issue_pkt_o = '0;
        issue_pkt_o.valid = decode_valid;
        issue_pkt_o.decode = decoded0;
        issue_pkt_o.uop_class = decoded0.op_class;
        issue_pkt_o.uop_subop = decoded0.subop;
        issue_pkt_o.uop_lsu_subop = decoded0.lsu_subop;
        issue_pkt_o.lane_mask = {slot0_b_capable, slot0_a_capable};
        issue_pkt_o.src0.used = decode_valid && if_id_src0_used_i;
        issue_pkt_o.src0.arch_addr = if_id_instr_i[19:15];
        issue_pkt_o.src1.used = decode_valid && if_id_src1_used_i;
        issue_pkt_o.src1.arch_addr = if_id_instr_i[24:20];
        issue_pkt_o.dst.writes_gpr = decode_valid && slot0_writes;
        issue_pkt_o.dst.rd_addr = if_id_instr_i[11:7];
        issue_pkt_o.ctrl.rs1_addr = if_id_instr_i[19:15];
        issue_pkt_o.ctrl.valid = decode_valid;
        issue_pkt_o.ctrl.rs2_addr = if_id_instr_i[24:20];
        issue_pkt_o.ctrl.rd_addr = if_id_instr_i[11:7];
        issue_pkt_o.ctrl.rs1_ren = decode_valid && if_id_src0_used_i;
        issue_pkt_o.ctrl.rs2_ren = decode_valid && if_id_src1_used_i;
        issue_pkt_o.ctrl.rd_wen = decode_valid && slot0_writes;
        issue_pkt_o.ctrl.lsu_req = decode_valid && decoded0_memory;
        issue_pkt_o.ctrl.store_req = decode_valid && decoded0_store;
        issue_pkt_o.ctrl.serialize_before = decode_valid && if_id_serial_i;

        issue_pkt1_o = '0;
        issue_pkt1_o.valid = decode_valid1;
        issue_pkt1_o.decode = decoded1;
        issue_pkt1_o.uop_class = decoded1.op_class;
        issue_pkt1_o.uop_subop = decoded1.subop;
        issue_pkt1_o.uop_lsu_subop = decoded1.lsu_subop;
        issue_pkt1_o.lane_mask = {slot1_b_capable, slot1_a_capable};
        issue_pkt1_o.src0.used = decode_valid1 && if_id1_src0_used_i;
        issue_pkt1_o.src0.arch_addr = if_id1_instr_i[19:15];
        issue_pkt1_o.src1.used = decode_valid1 && if_id1_src1_used_i;
        issue_pkt1_o.src1.arch_addr = if_id1_instr_i[24:20];
        issue_pkt1_o.dst.writes_gpr = decode_valid1 && slot1_writes;
        issue_pkt1_o.dst.rd_addr = if_id1_instr_i[11:7];
        issue_pkt1_o.ctrl.rs1_addr = if_id1_instr_i[19:15];
        issue_pkt1_o.ctrl.valid = decode_valid1;
        issue_pkt1_o.ctrl.rs2_addr = if_id1_instr_i[24:20];
        issue_pkt1_o.ctrl.rd_addr = if_id1_instr_i[11:7];
        issue_pkt1_o.ctrl.rs1_ren = decode_valid1 && if_id1_src0_used_i;
        issue_pkt1_o.ctrl.rs2_ren = decode_valid1 && if_id1_src1_used_i;
        issue_pkt1_o.ctrl.rd_wen = decode_valid1 && slot1_writes;
        issue_pkt1_o.ctrl.lsu_req = decode_valid1 && decoded1_memory;
        issue_pkt1_o.ctrl.store_req = decode_valid1 && decoded1_store;
        issue_pkt1_o.ctrl.serialize_before = decode_valid1 && if_id1_serial_i;
    end

    wire unused = &{1'b0, clk, rst_n, flush_i, if_id1_serial_i,
        decoded0_src0_addr, decoded0_src1_addr, decoded1_src0_addr,
        decoded1_src1_addr, decoded0_src0_used, decoded0_src1_used,
        decoded1_src0_used, decoded1_src1_used, decoded0_dst_addr,
        decoded1_dst_addr, decoded0_dst_writes, decoded1_dst_writes};
endmodule
