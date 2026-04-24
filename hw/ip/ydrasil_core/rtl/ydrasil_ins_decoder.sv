`include "define_alu.svh"
`include "define_rv32i_ins.svh"

module ydrasil_ins_decoder #(
	parameter int DATA_WIDTH = 32
)(
	input  logic [31:0] instr_i,

	output logic [4:0] rf_waddr_rd_o,
	output logic [4:0] rf_raddr_rs1_o,
	output logic [4:0] rf_raddr_rs2_o,
	output logic       rf_ren_rs1_o,
	output logic       rf_ren_rs2_o,

	output logic [31:0] imm_i_o,

	output logic       operand_b_rs_sel_o, // 选择ALU操作数B的来源：0表示来自寄存器，1表示来自立即数
	output logic       operamd_a_pc_sel_o, // 选择ALU操作数A的来源：0表示来自寄存器，1表示来自PC（用于AUIPC指令）
	output logic       bt_a_rs_sel_o, // 选择分支目标地址计算的操作数A的来源：0表示来自寄存器，1表示来自PC（用于JALR指令）

	output logic [`OPERATOR_WIDTH-1:0] operator_o,
	output logic [`OP_LSU_INFO_WIDTH-1:0] operator_lsu_o
	output logic [`OPERATOR_TYPE_WIDTH-1:0] operator_type_o
);


	logic [`OP_ALU_INFO_WIDTH-1:0] alu_op_info;
	logic [`OP_BJP_INFO_WIDTH-1:0] bjp_op_info;
	logic [`OP_LSU_INFO_WIDTH-1:0] lsu_op_info;

    logic func7_is_0000000 = (funct7 == 7'b0000000);
	logic func7_is_0100000 = (funct7 == 7'b0100000);
    logic func3_is_000 = (funct3 == 3'b000);
	logic func3_is_001 = (funct3 == 3'b001);


	logic opcode = instr_i[6:0];
	logic waddr_rd     = instr_i[11:7];
	logic funct3 = instr_i[14:12];
	logic raddr_rs1    = instr_i[19:15];
	logic raddr_rs2    = instr_i[24:20];
	logic funct7 = instr_i[31:25];

	logic [31:0] imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
	logic [31:0] imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
	logic [31:0] imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
	logic [31:0] imm_u = {instr_i[31:12], 12'b0};
	logic [31:0] imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
	logic [31:0] imm_shamt ={27'h0, instr_i[24:20]}; // 用于I类型中的移位指令，表示移位量

	logic is_op_imm   = (opcode == `RV32I_INS_TYPE_I);
	logic is_op_r_m   = (opcode == `RV32I_INS_TYPE_R_M);
    logic is_load     = (opcode == `RV32I_INS_TYPE_L);
    logic is_store    = (opcode == `RV32I_INS_TYPE_S);
    logic is_branch   = (opcode == `RV32I_INS_TYPE_B);
	logic is_jal      = (opcode == `RV32I_INS_JAL);
	logic is_jalr     = (opcode == `RV32I_INS_JALR) & func3_is_000;
	logic is_lui      = (opcode == `RV32I_INS_LUI);
	logic is_auipc    = (opcode == `RV32I_INS_AUIPC);
  
	logic is_beq      = is_branch & (funct3 == `RV32I_INS_BEQ);
	logic is_bne      = is_branch & (funct3 == `RV32I_INS_BNE);
	logic is_blt      = is_branch & (funct3 == `RV32I_INS_BLT);
	logic is_bge      = is_branch & (funct3 == `RV32I_INS_BGE);
	logic is_blto     = is_branch & (funct3 == `RV32I_INS_BLTU);
	logic is_bgeo     = is_branch & (funct3 == `RV32I_INS_BGEU);

	logic is_lb     = is_load & (funct3 == `RV32I_INS_LB);
	logic is_lh     = is_load & (funct3 == `RV32I_INS_LH);
	logic is_lw     = is_load & (funct3 == `RV32I_INS_LW);
	logic is_lbu    = is_load & (funct3 == `RV32I_INS_LBU);
	logic is_lhu    = is_load & (funct3 == `RV32I_INS_LHU);

	logic is_sb     = is_store & (funct3 == `RV32I_INS_SB);
	logic is_sh     = is_store & (funct3 == `RV32I_INS_SH);
	logic is_sw     = is_store & (funct3 == `RV32I_INS_SW);

	logic is_addi  = is_op_imm & (funct3 == `RV32I_INS_ADDI);
	logic is_slti  = is_op_imm & (funct3 == `RV32I_INS_SLTI);
	logic is_sltiu = is_op_imm & (funct3 == `RV32I_INS_SLTIU);
	logic is_xori  = is_op_imm & (funct3 == `RV32I_INS_XORI);
	logic is_ori   = is_op_imm & (funct3 == `RV32I_INS_ORI);
	logic is_andi  = is_op_imm & (funct3 == `RV32I_INS_ANDI);
	logic is_slli  = is_op_imm & (funct3 == `RV32I_INS_SLLI) 	& func7_is_0000000;
	logic is_srli  = is_op_imm & (funct3 == `RV32I_INS_SRI) 	& func7_is_0000000;
	logic is_srai  = is_op_imm & (funct3 == `RV32I_INS_SRI) 	& func7_is_0100000;

	logic is_shift = is_slli | is_srli | is_srai;

	logic is_add   = is_op_r_m & (funct3 == `RV32I_INS_ADD_SUB) 	& func7_is_0000000;
	logic is_sub   = is_op_r_m & (funct3 == `RV32I_INS_ADD_SUB) 	& func7_is_0100000;
	logic is_sll   = is_op_r_m & (funct3 == `RV32I_INS_SLL) 		& func7_is_0000000;
	logic is_slt   = is_op_r_m & (funct3 == `RV32I_INS_SLT) 		& func7_is_0000000;
	logic is_sltu  = is_op_r_m & (funct3 == `RV32I_INS_SLTU) 		& func7_is_0000000;
	logic is_xor   = is_op_r_m & (funct3 == `RV32I_INS_XOR) 		& func7_is_0000000;
	logic is_srl   = is_op_r_m & (funct3 == `RV32I_INS_SR) 			& func7_is_0000000;
	logic is_sra   = is_op_r_m & (funct3 == `RV32I_INS_SR) 			& func7_is_0100000;
	logic is_or    = is_op_r_m & (funct3 == `RV32I_INS_OR) 			& func7_is_0000000;
	logic is_and   = is_op_r_m & (funct3 == `RV32I_INS_AND) 		& func7_is_0000000;

	logic is_fence  = (opcode == `RV32I_INS_FENCE) & funct3_is_000;
	logic is_fence_i = (opcode == `RV32I_INS_FENCE) & funct3_is_001;


	logic is_nop    = (instr_i == `RV32I_INS_NOP); 
	logic is_fence = (instr_i == `RV32I_INS_FENCE);
	logic is_ecall = (instr_i == `RV32I_INS_ECALL);
	logic is_ebreak = (instr_i == `RV32I_INS_EBREAK);





	assign alu_op_info[`ALU_OP_ADD]   = is_addi | is_add | is_auipc_o | is_lui_o;
	assign alu_op_info[`ALU_OP_SUB]   = is_sub;
	assign alu_op_info[`ALU_OP_SLL]   = is_slli | is_sll;
	assign alu_op_info[`ALU_OP_SLT]   = is_slti | is_slt;
	assign alu_op_info[`ALU_OP_SLTU]  = is_sltiu | is_sltu;
	assign alu_op_info[`ALU_OP_XOR]   = is_xori | is_xor;
	assign alu_op_info[`ALU_OP_SRL]   = is_srli | is_srl;
	assign alu_op_info[`ALU_OP_SRA]   = is_srai | is_sra;
	assign alu_op_info[`ALU_OP_OR]    = is_ori | is_or;
	assign alu_op_info[`ALU_OP_AND]   = is_andi | is_and;
	assign alu_op_info[`ALU_OP_LUI]   = is_lui;
	assign alu_op_info[`ALU_OP_AUIPC] = is_auipc;

	assign bjp_op_info[`BJP_OP_JUMP] = is_jal | is_jalr;
	assign bjp_op_info[`BJP_OP_BEQ]  = is_beq;
	assign bjp_op_info[`BJP_OP_BNE]  = is_bne;
	assign bjp_op_info[`BJP_OP_BLT]  = is_blt;
	assign bjp_op_info[`BJP_OP_BGE]  = is_bge;
	assign bjp_op_info[`BJP_OP_BLTU] = is_bltu;
	assign bjp_op_info[`BJP_OP_BGEU] = is_bgeu;

	assign lsu_op_info[`LSU_OP_LB]  = is_lb;
	assign lsu_op_info[`LSU_OP_LH]  = is_lh;
	assign lsu_op_info[`LSU_OP_LW]  = is_lw;
	assign lsu_op_info[`LSU_OP_LBU] = is_lbu;
	assign lsu_op_info[`LSU_OP_LHU] = is_lhu;
	assign lsu_op_info[`LSU_OP_SB]  = is_sb;
	assign lsu_op_info[`LSU_OP_SH]  = is_sh;
	assign lsu_op_info[`LSU_OP_SW]  = is_sw;

	assign rf_waddr_rd_o = waddr_rd;
	assign rf_raddr_rs1_o = raddr_rs1;
	assign rf_raddr_rs2_o = raddr_rs2;
	assign rf_ren_rs1_o =	(~is_lui) 	& (~is_auipc) 	& (~is_jal) & 
                      		(~is_ecall) & (~is_ebreak) 	& (~is_fence) & 
                      		(~is_nop) 	;// U类型指令不需要rs1
	assign rf_ren_rs2_o = is_op_r_m | is_branch | is_store; // R类型和分支指令需要rs2


	assign operator_type_o [OPERATOR_TYPE_ALU] = is_op_imm | is_op_r_m | is_lui | is_auipc;
	assign operator_type_o [OPERATOR_TYPE_BJP] = is_branch | is_jal | is_jalr;
	assign operator_type_o [OPERATOR_TYPE_LOAD] = is_load;
	assign operator_type_o [OPERATOR_TYPE_STORE] = is_store;
	
	logic [`OPERATOR_WIDTH-1:0] alu_op_info_mark =  operator_type_o [OPERATOR_TYPE_ALU] 	? {{`OPERATOR_WIDTH-`OP_ALU_INFO_WIDTH{1'b0}},alu_op_info} : '0;
	logic [`OPERATOR_WIDTH-1:0] bjp_op_info_mark =  operator_type_o [OPERATOR_TYPE_BJP] 	? {{`OPERATOR_WIDTH-`OP_BJP_INFO_WIDTH{1'b0}},bjp_op_info} : '0;
	// assign lsu_op_info_mark =  operator_type_o [OPERATOR_TYPE_LOAD] ? {{`OPERATOR_WIDTH-`OP_LSU_INFO_WIDTH{1'b0}},lsu_op_info} : '0;
	logic [31:0] imm_i_mask = ((is_op_r_m & ! is_shift) | is_jalr | is_load) ? imm_i : '0;
	logic [31:0] imm_s_mask = is_store ? imm_s : '0;
	logic [31:0] imm_b_mask = is_branch ? imm_b : '0;
	logic [31:0] imm_u_mask = (is_lui | is_auipc) ? imm_u : '0;
	logic [31:0] imm_j_mask = is_jal ? imm_j : '0;
	logic [31:0] imm_shamt_mask = is_shift ? imm_shamt : '0;

	assign imm_i_o = imm_i_mask | imm_s_mask | imm_b_mask | imm_u_mask | imm_j_mask | imm_shamt_mask;

	assign operator_o = alu_op_info_mark | bjp_op_info_mark ;
	assign operator_lsu_o = lsu_op_info;

	logic operand_b_rs_sel = is_branch | is_store |is_op_r_m;
	logic operamd_a_pc_sel = is_auipc  ;
	logic bt_a_rs_sel = is_jalr;

	assign operand_b_rs_sel_o = operand_b_rs_sel;
	assign operamd_a_pc_sel_o = operamd_a_pc_sel;
	assign bt_a_rs_sel_o = bt_a_rs_sel;

endmodule
