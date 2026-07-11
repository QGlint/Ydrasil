
package ydrasil_pkg;
	// Memory and address configuration
	localparam int ITCM_ADDR_WIDTH = 13; // 32KB
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

	localparam int LSU_MODE_NEW = 0;
	localparam int LSU_MODE_LEGACY = 1;
`ifdef YDRASIL_LSU_IMPL_LEGACY
	localparam int LSU_MODE = LSU_MODE_LEGACY;
`elsif YDRASIL_LSU_IMPL_NEW
	localparam int LSU_MODE = LSU_MODE_NEW;
`else
	localparam int LSU_MODE = LSU_MODE_LEGACY;
`endif

	localparam int MEMS_MODE_NEW = 0;
	localparam int MEMS_MODE_LEGACY = 1;
`ifdef YDRASIL_MEMS_IMPL_LEGACY
	localparam int MEMS_MODE = MEMS_MODE_LEGACY;
`elsif YDRASIL_MEMS_IMPL_NEW
	localparam int MEMS_MODE = MEMS_MODE_NEW;
`else
	localparam int MEMS_MODE = MEMS_MODE_NEW;
`endif

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
	localparam logic [11:0] CSR_MHARTID       = 12'hf14;

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
	localparam int OPERATOR_TYPE_WIDTH = 8;
	localparam int OPERATOR_TYPE_ALU   = 0;
	localparam int OPERATOR_TYPE_BJP   = 1;
	localparam int OPERATOR_TYPE_LOAD  = 2;
	localparam int OPERATOR_TYPE_STORE = 3;
	localparam int OPERATOR_TYPE_CSR   = 4;
	localparam int OPERATOR_TYPE_SYS   = 5;
	localparam int OPERATOR_TYPE_MUL   = 6;
	localparam int OPERATOR_TYPE_BITMANIP = 7;
	localparam int OPERATOR_TYPE_LSU_BASE = 2;

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

	localparam int OP_CSR_INFO_WIDTH = 3;
	localparam int OP_CSR_CSRRW = 0;
	localparam int OP_CSR_CSRRS = 1;
	localparam int OP_CSR_CSRRC = 2;

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

	localparam int OPSEL_INFO_WIDTH = 3;
	localparam int ASELRS   = 0;
	localparam int BSELRS   = 1;
	localparam int BTASELRS = 2;

	localparam int BP_BTB_ENTRIES = 512;
	localparam int BP_BHT_ENTRIES = 512;

	typedef logic [REGS_ADDR_WIDTH-1:0] gpr_addr_t;
	typedef logic [REGS_DATA_WIDTH-1:0] xlen_t;
	typedef logic [INST_DATA_WIDTH-1:0] instr_t;
	typedef logic [INST_ADDR_WIDTH-1:0] pc_t;
	typedef logic [5:0] preg_t;
	typedef logic [5:0] rob_idx_t;
	typedef logic [CSR_ADDR_WIDTH-1:0] csr_addr_t;
	typedef logic [OPERATOR_WIDTH-1:0] alu_op_t;
	typedef logic [OP_LSU_INFO_WIDTH-1:0] lsu_op_t;
	typedef logic [OPERATOR_TYPE_WIDTH-1:0] op_type_t;
	typedef logic [OP_CSR_INFO_WIDTH-1:0] csr_op_t;
	typedef logic [OP_SYS_INFO_WIDTH-1:0] sys_op_t;

endpackage

