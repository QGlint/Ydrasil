`include "define_alu.svh"
`include "define_rv32i_ins.svh"

module ydrasil_ins_decoder #(
	parameter int DATA_WIDTH = 32
)(
	input  logic [31:0] instr_i,

	output logic [6:0]  opcode_o,
	output logic [2:0]  funct3_o,
	output logic [6:0]  funct7_o,
	output logic [4:0]  rd_o,
	output logic [4:0]  rs1_o,
	output logic [4:0]  rs2_o,

	output logic [DATA_WIDTH-1:0] imm_i_o,
	output logic [DATA_WIDTH-1:0] imm_s_o,
	output logic [DATA_WIDTH-1:0] imm_b_o,
	output logic [DATA_WIDTH-1:0] imm_u_o,
	output logic [DATA_WIDTH-1:0] imm_j_o,

	output logic                  is_op_o,
	output logic                  is_op_imm_o,
	output logic                  is_load_o,
	output logic                  is_store_o,
	output logic                  is_branch_o,
	output logic                  is_beq_o,
	output logic                  is_bne_o,
	output logic                  is_blt_o,
	output logic                  is_bge_o,
	output logic                  is_bltu_o,
	output logic                  is_bgeu_o,
	output logic                  is_lb_o,
	output logic                  is_lh_o,
	output logic                  is_lw_o,
	output logic                  is_lbu_o,
	output logic                  is_lhu_o,
	output logic                  is_sb_o,
	output logic                  is_sh_o,
	output logic                  is_sw_o,
	output logic                  is_jal_o,
	output logic                  is_jalr_o,
	output logic                  is_lui_o,
	output logic                  is_auipc_o,

	output logic [`ALU_OP_WIDTH-1:0] alu_op_info_o
);

	logic func7_is_0000000;
	logic func7_is_0100000;
    logic func3_is_000;
	logic is_addi;
	logic is_slti;
	logic is_sltiu;
	logic is_xori;
	logic is_ori;
	logic is_andi;
	logic is_slli;
	logic is_srli;
	logic is_srai;
	logic is_add;
	logic is_sub;
	logic is_sll;
	logic is_slt;
	logic is_sltu;
	logic is_xor;
	logic is_srl;
	logic is_sra;
	logic is_or;
	logic is_and;
	logic is_fence;
	logic is_ecall;
	logic is_ebreak;


    assign func7_is_0000000 = (funct7_o == 7'b0000000);
	assign func7_is_0100000 = (funct7_o == 7'b0100000);
    assign func3_is_000 = (funct3_o == 3'b000);


	assign opcode_o = instr_i[6:0];
	assign rd_o     = instr_i[11:7];
	assign funct3_o = instr_i[14:12];
	assign rs1_o    = instr_i[19:15];
	assign rs2_o    = instr_i[24:20];
	assign funct7_o = instr_i[31:25];

	assign imm_i_o = {{20{instr_i[31]}}, instr_i[31:20]};
	assign imm_s_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
	assign imm_b_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
	assign imm_u_o = {instr_i[31:12], 12'b0};
	assign imm_j_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

	assign is_op_imm_o = (opcode_o == `RV32I_INS_TYPE_I);
	assign is_op_o     = (opcode_o == `RV32I_INS_TYPE_R_M);
    assign is_load_o   = (opcode_o == `RV32I_INS_TYPE_L);
    assign is_store_o  = (opcode_o == `RV32I_INS_TYPE_S);
    assign is_branch_o = (opcode_o == `RV32I_INS_TYPE_B);
	assign is_jal_o    = (opcode_o == `RV32I_INS_JAL);
	assign is_jalr_o   = (opcode_o == `RV32I_INS_JALR) & func3_is_000;
	assign is_lui_o    = (opcode_o == `RV32I_INS_LUI);
	assign is_auipc_o  = (opcode_o == `RV32I_INS_AUIPC);

	assign is_beq_o    = is_branch_o & (funct3_o == `RV32I_INS_BEQ);
	assign is_bne_o    = is_branch_o & (funct3_o == `RV32I_INS_BNE);
	assign is_blt_o    = is_branch_o & (funct3_o == `RV32I_INS_BLT);
	assign is_bge_o    = is_branch_o & (funct3_o == `RV32I_INS_BGE);
	assign is_bltu_o   = is_branch_o & (funct3_o == `RV32I_INS_BLTU);
	assign is_bgeu_o   = is_branch_o & (funct3_o == `RV32I_INS_BGEU);

	assign is_lb_o     = is_load_o & (funct3_o == `RV32I_INS_LB);
	assign is_lh_o     = is_load_o & (funct3_o == `RV32I_INS_LH);
	assign is_lw_o     = is_load_o & (funct3_o == `RV32I_INS_LW);
	assign is_lbu_o    = is_load_o & (funct3_o == `RV32I_INS_LBU);
	assign is_lhu_o    = is_load_o & (funct3_o == `RV32I_INS_LHU);

	assign is_sb_o     = is_store_o & (funct3_o == `RV32I_INS_SB);
	assign is_sh_o     = is_store_o & (funct3_o == `RV32I_INS_SH);
	assign is_sw_o     = is_store_o & (funct3_o == `RV32I_INS_SW);

	assign is_addi  = is_op_imm_o & (funct3_o == `RV32I_INS_ADDI);
	assign is_slti  = is_op_imm_o & (funct3_o == `RV32I_INS_SLTI);
	assign is_sltiu = is_op_imm_o & (funct3_o == `RV32I_INS_SLTIU);
	assign is_xori  = is_op_imm_o & (funct3_o == `RV32I_INS_XORI);
	assign is_ori   = is_op_imm_o & (funct3_o == `RV32I_INS_ORI);
	assign is_andi  = is_op_imm_o & (funct3_o == `RV32I_INS_ANDI);
	assign is_slli  = is_op_imm_o & (funct3_o == `RV32I_INS_SLLI) & func7_is_0000000;
	assign is_srli  = is_op_imm_o & (funct3_o == `RV32I_INS_SRI) & func7_is_0000000;
	assign is_srai  = is_op_imm_o & (funct3_o == `RV32I_INS_SRI) & func7_is_0100000;

	assign is_add   = is_op_o & (funct3_o == `RV32I_INS_ADD_SUB) & func7_is_0000000;
	assign is_sub   = is_op_o & (funct3_o == `RV32I_INS_ADD_SUB) & func7_is_0100000;
	assign is_sll   = is_op_o & (funct3_o == `RV32I_INS_SLL) & func7_is_0000000;
	assign is_slt   = is_op_o & (funct3_o == `RV32I_INS_SLT) & func7_is_0000000;
	assign is_sltu  = is_op_o & (funct3_o == `RV32I_INS_SLTU) & func7_is_0000000;
	assign is_xor   = is_op_o & (funct3_o == `RV32I_INS_XOR) & func7_is_0000000;
	assign is_srl   = is_op_o & (funct3_o == `RV32I_INS_SR) & func7_is_0000000;
	assign is_sra   = is_op_o & (funct3_o == `RV32I_INS_SR) & func7_is_0100000;
	assign is_or    = is_op_o & (funct3_o == `RV32I_INS_OR) & func7_is_0000000;
	assign is_and   = is_op_o & (funct3_o == `RV32I_INS_AND) & func7_is_0000000;

	assign is_fence = (instr_i == `RV32I_INS_FENCE);
	assign is_ecall = (instr_i == `RV32I_INS_ECALL);
	assign is_ebreak = (instr_i == `RV32I_INS_EBREAK);


	assign alu_op_info_o[`ALU_OP_ADD]   = is_addi | is_add | is_auipc_o | is_lui_o;
	assign alu_op_info_o[`ALU_OP_SUB]   = is_sub;
	assign alu_op_info_o[`ALU_OP_SLL]   = is_slli | is_sll;
	assign alu_op_info_o[`ALU_OP_SLT]   = is_slti | is_slt;
	assign alu_op_info_o[`ALU_OP_SLTU]  = is_sltiu | is_sltu;
	assign alu_op_info_o[`ALU_OP_XOR]   = is_xori | is_xor;
	assign alu_op_info_o[`ALU_OP_SRL]   = is_srli | is_srl;
	assign alu_op_info_o[`ALU_OP_SRA]   = is_srai | is_sra;
	assign alu_op_info_o[`ALU_OP_OR]    = is_ori | is_or;
	assign alu_op_info_o[`ALU_OP_AND]   = is_andi | is_and;
	assign alu_op_info_o[`ALU_OP_LUI]   = is_lui_o;
	assign alu_op_info_o[`ALU_OP_AUIPC] = is_auipc_o;
	assign alu_op_info_o[`ALU_OP_JUMP]  = is_jal_o | is_jalr_o;

endmodule
