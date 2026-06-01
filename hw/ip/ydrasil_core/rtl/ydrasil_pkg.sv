
package ydrasil_pkg;
	// Memory and address configuration
	localparam int ITCM_ADDR_WIDTH = 12; // 16KB
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

	localparam int MUL_MODE_RADIX8 = 0;
	localparam int MUL_MODE_4CYCLE = 1;
	localparam int MUL_MODE = MUL_MODE_4CYCLE;

	localparam DIV_MODE =0;

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
	localparam logic [11:0] CSR_CYCLE    = 12'hc00;
	localparam logic [11:0] CSR_CYCLEH   = 12'hc80;
	localparam logic [11:0] CSR_MTVEC    = 12'h305;
	localparam logic [11:0] CSR_MCAUSE   = 12'h342;
	localparam logic [11:0] CSR_MEPC     = 12'h341;
	localparam logic [11:0] CSR_MIE      = 12'h304;
	localparam logic [11:0] CSR_MSTATUS  = 12'h300;
	localparam logic [11:0] CSR_MSCRATCH = 12'h340;

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
	localparam int OPERATOR_TYPE_WIDTH = 7;
	localparam int OPERATOR_TYPE_ALU   = 0;
	localparam int OPERATOR_TYPE_BJP   = 1;
	localparam int OPERATOR_TYPE_LOAD  = 2;
	localparam int OPERATOR_TYPE_STORE = 3;
	localparam int OPERATOR_TYPE_CSR   = 4;
	localparam int OPERATOR_TYPE_SYS   = 5;
	localparam int OPERATOR_TYPE_MUL   = 6;
	localparam int OPERATOR_TYPE_LSU_BASE = 2;

	localparam int OPERATOR_WIDTH = 12;

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

	localparam int OPSEL_INFO_WIDTH = 3;
	localparam int ASELRS   = 0;
	localparam int BSELRS   = 1;
	localparam int BTASELRS = 2;

	function automatic integer unsigned idx_width (input integer unsigned num_idx);
        return (num_idx > 32'd1) ? unsigned'($clog2(num_idx)) : 32'd1;
    endfunction



endpackage
