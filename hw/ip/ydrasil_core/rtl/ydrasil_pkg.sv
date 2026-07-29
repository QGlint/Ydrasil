
package ydrasil_pkg;
	// Memory and address configuration
	localparam int ITCM_ADDR_WIDTH = 13; // 32KB target for expanded images
	localparam int DTCM_ADDR_WIDTH = 16; // 256KB

	localparam logic [31:0] ITCM_BASE_ADDR = 32'h8000_0000;
	localparam int ITCM_SIZE = (1 << ITCM_ADDR_WIDTH);
	localparam logic [31:0] DTCM_BASE_ADDR = 32'h8010_0000;
	localparam int DTCM_SIZE = (1 << DTCM_ADDR_WIDTH);

`ifdef INIT_ITCM
	localparam int INIT_ITCM = `INIT_ITCM;
`else
	localparam int INIT_ITCM = 1;
`endif

`ifdef ITCM_INIT_FILE
	localparam string ITCM_INIT_FILE = `ITCM_INIT_FILE;
`else
	localparam string ITCM_INIT_FILE = "hw/dv/test_data/mem_generated/rv32ui-p-add.mem";
`endif

`ifdef INIT_DTCM
	localparam int INIT_DTCM = `INIT_DTCM;
`else
	localparam int INIT_DTCM = 1;
`endif

`ifdef DTCM_INIT_FILE
	localparam string DTCM_INIT_FILE = `DTCM_INIT_FILE;
