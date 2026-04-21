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
	output logic                  is_jal_o,
	output logic                  is_jalr_o,
	output logic                  is_lui_o,
	output logic                  is_auipc_o
);

    logic func7_is_0000000;
    logic func3_is_000;

    assign func7_is_0000000 = (funct7_o == 7'b0000000);
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

endmodule
