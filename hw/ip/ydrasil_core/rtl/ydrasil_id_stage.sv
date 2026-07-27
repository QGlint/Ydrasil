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

		fp_load = (instr_i[6:0] == 7'b0000111) && (instr_i[14:12] == 3'b010);
		fp_store = (instr_i[6:0] == 7'b0100111) && (instr_i[14:12] == 3'b010);
		fp_op = instr_i[6:0] == 7'b1010011;
		fp_fma = ((instr_i[6:0] == 7'b1000011) ||
		          (instr_i[6:0] == 7'b1000111) ||
		          (instr_i[6:0] == 7'b1001011) ||
		          (instr_i[6:0] == 7'b1001111)) && (instr_i[26:25] == 2'b00);
		fp_funct7 = instr_i[31:25];
		fp_funct3 = instr_i[14:12];
		fp_rs2 = instr_i[24:20];
		fp_known = fp_load || fp_store || fp_fma;
		fp_rm_used = 1'b0;
		decode_pkt_o.fp_op = FPU_OP_ADD;
		if (fp_fma) begin
			fp_rm_used = 1'b1;
			case (instr_i[6:0])
				7'b1000011: decode_pkt_o.fp_op = FPU_OP_FMADD;
				7'b1000111: decode_pkt_o.fp_op = FPU_OP_FMSUB;
				7'b1001011: decode_pkt_o.fp_op = FPU_OP_FNMSUB;
				default:    decode_pkt_o.fp_op = FPU_OP_FNMADD;
			endcase
		end else if (fp_op) begin
			case (fp_funct7)
				7'b0000000: begin fp_known = 1'b1; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_ADD; end
				7'b0000100: begin fp_known = 1'b1; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_SUB; end
				7'b0001000: begin fp_known = 1'b1; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_MUL; end
				7'b0001100: begin fp_known = 1'b1; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_DIV; end
				7'b0101100: begin fp_known = fp_rs2 == 5'd0; fp_rm_used = 1'b1; decode_pkt_o.fp_op = FPU_OP_SQRT; end
				7'b0010000: begin
					fp_known = fp_funct3 <= 3'b010;
					case (fp_funct3)
						3'b000: decode_pkt_o.fp_op = FPU_OP_SGNJ;
						3'b001: decode_pkt_o.fp_op = FPU_OP_SGNJN;
						default: decode_pkt_o.fp_op = FPU_OP_SGNJX;
					endcase
				end
				7'b0010100: begin
					fp_known = fp_funct3 <= 3'b001;
					decode_pkt_o.fp_op = fp_funct3[0] ? FPU_OP_MAX : FPU_OP_MIN;
				end
				7'b1010000: begin
					fp_known = (fp_funct3 == 3'b000) || (fp_funct3 == 3'b001) || (fp_funct3 == 3'b010);
					case (fp_funct3)
						3'b010: decode_pkt_o.fp_op = FPU_OP_EQ;
						3'b001: decode_pkt_o.fp_op = FPU_OP_LT;
						default: decode_pkt_o.fp_op = FPU_OP_LE;
					endcase
				end
				7'b1110000: begin
					fp_known = (fp_rs2 == 5'd0) && ((fp_funct3 == 3'b000) || (fp_funct3 == 3'b001));
					decode_pkt_o.fp_op = fp_funct3[0] ? FPU_OP_CLASS : FPU_OP_MV_X_W;
				end
				7'b1100000: begin
					fp_known = fp_rs2 <= 5'd1; fp_rm_used = 1'b1;
					decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_WU_S : FPU_OP_CVT_W_S;
				end
				7'b1101000: begin
					fp_known = fp_rs2 <= 5'd1; fp_rm_used = 1'b1;
					decode_pkt_o.fp_op = fp_rs2[0] ? FPU_OP_CVT_S_WU : FPU_OP_CVT_S_W;
				end
				7'b1111000: begin fp_known = (fp_rs2 == 5'd0) && (fp_funct3 == 3'b000); decode_pkt_o.fp_op = FPU_OP_MV_W_X; end
				default: fp_known = 1'b0;
			endcase
		end else if (fp_load) begin
			decode_pkt_o.fp_op = FPU_OP_FLW;
		end else if (fp_store) begin
			decode_pkt_o.fp_op = FPU_OP_FSW;
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
		decode_pkt_o.fp_rs1_fpr = fp_fma || (fp_op && (fp_funct7 != 7'b1101000) && (fp_funct7 != 7'b1111000));
		decode_pkt_o.fp_rs2_fpr = fp_fma || fp_store || (fp_op && ((fp_funct7 == 7'b0000000) ||
			(fp_funct7 == 7'b0000100) || (fp_funct7 == 7'b0001000) || (fp_funct7 == 7'b0001100) ||
			(fp_funct7 == 7'b0010000) || (fp_funct7 == 7'b0010100) || (fp_funct7 == 7'b1010000)));
		decode_pkt_o.fp_rs3_fpr = fp_fma;
		decode_pkt_o.fp_rd_gpr = fp_op && ((fp_funct7 == 7'b1010000) || (fp_funct7 == 7'b1110000) || (fp_funct7 == 7'b1100000));
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
    output ydrasil_issue_pkt_t   issue_pkt_o,
    output ydrasil_issue_pkt_t   issue_pkt1_o
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
    wire decode_valid = decode_count_q != '0;
    wire decode_valid1 = decode_count_q > COUNT_WIDTH'(1);
    ydrasil_decode_pkt_t decode_pkt;
    ydrasil_decode_pkt_t decode_pkt1;
    assign decode_pkt = decode_fifo_q[decode_rptr_q];
    assign decode_pkt1 = decode_fifo_q[decode_rptr1];

    wire slot0_simple_int = decode_valid &&
        (decode_pkt.operator_type[OPERATOR_TYPE_ALU] ||
         decode_pkt.operator_type[OPERATOR_TYPE_BITMANIP]) &&
        !decode_pkt.operator_type[OPERATOR_TYPE_BJP] &&
        !decode_pkt.operator_type[OPERATOR_TYPE_LOAD] &&
        !decode_pkt.operator_type[OPERATOR_TYPE_STORE] &&
        !decode_pkt.operator_type[OPERATOR_TYPE_MUL] &&
        !decode_pkt.operator_type[OPERATOR_TYPE_CSR] &&
        !decode_pkt.operator_type[OPERATOR_TYPE_SYS] && !decode_pkt.fence_i;
    wire slot1_light_bitmanip =
        decode_pkt1.operator_type[OPERATOR_TYPE_BITMANIP] &&
        (decode_pkt1.operator_info[OP_B_SH1ADD] |
         decode_pkt1.operator_info[OP_B_SH2ADD] |
         decode_pkt1.operator_info[OP_B_SH3ADD] |
         decode_pkt1.operator_info[OP_B_ANDN]   |
         decode_pkt1.operator_info[OP_B_ORN]    |
         decode_pkt1.operator_info[OP_B_XNOR]   |
         decode_pkt1.operator_info[OP_B_MIN]    |
         decode_pkt1.operator_info[OP_B_MAX]    |
         decode_pkt1.operator_info[OP_B_MINU]   |
         decode_pkt1.operator_info[OP_B_MAXU]   |
         decode_pkt1.operator_info[OP_B_REV8]   |
         decode_pkt1.operator_info[OP_B_SEXT_B] |
         decode_pkt1.operator_info[OP_B_SEXT_H] |
         decode_pkt1.operator_info[OP_B_ZEXT_H]);
    wire slot1_simple_int = decode_valid1 &&
        ((decode_pkt1.operator_type[OPERATOR_TYPE_ALU] &&
          !decode_pkt1.operator_type[OPERATOR_TYPE_BITMANIP]) ||
         slot1_light_bitmanip) &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_BJP] &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_LOAD] &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_STORE] &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_MUL] &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_CSR] &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_SYS] && !decode_pkt1.fence_i;
    wire slot1_memory = decode_valid1 &&
        (decode_pkt1.operator_type[OPERATOR_TYPE_LOAD] ||
         decode_pkt1.operator_type[OPERATOR_TYPE_STORE]) &&
        !decode_pkt1.operator_type[OPERATOR_TYPE_FPU];
    wire slot0_writes = decode_pkt.rd_wen && (decode_pkt.rd_addr != '0);
    wire pair_raw = slot0_writes &&
        ((decode_pkt1.rs1_ren && (decode_pkt1.rs1_addr == decode_pkt.rd_addr)) ||
         ((decode_pkt1.rs2_ren ||
           (decode_pkt1.operator_type[OPERATOR_TYPE_STORE] &&
            !decode_pkt1.operator_type[OPERATOR_TYPE_FPU])) &&
          (decode_pkt1.rs2_addr == decode_pkt.rd_addr)));
    wire pair_waw = slot0_writes && decode_pkt1.rd_wen &&
        (decode_pkt.rd_addr == decode_pkt1.rd_addr);
    wire pair_eligible = slot0_simple_int &&
        (slot1_simple_int || slot1_memory) && !pair_raw && !pair_waw;

    // ID owns the registered decode FIFO and emits a fixed packed dispatch
    // contract.  Issue consumes this packet without reaching back into the
    // decoder's internal state.
    always_comb begin
        issue_pkt_o = '0;
        issue_pkt_o.valid = decode_valid;
        issue_pkt_o.decode = decode_pkt;
        issue_pkt_o.dual_capable = decode_valid &&
            (decode_pkt.operator_type[OPERATOR_TYPE_ALU] ||
             decode_pkt.operator_type[OPERATOR_TYPE_BITMANIP]);
        issue_pkt_o.pair_eligible = pair_eligible;
        issue_pkt_o.memory_op = decode_valid &&
            (decode_pkt.operator_type[OPERATOR_TYPE_LOAD] ||
             decode_pkt.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.ctrl.rs1_addr = decode_pkt.rs1_addr;
        issue_pkt_o.ctrl.valid = decode_valid;
        issue_pkt_o.ctrl.rs2_addr = decode_pkt.rs2_addr;
        issue_pkt_o.ctrl.rd_addr = decode_pkt.rd_addr;
        issue_pkt_o.ctrl.rs1_ren = decode_valid && decode_pkt.rs1_ren;
        issue_pkt_o.ctrl.rs2_ren = decode_valid &&
            (decode_pkt.rs2_ren ||
             (decode_pkt.operator_type[OPERATOR_TYPE_STORE] &&
              !decode_pkt.operator_type[OPERATOR_TYPE_FPU]));
        issue_pkt_o.ctrl.rd_wen = decode_valid && (decode_pkt.rd_addr != '0) &&
            (decode_pkt.rd_wen ||
             (decode_pkt.operator_type[OPERATOR_TYPE_LOAD] &&
              !decode_pkt.operator_type[OPERATOR_TYPE_FPU]));
        issue_pkt_o.ctrl.lsu_req = decode_valid &&
            (decode_pkt.operator_type[OPERATOR_TYPE_LOAD] ||
             decode_pkt.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt_o.ctrl.store_req = decode_valid &&
            decode_pkt.operator_type[OPERATOR_TYPE_STORE];
        issue_pkt_o.ctrl.prev_alu_bypass_ok = decode_valid &&
            ((decode_pkt.operator_type[OPERATOR_TYPE_ALU] &&
              !decode_pkt.operator_type[OPERATOR_TYPE_BITMANIP]) ||
             decode_pkt.operator_type[OPERATOR_TYPE_LOAD] ||
             decode_pkt.operator_type[OPERATOR_TYPE_STORE] ||
             (decode_pkt.operator_type[OPERATOR_TYPE_BJP] &&
              decode_pkt.rs1_ren && decode_pkt.rs2_ren && !decode_pkt.rd_wen));
		issue_pkt_o.ctrl.serialize_before = decode_valid &&
            (decode_pkt.operator_type[OPERATOR_TYPE_CSR] ||
             decode_pkt.operator_type[OPERATOR_TYPE_SYS] || decode_pkt.fence_i);
        issue_pkt_o.ctrl.checkpoint_req = decode_valid &&
            decode_pkt.operator_type[OPERATOR_TYPE_BJP] &&
            !decode_pkt.operator_info[OP_BJP_JUMP];
        issue_pkt1_o = '0;
        issue_pkt1_o.valid = decode_valid1;
        issue_pkt1_o.lane1 = 1'b1;
        issue_pkt1_o.decode = decode_pkt1;
        issue_pkt1_o.dual_capable = decode_valid1 &&
            (decode_pkt1.operator_type[OPERATOR_TYPE_ALU] ||
             decode_pkt1.operator_type[OPERATOR_TYPE_BITMANIP]);
        issue_pkt1_o.memory_op = decode_valid1 &&
            (decode_pkt1.operator_type[OPERATOR_TYPE_LOAD] ||
             decode_pkt1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.ctrl.rs1_addr = decode_pkt1.rs1_addr;
        issue_pkt1_o.ctrl.valid = decode_valid1;
        issue_pkt1_o.ctrl.rs2_addr = decode_pkt1.rs2_addr;
        issue_pkt1_o.ctrl.rd_addr = decode_pkt1.rd_addr;
        issue_pkt1_o.ctrl.rs1_ren = decode_valid1 && decode_pkt1.rs1_ren;
        issue_pkt1_o.ctrl.rs2_ren = decode_valid1 &&
            (decode_pkt1.rs2_ren ||
             (decode_pkt1.operator_type[OPERATOR_TYPE_STORE] &&
              !decode_pkt1.operator_type[OPERATOR_TYPE_FPU]));
        issue_pkt1_o.ctrl.rd_wen = decode_valid1 &&
            (decode_pkt1.rd_addr != '0) &&
            (decode_pkt1.rd_wen ||
             (decode_pkt1.operator_type[OPERATOR_TYPE_LOAD] &&
              !decode_pkt1.operator_type[OPERATOR_TYPE_FPU]));
        issue_pkt1_o.ctrl.lsu_req = decode_valid1 &&
            (decode_pkt1.operator_type[OPERATOR_TYPE_LOAD] ||
             decode_pkt1.operator_type[OPERATOR_TYPE_STORE]);
        issue_pkt1_o.ctrl.store_req = decode_valid1 &&
            decode_pkt1.operator_type[OPERATOR_TYPE_STORE];
    end

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