`else
	localparam string DTCM_INIT_FILE = "hw/dv/test_data/mem/dram_test.mem";
`endif

	localparam int DIV_MODE_LZC = 0;
	localparam int DIV_MODE = DIV_MODE_LZC;

	// Bus and instruction widths
	localparam int BUS_DATA_WIDTH = 32;
	localparam int BUS_ADDR_WIDTH = 32;
	localparam int INST_DATA_WIDTH = 32;
	localparam int INST_ADDR_WIDTH = 32;

	// Register configuration
	localparam int REGS_ADDR_WIDTH = 5;
	localparam int REGS_DATA_WIDTH = 32;
	localparam int DOUBLE_REGS_WIDTH = 64;
	localparam int REGS_NUM = 32;
	localparam int CSR_ADDR_WIDTH = 12;

	// CSR addresses
	localparam logic [11:0] CSR_CYCLE         = 12'hc00;
	localparam logic [11:0] CSR_TIME          = 12'hc01;
	localparam logic [11:0] CSR_INSTRET       = 12'hc02;
	localparam logic [11:0] CSR_CYCLEH        = 12'hc80;
	localparam logic [11:0] CSR_TIMEH         = 12'hc81;
	localparam logic [11:0] CSR_INSTRETH      = 12'hc82;
	localparam logic [11:0] CSR_MCYCLE        = 12'hb00;
	localparam logic [11:0] CSR_MINSTRET      = 12'hb02;
	localparam logic [11:0] CSR_MCYCLEH       = 12'hb80;
	localparam logic [11:0] CSR_MINSTRETH     = 12'hb82;
	localparam logic [11:0] CSR_MSTATUS       = 12'h300;
	localparam logic [11:0] CSR_MISA          = 12'h301;
	localparam logic [11:0] CSR_MEDELEG       = 12'h302;
	localparam logic [11:0] CSR_MIDELEG       = 12'h303;
	localparam logic [11:0] CSR_MIE           = 12'h304;
	localparam logic [11:0] CSR_MTVEC         = 12'h305;
	localparam logic [11:0] CSR_MCOUNTEREN    = 12'h306;
	localparam logic [11:0] CSR_MCOUNTINHIBIT = 12'h320;
	localparam logic [11:0] CSR_MSCRATCH      = 12'h340;
	localparam logic [11:0] CSR_MEPC          = 12'h341;
	localparam logic [11:0] CSR_MCAUSE        = 12'h342;
	localparam logic [11:0] CSR_MTVAL         = 12'h343;
	localparam logic [11:0] CSR_MIP           = 12'h344;
	localparam logic [11:0] CSR_MVENDORID     = 12'hf11;
	localparam logic [11:0] CSR_MARCHID       = 12'hf12;
	localparam logic [11:0] CSR_MIMPID        = 12'hf13;
	localparam logic [31:0] MARCHID_VALUE     = 32'd5;
	localparam logic [11:0] CSR_MHARTID       = 12'hf14;
	localparam logic [11:0] CSR_FFLAGS        = 12'h001;
	localparam logic [11:0] CSR_FRM           = 12'h002;
	localparam logic [11:0] CSR_FCSR          = 12'h003;

	// RV32I instruction encodings
	localparam logic [6:0] RV32I_INS_TYPE_I   = 7'b0010011;
	localparam logic [2:0] RV32I_INS_ADDI     = 3'b000;
	localparam logic [2:0] RV32I_INS_SLTI     = 3'b010;
	localparam logic [2:0] RV32I_INS_SLTIU    = 3'b011;
	localparam logic [2:0] RV32I_INS_XORI     = 3'b100;
	localparam logic [2:0] RV32I_INS_ORI      = 3'b110;
	localparam logic [2:0] RV32I_INS_ANDI     = 3'b111;
	localparam logic [2:0] RV32I_INS_SLLI     = 3'b001;
	localparam logic [2:0] RV32I_INS_SRI      = 3'b101;

	localparam logic [6:0] RV32I_INS_TYPE_L   = 7'b0000011;
	localparam logic [2:0] RV32I_INS_LB       = 3'b000;
	localparam logic [2:0] RV32I_INS_LH       = 3'b001;
	localparam logic [2:0] RV32I_INS_LW       = 3'b010;
	localparam logic [2:0] RV32I_INS_LBU      = 3'b100;
	localparam logic [2:0] RV32I_INS_LHU      = 3'b101;

	localparam logic [6:0] RV32I_INS_TYPE_S   = 7'b0100011;
	localparam logic [2:0] RV32I_INS_SB       = 3'b000;
	localparam logic [2:0] RV32I_INS_SH       = 3'b001;
	localparam logic [2:0] RV32I_INS_SW       = 3'b010;

	localparam logic [6:0] RV32I_INS_TYPE_R_M = 7'b0110011;
	localparam logic [2:0] RV32I_INS_ADD_SUB  = 3'b000;
	localparam logic [2:0] RV32I_INS_SLL      = 3'b001;
	localparam logic [2:0] RV32I_INS_SLT      = 3'b010;
	localparam logic [2:0] RV32I_INS_SLTU     = 3'b011;
	localparam logic [2:0] RV32I_INS_XOR      = 3'b100;
	localparam logic [2:0] RV32I_INS_SR       = 3'b101;
	localparam logic [2:0] RV32I_INS_OR       = 3'b110;
	localparam logic [2:0] RV32I_INS_AND      = 3'b111;

	localparam logic [2:0] RV32I_INS_MUL      = 3'b000;
	localparam logic [2:0] RV32I_INS_MULH     = 3'b001;
	localparam logic [2:0] RV32I_INS_MULHSU   = 3'b010;
	localparam logic [2:0] RV32I_INS_MULHU    = 3'b011;
	localparam logic [2:0] RV32I_INS_DIV      = 3'b100;
	localparam logic [2:0] RV32I_INS_DIVU     = 3'b101;
	localparam logic [2:0] RV32I_INS_REM      = 3'b110;
	localparam logic [2:0] RV32I_INS_REMU     = 3'b111;

	localparam logic [6:0] RV32I_INS_JAL      = 7'b1101111;
	localparam logic [6:0] RV32I_INS_JALR     = 7'b1100111;
	localparam logic [6:0] RV32I_INS_LUI      = 7'b0110111;
	localparam logic [6:0] RV32I_INS_AUIPC    = 7'b0010111;
	localparam logic [31:0] RV32I_INS_RET     = 32'h00008067;

	localparam logic [6:0] RV32I_INS_TYPE_B   = 7'b1100011;
	localparam logic [2:0] RV32I_INS_BEQ      = 3'b000;
	localparam logic [2:0] RV32I_INS_BNE      = 3'b001;
	localparam logic [2:0] RV32I_INS_BLT      = 3'b100;
	localparam logic [2:0] RV32I_INS_BGE      = 3'b101;
	localparam logic [2:0] RV32I_INS_BLTU     = 3'b110;
	localparam logic [2:0] RV32I_INS_BGEU     = 3'b111;

	localparam logic [6:0] RV32I_INS_FENCE    = 7'b0001111;

	localparam logic [31:0] RV32I_INS_NOP     = 32'h00000013;
	localparam logic [31:0] RV32I_INS_ECALL   = 32'h00000073;
	localparam logic [31:0] RV32I_INS_EBREAK  = 32'h00100073;
	localparam logic [31:0] RV32I_INS_MRET    = 32'h30200073;
	localparam logic [31:0] RV32I_INS_DRET    = 32'h7b200073;
	localparam logic [31:0] RESET_INS         = 32'h8000_0000;

	localparam logic [6:0] RV32I_INS_CSR      = 7'b1110011;
	localparam logic [2:0] RV32I_INS_CSRRW    = 3'b001;
	localparam logic [2:0] RV32I_INS_CSRRS    = 3'b010;
	localparam logic [2:0] RV32I_INS_CSRRC    = 3'b011;
	localparam logic [2:0] RV32I_INS_CSRRWI   = 3'b101;
	localparam logic [2:0] RV32I_INS_CSRRSI   = 3'b110;
	localparam logic [2:0] RV32I_INS_CSRRCI   = 3'b111;

	// Decode constants
	localparam int OPERATOR_TYPE_WIDTH = 9;
	localparam int OPERATOR_TYPE_ALU   = 0;
	localparam int OPERATOR_TYPE_BJP   = 1;
	localparam int OPERATOR_TYPE_LOAD  = 2;
	localparam int OPERATOR_TYPE_STORE = 3;
	localparam int OPERATOR_TYPE_CSR   = 4;
	localparam int OPERATOR_TYPE_SYS   = 5;
	localparam int OPERATOR_TYPE_MUL   = 6;
	localparam int OPERATOR_TYPE_BITMANIP = 7;
	localparam int OPERATOR_TYPE_FPU   = 8;
		localparam int OPERATOR_TYPE_LSU_BASE = 2;
		localparam int RESOURCE_WIDTH = 6;
		localparam int RESOURCE_ALU = 0;
		localparam int RESOURCE_FULL_BITMANIP = 1;
		localparam int RESOURCE_BRU = 2;
		localparam int RESOURCE_LSU = 3;
		localparam int RESOURCE_MULDIV = 4;
		localparam int RESOURCE_SERIAL = 5;
		// ALU and bitmanip have one copy per execution lane. BRU, LSU, MULDIV
		// and serial resources remain single-owner.
		localparam logic [RESOURCE_WIDTH-1:0] RESOURCE_EXCLUSIVE_MASK = 6'b11_1100;

	localparam int OPERATOR_WIDTH = 40;

	localparam int OP_ALU_INFO_WIDTH = 12;
	localparam int OP_ALU_LUI   = 0;
	localparam int OP_ALU_AUIPC = 1;
	localparam int OP_ALU_ADD   = 2;
	localparam int OP_ALU_SUB   = 3;
	localparam int OP_ALU_SLL   = 4;
	localparam int OP_ALU_SLT   = 5;
	localparam int OP_ALU_SLTU  = 6;
	localparam int OP_ALU_XOR   = 7;
	localparam int OP_ALU_SRL   = 8;
	localparam int OP_ALU_SRA   = 9;
	localparam int OP_ALU_OR    = 10;
	localparam int OP_ALU_AND   = 11;

	localparam int OP_BJP_INFO_WIDTH = 7;
	localparam int OP_BJP_JUMP = 0;
	localparam int OP_BJP_BEQ  = 1;
	localparam int OP_BJP_BNE  = 2;
	localparam int OP_BJP_BLT  = 3;
	localparam int OP_BJP_BGE  = 4;
	localparam int OP_BJP_BLTU = 5;
	localparam int OP_BJP_BGEU = 6;

	localparam int OP_LSU_INFO_WIDTH  = 8;
	localparam int OP_LOAD_INFO_WIDTH = 5;
	localparam int OP_LSU_LB  = 0;
	localparam int OP_LSU_LH  = 1;
	localparam int OP_LSU_LW  = 2;
	localparam int OP_LSU_LBU = 3;
	localparam int OP_LSU_LHU = 4;
	localparam int OP_LSU_SB  = 5;
	localparam int OP_LSU_SH  = 6;
	localparam int OP_LSU_SW  = 7;

	localparam int OP_CSR_INFO_WIDTH = 4;
	localparam int OP_CSR_CSRRW = 0;
	localparam int OP_CSR_CSRRS = 1;
	localparam int OP_CSR_CSRRC = 2;
	localparam int OP_CSR_WRITE = 3;

	localparam int OP_SYS_INFO_WIDTH = 3;
	localparam int OP_SYS_ECALL  = 0;
	localparam int OP_SYS_EBREAK = 1;
	localparam int OP_SYS_MRET   = 2;

	localparam int OP_MUL_INFO_WIDTH = 8;
	localparam int OP_MUL_MUL    = 0;
	localparam int OP_MUL_MULH   = 1;
	localparam int OP_MUL_MULHSU = 2;
	localparam int OP_MUL_MULHU  = 3;
	localparam int OP_MUL_DIV    = 4;
	localparam int OP_MUL_DIVU   = 5;
	localparam int OP_MUL_REM    = 6;
	localparam int OP_MUL_REMU   = 7;

	localparam int OP_B_INFO_WIDTH = 40;
	localparam int OP_B_SH1ADD = 0;
	localparam int OP_B_SH2ADD = 1;
	localparam int OP_B_SH3ADD = 2;
	localparam int OP_B_ANDN   = 3;
	localparam int OP_B_CLZ    = 4;
	localparam int OP_B_CPOP   = 5;
	localparam int OP_B_CTZ    = 6;
	localparam int OP_B_MAX    = 7;
	localparam int OP_B_MAXU   = 8;
	localparam int OP_B_MIN    = 9;
	localparam int OP_B_MINU   = 10;
	localparam int OP_B_ORC_B  = 11;
	localparam int OP_B_ORN    = 12;
	localparam int OP_B_REV8   = 13;
	localparam int OP_B_ROL    = 14;
	localparam int OP_B_ROR    = 15;
	localparam int OP_B_RORI   = 16;
	localparam int OP_B_SEXT_B = 17;
	localparam int OP_B_SEXT_H = 18;
	localparam int OP_B_XNOR   = 19;
	localparam int OP_B_ZEXT_H = 20;
	localparam int OP_B_CLMUL  = 21;
	localparam int OP_B_CLMULH = 22;
	localparam int OP_B_CLMULR = 23;
	localparam int OP_B_BCLR   = 24;
	localparam int OP_B_BCLRI  = 25;
	localparam int OP_B_BEXT   = 26;
	localparam int OP_B_BEXTI  = 27;
	localparam int OP_B_BINV   = 28;
	localparam int OP_B_BINVI  = 29;
	localparam int OP_B_BSET   = 30;
	localparam int OP_B_BSETI  = 31;
	localparam int OP_B_BREV8  = 32;
	localparam int OP_B_PACK   = 33;
	localparam int OP_B_PACKH  = 34;
	localparam int OP_B_ZIP    = 35;
	localparam int OP_B_UNZIP  = 36;
	localparam int OP_B_XPERM4 = 37;
	localparam int OP_B_XPERM8 = 38;
	localparam int OP_B_RSVD   = 39;

	typedef enum logic [4:0] {
		FPU_OP_FMADD, FPU_OP_FMSUB, FPU_OP_FNMSUB, FPU_OP_FNMADD,
		FPU_OP_ADD, FPU_OP_SUB, FPU_OP_MUL, FPU_OP_DIV, FPU_OP_SQRT,
		FPU_OP_SGNJ, FPU_OP_SGNJN, FPU_OP_SGNJX, FPU_OP_MIN, FPU_OP_MAX,
		FPU_OP_EQ, FPU_OP_LT, FPU_OP_LE, FPU_OP_CLASS,
		FPU_OP_CVT_W_S, FPU_OP_CVT_WU_S, FPU_OP_CVT_S_W, FPU_OP_CVT_S_WU,
		FPU_OP_MV_X_W, FPU_OP_MV_W_X, FPU_OP_FLW, FPU_OP_FSW
	} ydrasil_fpu_op_t;

	localparam int OPSEL_INFO_WIDTH = 3;
	localparam int ASELRS   = 0;
	localparam int BSELRS   = 1;
	localparam int BTASELRS = 2;

	localparam int BP_BTB_ENTRIES = 512;
	localparam int BP_BHT_ENTRIES = 512;
	// Future File: each producer carries its value independently of the two
	// architectural writeback ports.
	localparam int PRODUCER_NUM = 8;
	localparam int PRODUCER_SLOT_WIDTH = $clog2(PRODUCER_NUM);
	localparam int PRODUCER_ID_WIDTH = PRODUCER_SLOT_WIDTH + 1;
	typedef logic [PRODUCER_SLOT_WIDTH-1:0] producer_slot_t;
	typedef logic [PRODUCER_ID_WIDTH-1:0] producer_id_t;
	typedef enum logic [1:0] {
		RESULT_ALU  = 2'b00,
		RESULT_LSU  = 2'b01,
		RESULT_MDU  = 2'b10,
		RESULT_NONE = 2'b11
	} ydrasil_result_class_t;

	typedef struct packed {
		logic                         used;
		logic [REGS_ADDR_WIDTH-1:0]   arch_addr;
		logic                         tag_valid;
		producer_id_t                 producer_tag;
		ydrasil_result_class_t        producer_class;
	} ydrasil_source_desc_t;

	typedef struct packed {
		logic                         writes_gpr;
		logic [REGS_ADDR_WIDTH-1:0]   rd_addr;
		producer_id_t                 rob_tag;
		ydrasil_result_class_t        result_class;
	} ydrasil_dest_desc_t;

	typedef struct packed {
		logic                         valid;
		logic                         done;
		logic                         writes_gpr;
		logic [REGS_ADDR_WIDTH-1:0]   rd_addr;
		producer_id_t                 tag;
		ydrasil_result_class_t        result_class;
		logic [INST_ADDR_WIDTH-1:0]   pc;
		logic [2:0]                   op_class;
		logic [2:0]                   exception_code;
	} ydrasil_rob_entry_t;
	typedef struct packed {
		logic                         live;
		logic                         done;
		logic [REGS_DATA_WIDTH-1:0]   result;
	} ydrasil_rob_source_state_t;
	typedef enum logic [1:0] {
		BYPASS_NONE  = 2'b00,
		BYPASS_LANE0 = 2'b01,
		BYPASS_LANE1 = 2'b10
	} ydrasil_bypass_sel_t;
	localparam int COMPLETION_LANES = 4;
	localparam int COMPLETION_ALU = 0;
	localparam int COMPLETION_LSU = 1;
	localparam int COMPLETION_MUL = 2;
	localparam int COMPLETION_DUAL_ALU = 3;

	typedef struct packed {
		logic [INST_ADDR_WIDTH-1:0]          pc;
		logic [INST_DATA_WIDTH-1:0]          instr;
		logic                                pred_hit;
		logic                                pred_taken;
		logic [INST_ADDR_WIDTH-1:0]          pred_target;
		logic [1:0]                          pred_counter;
		logic [INST_ADDR_WIDTH-1:0]          pred_bht_index;
		logic [REGS_ADDR_WIDTH-1:0]          rs1_addr;
		logic [REGS_ADDR_WIDTH-1:0]          rs2_addr;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		logic                                rs1_ren;
		logic                                rs2_ren;
		logic                                rd_wen;
		logic [REGS_DATA_WIDTH-1:0]          imm;
		logic                                operand_b_rs_sel;
		logic                                operand_a_pc_sel;
		logic                                operand_a_imm_sel;
		logic                                bt_a_rs_sel;
		logic                                operand_b_jump_sel;
		logic [OPERATOR_WIDTH-1:0]           operator_info;
		logic [OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
			logic [OPERATOR_TYPE_WIDTH-1:0]      operator_type;
			logic [RESOURCE_WIDTH-1:0]           resources;
		logic [CSR_ADDR_WIDTH-1:0]           csr_raddr;
		logic [CSR_ADDR_WIDTH-1:0]           csr_waddr;
		logic [OP_CSR_INFO_WIDTH-1:0]        csr_op_info;
		logic [OP_SYS_INFO_WIDTH-1:0]        sys_op_info;
		logic                                fence_i;
		logic                                fp_valid;
		logic                                fp_illegal;
		ydrasil_fpu_op_t                     fp_op;
		logic [2:0]                          fp_rm;
		logic [REGS_ADDR_WIDTH-1:0]          fp_rs1_addr;
		logic [REGS_ADDR_WIDTH-1:0]          fp_rs2_addr;
		logic [REGS_ADDR_WIDTH-1:0]          fp_rs3_addr;
		logic [REGS_ADDR_WIDTH-1:0]          fp_rd_addr;
		logic                                fp_rs1_fpr;
		logic                                fp_rs2_fpr;
		logic                                fp_rs3_fpr;
		logic                                fp_rd_fpr;
		logic                                fp_rd_gpr;
	} ydrasil_decode_pkt_t;

	typedef struct packed {
		logic                                valid;
		producer_id_t                        producer_id;
		logic                                conditional;
		logic [INST_ADDR_WIDTH-1:0]          pc;
		logic                                taken;
		logic [INST_ADDR_WIDTH-1:0]          target;
		logic [1:0]                          counter;
		logic [INST_ADDR_WIDTH-1:0]          bht_index;
	} ydrasil_bp_train_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic [REGS_ADDR_WIDTH-1:0]          rs1_addr;
		logic [REGS_ADDR_WIDTH-1:0]          rs2_addr;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		logic                                rs1_ren;
		logic                                rs2_ren;
		logic                                rd_wen;
		logic                                lsu_req;
		logic                                store_req;
		logic                                serialize_before;
		logic                                checkpoint_req;
	} ydrasil_id_ctrl_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic                                illegal;
		ydrasil_fpu_op_t                     op;
		logic [2:0]                          rm;
		logic [REGS_DATA_WIDTH-1:0]          operand_a;
		logic [REGS_DATA_WIDTH-1:0]          operand_b;
		logic [REGS_DATA_WIDTH-1:0]          operand_c;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		logic                                rd_fpr;
		logic                                rd_gpr;
		producer_id_t                        producer_id;
		logic                                producer_tracked;
		logic [INST_ADDR_WIDTH-1:0]          pc;
		logic [INST_DATA_WIDTH-1:0]          instr;
	} ydrasil_fpu_req_pkt_t;

	typedef struct packed {
		logic                                valid;
		producer_id_t                        producer_id;
		logic                                producer_tracked;
		logic [REGS_ADDR_WIDTH-1:0]          addr;
		logic [REGS_DATA_WIDTH-1:0]          data;
	} ydrasil_gpr_fwd_pkt_t;

	typedef ydrasil_gpr_fwd_pkt_t ydrasil_completion_bus_t [COMPLETION_LANES];

	typedef struct packed {
		logic                                valid;
		logic                                writes_gpr;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		logic [REGS_DATA_WIDTH-1:0]          value;
		logic [INST_ADDR_WIDTH-1:0]          pc;
	} ydrasil_commit_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic                                interrupt;
		logic                                flush_younger;
		producer_id_t                        producer_id;
		logic                                producer_tracked;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		logic                                alu_rf_wen;
		logic [OPERATOR_TYPE_WIDTH-1:0]      operator_type;
		logic [OPERATOR_WIDTH-1:0]           operator_info;
	} ydrasil_ex_hzd_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic                                is_load;
		logic                                is_store;
		logic [OP_LSU_INFO_WIDTH-1:0]        op;
		logic [BUS_ADDR_WIDTH-1:0]           addr;
		logic                                addr_is_dtcm;
		logic [REGS_ADDR_WIDTH-1:0]          rd_addr;
		producer_id_t                        producer_id;
		logic                                producer_tracked;
		logic [BUS_DATA_WIDTH-1:0]           store_data;
		logic [3:0]                          store_mask;
		logic                                store_data_valid;
		logic                                fp_load;
		logic [REGS_ADDR_WIDTH-1:0]          fp_rd_addr;
	} ydrasil_lsu_req_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic                                write;
		logic [BUS_ADDR_WIDTH-1:0]           addr;
		logic [BUS_DATA_WIDTH-1:0]           wdata;
		logic [3:0]                          wmask;
	} ydrasil_mem_req_pkt_t;

	typedef struct packed {
		ydrasil_mem_req_pkt_t                load;
		ydrasil_mem_req_pkt_t                store;
	} ydrasil_dtcm_req_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic [BUS_DATA_WIDTH-1:0]           rdata;
		logic                                error;
	} ydrasil_mem_rsp_pkt_t;

	typedef struct packed {
		logic                                software;
		logic                                timer;
		logic                                external;
	} ydrasil_irq_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic                                ecall;
		logic                                ebreak;
		logic                                illegal;
		logic                                mret;
		logic [INST_ADDR_WIDTH-1:0]          pc;
		logic [INST_DATA_WIDTH-1:0]          tval;
	} ydrasil_exception_req_pkt_t;

	typedef struct packed {
		logic [REGS_DATA_WIDTH-1:0]          mtvec;
		logic [REGS_DATA_WIDTH-1:0]          mepc;
		logic [REGS_DATA_WIDTH-1:0]          mstatus;
		logic [REGS_DATA_WIDTH-1:0]          mie;
		logic [REGS_DATA_WIDTH-1:0]          mip;
	} ydrasil_csr_trap_state_pkt_t;

	typedef struct packed {
		logic                                valid;
		logic [CSR_ADDR_WIDTH-1:0]           addr;
		logic [REGS_DATA_WIDTH-1:0]          data;
	} ydrasil_csr_write_pkt_t;

	typedef struct packed {
		logic                                stall;
		logic                                retire;
		logic                                redirect;
		logic [INST_ADDR_WIDTH-1:0]          redirect_addr;
	} ydrasil_trap_ctrl_pkt_t;

	typedef struct packed {
		logic                                busy;
		logic                                idle;
		logic                                fast_load;
	} ydrasil_lsu_status_pkt_t;

	typedef struct packed {
		logic                                  valid;
		logic                                  memory_op;
		logic [1:0]                            lane_mask;
		ydrasil_source_desc_t                  src0;
		ydrasil_source_desc_t                  src1;
		ydrasil_dest_desc_t                    dst;
		logic [INST_ADDR_WIDTH-1:0]            target;
		logic [INST_ADDR_WIDTH-1:0]            next_pc;
		ydrasil_id_ctrl_pkt_t                  ctrl;
		ydrasil_decode_pkt_t                   decode;
	} ydrasil_issue_pkt_t;

	// Registered Issue/EX contract. Operand selection, typed result lookup and
	// final lane steering terminate before this packet is produced.
	typedef struct packed {
		logic [REGS_DATA_WIDTH-1:0]           operand_a;
		logic [REGS_DATA_WIDTH-1:0]           operand_b;
		logic [OPERATOR_WIDTH-1:0]            operator_info;
		logic [OPERATOR_TYPE_WIDTH-1:0]       operator_type;
		logic                                valid;
		logic                                jalr;
		logic [INST_ADDR_WIDTH-1:0]           branch_target;
		logic [INST_ADDR_WIDTH-1:0]           branch_next_pc;
		logic                                branch_eq;
		logic                                branch_ge_signed;
		logic                                branch_ge_unsigned;
		logic [REGS_DATA_WIDTH-1:0]           bt_a_operand;
		logic [REGS_DATA_WIDTH-1:0]           bt_b_operand;
		logic                                pred_hit;
		logic                                pred_taken;
		logic [INST_ADDR_WIDTH-1:0]           pred_target;
		logic [1:0]                          pred_counter;
		logic [INST_ADDR_WIDTH-1:0]           pred_bht_index;
		logic [CSR_ADDR_WIDTH-1:0]            csr_raddr;
		logic [CSR_ADDR_WIDTH-1:0]            csr_waddr;
		logic [OP_CSR_INFO_WIDTH-1:0]         csr_op_info;
		logic [OP_SYS_INFO_WIDTH-1:0]         sys_op_info;
		logic [INST_ADDR_WIDTH-1:0]           pc;
		logic                                rd_wen;
		logic [REGS_ADDR_WIDTH-1:0]           rd_addr;
		producer_id_t                        producer_id;
		logic                                producer_tracked;
		ydrasil_lsu_req_pkt_t                lsu_req;
		ydrasil_fpu_req_pkt_t                fpu_req;
		logic [REGS_DATA_WIDTH-1:0]           lane1_operand_a;
		logic [REGS_DATA_WIDTH-1:0]           lane1_operand_b;
		logic [REGS_DATA_WIDTH-1:0]           lane1_branch_operand_a;
		logic [REGS_DATA_WIDTH-1:0]           lane1_branch_operand_b;
		logic [REGS_DATA_WIDTH-1:0]           lane1_branch_imm;
		logic [OPERATOR_WIDTH-1:0]            lane1_operator_info;
		logic [OPERATOR_TYPE_WIDTH-1:0]       lane1_operator_type;
		logic [OP_LSU_INFO_WIDTH-1:0]         lane1_operator_lsu;
			logic [REGS_DATA_WIDTH-1:0]           lane1_store_data;
			logic                                lane1_store_data_valid;
		logic [REGS_ADDR_WIDTH-1:0]           lane1_rd_addr;
		logic                                lane1_rd_wen;
		producer_id_t                        lane1_producer_id;
		logic                                lane1_producer_tracked;
		logic                                lane1_valid;
		logic [INST_ADDR_WIDTH-1:0]           lane1_pc;
		logic [INST_DATA_WIDTH-1:0]           lane1_instr;
		logic                                lane1_jalr;
		logic [INST_ADDR_WIDTH-1:0]           lane1_branch_target;
		logic [INST_ADDR_WIDTH-1:0]           lane1_branch_next_pc;
		logic                                lane1_pred_hit;
		logic                                lane1_pred_taken;
		logic [INST_ADDR_WIDTH-1:0]           lane1_pred_target;
		logic [1:0]                          lane1_pred_counter;
		logic [INST_ADDR_WIDTH-1:0]           lane1_pred_bht_index;
	} ydrasil_issue_ex_pkt_t;

endpackage
