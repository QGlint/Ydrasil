
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
	output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o,
	output logic [ydrasil_pkg::UOP_CLASS_WIDTH-1:0] uop_class_o,
	output logic [ydrasil_pkg::UOP_SUBOP_WIDTH-1:0] uop_subop_o,
	output logic [ydrasil_pkg::UOP_LSU_SUBOP_WIDTH-1:0] uop_lsu_subop_o,
	output wire full_bitmanip_o,
	output wire divrem_o
);


	wire [ydrasil_pkg::OP_ALU_INFO_WIDTH-1:0] alu_op_info;
	wire [ydrasil_pkg::OP_BJP_INFO_WIDTH-1:0] bjp_op_info;
	wire [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0] lsu_op_info;
	wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0] csr_op_info;
	wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0] sys_op_info;
	wire [ydrasil_pkg::OP_MUL_INFO_WIDTH-1:0] mul_op_info;
	wire [ydrasil_pkg::OP_B_INFO_WIDTH-1:0] bitmanip_op_info;

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
	wire funct7_is_0000001 ;
	wire funct7_is_0000100 ;
	wire funct7_is_0000101 ;
	wire funct7_is_0010000 ;
	wire funct7_is_0010100 ;
	wire funct7_is_0100100 ;
	wire funct7_is_0110000 ;
	wire funct7_is_0110100 ;
    wire funct3_is_000 	;
	wire funct3_is_001 	;
	wire funct3_is_101 	;

	assign funct7_is_0000000 = (funct7 == 7'b0000000);
	assign funct7_is_0100000 = (funct7 == 7'b0100000);
	assign funct7_is_0000001 = (funct7 == 7'b0000001);
	assign funct7_is_0000100 = (funct7 == 7'b0000100);
	assign funct7_is_0000101 = (funct7 == 7'b0000101);
	assign funct7_is_0010000 = (funct7 == 7'b0010000);
	assign funct7_is_0010100 = (funct7 == 7'b0010100);
	assign funct7_is_0100100 = (funct7 == 7'b0100100);
	assign funct7_is_0110000 = (funct7 == 7'b0110000);
	assign funct7_is_0110100 = (funct7 == 7'b0110100);
	assign funct3_is_000 	= (funct3 == 3'b000);
	assign funct3_is_001 	= (funct3 == 3'b001);
	assign funct3_is_101 	= (funct3 == 3'b101);

	wire rs2_is_00000;
	wire rs2_is_00001;
	wire rs2_is_00010;
	wire rs2_is_00100;
	wire rs2_is_00101;
	wire rs2_is_00111;
	wire rs2_is_01111;
	wire rs2_is_11000;

	assign rs2_is_00000 = (rf_raddr_rs2 == 5'b00000);
	assign rs2_is_00001 = (rf_raddr_rs2 == 5'b00001);
	assign rs2_is_00010 = (rf_raddr_rs2 == 5'b00010);
	assign rs2_is_00100 = (rf_raddr_rs2 == 5'b00100);
	assign rs2_is_00101 = (rf_raddr_rs2 == 5'b00101);
	assign rs2_is_00111 = (rf_raddr_rs2 == 5'b00111);
	assign rs2_is_01111 = (rf_raddr_rs2 == 5'b01111);
	assign rs2_is_11000 = (rf_raddr_rs2 == 5'b11000);

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
	wire is_mul   ;
	wire is_mulh  ;
	wire is_mulhsu;
	wire is_mulhu ;
	wire is_div   ;
	wire is_divu  ;
	wire is_rem   ;
	wire is_remu  ;
	wire is_sh1add;
	wire is_sh2add;
	wire is_sh3add;
	wire is_andn;
	wire is_clz;
	wire is_cpop;
	wire is_ctz;
	wire is_max;
	wire is_maxu;
	wire is_min;
	wire is_minu;
	wire is_orc_b;
	wire is_orn;
	wire is_rev8;
	wire is_rol;
	wire is_ror;
	wire is_rori;
	wire is_sext_b;
	wire is_sext_h;
	wire is_xnor;
	wire is_zext_h;
	wire is_clmul;
	wire is_clmulh;
	wire is_clmulr;
	wire is_bclr;
	wire is_bclri;
	wire is_bext;
	wire is_bexti;
	wire is_binv;
	wire is_binvi;
	wire is_bset;
	wire is_bseti;
	wire is_brev8;
	wire is_pack;
	wire is_packh;
	wire is_zip;
	wire is_unzip;

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
	assign is_mul   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_MUL) 		& funct7_is_0000001;
	assign is_mulh  = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_MULH) 		& funct7_is_0000001;
	assign is_mulhsu= is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_MULHSU) 	& funct7_is_0000001;
	assign is_mulhu = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_MULHU) 		& funct7_is_0000001;
	assign is_div   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_DIV) 		& funct7_is_0000001;
	assign is_divu  = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_DIVU) 		& funct7_is_0000001;
	assign is_rem   = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_REM) 		& funct7_is_0000001;
	assign is_remu  = is_op_r_m & (funct3 == ydrasil_pkg::RV32I_INS_REMU) 		& funct7_is_0000001;
	assign is_sh1add = is_op_r_m & (funct3 == 3'b010) & funct7_is_0010000;
	assign is_sh2add = is_op_r_m & (funct3 == 3'b100) & funct7_is_0010000;
	assign is_sh3add = is_op_r_m & (funct3 == 3'b110) & funct7_is_0010000;
	assign is_andn   = is_op_r_m & (funct3 == 3'b111) & funct7_is_0100000;
	assign is_clz    = is_op_imm & funct3_is_001 & funct7_is_0110000 & rs2_is_00000;
	assign is_cpop   = is_op_imm & funct3_is_001 & funct7_is_0110000 & rs2_is_00010;
	assign is_ctz    = is_op_imm & funct3_is_001 & funct7_is_0110000 & rs2_is_00001;
	assign is_max    = is_op_r_m & (funct3 == 3'b110) & funct7_is_0000101;
	assign is_maxu   = is_op_r_m & (funct3 == 3'b111) & funct7_is_0000101;
	assign is_min    = is_op_r_m & (funct3 == 3'b100) & funct7_is_0000101;
	assign is_minu   = is_op_r_m & (funct3 == 3'b101) & funct7_is_0000101;
	assign is_orc_b  = is_op_imm & funct3_is_101 & funct7_is_0010100 & rs2_is_00111;
	assign is_orn    = is_op_r_m & (funct3 == 3'b110) & funct7_is_0100000;
	assign is_rev8   = is_op_imm & funct3_is_101 & funct7_is_0110100 & rs2_is_11000;
	assign is_rol    = is_op_r_m & funct3_is_001 & funct7_is_0110000;
	assign is_ror    = is_op_r_m & funct3_is_101 & funct7_is_0110000;
	assign is_rori   = is_op_imm & funct3_is_101 & funct7_is_0110000;
	assign is_sext_b = is_op_imm & funct3_is_001 & funct7_is_0110000 & rs2_is_00100;
	assign is_sext_h = is_op_imm & funct3_is_001 & funct7_is_0110000 & rs2_is_00101;
	assign is_xnor   = is_op_r_m & (funct3 == 3'b100) & funct7_is_0100000;
	assign is_zext_h = is_op_r_m & (funct3 == 3'b100) & funct7_is_0000100 & rs2_is_00000;
	assign is_clmul  = is_op_r_m & funct3_is_001 & funct7_is_0000101;
	assign is_clmulh = is_op_r_m & (funct3 == 3'b011) & funct7_is_0000101;
	assign is_clmulr = is_op_r_m & (funct3 == 3'b010) & funct7_is_0000101;
	assign is_bclr   = is_op_r_m & funct3_is_001 & funct7_is_0100100;
	assign is_bclri  = is_op_imm & funct3_is_001 & funct7_is_0100100;
	assign is_bext   = is_op_r_m & funct3_is_101 & funct7_is_0100100;
	assign is_bexti  = is_op_imm & funct3_is_101 & funct7_is_0100100;
	assign is_binv   = is_op_r_m & funct3_is_001 & funct7_is_0110100;
	assign is_binvi  = is_op_imm & funct3_is_001 & funct7_is_0110100;
	assign is_bset   = is_op_r_m & funct3_is_001 & funct7_is_0010100;
	assign is_bseti  = is_op_imm & funct3_is_001 & funct7_is_0010100;
	assign is_brev8  = is_op_imm & funct3_is_101 & funct7_is_0110100 & rs2_is_00111;
	assign is_pack   = is_op_r_m & (funct3 == 3'b100) & funct7_is_0000100 & !rs2_is_00000;
	assign is_packh  = is_op_r_m & (funct3 == 3'b111) & funct7_is_0000100;
	assign is_zip    = is_op_imm & funct3_is_001 & funct7_is_0000100 & rs2_is_01111;
	assign is_unzip  = is_op_imm & funct3_is_101 & funct7_is_0000100 & rs2_is_01111;

	wire r_alu_group0 = is_add | is_sub | is_sll | is_slt;
	wire r_alu_group1 = is_sltu | is_xor | is_srl | is_sra;
	wire r_alu_group2 = is_or | is_and;
	wire is_r_alu_use = (r_alu_group0 | r_alu_group1) | r_alu_group2;
	wire mul_group0 = is_mul | is_mulh | is_mulhsu | is_mulhu;
	wire mul_group1 = is_div | is_divu | is_rem | is_remu;
	wire is_mul_use = mul_group0 | mul_group1;
	wire bitmanip_rs2_group0 = is_sh1add | is_sh2add | is_sh3add | is_andn;
	wire bitmanip_rs2_group1 = is_max | is_maxu | is_min | is_minu;
	wire bitmanip_rs2_group2 = is_orn | is_rol | is_ror | is_xnor;
	wire bitmanip_rs2_group3 = is_clmul | is_clmulh | is_clmulr | is_bclr;
	wire bitmanip_rs2_group4 = is_bext | is_binv | is_bset | is_pack;
	wire bitmanip_rs2_group5 = is_packh;
	wire bitmanip_rs2_half0 = bitmanip_rs2_group0 |
		bitmanip_rs2_group1 | bitmanip_rs2_group2;
	wire bitmanip_rs2_half1 = bitmanip_rs2_group3 |
		bitmanip_rs2_group4 | bitmanip_rs2_group5;
	wire is_bitmanip_rs2_use = bitmanip_rs2_half0 | bitmanip_rs2_half1;
	wire bitmanip_other_group0 = is_clz | is_cpop | is_ctz | is_orc_b;
	wire bitmanip_other_group1 = is_rev8 | is_rori | is_sext_b | is_sext_h;
	wire bitmanip_other_group2 = is_zext_h | is_bclri | is_bexti | is_binvi;
	wire bitmanip_other_group3 = is_bseti | is_brev8 | is_zip | is_unzip;
	wire bitmanip_other_use = (bitmanip_other_group0 |
		bitmanip_other_group1) | (bitmanip_other_group2 |
		bitmanip_other_group3);
	wire is_bitmanip_use = is_bitmanip_rs2_use | bitmanip_other_use;

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
	wire csr_imm = is_csrrwi | is_csrrsi | is_csrrci;


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
	assign csr_op_info[ydrasil_pkg::OP_CSR_WRITE]  =
		is_csrrw | is_csrrwi |
		((is_csrrs | is_csrrsi | is_csrrc | is_csrrci) &&
		 (instr_i[19:15] != '0));

	assign sys_op_info[ydrasil_pkg::OP_SYS_ECALL]  = is_ecall;
	assign sys_op_info[ydrasil_pkg::OP_SYS_EBREAK] = is_ebreak;
	assign sys_op_info[ydrasil_pkg::OP_SYS_MRET]   = is_mret;

	assign mul_op_info[ydrasil_pkg::OP_MUL_MUL]    = is_mul;
	assign mul_op_info[ydrasil_pkg::OP_MUL_MULH]   = is_mulh;
	assign mul_op_info[ydrasil_pkg::OP_MUL_MULHSU] = is_mulhsu;
	assign mul_op_info[ydrasil_pkg::OP_MUL_MULHU]  = is_mulhu;
	assign mul_op_info[ydrasil_pkg::OP_MUL_DIV]    = is_div;
	assign mul_op_info[ydrasil_pkg::OP_MUL_DIVU]   = is_divu;
	assign mul_op_info[ydrasil_pkg::OP_MUL_REM]    = is_rem;
	assign mul_op_info[ydrasil_pkg::OP_MUL_REMU]   = is_remu;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_SH1ADD] = is_sh1add;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_SH2ADD] = is_sh2add;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_SH3ADD] = is_sh3add;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ANDN]   = is_andn;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CLZ]    = is_clz;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CPOP]   = is_cpop;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CTZ]    = is_ctz;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_MAX]    = is_max;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_MAXU]   = is_maxu;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_MIN]    = is_min;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_MINU]   = is_minu;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ORC_B]  = is_orc_b;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ORN]    = is_orn;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_REV8]   = is_rev8;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ROL]    = is_rol;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ROR]    = is_ror;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_RORI]   = is_rori;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_SEXT_B] = is_sext_b;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_SEXT_H] = is_sext_h;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_XNOR]   = is_xnor;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ZEXT_H] = is_zext_h;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CLMUL]  = is_clmul;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CLMULH] = is_clmulh;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_CLMULR] = is_clmulr;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BCLR]   = is_bclr;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BCLRI]  = is_bclri;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BEXT]   = is_bext;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BEXTI]  = is_bexti;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BINV]   = is_binv;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BINVI]  = is_binvi;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BSET]   = is_bset;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BSETI]  = is_bseti;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_BREV8]  = is_brev8;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_PACK]   = is_pack;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_PACKH]  = is_packh;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_ZIP]    = is_zip;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_UNZIP]  = is_unzip;
	assign bitmanip_op_info[ydrasil_pkg::OP_B_RSVD]   = 1'b0;


	wire rf_ren_rs1 =	(~is_lui) 	& (~is_auipc) 	& (~is_jal) &
						(~is_ecall) & (~is_ebreak) & (~is_fence) &
						(~is_nop) 	& (~is_fence_i) & (~csr_imm);// U类型指令不需要rs1
	wire rf_ren_rs2 = is_r_alu_use | is_mul_use | is_branch | is_bitmanip_rs2_use; // R类型和分支指令需要rs2

	wire rf_wen_group0 = is_lui | is_auipc | is_jal | is_jalr;
	wire rf_wen_group1 = is_op_imm | is_r_alu_use;
	wire rf_wen_group2 = is_mul_use | is_bitmanip_use;
	wire rf_wen_rd = (rf_wen_group0 | rf_wen_group1) |
		(rf_wen_group2 | is_csr); // 需要写回寄存器的指令类型

	wire is_alu_use = is_op_imm | is_r_alu_use | is_lui | is_auipc;
	wire is_bjp_use = is_branch | is_jal | is_jalr;


	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_ALU] = is_alu_use;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_BJP] = is_bjp_use;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_LOAD] = is_load;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_STORE] = is_store;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_CSR] = is_csr;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_SYS] = is_sys;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_MUL] = is_mul_use;
	assign operator_type_o [ydrasil_pkg::OPERATOR_TYPE_BITMANIP] = is_bitmanip_use;

	always_comb begin
		uop_class_o = ydrasil_pkg::UOP_CLASS_ALU;
		if (is_bjp_use)
			uop_class_o = ydrasil_pkg::UOP_CLASS_BJP;
		else if (is_load)
			uop_class_o = ydrasil_pkg::UOP_CLASS_LOAD;
		else if (is_store)
			uop_class_o = ydrasil_pkg::UOP_CLASS_STORE;
		else if (is_sys)
			uop_class_o = ydrasil_pkg::UOP_CLASS_SYS;
		else if (is_csr)
			uop_class_o = ydrasil_pkg::UOP_CLASS_CSR;
		else if (is_mul_use)
			uop_class_o = ydrasil_pkg::UOP_CLASS_MUL;
		else if (is_bitmanip_use)
			uop_class_o = ydrasil_pkg::UOP_CLASS_BITMANIP;

		uop_subop_o = '0;
		unique case (uop_class_o)
			ydrasil_pkg::UOP_CLASS_ALU: begin
				unique case (1'b1)
					is_lui:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_LUI);
					is_auipc: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_AUIPC);
					is_addi || is_add: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_ADD);
					is_sub:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SUB);
					is_slli || is_sll: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SLL);
					is_slti || is_slt: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SLT);
					is_sltiu || is_sltu: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SLTU);
					is_xori || is_xor: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_XOR);
					is_srli || is_srl: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SRL);
					is_srai || is_sra: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_SRA);
					is_ori || is_or: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_OR);
					is_andi || is_and: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_ALU_AND);
					default: uop_subop_o = '0;
				endcase
			end
			ydrasil_pkg::UOP_CLASS_BJP: begin
				unique case (1'b1)
					is_jal || is_jalr: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_JUMP);
					is_beq:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BEQ);
					is_bne:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BNE);
					is_blt:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BLT);
					is_bge:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BGE);
					is_bltu: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BLTU);
					is_bgeu: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_BJP_BGEU);
					default: uop_subop_o = '0;
				endcase
			end
			ydrasil_pkg::UOP_CLASS_MUL:
				uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(funct3);
			ydrasil_pkg::UOP_CLASS_BITMANIP: begin
				unique case (1'b1)
					is_sh1add: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_SH1ADD);
					is_sh2add: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_SH2ADD);
					is_sh3add: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_SH3ADD);
					is_andn:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ANDN);
					is_clz:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CLZ);
					is_cpop:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CPOP);
					is_ctz:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CTZ);
					is_max:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_MAX);
					is_maxu:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_MAXU);
					is_min:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_MIN);
					is_minu:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_MINU);
					is_orc_b:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ORC_B);
					is_orn:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ORN);
					is_rev8:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_REV8);
					is_rol:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ROL);
					is_ror:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ROR);
					is_rori:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_RORI);
					is_sext_b: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_SEXT_B);
					is_sext_h: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_SEXT_H);
					is_xnor:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_XNOR);
					is_zext_h: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ZEXT_H);
					is_clmul:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CLMUL);
					is_clmulh: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CLMULH);
					is_clmulr: uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_CLMULR);
					is_bclr:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BCLR);
					is_bclri:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BCLRI);
					is_bext:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BEXT);
					is_bexti:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BEXTI);
					is_binv:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BINV);
					is_binvi:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BINVI);
					is_bset:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BSET);
					is_bseti:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BSETI);
					is_brev8:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_BREV8);
					is_pack:   uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_PACK);
					is_packh:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_PACKH);
					is_zip:    uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_ZIP);
					is_unzip:  uop_subop_o = ydrasil_pkg::UOP_SUBOP_WIDTH'(ydrasil_pkg::OP_B_UNZIP);
					default: uop_subop_o = '0;
				endcase
			end
			default: uop_subop_o = '0;
		endcase

		uop_lsu_subop_o = '0;
		unique case (1'b1)
			is_lb:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_LB);
			is_lh:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_LH);
			is_lw:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_LW);
			is_lbu: uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_LBU);
			is_lhu: uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_LHU);
			is_sb:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_SB);
			is_sh:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_SH);
			is_sw:  uop_lsu_subop_o = ydrasil_pkg::UOP_LSU_SUBOP_WIDTH'(ydrasil_pkg::OP_LSU_SW);
			default: uop_lsu_subop_o = '0;
		endcase
	end

	assign full_bitmanip_o = is_bitmanip_use &&
		!(is_sh1add || is_sh2add || is_sh3add || is_andn || is_orn ||
		  is_xnor || is_min || is_max || is_minu || is_maxu || is_rev8 ||
		  is_sext_b || is_sext_h || is_zext_h);
	assign divrem_o = is_div || is_divu || is_rem || is_remu;
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

	assign operator_o = ({ydrasil_pkg::OPERATOR_WIDTH{is_alu_use }}& {{(ydrasil_pkg::OPERATOR_WIDTH-ydrasil_pkg::OP_ALU_INFO_WIDTH){1'b0}},alu_op_info})|
						({ydrasil_pkg::OPERATOR_WIDTH{is_bjp_use }}& {{(ydrasil_pkg::OPERATOR_WIDTH-ydrasil_pkg::OP_BJP_INFO_WIDTH){1'b0}},bjp_op_info}) |
						({ydrasil_pkg::OPERATOR_WIDTH{is_mul_use }}& {{(ydrasil_pkg::OPERATOR_WIDTH-ydrasil_pkg::OP_MUL_INFO_WIDTH){1'b0}},mul_op_info}) |
						({ydrasil_pkg::OPERATOR_WIDTH{is_bitmanip_use }}& bitmanip_op_info);
	assign operator_lsu_o = lsu_op_info;

	wire operand_b_rs_sel 	;
	wire operand_a_pc_sel 	;
	wire operand_a_imm_sel	;
	wire bt_a_rs_sel 		;

	assign operand_a_imm_sel = csr_imm;

	assign operand_b_rs_sel = is_branch | is_r_alu_use | is_mul_use | is_bitmanip_rs2_use;
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
