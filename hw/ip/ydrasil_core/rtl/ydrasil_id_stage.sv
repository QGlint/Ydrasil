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
    input  wire [BP_GHR_WIDTH-1:0] pred_history_i,
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
		decode_pkt_o.branch_target = pc_i + imm;
		decode_pkt_o.next_pc = pc_i + 32'd4;
        decode_pkt_o.pred_hit = pred_hit_i;
        decode_pkt_o.pred_taken = pred_taken_i;
        decode_pkt_o.pred_target = pred_target_i;
        decode_pkt_o.pred_counter = pred_counter_i;
        decode_pkt_o.pred_bht_index = pred_bht_index_i;
        decode_pkt_o.pred_history = pred_history_i;
        decode_pkt_o.rs1_addr = rs1_addr;
        decode_pkt_o.rs2_addr = rs2_addr;
        decode_pkt_o.rd_addr = rd_addr;
        decode_pkt_o.rs1_ren = rs1_ren;
		// Store data is a true ROB source even though the legacy pipeline
		// tracked it outside the decoder's integer rs2 read-enable.
		decode_pkt_o.rs2_ren = rs2_ren || operator_type[OPERATOR_TYPE_STORE];
		// In the unified ROB this bit describes the architectural destination,
		// including loads whose writeback used to be tracked only by the LSU.
		decode_pkt_o.rd_wen = rd_wen || operator_type[OPERATOR_TYPE_LOAD];
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

module ydrasil_oldest_pair_select
import ydrasil_pkg::*;
(
    input  ydrasil_sched_candidate_pkt_t candidate_i [0:PRODUCER_NUM-1],
    output ydrasil_sched_pair_pkt_t      selected_o
);
    ydrasil_sched_pair_pkt_t level0 [0:PRODUCER_NUM-1];
    ydrasil_sched_pair_pkt_t level1 [0:31];
    ydrasil_sched_pair_pkt_t level2 [0:15];
    ydrasil_sched_pair_pkt_t level3 [0:7];
    ydrasil_sched_pair_pkt_t level4 [0:3];
    ydrasil_sched_pair_pkt_t level5 [0:1];

    function automatic ydrasil_sched_candidate_pkt_t older_candidate(
        input ydrasil_sched_candidate_pkt_t lhs,
        input ydrasil_sched_candidate_pkt_t rhs
    );
        if (!lhs.valid)
            older_candidate = rhs;
        else if (!rhs.valid)
            older_candidate = lhs;
        else if (lhs.age <= rhs.age)
            older_candidate = lhs;
        else
            older_candidate = rhs;
    endfunction

    function automatic ydrasil_sched_pair_pkt_t merge_pair(
        input ydrasil_sched_pair_pkt_t lhs,
        input ydrasil_sched_pair_pkt_t rhs
    );
        ydrasil_sched_candidate_pkt_t first;
        begin
            merge_pair = '0;
            first = older_candidate(lhs.first, rhs.first);
            merge_pair.first = first;
            if (first.valid && lhs.first.valid &&
                first.tag == lhs.first.tag)
                merge_pair.second = older_candidate(lhs.second, rhs.first);
            else
                merge_pair.second = older_candidate(rhs.second, lhs.first);
        end
    endfunction

    genvar leaf;
    generate
        for (leaf = 0; leaf < PRODUCER_NUM; leaf = leaf + 1) begin : gen_leaf
            always_comb begin
                level0[leaf] = '0;
                level0[leaf].first = candidate_i[leaf];
            end
        end
        for (leaf = 0; leaf < 32; leaf = leaf + 1) begin : gen_level1
            always_comb level1[leaf] = merge_pair(level0[leaf*2], level0[leaf*2+1]);
        end
        for (leaf = 0; leaf < 16; leaf = leaf + 1) begin : gen_level2
            always_comb level2[leaf] = merge_pair(level1[leaf*2], level1[leaf*2+1]);
        end
        for (leaf = 0; leaf < 8; leaf = leaf + 1) begin : gen_level3
            always_comb level3[leaf] = merge_pair(level2[leaf*2], level2[leaf*2+1]);
        end
        for (leaf = 0; leaf < 4; leaf = leaf + 1) begin : gen_level4
            always_comb level4[leaf] = merge_pair(level3[leaf*2], level3[leaf*2+1]);
        end
        for (leaf = 0; leaf < 2; leaf = leaf + 1) begin : gen_level5
            always_comb level5[leaf] = merge_pair(level4[leaf*2], level4[leaf*2+1]);
        end
    endgenerate

    always_comb selected_o = merge_pair(level5[0], level5[1]);
endmodule