package ydrasil_pipeline_pkg;
	import ydrasil_pkg::*;

	typedef enum logic [3:0] {
		PAIR_BLOCK_NONE      = 4'd0,
		PAIR_BLOCK_PREDICTOR = 4'd1,
		PAIR_BLOCK_QUEUE     = 4'd2,
		PAIR_BLOCK_RULE      = 4'd3,
		PAIR_BLOCK_RENAME    = 4'd4,
		PAIR_BLOCK_ISSUE     = 4'd5,
		PAIR_BLOCK_REDIRECT  = 4'd6,
		PAIR_BLOCK_STALL     = 4'd7,
		PAIR_BLOCK_ITCM      = 4'd8
	} pair_block_e;

	typedef struct packed {
		logic       valid;
		logic       hit;
		logic       taken;
		pc_t        target;
		logic [1:0] counter;
		pc_t        bht_index;
		logic       l0_taken;
		logic       redirect_consumed;
	} predict_pkt_t;

	typedef struct packed {
		logic        request_valid;
		logic        fetch_pair_try;
		logic        fetch_pair_allow;
		logic        decode_pair_allow;
		logic        slot1_valid;
		logic        slot1_kill;
		pair_block_e block_reason;
	} pair_ctrl_t;

	typedef struct packed {
		logic         valid;
		pc_t          pc;
		instr_t       instr;
		predict_pkt_t pred;
	} fetch_pkt_t;

	typedef struct packed {
		fetch_pkt_t slot0;
		fetch_pkt_t slot1;
		pair_ctrl_t pair_ctrl;
	} fetch_pair_pkt_t;

	typedef struct packed {
		logic       valid;
		pc_t        pc;
		instr_t     instr;
		logic       pred_hit;
		logic       pred_taken;
		xlen_t      pred_target;
		logic [1:0] pred_counter;
		xlen_t      pred_bht_index;
		logic       pred_l0_taken;

		gpr_addr_t  rf_raddr_rs1;
		gpr_addr_t  rf_raddr_rs2;
		logic       rf_ren_rs1;
		logic       rf_ren_rs2;
		gpr_addr_t  rf_waddr_rd;
		logic       rf_wen_rd;

		xlen_t      imm;
		logic       operand_b_rs_sel;
		logic       operand_a_pc_sel;
		logic       operand_a_imm_sel;
		logic       bt_a_rs_sel;
		logic       operand_b_jump_sel;

		alu_op_t    operator;
		lsu_op_t    operator_lsu;
		op_type_t   operator_type;
		csr_addr_t  csr_reg_raddr;
		csr_addr_t  csr_ex_waddr;
		csr_op_t    csr_op_info;
		sys_op_t    sys_op_info;
		logic       fence_i;
	} decode_pkt_t;

	typedef struct packed {
		logic  rs1_ready;
		logic  rs2_ready;
		preg_t rs1_psrc;
		preg_t rs2_psrc;
		preg_t pdst;
		logic  pdst_valid;
		rob_idx_t rob_idx;
		logic     rob_valid;
	} rename_pkt_t;

	typedef struct packed {
		decode_pkt_t dec;
		rename_pkt_t rn;
		logic        wait_rs1;
		logic        wait_rs2;
	} issue_pkt_t;

	typedef struct packed {
		decode_pkt_t slot0;
		decode_pkt_t slot1;
		pair_ctrl_t  pair_ctrl;
	} decode_pair_pkt_t;

	typedef struct packed {
		issue_pkt_t slot0;
		issue_pkt_t slot1;
		pair_ctrl_t pair_ctrl;
	} issue_pair_pkt_t;

	typedef struct packed {
		logic      valid;
		logic      rf_wen;
		gpr_addr_t rf_waddr;
		preg_t     pdst;
		xlen_t     data;
	} wb_pkt_t;

	typedef struct packed {
		logic      flush_id;
		logic      flush_ex;
		logic      interrupt;

		instr_t    if_id_instr;
		pc_t       bp_predict_pc;
		logic      bp_predict_hit;
		logic      bp_predict_taken;
		pc_t       bp_predict_target;
		logic [1:0] bp_predict_counter;
		logic      dbg_bp_resolve_valid;
		pc_t       dbg_bp_resolve_pc;
		logic      dbg_bp_actual_taken;
		pc_t       dbg_bp_actual_target;
		pc_t       dbg_bp_actual_next_pc;
		logic      dbg_bp_pred_hit;
		logic      dbg_bp_pred_taken;
		pc_t       dbg_bp_pred_target;
		logic [1:0] dbg_bp_pred_counter;
		logic      dbg_bp_pred_l0_taken;
		pc_t       dbg_bp_pred_next_pc;
		logic      dbg_bp_mispredict;

		logic      alu_rf_wen_rd;
		gpr_addr_t alu_rf_waddr_rd;
		xlen_t     alu_result;
		preg_t     alu_rn_pdst;
		logic      lsu_rf_wen_rd;
		gpr_addr_t lsu_rf_waddr_rd;
		xlen_t     lsu_wb_result;
		logic      wb_mul_complete;
		gpr_addr_t wb_mul_complete_waddr;
		logic      pipe1_alu_rf_wen_rd_to_wb;
		gpr_addr_t pipe1_alu_rf_waddr_rd_to_wb;
		xlen_t     pipe1_alu_result_to_wb;

		logic      id_ex_valid;
		logic      id_ex_rd_issue;
		logic      id_alu_rf_wen_rd;
		gpr_addr_t id_rf_waddr_rd;
		op_type_t  operator_type;
		logic      id_ctrl_rs1_ren;
		logic      id_ctrl_rs2_ren;
		logic      id_ctrl_rd_wen;
		gpr_addr_t id_ctrl_rs1_addr;
		gpr_addr_t id_ctrl_rs2_addr;
		gpr_addr_t id_ctrl_rd_addr;
		pc_t       id_instr_addr;
		logic      rn_alloc_valid;
		gpr_addr_t rn_alloc_rd_addr;
		logic      commit_trace_alloc_valid;
		pc_t       commit_trace_alloc_pc;
		instr_t    commit_trace_alloc_instr;
		logic      commit_trace_alloc1_valid;
		pc_t       commit_trace_alloc1_pc;
		instr_t    commit_trace_alloc1_instr;

		logic      pipe1_issue_valid;
		logic      pipe1_issue_valid_to_ex;
		logic      pipe1_rf_wen_rd_to_ex;
		gpr_addr_t pipe1_rf_waddr_rd_to_ex;
		logic      pipe1_rd_issue;
		gpr_addr_t pipe1_rf_waddr_rd_issue;
		gpr_addr_t pipe1_rf_raddr_rs1;
		gpr_addr_t pipe1_rf_raddr_rs2;
		pc_t       pipe1_pc;
		logic      pipe1_commit_rf_wen;
		logic      rs1_pending_stall;
		logic      rs2_pending_stall;
		logic      rd_waw_stall;

		logic      wb_rf_wen_rd;
		gpr_addr_t wb_rf_waddr_rd;
		xlen_t     wb_rf_wdata_rd;
		logic      wb_hzd_valid;
		gpr_addr_t wb_hzd_addr;
		logic      ex_mul_issue;
		logic      rf_wen_rd;
		gpr_addr_t rf_waddr_rd;
		xlen_t     rf_wdata_rd;

		logic      prf_rd0_en;
		logic      prf_rd1_en;
		logic      prf_rd2_en;
		logic      prf_rd3_en;
		preg_t     prf_rd0_addr;
		preg_t     prf_rd1_addr;
		preg_t     prf_rd2_addr;
		preg_t     prf_rd3_addr;
		logic      prf_wr0_en;
		logic      prf_wr1_en;
		preg_t     prf_wr0_addr;
		preg_t     prf_wr1_addr;
		xlen_t     prf_wr0_data;
		xlen_t     prf_wr1_data;

		logic      rn_real_wb_pdst_found;
		preg_t     rn_real_wb_pdst;
		logic      rn_real_lsu_pdst_found;
		preg_t     rn_real_lsu_pdst;
		logic      rn_real_mul_pdst_found;
		preg_t     rn_real_mul_pdst;
		logic      rn_real_pipe1_pdst_found;
		preg_t     rn_real_pipe1_pdst;
	} observer_pkt_t;

	typedef struct packed {
		pc_t       bp_predict_pc;
		logic      bp_predict_hit;
		logic      bp_predict_taken;
		pc_t       bp_predict_target;
		logic [1:0] bp_predict_counter;
		logic      bp_resolve_valid;
		pc_t       bp_resolve_pc;
		logic      bp_actual_taken;
		pc_t       bp_actual_target;
		pc_t       bp_actual_next_pc;
		logic      bp_pred_hit;
		logic      bp_pred_taken;
		pc_t       bp_pred_target;
		logic [1:0] bp_pred_counter;
		logic      bp_pred_l0_taken;
		pc_t       bp_pred_next_pc;
		logic      bp_mispredict;
	} observer_dbg_pkt_t;
endpackage
