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
		logic fp_load;
		logic fp_store;
		logic fp_op;
		logic fp_fma;
		logic fp_known;
		logic fp_rm_used;
		logic fp_is_double;
		logic fp_double_enabled;
		logic [6:0] fp_funct7;
		logic [2:0] fp_funct3;
		logic [4:0] fp_rs2;
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

		fp_load = (instr_i[6:0] == 7'b0000111) &&
			((instr_i[14:12] == 3'b010) || (instr_i[14:12] == 3'b011));
		fp_store = (instr_i[6:0] == 7'b0100111) &&
			((instr_i[14:12] == 3'b010) || (instr_i[14:12] == 3'b011));
		fp_op = instr_i[6:0] == 7'b1010011;
		fp_fma = ((instr_i[6:0] == 7'b1000011) ||
		          (instr_i[6:0] == 7'b1000111) ||
		          (instr_i[6:0] == 7'b1001011) ||
		          (instr_i[6:0] == 7'b1001111)) &&
			((instr_i[26:25] == 2'b00) || (instr_i[26:25] == 2'b01));
		fp_funct7 = instr_i[31:25];
		fp_funct3 = instr_i[14:12];
		fp_rs2 = instr_i[24:20];
`ifdef YDRASIL_FPU_DOUBLE
		fp_double_enabled = 1'b1;
`else
		fp_double_enabled = 1'b0;
`endif
		fp_is_double = fp_load || fp_store ? (fp_funct3 == 3'b011) :
			fp_fma ? (instr_i[26:25] == 2'b01) : fp_funct7[0];
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

`ifdef YDRASIL_ENABLE_FPU
		decode_pkt_o.fp_valid = fp_load || fp_store || fp_fma || fp_op;
		decode_pkt_o.fp_illegal = decode_pkt_o.fp_valid &&
			(!fp_known || (fp_rm_used && (fp_funct3 > 3'b100) && (fp_funct3 != 3'b111)));
		decode_pkt_o.fp_rm = fp_funct3;
		decode_pkt_o.fp_rs1_addr = instr_i[19:15];
		decode_pkt_o.fp_rs2_addr = instr_i[24:20];
		decode_pkt_o.fp_rs3_addr = instr_i[31:27];
		decode_pkt_o.fp_rd_addr = instr_i[11:7];
		decode_pkt_o.fp_rs1_fpr = fp_fma || (fp_op &&
			!((fp_funct7[6:1] == 6'b110100) || (fp_funct7[6:1] == 6'b111100)));
		decode_pkt_o.fp_rs2_fpr = fp_fma || fp_store || (fp_op &&
			((fp_funct7[6:1] == 6'b000000) || (fp_funct7[6:1] == 6'b000010) ||
			 (fp_funct7[6:1] == 6'b000100) || (fp_funct7[6:1] == 6'b000110) ||
			 (fp_funct7[6:1] == 6'b001000) || (fp_funct7[6:1] == 6'b001010) ||
			 (fp_funct7[6:1] == 6'b101000)));
		decode_pkt_o.fp_rs3_fpr = fp_fma;
		decode_pkt_o.fp_rd_gpr = fp_op &&
			((fp_funct7[6:1] == 6'b101000) || (fp_funct7[6:1] == 6'b111000) ||
			 (fp_funct7[6:1] == 6'b110000));
		decode_pkt_o.fp_rd_fpr = decode_pkt_o.fp_valid && !fp_store && !decode_pkt_o.fp_rd_gpr;
		if (decode_pkt_o.fp_valid) begin
			decode_pkt_o.operator_type[OPERATOR_TYPE_FPU] = 1'b1;
			decode_pkt_o.operator_type[OPERATOR_TYPE_LOAD] = fp_load;
			decode_pkt_o.operator_type[OPERATOR_TYPE_STORE] = fp_store;
			decode_pkt_o.operator_lsu = '0;
			decode_pkt_o.operator_lsu[OP_LSU_LW] = fp_load;
			decode_pkt_o.operator_lsu[OP_LSU_SW] = fp_store;
			decode_pkt_o.rs1_addr = instr_i[19:15];
			decode_pkt_o.rs2_addr = instr_i[24:20];
			decode_pkt_o.rd_addr = instr_i[11:7];
			decode_pkt_o.rs1_ren = !decode_pkt_o.fp_rs1_fpr;
			decode_pkt_o.rs2_ren = 1'b0;
			decode_pkt_o.rd_wen = decode_pkt_o.fp_rd_gpr;
			decode_pkt_o.imm = fp_load ? {{20{instr_i[31]}}, instr_i[31:20]} :
				fp_store ? {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]} : '0;
		end
`else
		decode_pkt_o.fp_valid = fp_load || fp_store || fp_fma || fp_op;
		decode_pkt_o.fp_illegal = decode_pkt_o.fp_valid;
		decode_pkt_o.operator_type[OPERATOR_TYPE_FPU] = decode_pkt_o.fp_valid;
`endif
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
    output wire                  decode_pair_eligible_o,
    output ydrasil_decode_pkt_t  decode_pkt_o,
    output ydrasil_decode_pkt_t  decode_pkt1_o
);
    localparam int COUNT_WIDTH = $clog2(DECODE_FIFO_DEPTH + 1);
    localparam int PTR_WIDTH = $clog2(DECODE_FIFO_DEPTH);

    typedef struct packed {
        logic       simple_int;
        logic [4:0] rs1_addr;
        logic [4:0] rs2_addr;
        logic [4:0] rd_addr;
        logic       rs1_ren;
        logic       rs2_ren;
        logic       rd_wen;
    } pair_meta_t;

    reg [COUNT_WIDTH-1:0] decode_count_q;
    (* max_fanout = 32 *) reg [PTR_WIDTH-1:0] decode_rptr_q;
    reg [PTR_WIDTH-1:0] decode_wptr_q;
    ydrasil_decode_pkt_t decode_fifo_q [0:DECODE_FIFO_DEPTH-1];
    pair_meta_t pair_meta_fifo_q [0:DECODE_FIFO_DEPTH-1];
    ydrasil_decode_pkt_t decoded0;
    ydrasil_decode_pkt_t decoded1;
    pair_meta_t decoded_meta0;
    pair_meta_t decoded_meta1;
    wire decoded0_fast_bitmanip =
        decoded0.operator_type[OPERATOR_TYPE_BITMANIP] &&
        (decoded0.operator_info[OP_B_SH1ADD] |
         decoded0.operator_info[OP_B_SH2ADD] |
         decoded0.operator_info[OP_B_SH3ADD] |
         decoded0.operator_info[OP_B_ANDN] |
         decoded0.operator_info[OP_B_ORN] |
         decoded0.operator_info[OP_B_XNOR] |
         decoded0.operator_info[OP_B_BCLR] |
         decoded0.operator_info[OP_B_BCLRI] |
         decoded0.operator_info[OP_B_BEXT] |
         decoded0.operator_info[OP_B_BEXTI] |
         decoded0.operator_info[OP_B_BINV] |
         decoded0.operator_info[OP_B_BINVI] |
         decoded0.operator_info[OP_B_BSET] |
         decoded0.operator_info[OP_B_BSETI] |
         decoded0.operator_info[OP_B_PACK] |
         decoded0.operator_info[OP_B_PACKH] |
         decoded0.operator_info[OP_B_REV8] |
         decoded0.operator_info[OP_B_SEXT_B] |
         decoded0.operator_info[OP_B_SEXT_H] |
         decoded0.operator_info[OP_B_ZEXT_H]);
    wire decoded1_fast_bitmanip =
        decoded1.operator_type[OPERATOR_TYPE_BITMANIP] &&
        (decoded1.operator_info[OP_B_SH1ADD] |
         decoded1.operator_info[OP_B_SH2ADD] |
         decoded1.operator_info[OP_B_SH3ADD] |
         decoded1.operator_info[OP_B_ANDN] |
         decoded1.operator_info[OP_B_ORN] |
         decoded1.operator_info[OP_B_XNOR] |
         decoded1.operator_info[OP_B_BCLR] |
         decoded1.operator_info[OP_B_BCLRI] |
         decoded1.operator_info[OP_B_BEXT] |
         decoded1.operator_info[OP_B_BEXTI] |
         decoded1.operator_info[OP_B_BINV] |
         decoded1.operator_info[OP_B_BINVI] |
         decoded1.operator_info[OP_B_BSET] |
         decoded1.operator_info[OP_B_BSETI] |
         decoded1.operator_info[OP_B_PACK] |
         decoded1.operator_info[OP_B_PACKH] |
         decoded1.operator_info[OP_B_REV8] |
         decoded1.operator_info[OP_B_SEXT_B] |
         decoded1.operator_info[OP_B_SEXT_H] |
         decoded1.operator_info[OP_B_ZEXT_H]);

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
    wire [PTR_WIDTH-1:0] decode_rptr1 =
        decode_rptr_q + PTR_WIDTH'(1);
    wire [PTR_WIDTH-1:0] decode_wptr1 =
        decode_wptr_q + PTR_WIDTH'(1);
    pair_meta_t pair_meta0;
    pair_meta_t pair_meta1;
    wire pair0_writes;
    wire pair1_writes;
    wire pair_raw;
    wire pair_waw;

    always_comb begin
        decoded_meta0 = '0;
        decoded_meta0.simple_int =
            (decoded0.operator_type[OPERATOR_TYPE_ALU] ||
             decoded0_fast_bitmanip) &&
            !decoded0.operator_type[OPERATOR_TYPE_BJP] &&
            !decoded0.operator_type[OPERATOR_TYPE_LOAD] &&
            !decoded0.operator_type[OPERATOR_TYPE_STORE] &&
            !decoded0.operator_type[OPERATOR_TYPE_MUL] &&
            !decoded0.operator_type[OPERATOR_TYPE_CSR] &&
            !decoded0.operator_type[OPERATOR_TYPE_SYS] && !decoded0.fence_i;
        decoded_meta0.rs1_addr = decoded0.rs1_addr;
        decoded_meta0.rs2_addr = decoded0.rs2_addr;
        decoded_meta0.rd_addr = decoded0.rd_addr;
        decoded_meta0.rs1_ren = decoded0.rs1_ren;
        decoded_meta0.rs2_ren = decoded0.rs2_ren;
        decoded_meta0.rd_wen = decoded0.rd_wen;

        decoded_meta1 = '0;
        decoded_meta1.simple_int =
            (decoded1.operator_type[OPERATOR_TYPE_ALU] ||
             decoded1_fast_bitmanip) &&
            !decoded1.operator_type[OPERATOR_TYPE_BJP] &&
            !decoded1.operator_type[OPERATOR_TYPE_LOAD] &&
            !decoded1.operator_type[OPERATOR_TYPE_STORE] &&
            !decoded1.operator_type[OPERATOR_TYPE_MUL] &&
            !decoded1.operator_type[OPERATOR_TYPE_CSR] &&
            !decoded1.operator_type[OPERATOR_TYPE_SYS] && !decoded1.fence_i;
        decoded_meta1.rs1_addr = decoded1.rs1_addr;
        decoded_meta1.rs2_addr = decoded1.rs2_addr;
        decoded_meta1.rd_addr = decoded1.rd_addr;
        decoded_meta1.rs1_ren = decoded1.rs1_ren;
        decoded_meta1.rs2_ren = decoded1.rs2_ren;
        decoded_meta1.rd_wen = decoded1.rd_wen;
    end

    assign if_id_ready_o = has_room_one;
    assign if_id_consume_two_o = push1;
    assign decode_valid_o = decode_count_q != '0;
    assign decode_valid1_o = decode_count_q > COUNT_WIDTH'(1);
    assign decode_pkt_o = decode_fifo_q[decode_rptr_q];
    assign decode_pkt1_o = decode_fifo_q[decode_rptr1];
    assign pair_meta0 = pair_meta_fifo_q[decode_rptr_q];
    assign pair_meta1 = pair_meta_fifo_q[decode_rptr1];
    assign pair0_writes = pair_meta0.rd_wen && (pair_meta0.rd_addr != '0);
    assign pair1_writes = pair_meta1.rd_wen && (pair_meta1.rd_addr != '0);
    assign pair_raw = pair0_writes &&
        ((pair_meta1.rs1_ren && (pair_meta1.rs1_addr == pair_meta0.rd_addr)) ||
         (pair_meta1.rs2_ren && (pair_meta1.rs2_addr == pair_meta0.rd_addr)));
    assign pair_waw = pair0_writes && pair1_writes &&
        (pair_meta0.rd_addr == pair_meta1.rd_addr);
    assign decode_pair_eligible_o = decode_count_q > COUNT_WIDTH'(1) &&
        pair_meta0.simple_int && pair_meta1.simple_int && !pair_raw && !pair_waw;

    integer idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_count_q <= '0;
            decode_rptr_q <= '0;
            decode_wptr_q <= '0;
            for (idx = 0; idx < DECODE_FIFO_DEPTH; idx = idx + 1) begin
                decode_fifo_q[idx] <= '0;
                pair_meta_fifo_q[idx] <= '0;
            end
        end else if (flush_i) begin
            decode_count_q <= '0;
            decode_rptr_q <= '0;
            decode_wptr_q <= '0;
        end else begin
            decode_rptr_q <= decode_rptr_q + PTR_WIDTH'(pop_count);
            decode_wptr_q <= decode_wptr_q + PTR_WIDTH'(push_count);
            if (push0) begin
                decode_fifo_q[decode_wptr_q] <= decoded0;
                pair_meta_fifo_q[decode_wptr_q] <= decoded_meta0;
            end
            if (push1) begin
                decode_fifo_q[decode_wptr1] <= decoded1;
                pair_meta_fifo_q[decode_wptr1] <= decoded_meta1;
            end
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