module ydrasil_id_stage
import ydrasil_pkg::*;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_redirect_pkt_t redirect_pkt_i,
    input  ydrasil_trap_ctrl_pkt_t trap_ctrl_i,
    input  wire                  issue_ready_i,
    input  wire                  lsu_ready_i,
    input  wire                  serial_ready_i,
    input  ydrasil_completion_bus_t completion_bus_i,
    input  ydrasil_gpr_fwd_pkt_t load_wakeup_i,
    input  wire [31:0]           if_id_pc_i,
    input  wire [31:0]           if_id_instr_i,
    input  wire                  if_id_pred_hit_i,
    input  wire                  if_id_pred_taken_i,
    input  wire [31:0]           if_id_pred_target_i,
    input  wire [1:0]            if_id_pred_counter_i,
    input  wire [31:0]           if_id_pred_bht_index_i,
    input  wire [BP_GHR_WIDTH-1:0] if_id_pred_history_i,
    input  wire                  if_id_valid_i,
    input  wire [31:0]           if_id1_pc_i,
    input  wire [31:0]           if_id1_instr_i,
    input  wire                  if_id1_pred_hit_i,
    input  wire                  if_id1_pred_taken_i,
    input  wire [31:0]           if_id1_pred_target_i,
    input  wire [1:0]            if_id1_pred_counter_i,
    input  wire [31:0]           if_id1_pred_bht_index_i,
    input  wire [BP_GHR_WIDTH-1:0] if_id1_pred_history_i,
    input  wire                  if_id1_valid_i,
    input  wire [REGS_DATA_WIDTH-1:0] rf_rdata_rs1_i,
    input  wire [REGS_DATA_WIDTH-1:0] rf_rdata_rs2_i,
    input  wire [REGS_DATA_WIDTH-1:0] rf_rdata_rs3_i,
    input  wire [REGS_DATA_WIDTH-1:0] rf_rdata_rs4_i,
    output wire                  if_id_ready_o,
    output wire                  if_id_consume_two_o,
    output wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs1_o,
    output wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs2_o,
    output wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs3_o,
    output wire [REGS_ADDR_WIDTH-1:0] rf_addr_rs4_o,
    output ydrasil_issue_pkt_t   issue_pkt_o,
    output ydrasil_issue_pkt_t   issue_pkt1_o,
    output ydrasil_retire_bus_t  retire_bus_o,
    output ydrasil_gpr_commit_bus_t gpr_commit_bus_o,
    output ydrasil_rob_status_pkt_t status_o
);
    localparam int ROB_DEPTH = PRODUCER_NUM;
    localparam int COUNT_WIDTH = $clog2(ROB_DEPTH + 1);

    ydrasil_decode_pkt_t decoded0;
    ydrasil_decode_pkt_t decoded1;

    reg [ROB_DEPTH-1:0] rob_valid_q;
    reg [ROB_DEPTH-1:0] rob_issued_q;
    reg [ROB_DEPTH-1:0] rob_done_q;
	reg [ROB_DEPTH-1:0] rob_main_launch_q;
	reg [ROB_DEPTH-1:0] rob_dual_launch_q;
	reg [ROB_DEPTH-1:0] rob_load_ready_q;
    rob_tag_t rob_tag_q [0:ROB_DEPTH-1];
    ydrasil_decode_pkt_t rob_decode_q [0:ROB_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] rob_result_q [0:ROB_DEPTH-1];
    reg [ROB_DEPTH-1:0] rob_rs1_ready_q;
    reg [ROB_DEPTH-1:0] rob_rs2_ready_q;
    rob_tag_t rob_rs1_tag_q [0:ROB_DEPTH-1];
    rob_tag_t rob_rs2_tag_q [0:ROB_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] rob_rs1_value_q [0:ROB_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] rob_rs2_value_q [0:ROB_DEPTH-1];

    reg [REGS_NUM-1:0] rat_valid_q;
    rob_tag_t rat_tag_q [0:REGS_NUM-1];
    ydrasil_retire_bus_t retire_bus_q;
    ydrasil_retire_bus_t retire_bus;
    ydrasil_gpr_commit_bus_t gpr_commit_bus_q;
    ydrasil_gpr_commit_bus_t gpr_commit_bus;
    ydrasil_completion_bus_t completion_bus_q;
    reg lsu_ready_q;
    reg serial_ready_q;
    rob_tag_t head_tag_q;
    rob_tag_t tail_tag_q;
    reg [COUNT_WIDTH-1:0] rob_count_q;

    integer completion_pipe_lane;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsu_ready_q <= 1'b0;
            serial_ready_q <= 1'b0;
            for (completion_pipe_lane = 0;
                 completion_pipe_lane < COMPLETION_LANES;
                 completion_pipe_lane = completion_pipe_lane + 1)
                completion_bus_q[completion_pipe_lane] <= '0;
        end else begin
            lsu_ready_q <= lsu_ready_i;
            serial_ready_q <= serial_ready_i;
            for (completion_pipe_lane = 0;
                 completion_pipe_lane < COMPLETION_LANES;
                 completion_pipe_lane = completion_pipe_lane + 1)
                completion_bus_q[completion_pipe_lane] <=
                    completion_bus_i[completion_pipe_lane];
        end
    end

    ydrasil_decode_slot u_decode0 (
        .pc_i(if_id_pc_i), .instr_i(if_id_instr_i),
        .pred_hit_i(if_id_pred_hit_i), .pred_taken_i(if_id_pred_taken_i),
        .pred_target_i(if_id_pred_target_i), .pred_counter_i(if_id_pred_counter_i),
        .pred_bht_index_i(if_id_pred_bht_index_i),
        .pred_history_i(if_id_pred_history_i), .decode_pkt_o(decoded0)
    );
    ydrasil_decode_slot u_decode1 (
        .pc_i(if_id1_pc_i), .instr_i(if_id1_instr_i),
        .pred_hit_i(if_id1_pred_hit_i), .pred_taken_i(if_id1_pred_taken_i),
        .pred_target_i(if_id1_pred_target_i), .pred_counter_i(if_id1_pred_counter_i),
        .pred_bht_index_i(if_id1_pred_bht_index_i),
        .pred_history_i(if_id1_pred_history_i), .decode_pkt_o(decoded1)
    );

    function automatic logic is_simple_int(input ydrasil_decode_pkt_t pkt);
        is_simple_int =
            (pkt.operator_type[OPERATOR_TYPE_ALU] ||
             pkt.operator_type[OPERATOR_TYPE_BITMANIP]) &&
            !pkt.operator_type[OPERATOR_TYPE_BJP] &&
            !pkt.operator_type[OPERATOR_TYPE_LOAD] &&
            !pkt.operator_type[OPERATOR_TYPE_STORE] &&
            !pkt.operator_type[OPERATOR_TYPE_MUL] &&
            !pkt.operator_type[OPERATOR_TYPE_CSR] &&
            !pkt.operator_type[OPERATOR_TYPE_SYS] &&
            !pkt.operator_type[OPERATOR_TYPE_FPU] && !pkt.fence_i;
    endfunction

	function automatic logic is_bypassable_alu(input ydrasil_decode_pkt_t pkt);
		is_bypassable_alu = pkt.rd_wen && (pkt.rd_addr != '0) &&
			is_simple_int(pkt);
	endfunction

	function automatic logic early_dual_ready(input rob_tag_t tag);
		producer_slot_t slot;
		begin
			slot = tag[PRODUCER_SLOT_WIDTH-1:0];
			early_dual_ready = rob_dual_launch_q[slot] &&
				rob_valid_q[slot] && rob_tag_q[slot] == tag &&
				is_simple_int(rob_decode_q[slot]);
		end
	endfunction

	function automatic logic early_load_ready(input rob_tag_t tag);
		producer_slot_t slot;
		logic [REGS_DATA_WIDTH-1:0] load_addr;
		begin
			slot = tag[PRODUCER_SLOT_WIDTH-1:0];
			load_addr = rob_rs1_value_q[slot] + rob_decode_q[slot].imm;
			early_load_ready = rob_load_ready_q[slot] &&
				rob_valid_q[slot] && rob_tag_q[slot] == tag &&
				rob_rs1_ready_q[slot] &&
				rob_decode_q[slot].operator_type[OPERATOR_TYPE_LOAD] &&
				(load_addr[31:DTCM_ADDR_WIDTH+2] ==
				 DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2]);
		end
	endfunction

    function automatic logic is_mul_div(input ydrasil_decode_pkt_t pkt);
        is_mul_div = pkt.operator_type[OPERATOR_TYPE_MUL];
    endfunction

    function automatic logic is_branch(input ydrasil_decode_pkt_t pkt);
        is_branch = pkt.operator_type[OPERATOR_TYPE_BJP];
    endfunction

    function automatic logic is_cond_branch(input ydrasil_decode_pkt_t pkt);
        is_cond_branch = pkt.operator_type[OPERATOR_TYPE_BJP] &&
            !pkt.operator_info[OP_BJP_JUMP];
    endfunction

    function automatic logic is_order_barrier(input ydrasil_decode_pkt_t pkt);
        is_order_barrier = pkt.operator_type[OPERATOR_TYPE_BJP] ||
            pkt.operator_type[OPERATOR_TYPE_STORE] ||
            pkt.operator_type[OPERATOR_TYPE_CSR] ||
            pkt.operator_type[OPERATOR_TYPE_SYS] ||
            pkt.operator_type[OPERATOR_TYPE_FPU] || pkt.fence_i;
    endfunction

    function automatic logic needs_serial_backend(input ydrasil_decode_pkt_t pkt);
        // The LSU owns an ordered request FIFO, including stores whose data is
        // still waiting on a ROB tag.  Only architecturally serial backends
        // need the whole memory system to be idle before issue.
        needs_serial_backend = pkt.operator_type[OPERATOR_TYPE_CSR] ||
            pkt.operator_type[OPERATOR_TYPE_SYS] ||
            pkt.operator_type[OPERATOR_TYPE_FPU] || pkt.fence_i;
    endfunction

    function automatic logic is_memory(input ydrasil_decode_pkt_t pkt);
        is_memory = pkt.operator_type[OPERATOR_TYPE_LOAD] ||
            pkt.operator_type[OPERATOR_TYPE_STORE];
    endfunction

    function automatic logic is_strict_control_barrier(input ydrasil_decode_pkt_t pkt);
        is_strict_control_barrier = pkt.operator_type[OPERATOR_TYPE_BJP] ||
            pkt.operator_type[OPERATOR_TYPE_CSR] ||
            pkt.operator_type[OPERATOR_TYPE_SYS] ||
            pkt.operator_type[OPERATOR_TYPE_FPU] || pkt.fence_i;
    endfunction

    wire producer_slot_t head_slot = head_tag_q[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t head1_slot = head_slot + producer_slot_t'(1);
    wire producer_slot_t head2_slot = head_slot + producer_slot_t'(2);
    wire producer_slot_t head3_slot = head_slot + producer_slot_t'(3);
    wire rob_tag_t redirect_age = redirect_pkt_i.rob_tag - head_tag_q;
    wire [COUNT_WIDTH-1:0] redirect_keep_count =
        COUNT_WIDTH'(redirect_age) + COUNT_WIDTH'(1);
    wire head_valid = rob_valid_q[head_slot] && rob_tag_q[head_slot] == head_tag_q;
    wire head1_valid = rob_count_q > COUNT_WIDTH'(1) && rob_valid_q[head1_slot] &&
        rob_tag_q[head1_slot] == (head_tag_q + rob_tag_t'(1));
    wire head2_valid = rob_count_q > COUNT_WIDTH'(2) && rob_valid_q[head2_slot] &&
        rob_tag_q[head2_slot] == (head_tag_q + rob_tag_t'(2));
    wire head3_valid = rob_count_q > COUNT_WIDTH'(3) && rob_valid_q[head3_slot] &&
        rob_tag_q[head3_slot] == (head_tag_q + rob_tag_t'(3));
    wire rob_tag_t youngest_tag = tail_tag_q - rob_tag_t'(1);
    wire producer_slot_t youngest_slot =
        youngest_tag[PRODUCER_SLOT_WIDTH-1:0];

    // Completion tags are unique while live. Decode the four execution lanes
    // once at the ROB boundary, then let completion and source wakeup use a
    // direct slot lookup plus the generation-bit check.
    ydrasil_gpr_fwd_pkt_t completion_slot_pkt [0:ROB_DEPTH-1];
    integer completion_slot;
    integer completion_lane;
    always_comb begin
        for (completion_slot = 0; completion_slot < ROB_DEPTH;
             completion_slot = completion_slot + 1) begin
            completion_slot_pkt[completion_slot] = '0;
            // The registered copy guarantees that a pulse remains visible
            // across the scheduler boundary.
            for (completion_lane = 0; completion_lane < COMPLETION_LANES;
                 completion_lane = completion_lane + 1) begin
                if (completion_bus_q[completion_lane].valid &&
                    completion_bus_q[completion_lane].producer_tracked &&
                    completion_bus_q[completion_lane].producer_id[
                        PRODUCER_SLOT_WIDTH-1:0] == producer_slot_t'(completion_slot))
                    completion_slot_pkt[completion_slot] = completion_bus_q[completion_lane];
            end
        end
    end

    function automatic logic completion_hit(input rob_tag_t tag);
        producer_slot_t slot;
        begin
            slot = tag[PRODUCER_SLOT_WIDTH-1:0];
            completion_hit = completion_slot_pkt[slot].valid &&
                completion_slot_pkt[slot].producer_tracked &&
                completion_slot_pkt[slot].producer_id == tag;
        end
    endfunction

    function automatic logic [REGS_DATA_WIDTH-1:0] completion_value(input rob_tag_t tag);
        completion_value = completion_slot_pkt[
            tag[PRODUCER_SLOT_WIDTH-1:0]].data;
    endfunction

    function automatic logic completion_now_hit(input rob_tag_t tag);
        integer lane;
        begin
            completion_now_hit = 1'b0;
            for (lane = 0; lane < COMPLETION_LANES; lane = lane + 1)
                if (completion_bus_i[lane].valid &&
                    completion_bus_i[lane].producer_tracked &&
                    completion_bus_i[lane].producer_id == tag)
                    completion_now_hit = 1'b1;
        end
    endfunction

    function automatic logic [REGS_DATA_WIDTH-1:0] completion_now_value(
        input rob_tag_t tag
    );
        integer lane;
        begin
            completion_now_value = '0;
            for (lane = 0; lane < COMPLETION_LANES; lane = lane + 1)
                if (completion_bus_i[lane].valid &&
                    completion_bus_i[lane].producer_tracked &&
                    completion_bus_i[lane].producer_id == tag)
                    completion_now_value = completion_bus_i[lane].data;
        end
    endfunction

	function automatic logic early_alu_ready(input rob_tag_t tag);
		producer_slot_t slot;
		begin
			slot = tag[PRODUCER_SLOT_WIDTH-1:0];
			early_alu_ready = rob_main_launch_q[slot] &&
				rob_valid_q[slot] && rob_tag_q[slot] == tag &&
				is_bypassable_alu(rob_decode_q[slot]);
		end
	endfunction

    integer status_slot;
    logic execution_pending;
    always_comb begin
        execution_pending = 1'b0;
        for (status_slot = 0; status_slot < ROB_DEPTH;
             status_slot = status_slot + 1) begin
            if (rob_valid_q[status_slot] && rob_issued_q[status_slot] &&
                !rob_done_q[status_slot] &&
				!completion_hit(rob_tag_q[status_slot]) &&
                !rob_decode_q[status_slot].operator_type[OPERATOR_TYPE_SYS] &&
                !rob_decode_q[status_slot].fp_illegal)
                execution_pending = 1'b1;
        end

        status_o = '0;
        status_o.empty = (rob_count_q == '0);
        status_o.full = (rob_count_q == COUNT_WIDTH'(ROB_DEPTH));
        status_o.execution_idle = !execution_pending;
        status_o.count = rob_count_q;
        status_o.resume_pc = if_id_pc_i;
        if (rob_count_q != '0)
            status_o.resume_pc =
                rob_decode_q[youngest_slot].pred_taken ?
                rob_decode_q[youngest_slot].pred_target :
                (rob_decode_q[youngest_slot].pc + 32'd4);
    end

    function automatic ydrasil_commit_pkt_t make_retire_pkt(input rob_tag_t tag);
        producer_slot_t slot;
        begin
            slot = tag[PRODUCER_SLOT_WIDTH-1:0];
            make_retire_pkt = '0;
            make_retire_pkt.valid = 1'b1;
            make_retire_pkt.rob_tag = tag;
            make_retire_pkt.writes_gpr = rob_decode_q[slot].rd_wen &&
                rob_decode_q[slot].rd_addr != '0;
            make_retire_pkt.rd_addr = rob_decode_q[slot].rd_addr;
            make_retire_pkt.value = completion_now_hit(tag) ?
                completion_now_value(tag) : completion_hit(tag) ?
                completion_value(tag) : rob_result_q[slot];
            make_retire_pkt.pc = rob_decode_q[slot].pc;
            make_retire_pkt.instr = rob_decode_q[slot].instr;
        end
    endfunction

    function automatic logic retire_ready(input rob_tag_t tag);
        producer_slot_t slot;
        begin
            slot = tag[PRODUCER_SLOT_WIDTH-1:0];
            retire_ready = rob_done_q[slot] || completion_hit(tag) ||
                completion_now_hit(tag);
        end
    endfunction

    wire head0_writes_gpr = rob_decode_q[head_slot].rd_wen &&
        rob_decode_q[head_slot].rd_addr != '0;
    wire head1_writes_gpr = rob_decode_q[head1_slot].rd_wen &&
        rob_decode_q[head1_slot].rd_addr != '0;
    wire head2_writes_gpr = rob_decode_q[head2_slot].rd_wen &&
        rob_decode_q[head2_slot].rd_addr != '0;
    wire head3_writes_gpr = rob_decode_q[head3_slot].rd_wen &&
        rob_decode_q[head3_slot].rd_addr != '0;
    wire [2:0] head012_gpr_count = {2'b0, head0_writes_gpr} +
        {2'b0, head1_writes_gpr} + {2'b0, head2_writes_gpr};
    wire [2:0] head0123_gpr_count = head012_gpr_count +
        {2'b0, head3_writes_gpr};
    wire retire0_valid = !redirect_pkt_i.valid && !trap_ctrl_i.redirect &&
        head_valid && retire_ready(head_tag_q);
    wire retire1_valid = retire0_valid && head1_valid &&
        retire_ready(head_tag_q + rob_tag_t'(1));
    wire retire2_valid = retire1_valid && head2_valid &&
        retire_ready(head_tag_q + rob_tag_t'(2)) &&
        (head012_gpr_count <= 3'd2);
    wire retire3_valid = retire2_valid && head3_valid &&
        retire_ready(head_tag_q + rob_tag_t'(3)) &&
        (head0123_gpr_count <= 3'd2);

    always_comb begin
        retire_bus_o = retire_bus_q;
        gpr_commit_bus_o = gpr_commit_bus_q;
        retire_bus = '0;
        gpr_commit_bus = '0;

        if (retire0_valid)
            retire_bus.slot0 = make_retire_pkt(head_tag_q);
        if (retire1_valid)
            retire_bus.slot1 = make_retire_pkt(head_tag_q + rob_tag_t'(1));
        if (retire2_valid)
            retire_bus.slot2 = make_retire_pkt(head_tag_q + rob_tag_t'(2));
        if (retire3_valid)
            retire_bus.slot3 = make_retire_pkt(head_tag_q + rob_tag_t'(3));

        if (retire_bus.slot0.valid && retire_bus.slot0.writes_gpr)
            gpr_commit_bus.slot0 = retire_bus.slot0;
        if (retire_bus.slot1.valid && retire_bus.slot1.writes_gpr) begin
            if (!gpr_commit_bus.slot0.valid)
                gpr_commit_bus.slot0 = retire_bus.slot1;
            else
                gpr_commit_bus.slot1 = retire_bus.slot1;
        end
        if (retire_bus.slot2.valid && retire_bus.slot2.writes_gpr) begin
            if (!gpr_commit_bus.slot0.valid)
                gpr_commit_bus.slot0 = retire_bus.slot2;
            else
                gpr_commit_bus.slot1 = retire_bus.slot2;
        end
        if (retire_bus.slot3.valid && retire_bus.slot3.writes_gpr) begin
            if (!gpr_commit_bus.slot0.valid)
                gpr_commit_bus.slot0 = retire_bus.slot3;
            else
                gpr_commit_bus.slot1 = retire_bus.slot3;
        end
    end

    wire [2:0] retire_count = retire_bus.slot3.valid ? 3'd4 :
        retire_bus.slot2.valid ? 3'd3 : retire_bus.slot1.valid ? 3'd2 :
        (retire_bus.slot0.valid ? 3'd1 : 3'd0);

    function automatic logic [REGS_DATA_WIDTH-1:0] committed_value(
        input logic [REGS_ADDR_WIDTH-1:0] addr,
        input logic [REGS_DATA_WIDTH-1:0] rf_value
    );
        begin
            committed_value = rf_value;
            if (gpr_commit_bus_q.slot0.valid &&
                gpr_commit_bus_q.slot0.rd_addr == addr)
                committed_value = gpr_commit_bus_q.slot0.value;
            if (gpr_commit_bus_q.slot1.valid &&
                gpr_commit_bus_q.slot1.rd_addr == addr)
                committed_value = gpr_commit_bus_q.slot1.value;
        end
    endfunction

    wire [COUNT_WIDTH:0] count_after_commit =
        {1'b0, rob_count_q} - (COUNT_WIDTH + 1)'(retire_count);
    wire has_room_one = count_after_commit < (COUNT_WIDTH + 1)'(ROB_DEPTH);
    wire has_room_two = count_after_commit <= (COUNT_WIDTH + 1)'(ROB_DEPTH - 2);
    wire push0 = if_id_valid_i && has_room_one && !trap_ctrl_i.stall;
    wire push1 = push0 && if_id1_valid_i && has_room_two;
    wire [1:0] push_count = push1 ? 2'd2 : (push0 ? 2'd1 : 2'd0);

    integer select_slot;
    logic [ROB_DEPTH-1:0] slot_live;
    logic [ROB_DEPTH-1:0] slot_rs1_ready;
    logic [ROB_DEPTH-1:0] slot_rs2_ready;
	logic [ROB_DEPTH-1:0] slot_rs1_completion;
	logic [ROB_DEPTH-1:0] slot_rs2_completion;
	logic [ROB_DEPTH-1:0] slot_rs1_early_alu;
	logic [ROB_DEPTH-1:0] slot_rs2_early_alu;
	logic [ROB_DEPTH-1:0] slot_rs1_early_dual;
	logic [ROB_DEPTH-1:0] slot_rs2_early_dual;
	logic [ROB_DEPTH-1:0] slot_rs1_early_load;
	logic [ROB_DEPTH-1:0] slot_rs2_early_load;
    logic [ROB_DEPTH-1:0] slot_mem_is_dtcm;
    logic [ROB_DEPTH-1:0] slot_sources_ready;
    logic [ROB_DEPTH-1:0] slot_resource_ready;
    logic [COUNT_WIDTH-1:0] slot_age [0:ROB_DEPTH-1];
    logic [REGS_DATA_WIDTH-1:0] slot_rs1_value [0:ROB_DEPTH-1];
    logic [REGS_DATA_WIDTH-1:0] slot_rs2_value [0:ROB_DEPTH-1];
    logic [BUS_ADDR_WIDTH-1:0] slot_mem_addr [0:ROB_DEPTH-1];

    always_comb begin
        slot_live = '0;
        slot_rs1_ready = '0;
        slot_rs2_ready = '0;
		slot_rs1_completion = '0;
		slot_rs2_completion = '0;
		slot_rs1_early_alu = '0;
		slot_rs2_early_alu = '0;
		slot_rs1_early_dual = '0;
		slot_rs2_early_dual = '0;
		slot_rs1_early_load = '0;
		slot_rs2_early_load = '0;
        slot_mem_is_dtcm = '0;
        slot_sources_ready = '0;
        slot_resource_ready = '0;

        // Compute every physical slot independently. Age tags recover ROB
        // order without rotating the wide entry arrays through head_slot.
        for (select_slot = 0; select_slot < ROB_DEPTH;
             select_slot = select_slot + 1) begin
            slot_age[select_slot] = COUNT_WIDTH'(
                rob_tag_q[select_slot] - head_tag_q);
            slot_live[select_slot] = rob_valid_q[select_slot] &&
                (slot_age[select_slot] < rob_count_q);
            // Long-latency completion packets update the ROB at the clock
            // boundary. A main-lane single-cycle ALU launched last cycle is
            // predicted ready from registered issue state and consumed through
            // the EX bypass, keeping dependent ALU chains at one per cycle.
			slot_rs1_early_alu[select_slot] =
				!rob_rs1_ready_q[select_slot] &&
				early_alu_ready(rob_rs1_tag_q[select_slot]);
			slot_rs2_early_alu[select_slot] =
				!rob_rs2_ready_q[select_slot] &&
				early_alu_ready(rob_rs2_tag_q[select_slot]);
			slot_rs1_early_dual[select_slot] =
				!rob_rs1_ready_q[select_slot] &&
				early_dual_ready(rob_rs1_tag_q[select_slot]);
			slot_rs2_early_dual[select_slot] =
				!rob_rs2_ready_q[select_slot] &&
				early_dual_ready(rob_rs2_tag_q[select_slot]);
			slot_rs1_early_load[select_slot] =
				!rob_rs1_ready_q[select_slot] &&
				early_load_ready(rob_rs1_tag_q[select_slot]);
			slot_rs2_early_load[select_slot] =
				!rob_rs2_ready_q[select_slot] &&
				early_load_ready(rob_rs2_tag_q[select_slot]);
				slot_rs1_completion[select_slot] =
					!rob_rs1_ready_q[select_slot] &&
					completion_hit(rob_rs1_tag_q[select_slot]);
				slot_rs2_completion[select_slot] =
					!rob_rs2_ready_q[select_slot] &&
					completion_hit(rob_rs2_tag_q[select_slot]);
				slot_rs1_ready[select_slot] = rob_rs1_ready_q[select_slot] ||
					slot_rs1_completion[select_slot] ||
					slot_rs1_early_alu[select_slot] ||
				slot_rs1_early_dual[select_slot] ||
				slot_rs1_early_load[select_slot];
				slot_rs2_ready[select_slot] = rob_rs2_ready_q[select_slot] ||
					slot_rs2_completion[select_slot] ||
				slot_rs2_early_alu[select_slot] ||
				slot_rs2_early_dual[select_slot] ||
				slot_rs2_early_load[select_slot];
            slot_rs1_value[select_slot] = slot_rs1_completion[select_slot] ?
				completion_value(rob_rs1_tag_q[select_slot]) :
				rob_rs1_value_q[select_slot];
            slot_rs2_value[select_slot] = slot_rs2_completion[select_slot] ?
				completion_value(rob_rs2_tag_q[select_slot]) :
				rob_rs2_value_q[select_slot];
            slot_mem_addr[select_slot] = rob_rs1_value_q[select_slot] +
                rob_decode_q[select_slot].imm;
            slot_mem_is_dtcm[select_slot] =
                slot_mem_addr[select_slot][31:DTCM_ADDR_WIDTH+2] ==
                DTCM_BASE_ADDR[31:DTCM_ADDR_WIDTH+2];
            slot_sources_ready[select_slot] = slot_rs1_ready[select_slot] &&
                (slot_rs2_ready[select_slot] ||
                 rob_decode_q[select_slot].operator_type[OPERATOR_TYPE_STORE]);
            slot_resource_ready[select_slot] =
                (!is_memory(rob_decode_q[select_slot]) || lsu_ready_q) &&
                (!needs_serial_backend(rob_decode_q[select_slot]) ||
                 serial_ready_q);
        end
    end

    ydrasil_sched_candidate_pkt_t tree_memory_candidate [0:ROB_DEPTH-1];
    ydrasil_sched_candidate_pkt_t tree_branch_candidate [0:ROB_DEPTH-1];
    ydrasil_sched_candidate_pkt_t tree_exception_candidate [0:ROB_DEPTH-1];
    ydrasil_sched_candidate_pkt_t tree_main_candidate [0:ROB_DEPTH-1];
    ydrasil_sched_candidate_pkt_t tree_simple_candidate [0:ROB_DEPTH-1];
    ydrasil_sched_pair_pkt_t tree_memory_selected;
    ydrasil_sched_pair_pkt_t tree_branch_selected;
    ydrasil_sched_pair_pkt_t tree_exception_selected;
    ydrasil_sched_pair_pkt_t tree_main_selected;
    ydrasil_sched_pair_pkt_t tree_simple_selected;
    logic [ROB_DEPTH-1:0] tree_main_eligible;
    logic [ROB_DEPTH-1:0] tree_simple_eligible;
    logic tree_schedule0_valid;
    logic tree_schedule1_valid;
    rob_tag_t tree_schedule0_tag;
    rob_tag_t tree_schedule1_tag;
    integer tree_slot;

    ydrasil_oldest_pair_select u_memory_oldest (
        .candidate_i(tree_memory_candidate), .selected_o(tree_memory_selected)
    );
    ydrasil_oldest_pair_select u_branch_oldest (
        .candidate_i(tree_branch_candidate), .selected_o(tree_branch_selected)
    );
    ydrasil_oldest_pair_select u_exception_oldest (
        .candidate_i(tree_exception_candidate), .selected_o(tree_exception_selected)
    );
    ydrasil_oldest_pair_select u_main_oldest (
        .candidate_i(tree_main_candidate), .selected_o(tree_main_selected)
    );
    ydrasil_oldest_pair_select u_simple_oldest (
        .candidate_i(tree_simple_candidate), .selected_o(tree_simple_selected)
    );

    always_comb begin
        for (tree_slot = 0; tree_slot < ROB_DEPTH; tree_slot = tree_slot + 1) begin
            tree_memory_candidate[tree_slot] = '0;
            tree_memory_candidate[tree_slot].valid = slot_live[tree_slot] &&
                !rob_issued_q[tree_slot] && is_memory(rob_decode_q[tree_slot]);
            tree_memory_candidate[tree_slot].age = rob_tag_t'(slot_age[tree_slot]);
            tree_memory_candidate[tree_slot].tag = rob_tag_q[tree_slot];

            tree_branch_candidate[tree_slot] = '0;
            tree_branch_candidate[tree_slot].valid = slot_live[tree_slot] &&
                !rob_done_q[tree_slot] && !completion_hit(rob_tag_q[tree_slot]) &&
                is_branch(rob_decode_q[tree_slot]);
            tree_branch_candidate[tree_slot].age = rob_tag_t'(slot_age[tree_slot]);
            tree_branch_candidate[tree_slot].tag = rob_tag_q[tree_slot];

            tree_exception_candidate[tree_slot] = '0;
            tree_exception_candidate[tree_slot].valid = slot_live[tree_slot] &&
                !rob_done_q[tree_slot] && !completion_hit(rob_tag_q[tree_slot]) &&
                (rob_decode_q[tree_slot].operator_type[OPERATOR_TYPE_CSR] ||
                 rob_decode_q[tree_slot].operator_type[OPERATOR_TYPE_SYS] ||
                 rob_decode_q[tree_slot].operator_type[OPERATOR_TYPE_FPU] ||
                 rob_decode_q[tree_slot].fence_i);
            tree_exception_candidate[tree_slot].age = rob_tag_t'(slot_age[tree_slot]);
            tree_exception_candidate[tree_slot].tag = rob_tag_q[tree_slot];
        end
    end

    always_comb begin
        tree_main_eligible = '0;
        tree_simple_eligible = '0;
        tree_schedule0_valid = 1'b0;
        tree_schedule1_valid = 1'b0;
        tree_schedule0_tag = '0;
        tree_schedule1_tag = '0;
        for (tree_slot = 0; tree_slot < ROB_DEPTH; tree_slot = tree_slot + 1) begin
            tree_main_candidate[tree_slot] = '0;
            tree_simple_candidate[tree_slot] = '0;

            tree_simple_eligible[tree_slot] = slot_live[tree_slot] &&
                !rob_issued_q[tree_slot] && slot_rs1_ready[tree_slot] &&
                slot_rs2_ready[tree_slot] && is_simple_int(rob_decode_q[tree_slot]) &&
                !(tree_exception_selected.first.valid &&
                  tree_exception_selected.first.age < rob_tag_t'(slot_age[tree_slot]));

            tree_main_eligible[tree_slot] = slot_live[tree_slot] &&
                !rob_issued_q[tree_slot] && slot_resource_ready[tree_slot] &&
                !(tree_exception_selected.first.valid &&
                  tree_exception_selected.first.age < rob_tag_t'(slot_age[tree_slot])) &&
                (((slot_rs1_early_load[tree_slot] || slot_rs2_early_load[tree_slot]) &&
                  is_simple_int(rob_decode_q[tree_slot]) &&
                  slot_rs1_ready[tree_slot] && slot_rs2_ready[tree_slot]) ||
                 (is_mul_div(rob_decode_q[tree_slot]) &&
                  slot_sources_ready[tree_slot]) ||
                 (is_branch(rob_decode_q[tree_slot]) &&
                  slot_sources_ready[tree_slot]) ||
                 (is_memory(rob_decode_q[tree_slot]) &&
                  tree_memory_selected.first.valid &&
                  tree_memory_selected.first.tag == rob_tag_q[tree_slot] &&
                  (!(tree_branch_selected.first.valid &&
                     tree_branch_selected.first.age < rob_tag_t'(slot_age[tree_slot])) ||
                   (rob_decode_q[tree_slot].operator_type[OPERATOR_TYPE_LOAD] &&
                    rob_rs1_ready_q[tree_slot] && slot_mem_is_dtcm[tree_slot]))) ||
                 (rob_decode_q[tree_slot].operator_type[OPERATOR_TYPE_CSR] &&
                  slot_age[tree_slot] == '0 && slot_sources_ready[tree_slot]) ||
                 ((slot_age[tree_slot] == '0) &&
                  slot_sources_ready[tree_slot] &&
                  !is_simple_int(rob_decode_q[tree_slot])));

            tree_main_candidate[tree_slot].valid = tree_main_eligible[tree_slot];
            tree_main_candidate[tree_slot].age = rob_tag_t'(slot_age[tree_slot]);
            tree_main_candidate[tree_slot].tag = rob_tag_q[tree_slot];
            tree_simple_candidate[tree_slot].valid = tree_simple_eligible[tree_slot];
            tree_simple_candidate[tree_slot].age = rob_tag_t'(slot_age[tree_slot]);
            tree_simple_candidate[tree_slot].tag = rob_tag_q[tree_slot];
        end

        if (tree_main_selected.first.valid) begin
            tree_schedule0_valid = 1'b1;
            tree_schedule0_tag = tree_main_selected.first.tag;
            if (tree_simple_selected.first.valid) begin
                if (tree_simple_selected.first.tag != tree_schedule0_tag) begin
                    tree_schedule1_valid = 1'b1;
                    tree_schedule1_tag = tree_simple_selected.first.tag;
                end else if (tree_simple_selected.second.valid) begin
                    tree_schedule1_valid = 1'b1;
                    tree_schedule1_tag = tree_simple_selected.second.tag;
                end
            end else if (tree_main_selected.second.valid &&
                         is_cond_branch(rob_decode_q[
                             tree_main_selected.second.tag[PRODUCER_SLOT_WIDTH-1:0]])) begin
                // The secondary compare pipe accepts the next ready conditional
                // branch. Predictor updates are serialized after resolution, so
                // two branches may execute without requiring a dual-write BHT.
                tree_schedule1_valid = 1'b1;
                tree_schedule1_tag = tree_main_selected.second.tag;
            end
        end else if (tree_simple_selected.first.valid) begin
            tree_schedule0_valid = 1'b1;
            tree_schedule0_tag = tree_simple_selected.first.tag;
            if (tree_simple_selected.second.valid) begin
                tree_schedule1_valid = 1'b1;
                tree_schedule1_tag = tree_simple_selected.second.tag;
            end
        end
    end

    // Arbitration produces two binary tags. Packed issue payloads are then
	// materialized through two selected ROB read ports in the same launch stage.
    wire issue_active0_valid = tree_schedule0_valid;
    wire issue_active1_valid = tree_schedule1_valid;
    wire rob_tag_t issue_active0_tag = tree_schedule0_tag;
    wire rob_tag_t issue_active1_tag = tree_schedule1_tag;
    wire producer_slot_t issue_slot0 =
        issue_active0_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t issue_slot1 =
        issue_active1_tag[PRODUCER_SLOT_WIDTH-1:0];
    always_comb begin
        issue_pkt_o = '0;
        issue_pkt1_o = '0;
        if (issue_active0_valid && rob_valid_q[issue_slot0] &&
            rob_tag_q[issue_slot0] == issue_active0_tag &&
            !redirect_pkt_i.valid && !trap_ctrl_i.redirect) begin
            issue_pkt_o.valid = 1'b1;
            issue_pkt_o.rob_tag = issue_active0_tag;
            issue_pkt_o.decode = rob_decode_q[issue_slot0];
            issue_pkt_o.rs1_ready = slot_rs1_ready[issue_slot0];
            issue_pkt_o.rs2_ready = slot_rs2_ready[issue_slot0];
			issue_pkt_o.rs1_early_alu = slot_rs1_early_alu[issue_slot0];
			issue_pkt_o.rs2_early_alu = slot_rs2_early_alu[issue_slot0];
			issue_pkt_o.rs1_early_dual = slot_rs1_early_dual[issue_slot0];
			issue_pkt_o.rs2_early_dual = slot_rs2_early_dual[issue_slot0];
			issue_pkt_o.rs1_early_load = slot_rs1_early_load[issue_slot0];
			issue_pkt_o.rs2_early_load = slot_rs2_early_load[issue_slot0];
            issue_pkt_o.rs1_tag = rob_rs1_tag_q[issue_slot0];
            issue_pkt_o.rs2_tag = rob_rs2_tag_q[issue_slot0];
            issue_pkt_o.rs1_value = slot_rs1_value[issue_slot0];
            issue_pkt_o.rs2_value = slot_rs2_value[issue_slot0];
        end
		if (issue_pkt_o.valid && issue_active1_valid && rob_valid_q[issue_slot1] &&
			rob_tag_q[issue_slot1] == issue_active1_tag &&
            !redirect_pkt_i.valid && !trap_ctrl_i.redirect) begin
            issue_pkt1_o.valid = 1'b1;
            issue_pkt1_o.rob_tag = issue_active1_tag;
            issue_pkt1_o.decode = rob_decode_q[issue_slot1];
            issue_pkt1_o.rs1_ready = slot_rs1_ready[issue_slot1];
            issue_pkt1_o.rs2_ready = slot_rs2_ready[issue_slot1];
			issue_pkt1_o.rs1_early_alu = slot_rs1_early_alu[issue_slot1];
			issue_pkt1_o.rs2_early_alu = slot_rs2_early_alu[issue_slot1];
			issue_pkt1_o.rs1_early_dual = slot_rs1_early_dual[issue_slot1];
			issue_pkt1_o.rs2_early_dual = slot_rs2_early_dual[issue_slot1];
			issue_pkt1_o.rs1_early_load = slot_rs1_early_load[issue_slot1];
			issue_pkt1_o.rs2_early_load = slot_rs2_early_load[issue_slot1];
            issue_pkt1_o.rs1_tag = rob_rs1_tag_q[issue_slot1];
            issue_pkt1_o.rs2_tag = rob_rs2_tag_q[issue_slot1];
            issue_pkt1_o.rs1_value = slot_rs1_value[issue_slot1];
            issue_pkt1_o.rs2_value = slot_rs2_value[issue_slot1];
        end
    end

    assign if_id_ready_o = has_room_one && !trap_ctrl_i.stall;
    assign if_id_consume_two_o = push1;
    assign rf_addr_rs1_o = decoded0.rs1_addr;
    assign rf_addr_rs2_o = decoded0.rs2_addr;
    assign rf_addr_rs3_o = decoded1.rs1_addr;
    assign rf_addr_rs4_o = decoded1.rs2_addr;

    wire producer_slot_t tail0_slot = tail_tag_q[PRODUCER_SLOT_WIDTH-1:0];
    wire rob_tag_t tail1_tag = tail_tag_q + rob_tag_t'(1);
    wire producer_slot_t tail1_slot = tail1_tag[PRODUCER_SLOT_WIDTH-1:0];

`ifndef SYNTHESIS
    // Keep the existing performance monitor connected while changing the
    // ownership model from a producer table to the unified ROB.
    localparam logic [2:0] DBG_PRODUCER_ALU = 3'd1;
    localparam logic [2:0] DBG_PRODUCER_LOAD = 3'd2;
    localparam logic [2:0] DBG_PRODUCER_MUL = 3'd3;
    localparam logic [2:0] DBG_PRODUCER_OTHER = 3'd4;
    wire [ROB_DEPTH-1:0] producer_valid_q = rob_valid_q;
    wire [ROB_DEPTH-1:0] producer_ready_q = rob_done_q;
    logic [ROB_DEPTH-1:0] producer_complete_mask;
    logic [ROB_DEPTH-1:0] producer_retire_q;
    wire producer_alloc_ex = push0;
    wire producer_full_stall = !has_room_one;
    wire lsu_serialize_stall = !serial_ready_i;
    wire rs1_has_producer = issue_pkt_o.valid && !issue_pkt_o.rs1_ready;
    wire rs2_has_producer = issue_pkt_o.valid && !issue_pkt_o.rs2_ready;
    wire producer_slot_t rs1_producer_slot = issue_pkt_o.rs1_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t rs2_producer_slot = issue_pkt_o.rs2_tag[PRODUCER_SLOT_WIDTH-1:0];
    wire rs1_producer_ready = issue_pkt_o.rs1_ready;
    wire rs2_producer_ready = issue_pkt_o.rs2_ready;
    wire [2:0] dbg_rs1_producer_kind = DBG_PRODUCER_OTHER;
    wire [2:0] dbg_rs2_producer_kind = DBG_PRODUCER_OTHER;
    integer dbg_lane;
    always_comb begin
        producer_complete_mask = '0;
        producer_retire_q = '0;
        for (dbg_lane = 0; dbg_lane < COMPLETION_LANES; dbg_lane = dbg_lane + 1)
            if (completion_bus_i[dbg_lane].valid && completion_bus_i[dbg_lane].producer_tracked)
                producer_complete_mask[completion_bus_i[dbg_lane].producer_id[
                    PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
        if (retire_bus.slot0.valid)
            producer_retire_q[retire_bus.slot0.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
        if (retire_bus.slot1.valid)
            producer_retire_q[retire_bus.slot1.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
        if (retire_bus.slot2.valid)
            producer_retire_q[retire_bus.slot2.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
        if (retire_bus.slot3.valid)
            producer_retire_q[retire_bus.slot3.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] = 1'b1;
    end
`endif

    integer idx;
    integer reg_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rob_valid_q <= '0;
            rob_issued_q <= '0;
            rob_done_q <= '0;
			rob_main_launch_q <= '0;
			rob_dual_launch_q <= '0;
			rob_load_ready_q <= '0;
            rob_rs1_ready_q <= '0;
            rob_rs2_ready_q <= '0;
            rat_valid_q <= '0;
            retire_bus_q <= '0;
            gpr_commit_bus_q <= '0;
            head_tag_q <= '0;
            tail_tag_q <= '0;
            rob_count_q <= '0;
            for (idx = 0; idx < ROB_DEPTH; idx = idx + 1) begin
                rob_tag_q[idx] <= '0;
                rob_decode_q[idx] <= '0;
                rob_result_q[idx] <= '0;
                rob_rs1_tag_q[idx] <= '0;
                rob_rs2_tag_q[idx] <= '0;
                rob_rs1_value_q[idx] <= '0;
                rob_rs2_value_q[idx] <= '0;
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx = reg_idx + 1)
                rat_tag_q[reg_idx] <= '0;
        end else if (trap_ctrl_i.redirect) begin
            rob_valid_q <= '0;
            rob_issued_q <= '0;
            rob_done_q <= '0;
			rob_main_launch_q <= '0;
			rob_dual_launch_q <= '0;
			rob_load_ready_q <= '0;
            rob_rs1_ready_q <= '0;
            rob_rs2_ready_q <= '0;
            rat_valid_q <= '0;
            retire_bus_q <= '0;
            gpr_commit_bus_q <= '0;
            head_tag_q <= tail_tag_q;
            rob_count_q <= '0;
		end else if (redirect_pkt_i.valid && !redirect_pkt_i.recover_rob) begin
			// Trap/return redirection trails the interrupt pulse that already
			// cleared the window. Hold that empty architectural state while the
			// registered redirect flushes the front end.
						retire_bus_q <= '0;
						gpr_commit_bus_q <= '0;
					rob_main_launch_q <= '0;
					rob_dual_launch_q <= '0;
					rob_load_ready_q <= '0;
				end else if (redirect_pkt_i.valid) begin
            // A branch may resolve before it reaches the head. Preserve the
            // precise prefix through that branch and discard only younger work.
            rob_valid_q <= '0;
            rob_issued_q <= '0;
            rob_done_q <= '0;
			rob_main_launch_q <= '0;
			rob_dual_launch_q <= '0;
			rob_load_ready_q <= '0;
            rob_rs1_ready_q <= '0;
            rob_rs2_ready_q <= '0;
            retire_bus_q <= '0;
            gpr_commit_bus_q <= '0;
            for (idx = 0; idx < ROB_DEPTH; idx = idx + 1) begin
                if (idx < redirect_keep_count) begin
                    rob_valid_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b1;
					if (completion_hit(rob_tag_q[
							(head_slot + idx) & (ROB_DEPTH - 1)])) begin
						rob_issued_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b1;
					end else if ((redirect_pkt_i.replay_valid &&
							 rob_tag_q[(head_slot + idx) & (ROB_DEPTH - 1)] ==
							 redirect_pkt_i.replay_tag) ||
							(redirect_pkt_i.replay1_valid &&
							 rob_tag_q[(head_slot + idx) & (ROB_DEPTH - 1)] ==
							 redirect_pkt_i.replay1_tag)) begin
						rob_issued_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b0;
					end else begin
						rob_issued_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
							rob_issued_q[(head_slot + idx) & (ROB_DEPTH - 1)];
					end
                    if (completion_hit(rob_tag_q[
                            (head_slot + idx) & (ROB_DEPTH - 1)])) begin
                        rob_done_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b1;
                        rob_result_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            completion_value(rob_tag_q[
                                (head_slot + idx) & (ROB_DEPTH - 1)]);
                    end else begin
                        rob_done_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            rob_done_q[(head_slot + idx) & (ROB_DEPTH - 1)];
                    end
                    if (!rob_rs1_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] &&
                        completion_hit(rob_rs1_tag_q[
                            (head_slot + idx) & (ROB_DEPTH - 1)])) begin
                        rob_rs1_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b1;
                        rob_rs1_value_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            completion_value(rob_rs1_tag_q[
                                (head_slot + idx) & (ROB_DEPTH - 1)]);
                    end else begin
                        rob_rs1_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            rob_rs1_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)];
                    end
                    if (!rob_rs2_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] &&
                        completion_hit(rob_rs2_tag_q[
                            (head_slot + idx) & (ROB_DEPTH - 1)])) begin
                        rob_rs2_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] <= 1'b1;
                        rob_rs2_value_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            completion_value(rob_rs2_tag_q[
                                (head_slot + idx) & (ROB_DEPTH - 1)]);
                    end else begin
                        rob_rs2_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)] <=
                            rob_rs2_ready_q[(head_slot + idx) & (ROB_DEPTH - 1)];
                    end
                end
            end
            rob_issued_q[redirect_pkt_i.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            rob_done_q[redirect_pkt_i.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            rob_result_q[redirect_pkt_i.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <=
                rob_decode_q[redirect_pkt_i.rob_tag[
                    PRODUCER_SLOT_WIDTH-1:0]].pc + 32'd4;
            tail_tag_q <= redirect_pkt_i.rob_tag + rob_tag_t'(1);
            rob_count_q <= redirect_keep_count;
            rat_valid_q <= '0;
            for (idx = 0; idx < ROB_DEPTH; idx = idx + 1) begin
                if (idx < redirect_keep_count &&
                    rob_decode_q[(head_slot + idx) & (ROB_DEPTH - 1)].rd_wen &&
                    rob_decode_q[(head_slot + idx) & (ROB_DEPTH - 1)].rd_addr != '0) begin
                    rat_valid_q[rob_decode_q[
                        (head_slot + idx) & (ROB_DEPTH - 1)].rd_addr] <= 1'b1;
                    rat_tag_q[rob_decode_q[
                        (head_slot + idx) & (ROB_DEPTH - 1)].rd_addr] <=
                            rob_tag_q[(head_slot + idx) & (ROB_DEPTH - 1)];
                end
            end
        end else begin
            retire_bus_q <= retire_bus;
			gpr_commit_bus_q <= gpr_commit_bus;
			rob_main_launch_q <= '0;
			rob_dual_launch_q <= '0;
			rob_load_ready_q <= '0;
			if (load_wakeup_i.valid && load_wakeup_i.producer_tracked &&
				rob_valid_q[load_wakeup_i.producer_id[
					PRODUCER_SLOT_WIDTH-1:0]] &&
				(rob_tag_q[load_wakeup_i.producer_id[
					PRODUCER_SLOT_WIDTH-1:0]] ==
				 load_wakeup_i.producer_id) &&
				!(push0 && (tail0_slot == load_wakeup_i.producer_id[
					PRODUCER_SLOT_WIDTH-1:0])) &&
				!(push1 && (tail1_slot == load_wakeup_i.producer_id[
					PRODUCER_SLOT_WIDTH-1:0])))
				rob_load_ready_q[load_wakeup_i.producer_id[
					PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
            for (idx = 0; idx < ROB_DEPTH; idx = idx + 1) begin
                if (rob_valid_q[idx] &&
                    (completion_now_hit(rob_tag_q[idx]) ||
                     completion_hit(rob_tag_q[idx]))) begin
                    rob_done_q[idx] <= 1'b1;
                    rob_result_q[idx] <= completion_now_hit(rob_tag_q[idx]) ?
                        completion_now_value(rob_tag_q[idx]) :
                        completion_value(rob_tag_q[idx]);
                end
                if (rob_valid_q[idx] && !rob_rs1_ready_q[idx] &&
                    (completion_now_hit(rob_rs1_tag_q[idx]) ||
                     completion_hit(rob_rs1_tag_q[idx]))) begin
                    rob_rs1_ready_q[idx] <= 1'b1;
                    rob_rs1_value_q[idx] <= completion_now_hit(rob_rs1_tag_q[idx]) ?
                        completion_now_value(rob_rs1_tag_q[idx]) :
                        completion_value(rob_rs1_tag_q[idx]);
                end
                if (rob_valid_q[idx] && !rob_rs2_ready_q[idx] &&
                    (completion_now_hit(rob_rs2_tag_q[idx]) ||
                     completion_hit(rob_rs2_tag_q[idx]))) begin
                    rob_rs2_ready_q[idx] <= 1'b1;
                    rob_rs2_value_q[idx] <= completion_now_hit(rob_rs2_tag_q[idx]) ?
                        completion_now_value(rob_rs2_tag_q[idx]) :
                        completion_value(rob_rs2_tag_q[idx]);
                end
            end

			if (issue_ready_i && issue_pkt_o.valid) begin
				rob_issued_q[issue_pkt_o.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
				rob_main_launch_q[
					issue_pkt_o.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
			end
            if (issue_ready_i && issue_pkt1_o.valid) begin
                rob_issued_q[issue_pkt1_o.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
				rob_dual_launch_q[
					issue_pkt1_o.rob_tag[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
			end

            if (retire_bus.slot0.valid) begin
                rob_valid_q[head_slot] <= 1'b0;
                rob_issued_q[head_slot] <= 1'b0;
                rob_done_q[head_slot] <= 1'b0;
                if (retire_bus.slot0.writes_gpr &&
                    rat_valid_q[retire_bus.slot0.rd_addr] &&
                    rat_tag_q[retire_bus.slot0.rd_addr] == retire_bus.slot0.rob_tag)
                    rat_valid_q[retire_bus.slot0.rd_addr] <= 1'b0;
            end
            if (retire_bus.slot1.valid) begin
                rob_valid_q[head1_slot] <= 1'b0;
                rob_issued_q[head1_slot] <= 1'b0;
                rob_done_q[head1_slot] <= 1'b0;
                if (retire_bus.slot1.writes_gpr &&
                    rat_valid_q[retire_bus.slot1.rd_addr] &&
                    rat_tag_q[retire_bus.slot1.rd_addr] == retire_bus.slot1.rob_tag)
                    rat_valid_q[retire_bus.slot1.rd_addr] <= 1'b0;
            end
            if (retire_bus.slot2.valid) begin
                rob_valid_q[head2_slot] <= 1'b0;
                rob_issued_q[head2_slot] <= 1'b0;
                rob_done_q[head2_slot] <= 1'b0;
                if (retire_bus.slot2.writes_gpr &&
                    rat_valid_q[retire_bus.slot2.rd_addr] &&
                    rat_tag_q[retire_bus.slot2.rd_addr] == retire_bus.slot2.rob_tag)
                    rat_valid_q[retire_bus.slot2.rd_addr] <= 1'b0;
            end
            if (retire_bus.slot3.valid) begin
                rob_valid_q[head3_slot] <= 1'b0;
                rob_issued_q[head3_slot] <= 1'b0;
                rob_done_q[head3_slot] <= 1'b0;
                if (retire_bus.slot3.writes_gpr &&
                    rat_valid_q[retire_bus.slot3.rd_addr] &&
                    rat_tag_q[retire_bus.slot3.rd_addr] == retire_bus.slot3.rob_tag)
                    rat_valid_q[retire_bus.slot3.rd_addr] <= 1'b0;
            end
            head_tag_q <= head_tag_q + rob_tag_t'(retire_count);

            if (push0) begin
                rob_valid_q[tail0_slot] <= 1'b1;
                rob_issued_q[tail0_slot] <= 1'b0;
                rob_done_q[tail0_slot] <= 1'b0;
                rob_tag_q[tail0_slot] <= tail_tag_q;
                rob_decode_q[tail0_slot] <= decoded0;
                rob_result_q[tail0_slot] <= '0;
                if (!decoded0.rs1_ren || decoded0.rs1_addr == '0 || !rat_valid_q[decoded0.rs1_addr]) begin
                    rob_rs1_ready_q[tail0_slot] <= 1'b1;
                    rob_rs1_tag_q[tail0_slot] <= '0;
                    rob_rs1_value_q[tail0_slot] <= committed_value(
                        decoded0.rs1_addr, rf_rdata_rs1_i);
                end else begin
                    rob_rs1_tag_q[tail0_slot] <= rat_tag_q[decoded0.rs1_addr];
                    rob_rs1_ready_q[tail0_slot] <=
                        completion_hit(rat_tag_q[decoded0.rs1_addr]) ||
                        (rob_done_q[rat_tag_q[decoded0.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]] &&
                         rob_tag_q[rat_tag_q[decoded0.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]] ==
                         rat_tag_q[decoded0.rs1_addr]);
                    rob_rs1_value_q[tail0_slot] <= completion_hit(rat_tag_q[decoded0.rs1_addr]) ?
                        completion_value(rat_tag_q[decoded0.rs1_addr]) :
                        rob_result_q[rat_tag_q[decoded0.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]];
                end
                if (!decoded0.rs2_ren || decoded0.rs2_addr == '0 || !rat_valid_q[decoded0.rs2_addr]) begin
                    rob_rs2_ready_q[tail0_slot] <= 1'b1;
                    rob_rs2_tag_q[tail0_slot] <= '0;
                    rob_rs2_value_q[tail0_slot] <= committed_value(
                        decoded0.rs2_addr, rf_rdata_rs2_i);
                end else begin
                    rob_rs2_tag_q[tail0_slot] <= rat_tag_q[decoded0.rs2_addr];
                    rob_rs2_ready_q[tail0_slot] <=
                        completion_hit(rat_tag_q[decoded0.rs2_addr]) ||
                        (rob_done_q[rat_tag_q[decoded0.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]] &&
                         rob_tag_q[rat_tag_q[decoded0.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]] ==
                         rat_tag_q[decoded0.rs2_addr]);
                    rob_rs2_value_q[tail0_slot] <= completion_hit(rat_tag_q[decoded0.rs2_addr]) ?
                        completion_value(rat_tag_q[decoded0.rs2_addr]) :
                        rob_result_q[rat_tag_q[decoded0.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]];
                end
                if (decoded0.rd_wen && decoded0.rd_addr != '0) begin
                    rat_valid_q[decoded0.rd_addr] <= 1'b1;
                    rat_tag_q[decoded0.rd_addr] <= tail_tag_q;
                end
            end

            if (push1) begin
                rob_valid_q[tail1_slot] <= 1'b1;
                rob_issued_q[tail1_slot] <= 1'b0;
                rob_done_q[tail1_slot] <= 1'b0;
                rob_tag_q[tail1_slot] <= tail1_tag;
                rob_decode_q[tail1_slot] <= decoded1;
                rob_result_q[tail1_slot] <= '0;
                if (decoded1.rs1_ren && decoded1.rs1_addr != '0 && decoded0.rd_wen &&
                    decoded0.rd_addr != '0 && decoded1.rs1_addr == decoded0.rd_addr) begin
                    rob_rs1_ready_q[tail1_slot] <= 1'b0;
                    rob_rs1_tag_q[tail1_slot] <= tail_tag_q;
                    rob_rs1_value_q[tail1_slot] <= '0;
                end else if (!decoded1.rs1_ren || decoded1.rs1_addr == '0 || !rat_valid_q[decoded1.rs1_addr]) begin
                    rob_rs1_ready_q[tail1_slot] <= 1'b1;
                    rob_rs1_tag_q[tail1_slot] <= '0;
                    rob_rs1_value_q[tail1_slot] <= committed_value(
                        decoded1.rs1_addr, rf_rdata_rs3_i);
                end else begin
                    rob_rs1_tag_q[tail1_slot] <= rat_tag_q[decoded1.rs1_addr];
                    rob_rs1_ready_q[tail1_slot] <= completion_hit(rat_tag_q[decoded1.rs1_addr]) ||
                        (rob_done_q[rat_tag_q[decoded1.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]] &&
                         rob_tag_q[rat_tag_q[decoded1.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]] ==
                         rat_tag_q[decoded1.rs1_addr]);
                    rob_rs1_value_q[tail1_slot] <= completion_hit(rat_tag_q[decoded1.rs1_addr]) ?
                        completion_value(rat_tag_q[decoded1.rs1_addr]) :
                        rob_result_q[rat_tag_q[decoded1.rs1_addr][PRODUCER_SLOT_WIDTH-1:0]];
                end
                if (decoded1.rs2_ren && decoded1.rs2_addr != '0 && decoded0.rd_wen &&
                    decoded0.rd_addr != '0 && decoded1.rs2_addr == decoded0.rd_addr) begin
                    rob_rs2_ready_q[tail1_slot] <= 1'b0;
                    rob_rs2_tag_q[tail1_slot] <= tail_tag_q;
                    rob_rs2_value_q[tail1_slot] <= '0;
                end else if (!decoded1.rs2_ren || decoded1.rs2_addr == '0 || !rat_valid_q[decoded1.rs2_addr]) begin
                    rob_rs2_ready_q[tail1_slot] <= 1'b1;
                    rob_rs2_tag_q[tail1_slot] <= '0;
                    rob_rs2_value_q[tail1_slot] <= committed_value(
                        decoded1.rs2_addr, rf_rdata_rs4_i);
                end else begin
                    rob_rs2_tag_q[tail1_slot] <= rat_tag_q[decoded1.rs2_addr];
                    rob_rs2_ready_q[tail1_slot] <= completion_hit(rat_tag_q[decoded1.rs2_addr]) ||
                        (rob_done_q[rat_tag_q[decoded1.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]] &&
                         rob_tag_q[rat_tag_q[decoded1.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]] ==
                         rat_tag_q[decoded1.rs2_addr]);
                    rob_rs2_value_q[tail1_slot] <= completion_hit(rat_tag_q[decoded1.rs2_addr]) ?
                        completion_value(rat_tag_q[decoded1.rs2_addr]) :
                        rob_result_q[rat_tag_q[decoded1.rs2_addr][PRODUCER_SLOT_WIDTH-1:0]];
                end
                if (decoded1.rd_wen && decoded1.rd_addr != '0) begin
                    rat_valid_q[decoded1.rd_addr] <= 1'b1;
                    rat_tag_q[decoded1.rd_addr] <= tail1_tag;
                end
            end

            tail_tag_q <= tail_tag_q + rob_tag_t'(push_count);
            rob_count_q <= rob_count_q + COUNT_WIDTH'(push_count) - COUNT_WIDTH'(retire_count);
        end
    end

`ifndef SYNTHESIS
    integer assert_offset;
    integer assert_slot;
    integer assert_reg;
    always_ff @(posedge clk) begin
		if (rst_n && redirect_pkt_i.valid && redirect_pkt_i.recover_rob &&
			!trap_ctrl_i.redirect) begin
            assert (redirect_age < rob_count_q &&
                    rob_valid_q[redirect_pkt_i.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0]] &&
                    rob_tag_q[redirect_pkt_i.rob_tag[
                        PRODUCER_SLOT_WIDTH-1:0]] == redirect_pkt_i.rob_tag)
                else $fatal(1, "redirect tag is not a live ROB branch tag=%0d head=%0d count=%0d",
                            redirect_pkt_i.rob_tag, head_tag_q, rob_count_q);
        end
        if (rst_n && !redirect_pkt_i.valid && !trap_ctrl_i.redirect) begin
            assert (rob_count_q <= COUNT_WIDTH'(ROB_DEPTH))
                else $fatal(1, "ROB overflow");
            assert ($countones(rob_valid_q) == rob_count_q)
                else $fatal(1, "ROB count/valid mismatch count=%0d valid=0x%0h",
                            rob_count_q, rob_valid_q);
            assert (!(issue_pkt1_o.valid && !issue_pkt_o.valid))
                else $fatal(1, "secondary issue without primary issue");
            assert ((rob_issued_q & ~rob_valid_q) == '0)
                else $fatal(1, "issued state exists outside live ROB entries");
            assert ((rob_done_q & ~rob_valid_q) == '0)
                else $fatal(1, "done state exists outside live ROB entries");
            for (assert_offset = 0; assert_offset < ROB_DEPTH;
                 assert_offset = assert_offset + 1) begin
                assert_slot = (head_slot + assert_offset) & (ROB_DEPTH - 1);
                if (assert_offset < rob_count_q) begin
                    assert (rob_valid_q[assert_slot] &&
                            rob_tag_q[assert_slot] ==
                                (head_tag_q + rob_tag_t'(assert_offset)))
                        else $fatal(1,
                            "ROB age order broken offset=%0d slot=%0d head=%0d tag=%0d",
                            assert_offset, assert_slot, head_tag_q,
                            rob_tag_q[assert_slot]);
                end
            end
            for (assert_reg = 1; assert_reg < REGS_NUM;
                 assert_reg = assert_reg + 1) begin
                if (rat_valid_q[assert_reg]) begin
                    assert (rob_valid_q[rat_tag_q[assert_reg][
                                PRODUCER_SLOT_WIDTH-1:0]] &&
                            rob_tag_q[rat_tag_q[assert_reg][
                                PRODUCER_SLOT_WIDTH-1:0]] == rat_tag_q[assert_reg])
                        else $fatal(1, "RAT points outside ROB reg=%0d tag=%0d",
                                    assert_reg, rat_tag_q[assert_reg]);
                end
            end
        end
    end
`endif
endmodule
