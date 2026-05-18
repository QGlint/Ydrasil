`include "define_decode.svh"
`include "define_mem_reg.svh"

module ydrasil_core #(
)(
	input  wire clk,
	input  wire rst_n
    
    
    ,output wire [31:0]  perip_addr,
    output wire         perip_wen,
	output wire [ 3:0]  perip_mask,
    output wire [31:0]  perip_wdata,
    input  wire [31:0]  perip_rdata
);


    localparam DRAM_ADDR_START = 32'h8010_0000;
    localparam DRAM_ADDR_END   = 32'h8013_FFFF;

	// IF <-> MEMS
	wire [`INST_ADDR_WIDTH-1:0] if_mem_addr;
	wire [`INST_DATA_WIDTH-1:0] if_mem_rdata;

	// IF/ID pipeline
	wire [31:0] if_id_pc;
	wire [31:0] if_id_instr;

	// CTRL signals
	wire                        stall_if;
	wire                        stall_id;
    wire                       stall_pc;
	wire                        flush_if;
	wire                        flush_id;
	wire                        flush_ex;
	wire                        branch_jump;
	wire [`INST_ADDR_WIDTH-1:0] branch_target;

	// ID <-> RF
	wire [`REGS_ADDR_WIDTH-1:0] rf_raddr_rs1;
	wire [`REGS_ADDR_WIDTH-1:0] rf_raddr_rs2;
	wire [`REGS_DATA_WIDTH-1:0] rf_rdata_rs1;
	wire [`REGS_DATA_WIDTH-1:0] rf_rdata_rs2;

	// ID -> EX
	wire [31:0]                    operand_a;
	wire [31:0]                    operand_b;
	wire [`OPERATOR_WIDTH-1:0]     operator;
	wire [31:0]                    bt_a_operand;
	wire [31:0]                    bt_b_operand;
	wire [`OP_LSU_INFO_WIDTH-1:0]  operator_lsu;
    wire                           id_lsu_rs2_rd_forward;
    wire id_ex_rs2_rd_forward;
    wire id_ex_rs1_rd_forward;
    wire id_ex_bt_rs1_rd_forward;
	wire [31:0]                    id_lsu_rs2_data;
	wire [`OPERATOR_TYPE_WIDTH-1:0] operator_type;
	wire                           id_alu_rf_wen_rd;
	wire [`REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd;

	// EX outputs
	wire                        ex_branch_jump;
	wire [`INST_ADDR_WIDTH-1:0] ex_branch_target;
	wire [`BUS_ADDR_WIDTH-1:0]  ex_lsu_mem_addr;
    wire [31:0]                 ex_lsu_result;
	wire [`REGS_DATA_WIDTH-1:0] alu_result;
	wire                        alu_rf_wen_rd;
	wire [`REGS_ADDR_WIDTH-1:0] alu_rf_waddr_rd;

	// LSU request path
	wire [1:0]                  operator_lsu_type;
	wire [`BUS_DATA_WIDTH-1:0]  lsu_mem_wdata;
	wire [`BUS_ADDR_WIDTH-1:0]  lsu_mem_addr;
	wire                        lsu_mem_we;
	wire                        lsu_mem_req;
	wire [3:0]                  lsu_mem_wmask;
	wire [`BUS_DATA_WIDTH-1:0]  lsu_mem_rdata;
	wire                        hold_flag;

	wire [`REGS_DATA_WIDTH-1:0] lsu_wb_result;
	wire                        lsu_rf_wen_rd;
	wire [`REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd;

	// WB -> RF
	wire [`REGS_DATA_WIDTH-1:0] rf_wdata_rd;
	wire                        rf_wen_rd;
	wire [`REGS_ADDR_WIDTH-1:0] rf_waddr_rd;
	wire [`OPSEL_INFO_WIDTH-1:0]		sel_rs;
	wire [`REGS_ADDR_WIDTH-1:0]      id_ex_rs2_raddr;
	wire [`REGS_ADDR_WIDTH-1:0]      id_ex_rs1_raddr;
	wire [`REGS_DATA_WIDTH-1:0]     wb_ex_pending_wdata_rd_ff;
	wire [`REGS_ADDR_WIDTH-1:0]		wb_ex_pending_waddr_rd_ff;
	wire                       		wb_ex_pending_ff;

    wire [`BUS_DATA_WIDTH-1:0]  lsu_mem_rdata_m; // 从DRAM读取的数据

    //LSU -> CTRL
    wire                            lsu_ctrl_stall;   
    wire                           	lsu_ctrl_stall_wb;
    wire [`REGS_ADDR_WIDTH-1:0]    	lsu_ctrl_waddr_rd;
    wire [`REGS_ADDR_WIDTH-1:0]    	lsu_ctrl_waddr_rd_wb;

    //LSU -> ID
    wire [`REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr;
    wire [`REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr;

    wire [`CSR_ADDR_WIDTH-1:0]       id_csr_raddr;
    wire [`CSR_ADDR_WIDTH-1:0]       id_ex_csr_waddr;
    wire [`OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info;

	wire [`REGS_DATA_WIDTH-1:0]      csr_ex_rdata;
	wire 					    ex_csr_wen;
	wire [`REGS_DATA_WIDTH-1:0]      ex_csr_wdata;
	wire [`CSR_ADDR_WIDTH-1:0]       ex_csr_waddr;

	// CSR <-> CLINT wires
	wire                             clint_csr_we;
	wire [`CSR_ADDR_WIDTH-1:0]       clint_csr_waddr;
	wire [`CSR_ADDR_WIDTH-1:0]       clint_csr_raddr;
	wire [`REGS_DATA_WIDTH-1:0]      clint_csr_wdata;
	wire [`REGS_DATA_WIDTH-1:0]      csr_clint_data;
	wire [`REGS_DATA_WIDTH-1:0]      csr_clint_mtvec;
	wire [`REGS_DATA_WIDTH-1:0]      csr_clint_mepc;
	wire [`REGS_DATA_WIDTH-1:0]      csr_clint_mstatus;
	wire                             global_int_en;
	wire                             interrupt;
	wire [`INST_ADDR_WIDTH-1:0]      clint_ex_int_addr;
	wire                             clint_stall;

    wire [`BUS_ADDR_WIDTH-1:0] id_instr_addr;

    wire [`OP_SYS_INFO_WIDTH-1:0] id_op_sys_info;

    reg dram_addr_sel_ff; 
    reg lsu_mem_read_ff;
    wire dram_sel;  
    wire dram_addr_sel;
    assign dram_addr_sel = (lsu_mem_addr >= DRAM_ADDR_START) && (lsu_mem_addr <= DRAM_ADDR_END);

    assign dram_sel =( lsu_mem_we& lsu_mem_we) | (dram_addr_sel_ff & lsu_mem_read_ff); // 写操作直接使用当前地址判断，读操作使用上一个周期的地址判断

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dram_addr_sel_ff <= 1'b0;
            lsu_mem_read_ff <= 1'b0;
        end else begin
            dram_addr_sel_ff <= dram_addr_sel;
            lsu_mem_read_ff <= (lsu_mem_req && !lsu_mem_we); // 只有在发出读请求时才认为是读操作
        end
    end

	assign operator_lsu_type[0] = operator_type[`OPERATOR_TYPE_LOAD];
	assign operator_lsu_type[1] = operator_type[`OPERATOR_TYPE_STORE];

	assign perip_addr = lsu_mem_addr;
	assign perip_wen = lsu_mem_req && lsu_mem_we;
	assign perip_mask = lsu_mem_wmask;
	assign perip_wdata = lsu_mem_wdata;
	assign lsu_mem_rdata = dram_sel ? lsu_mem_rdata_m : perip_rdata ; 

	ydrasil_load_store_unit u_ydrasil_load_store_unit (
		.clk               (clk),
		.rst_n             (rst_n),
		.ex_lsu_mem_addr_i (ex_lsu_mem_addr),
		.id_rd_waddr_i      (id_rf_waddr_rd),
		.operator_lsu_i    (operator_lsu),
		.operator_lsu_type_i(operator_lsu_type),
        .ex_lsu_rd_data_i (ex_lsu_result),
		.id_lsu_rs2_data_i (id_lsu_rs2_data),
        .id_lsu_rs2_rd_forward_i(id_lsu_rs2_rd_forward),
		.lsu_mem_rdata_i   (lsu_mem_rdata),
		.lsu_mem_wdata_o   (lsu_mem_wdata),
		.lsu_mem_addr_o    (lsu_mem_addr),
		.lsu_mem_wen_o     (lsu_mem_we),
		.lsu_mem_req_o     (lsu_mem_req),
		.lsu_mem_wmask_o   (lsu_mem_wmask),
		.lsu_ctrl_stall_o       (lsu_ctrl_stall),
		.lsu_ctrl_stall_wb_o    (lsu_ctrl_stall_wb),
		.lsu_ctrl_waddr_rd_o    (lsu_ctrl_waddr_rd),
		.lsu_ctrl_waddr_rd_wb_o (lsu_ctrl_waddr_rd_wb),
		.lsu_wb_result_o   (lsu_wb_result),
		.lsu_rf_rd_wen_o   (lsu_rf_wen_rd),
		.lsu_rf_rd_waddr_o (lsu_rf_waddr_rd)
	);

	ydrasil_if_stage u_ydrasil_if_stage (
		.clk           (clk),
		.rst_n         (rst_n),
		.stall_if_i      (stall_if),
        .stall_pc_i      (stall_pc),
		.flush_if_i      (flush_if),
		.branch_jump_i   (branch_jump),
		.branch_target_i (branch_target),
		.if_mem_addr_o   (if_mem_addr),
		.if_mem_rdata_i  (if_mem_rdata),
		.if_id_pc_o      (if_id_pc),
		.if_id_instr_o   (if_id_instr)
	);

	ydrasil_id_stage u_ydrasil_id_stage (
		.clk              (clk),
		.rst_n            (rst_n),
		.stall_id_i         (stall_id),
		.flush_id_i         (flush_id),
		.if_id_pc_i         (if_id_pc),
		.if_id_instr_i      (if_id_instr),
		.rf_addr_rs1_o      (rf_raddr_rs1),
		.rf_addr_rs2_o      (rf_raddr_rs2),
		.rf_rdata_rs1_i     (rf_rdata_rs1),
		.rf_rdata_rs2_i     (rf_rdata_rs2),
		.operand_a_o        (operand_a),
		.operand_b_o        (operand_b),
		.operator_o         (operator),
		.bt_a_operand_o     (bt_a_operand),
		.bt_b_operand_o     (bt_b_operand),
		.operator_lsu_o     (operator_lsu),
		.sel_rs_o            (sel_rs),
		.id_ex_rs2_raddr_o (id_ex_rs2_raddr),
		.id_ex_rs1_raddr_o (id_ex_rs1_raddr),
		.id_lsu_rs2_data_o  (id_lsu_rs2_data),
		.operator_type_o    (operator_type),
		.id_ex_rs2_rd_forward_o (id_ex_rs2_rd_forward),
		.id_ex_rs1_rd_forward_o (id_ex_rs1_rd_forward),
		.id_lsu_rs2_rd_forward_o (id_lsu_rs2_rd_forward),
        .id_ex_bt_rs1_rd_forward_o (id_ex_bt_rs1_rd_forward),
		.id_ctrl_rs1_addr_o (id_ctrl_rs1_addr),
		.id_ctrl_rs2_addr_o (id_ctrl_rs2_addr),
		.id_csr_raddr_o     (id_csr_raddr),
		.id_ex_csr_waddr_o  (id_ex_csr_waddr),
		.id_op_csr_info_o   (id_op_csr_info),
        .id_op_sys_info_o   (id_op_sys_info),
        .id_instr_addr_o     (id_instr_addr),
		.id_alu_rf_wen_rd_o (id_alu_rf_wen_rd),
		.id_rf_waddr_rd_o   (id_rf_waddr_rd)
	);

	ydrasil_ex_block u_ydrasil_ex_block (
		.clk              (clk),
		.rst_n            (rst_n),
		.flush_ex_i         (flush_ex),
		.bt_a_operand_i     (bt_a_operand),
		.bt_b_operand_i     (bt_b_operand),
		.operand_a_i        (operand_a),
		.operand_b_i        (operand_b),
		.operator_i         (operator),
		.operator_type_i    (operator_type),
        .interrupt_i          (interrupt), 
        .clint_ex_int_addr_i    (clint_ex_int_addr),
		.id_rf_waddr_rd_i   (id_rf_waddr_rd),
		.id_alu_rf_wen_rd_i (id_alu_rf_wen_rd),
        .id_ex_rs2_rd_forward_i (id_ex_rs2_rd_forward),
        .id_ex_rs1_rd_forward_i (id_ex_rs1_rd_forward),
        .id_ex_bt_rs1_rd_forward_i (id_ex_bt_rs1_rd_forward),
		.id_ex_csr_waddr_i  (id_ex_csr_waddr) ,
        .id_op_csr_info_i(id_op_csr_info) ,
        .csr_ex_rdata_i(csr_ex_rdata) ,
        .ex_csr_wen_o(ex_csr_wen),
        .ex_csr_wdata_o(ex_csr_wdata),
        .ex_csr_waddr_o(ex_csr_waddr),
		.sel_rs_i(sel_rs),
		.wb_ex_pending_wdata_rd_ff_i(wb_ex_pending_wdata_rd_ff),
		.wb_ex_pending_waddr_rd_ff_i(wb_ex_pending_waddr_rd_ff),
		.wb_ex_pending_ff_i(wb_ex_pending_ff),
		.id_ex_rs2_raddr_i(id_ex_rs2_raddr),
		.id_ex_rs1_raddr_i(id_ex_rs1_raddr),
		.ex_branch_jump_o   (ex_branch_jump),
		.ex_branch_target_o (ex_branch_target),
		.ex_lsu_mem_addr_o  (ex_lsu_mem_addr),
        .ex_lsu_result_o     (ex_lsu_result),
		.alu_result_o       (alu_result),
		.alu_rf_wen_rd_o    (alu_rf_wen_rd),
		.alu_rf_waddr_rd_o  (alu_rf_waddr_rd)
	);

	ydrasil_mems u_ydrasil_mems (
		.clk           (clk),
		.rst_n         (rst_n),
		.if_mem_addr_i (if_mem_addr),
		.if_mem_rdata_o(if_mem_rdata),
		.lsu_mem_addr_i(lsu_mem_addr),
		.lsu_mem_data_i(lsu_mem_wdata),
		.lsu_mem_data_o(lsu_mem_rdata_m),
		.lsu_mem_we_i  (lsu_mem_we),
		.lsu_mem_req_i (lsu_mem_req),
		.lsu_mem_wmask_i(lsu_mem_wmask),
        .dram_sel_i     (dram_sel)
		// .hold_flag_o   (hold_flag)
	);

	ydrasil_wb_stage u_ydrasil_wb_stage (
		.clk              (clk),
		.rst_n            (rst_n),
		.alu_wdata_rd_i   (alu_result),
		.alu_rf_wen_rd_i  (alu_rf_wen_rd),
		.alu_rf_waddr_rd_i(alu_rf_waddr_rd),
		.lsu_wb_result_i  (lsu_wb_result),
		.lsu_rf_wen_rd_i  (lsu_rf_wen_rd),
		.lsu_rf_waddr_rd_i(lsu_rf_waddr_rd),
		.wb_ex_pending_wdata_rd_ff_o(wb_ex_pending_wdata_rd_ff),
		.wb_ex_pending_waddr_rd_ff_o(wb_ex_pending_waddr_rd_ff),
		.wb_ex_pending_ff_o(wb_ex_pending_ff),
		.rf_wdata_rd_o    (rf_wdata_rd),
		.rf_wen_rd_o      (rf_wen_rd),
		.rf_waddr_rd_o    (rf_waddr_rd)
	);

	ydrasil_registers u_ydrasil_registers (
		.clk          (clk),
		.rst_n        (rst_n),
		.rf_wen_rd_i  (rf_wen_rd),
		.rf_waddr_rd_i(rf_waddr_rd),
		.rf_wdata_rd_i(rf_wdata_rd),
		.rf_raddr_rs1_i(rf_raddr_rs1),
		.rf_rdata_rs1_o(rf_rdata_rs1),
		.rf_raddr_rs2_i(rf_raddr_rs2),
		.rf_rdata_rs2_o(rf_rdata_rs2)
	);

	ydrasil_ctrl u_ctrl (
		.rst_n             (rst_n),
		.ex_branch_jump_i  (ex_branch_jump),
		.ex_branch_target_i(ex_branch_target),
		.lsu_ctrl_stall_i       (lsu_ctrl_stall),
		.lsu_ctrl_stall_wb_i    (lsu_ctrl_stall_wb),
		.lsu_ctrl_waddr_rd_i    (lsu_ctrl_waddr_rd),
		.lsu_ctrl_waddr_rd_wb_i (lsu_ctrl_waddr_rd_wb),
		.id_ctrl_rs1_addr_i     (id_ctrl_rs1_addr),
		.id_ctrl_rs2_addr_i     (id_ctrl_rs2_addr),
        .clint_stall_i        (clint_stall),
		.stall_if_o        (stall_if),
		.stall_id_o        (stall_id),
        .stall_pc_o        (stall_pc),
		.flush_if_o        (flush_if),
		.flush_id_o        (flush_id),
		.flush_ex_o        (flush_ex),
		.branch_jump_o     (branch_jump),
		.branch_target_o   (branch_target)
	);

	ydrasil_registers_csr u_ydrasil_registers_csr (
		.clk               (clk),
		.rst_n             (rst_n),
		.ex_csr_wen_i      (ex_csr_wen),
		.id_csr_raddr_i    (id_csr_raddr),
		.ex_csr_waddr_i    (ex_csr_waddr),
		.ex_csr_data_i     (ex_csr_wdata),
		.clint_csr_we_i    (clint_csr_we),
		.clint_csr_raddr_i (clint_csr_raddr),
		.clint_csr_waddr_i (clint_csr_waddr),
		.clint_csr_data_i  (clint_csr_wdata),
		.global_int_en_o   (global_int_en),
		.csr_clint_data_o  (csr_clint_data),
		.csr_clint_mtvec   (csr_clint_mtvec),
		.csr_clint_mepc    (csr_clint_mepc),
		.csr_clint_mstatus (csr_clint_mstatus),
		.csr_ex_data_o     (csr_ex_rdata)
	);

	ydrasil_clint u_clint (
		.clk               (clk),
		.rst_n             (rst_n),
		.instr_addr_i       (id_instr_addr),
		.ex_branch_jump_i       (ex_branch_jump),
		.ex_branch_target_i       (ex_branch_target),
        .sys_op_info_i      (id_op_sys_info),
        .sys_op_i           (operator_type[`OPERATOR_TYPE_SYS]), // 只要有任意
		.csr_clint_data_i  (csr_clint_data),
		.csr_clint_mtvec   (csr_clint_mtvec),
		.csr_clint_mepc    (csr_clint_mepc),
		.csr_clint_mstatus (csr_clint_mstatus),
		.global_int_en_i   (global_int_en),
		.clint_stall_o     (clint_stall),
		.clint_csr_we_o    (clint_csr_we),
		.clint_csr_waddr_o (clint_csr_waddr),
		.clint_csr_raddr_o (clint_csr_raddr),
		.clint_csr_data_o  (clint_csr_wdata),
		.interrupt_o        (interrupt),
		.clint_ex_int_addr_o      (clint_ex_int_addr)
	);



endmodule
