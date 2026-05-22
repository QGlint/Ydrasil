
module ydrasil_ins_decoder 
import ydrasil_pkg::*;
#(
	parameter int DATA_WIDTH = 32
)(
	input  wire [DATA_WIDTH-1:0] instr_i,

	output wire [4:0] rf_waddr_rd_o,
	output wire [4:0] rf_raddr_rs1_o,
	output wire [4:0] rf_raddr_rs2_o,
	output wire       rf_ren_rs1_o,
	output wire       rf_ren_rs2_o,
	output wire       rf_wen_rd_o,

	output wire [DATA_WIDTH-1:0] imm_i_o,

	output wire       operand_b_rs_sel_o, // 选择ALU操作数B的来源：0表示来自寄存器，1表示来自立即数
	output wire       operand_a_pc_sel_o, // 选择ALU操作数A的来源：0表示来自寄存器，1表示来自PC（用于AUIPC指令）
	output wire       bt_a_rs_sel_o, // 选择分支目标地址计算的操作数A的来源：0表示来自寄存器，1表示来自PC（用于JALR指令）
	output wire       operand_a_imm_sel_o, // 选择ALU操作数A的立即数来源：0表示不使用，1表示使用
	output wire 	  operand_b_jump_sel_o, 


	output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_o,  // 读CSR寄存器地址
    // output wire                        	 csr_ex_we_o,        // 写CSR寄存器标志
	output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_ex_waddr_o,      // 写CSR寄存器地址
	output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] csr_op_info_o,
	output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] sys_op_info_o,


	output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0] operator_o,
	output wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] operator_lsu_o,
	output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o
);


	wire [ydrasil_pkg::OP_ALU_INFO_WIDTH-1:0] alu_op_info;
	wire [ydrasil_pkg::OP_BJP_INFO_WIDTH-1:0] bjp_op_info;
	wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] lsu_op_info;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] csr_op_info;
	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] sys_op_info;

	wire [6:0] opcode 		;
	wire [4:0]	rf_waddr_rd ;
	wire [2:0] funct3 		;
	wire [4:0]	rf_raddr_rs1;
	wire [4:0]	rf_raddr_rs2;
	wire [6:0] funct7 		;

	assign opcode 		= instr_i[6:0];
	assign rf_waddr_rd  = instr_i[11:7];
	assign funct3 		= instr_i[14:12];
	assign rf_raddr_rs1 = instr_i[19:15];
	assign rf_raddr_rs2 = instr_i[24:20];
	assign funct7 		= instr_i[31:25];


    wire funct7_is_0000000 ;
	wire funct7_is_0100000 ;
    wire funct3_is_000 	;
	wire funct3_is_001 	;

	assign funct7_is_0000000 = (funct7 == 7'b0000000);
	assign funct7_is_0100000 = (funct7 == 7'b0100000);
	assign funct3_is_000 	= (funct3 == 3'b000);
	assign funct3_is_001 	= (funct3 == 3'b001);

	wire [31:0] imm_i 		;
	wire [31:0] imm_s 		;
	wire [31:0] imm_b 		;
	wire [31:0] imm_u 		;
	wire [31:0] imm_j 		;
	wire [31:0] imm_shamt 	;
    wire [31:0] imm_csr;
	assign imm_i 		= {{20{instr_i[31]}}, instr_i[31:20]};
	assign imm_s 		= {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
	assign imm_b 		= {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
	assign imm_u 		= {instr_i[31:12], 12'b0};
	assign imm_j 		= {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
	assign imm_shamt 	= {27'h0, instr_i[24:20]}; // 用于I类型中的移位指令，表示移位量
	assign imm_csr 		= {27'h0, instr_i[19:15]};

	wire is_op_imm   ;
	wire is_op_r_m   ;
    wire is_load     ;
    wire is_store    ;
    wire is_branch   ;
	wire is_jal      ;
	wire is_jalr     ;
	wire is_lui      ;
	wire is_auipc    ;
	wire is_csr	  ;
	wire is_sys		;

	assign is_op_imm   = (opcode == ydrasil_pkg::RV32I_INS_TYPE_I);
	assign is_op_r_m   = (opcode == ydrasil_pkg::RV32I_INS_TYPE_R_M);
	assign is_load     = (opcode == ydrasil_pkg::RV32I_INS_TYPE_L);
	assign is_store    = (opcode == ydrasil_pkg::RV32I_INS_TYPE_S);
	assign is_branch   = (opcode == ydrasil_pkg::RV32I_INS_TYPE_B);
	assign is_jal      = (opcode == ydrasil_pkg::RV32I_INS_JAL);
	assign is_jalr     = (opcode == ydrasil_pkg::RV32I_INS_JALR) & funct3_is_000;
	assign is_lui      = (opcode == ydrasil_pkg::RV32I_INS_LUI);
	assign is_auipc    = (opcode == ydrasil_pkg::RV32I_INS_AUIPC);
	assign is_csr      = (opcode == ydrasil_pkg::RV32I_INS_CSR);

	wire is_beq      ;
	wire is_bne      ;
	wire is_blt      ;
	wire is_bge      ;
	wire is_bltu     ;
	wire is_bgeu     ;

	assign is_beq      = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BEQ);
	assign is_bne      = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BNE);
	assign is_blt      = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BLT);
	assign is_bge      = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BGE);
	assign is_bltu     = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BLTU);
	assign is_bgeu     = is_branch & (funct3 == ydrasil_pkg::RV32I_INS_BGEU);

	wire is_lb     ;
	wire is_lh     ;
	wire is_lw     ;
	wire is_lbu    ;
	wire is_lhu    ;

	assign is_lb     = is_load & (funct3 == ydrasil_pkg::RV32I_INS_LB);
	assign is_lh     = is_load & (funct3 == ydrasil_pkg::RV32I_INS_LH);
	assign is_lw     = is_load & (funct3 == ydrasil_pkg::RV32I_INS_LW);
	assign is_lbu    = is_load & (funct3 == ydrasil_pkg::RV32I_INS_LBU);
	assign is_lhu    = is_load & (funct3 == ydrasil_pkg::RV32I_INS_LHU);

	wire is_sb     ;
	wire is_sh     ;
	wire is_sw     ;

	assign is_sb     = is_store & (funct3 == ydrasil_pkg::RV32I_INS_SB);
	assign is_sh     = is_store & (funct3 == ydrasil_pkg::RV32I_INS_SH);
	assign is_sw     = is_store & (funct3 == ydrasil_pkg::RV32I_INS_SW);

	wire is_addi  ;
	wire is_slti  ;
	wire is_sltiu ;
	wire is_xori  ;
	wire is_ori   ;
	wire is_andi  ;
	wire is_slli  ;
	wire is_srli  ;
	wire is_srai  ;

	assign is_addi  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_ADDI);
	assign is_slti  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_SLTI);
	assign is_sltiu = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_SLTIU);
	assign is_xori  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_XORI);
	assign is_ori   = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_ORI);
	assign is_andi  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_ANDI);
	assign is_slli  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_SLLI) 	& funct7_is_0000000;
	assign is_srli  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_SRI) 	& funct7_is_0000000;
	assign is_srai  = is_op_imm & (funct3 == ydrasil_pkg::RV32I_INS_SRI) 	& funct7_is_0100000;

	wire is_shift ;

	wire is_add   ;
	wire is_sub   ;
	wire is_sll   ;
	wire is_slt   ;
	wire is_sltu  ;
	wire is_xor   ;
	wire is_srl   ;
	wire is_sra   ;
	wire is_or    ;
	wire is_and   ;

	assign is_shift = is_slli | is_srli | is_srai;
	assign is_add   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_ADD_SUB) 	& funct7_is_0000000;
	assign is_sub   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_ADD_SUB) 	& funct7_is_0100000;
	assign is_sll   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_SLL) 		& funct7_is_0000000;
	assign is_slt   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_SLT) 		& funct7_is_0000000;
	assign is_sltu  = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_SLTU) 		& funct7_is_0000000;
	assign is_xor   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_XOR) 		& funct7_is_0000000;
	assign is_srl   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_SR) 			& funct7_is_0000000;
	assign is_sra   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_SR) 			& funct7_is_0100000;
	assign is_or    = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_OR) 			& funct7_is_0000000;
	assign is_and   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_AND) 		& funct7_is_0000000;

	wire is_fence  ;
	wire is_fence_i;
	assign is_fence  = (opcode == ydrasil_pkg::RV32I_INS_FENCE) & funct3_is_000;
	assign is_fence_i = (opcode == ydrasil_pkg::RV32I_INS_FENCE) & funct3_is_001;

	wire is_nop    ;
	wire is_ecall  ;
	wire is_ebreak ;
	wire is_mret    ;

	assign is_nop    = (instr_i == ydrasil_pkg::RV32I_INS_NOP);
	assign is_ecall  = (instr_i == ydrasil_pkg::RV32I_INS_ECALL);
	assign is_ebreak = (instr_i == ydrasil_pkg::RV32I_INS_EBREAK);
	assign is_mret    = (instr_i == ydrasil_pkg::RV32I_INS_MRET);

	assign is_sys = is_ecall | is_ebreak | is_mret;

	wire is_csrrw ;
    wire is_csrrs ;
    wire is_csrrc ;
    wire is_csrrwi;
    wire is_csrrsi;
    wire is_csrrci;


	assign is_csrrw =  is_csr 	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRW);
	assign is_csrrs =  is_csr 	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRS);
	assign is_csrrc =  is_csr 	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRC);
	assign is_csrrwi = is_csr  	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRWI);
	assign is_csrrsi = is_csr  	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRSI);
	assign is_csrrci = is_csr  	& (funct3 == ydrasil_pkg::RV32I_INS_CSRRCI);


	assign alu_op_info[ydrasil_pkg::OP_ALU_ADD]   = is_addi | is_add ;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SUB]   = is_sub;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SLL]   = is_slli | is_sll;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SLT]   = is_slti | is_slt;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SLTU]  = is_sltiu | is_sltu;
	assign alu_op_info[ydrasil_pkg::OP_ALU_XOR]   = is_xori | is_xor;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SRL]   = is_srli | is_srl;
	assign alu_op_info[ydrasil_pkg::OP_ALU_SRA]   = is_srai | is_sra;
	assign alu_op_info[ydrasil_pkg::OP_ALU_OR]    = is_ori | is_or;
	assign alu_op_info[ydrasil_pkg::OP_ALU_AND]   = is_andi | is_and;
	assign alu_op_info[ydrasil_pkg::OP_ALU_LUI]   = is_lui;
	assign alu_op_info[ydrasil_pkg::OP_ALU_AUIPC] = is_auipc;

	assign bjp_op_info[ydrasil_pkg::OP_BJP_JUMP] = is_jal | is_jalr;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BEQ]  = is_beq;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BNE]  = is_bne;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BLT]  = is_blt;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BGE]  = is_bge;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BLTU] = is_bltu;
	assign bjp_op_info[ydrasil_pkg::OP_BJP_BGEU] = is_bgeu;

	assign lsu_op_info[ydrasil_pkg::OP_LSU_LB]  = is_lb;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_LH]  = is_lh;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_LW]  = is_lw;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_LBU] = is_lbu;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_LHU] = is_lhu;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_SB]  = is_sb;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_SH]  = is_sh;
	assign lsu_op_info[ydrasil_pkg::OP_LSU_SW]  = is_sw;

	assign csr_op_info[ydrasil_pkg::OP_CSR_CSRRW]  = is_csrrw | is_csrrwi;
	assign csr_op_info[ydrasil_pkg::OP_CSR_CSRRS]  = is_csrrs | is_csrrsi;
	assign csr_op_info[ydrasil_pkg::OP_CSR_CSRRC]  = is_csrrc | is_csrrci;

	assign sys_op_info[ydrasil_pkg::OP_SYS_ECALL]  = is_ecall;
	assign sys_op_info[ydrasil_pkg::OP_SYS_EBREAK] = is_ebreak;
	assign sys_op_info[ydrasil_pkg::OP_SYS_MRET]   = is_mret;


	wire rf_ren_rs1 =	(~is_lui) 	& (~is_auipc) 	& (~is_jal) &  
       					(~is_ecall) & (~is_ebreak) 	& (~is_fence) & 
       					(~is_nop) 	& (~is_fence_i);// U类型指令不需要rs1
	wire rf_ren_rs2 = is_op_r_m | is_branch ; // R类型和分支指令需要rs2

	wire rf_wen_rd = is_lui | is_auipc | is_jal | is_jalr | is_op_imm | is_op_r_m ; // 需要写回寄存器的指令类型 

	wire is_alu_use = is_op_imm | is_op_r_m | is_lui | is_auipc;
	wire is_bjp_use = is_branch | is_jal | is_jalr;


	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_ALU] = is_alu_use;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_BJP] = is_bjp_use;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_LOAD] = is_load;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_STORE] = is_store;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_CSR] = is_csr;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_SYS] = is_sys;
	// wire [`OPERATOR_WIDTH-1:0] alu_op_info_mark = ({`OPERATOR_WIDTH{is_alu_use }}& {{{`OPERATOR_WIDTH-`OP_ALU_INFO_WIDTH}{1'b0}},alu_op_info});
	// wire [`OPERATOR_WIDTH-1:0] bjp_op_info_mark = ({`OPERATOR_WIDTH{is_bjp_use }}& {{{`OPERATOR_WIDTH-`OP_BJP_INFO_WIDTH}{1'b0}},bjp_op_info});
	// assign lsu_op_info_mark =  operator_type_o [OPERATOR_TYPE_LOAD] ? {{`OPERATOR_WIDTH-`OP_LSU_INFO_WIDTH{1'b0}},lsu_op_info} : '0;
	wire [31:0] imm_i_mask 		;
	wire [31:0] imm_s_mask 		;
	wire [31:0] imm_b_mask 		;
	wire [31:0] imm_u_mask 		;
	wire [31:0] imm_j_mask 		;
	wire [31:0] imm_shamt_mask ;
	wire [31:0] imm_csr_mask	;

	assign imm_i_mask 	= ((is_op_imm & ! is_shift) | is_jalr | is_load) ? imm_i : '0;
	assign imm_s_mask 	= is_store ? imm_s : '0;
	assign imm_b_mask 	= is_branch ? imm_b : '0;
	assign imm_u_mask 	= (is_lui | is_auipc) ? imm_u : '0;
	assign imm_j_mask 	= is_jal ? imm_j : '0;
	assign imm_shamt_mask = is_shift ? imm_shamt : '0;
	assign imm_csr_mask = is_csr ? imm_csr : '0;

	assign imm_i_o = imm_i_mask | imm_s_mask | imm_b_mask | imm_u_mask | imm_j_mask | imm_shamt_mask | imm_csr_mask;

	assign operator_o = ({ydrasil_pkg::OPERATOR_WIDTH{is_alu_use }}& {{0{1'b0}},alu_op_info})|
						({ydrasil_pkg::OPERATOR_WIDTH{is_bjp_use }}& {{5{1'b0}},bjp_op_info});
	assign operator_lsu_o = lsu_op_info;

	wire operand_b_rs_sel 	;
	wire operand_a_pc_sel 	;
	wire operand_a_imm_sel	;
	wire bt_a_rs_sel 		;

	assign operand_a_imm_sel = is_csrrwi | is_csrrsi | is_csrrci;

	assign operand_b_rs_sel = is_branch |is_op_r_m;
	assign operand_a_pc_sel = is_auipc  |is_jal |is_jalr;
	assign bt_a_rs_sel = is_jalr;

	assign operand_b_rs_sel_o = operand_b_rs_sel;
	assign operand_a_pc_sel_o = operand_a_pc_sel;
	assign operand_a_imm_sel_o = operand_a_imm_sel;
	assign bt_a_rs_sel_o = bt_a_rs_sel;
	assign operand_b_jump_sel_o = is_jal | is_jalr;

	assign rf_waddr_rd_o = rf_waddr_rd;
	assign rf_raddr_rs1_o = rf_raddr_rs1;
	assign rf_raddr_rs2_o = rf_raddr_rs2;
	assign rf_ren_rs1_o = rf_ren_rs1;
	assign rf_ren_rs2_o = rf_ren_rs2;
	assign rf_wen_rd_o = rf_wen_rd;

	assign csr_reg_raddr_o = instr_i[31:20];
	// assign csr_ex_we_o = is_csr;
	assign csr_ex_waddr_o = instr_i[31:20];
	assign csr_op_info_o = csr_op_info;
	assign sys_op_info_o = sys_op_info;

endmodule
