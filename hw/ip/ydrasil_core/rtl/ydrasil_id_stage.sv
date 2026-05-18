`include "define_decode.svh"
`include "define_mem_reg.svh"
module ydrasil_id_stage #(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_id_i,
    input  wire                            flush_id_i,

    // IF/ID input  
    input  wire [DATA_WIDTH-1:0]           if_id_pc_i,
    input  wire [DATA_WIDTH-1:0]           if_id_instr_i,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,

    // Dispatch to EX   
    // output wire                            alu_valid_o,
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [`OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,

    output wire [`OP_LSU_INFO_WIDTH-1:0]   operator_lsu_o,
    output wire [DATA_WIDTH-1:0]           id_lsu_rs2_data_o, // 操作类型信号

    output wire [`OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_rs2_rd_forward_o, // 前递控制信号
    output wire                            id_ex_rs1_rd_forward_o, // 前递控制信号
    output wire                            id_ex_bt_rs1_rd_forward_o, // 前递控制信号
    output wire                            id_lsu_rs2_rd_forward_o, // 前递控制信号
    // output wire                            id_lsu_rs1_rd_forward_o, // 前递控制信号
    output wire [`OPSEL_INFO_WIDTH-1:0]                      sel_rs_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     id_ex_rs1_raddr_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     id_ex_rs2_raddr_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     id_ctrl_rs1_addr_o,
    output wire [`REGS_ADDR_WIDTH-1:0]     id_ctrl_rs2_addr_o,

	output wire [`CSR_ADDR_WIDTH-1:0] 	    id_csr_raddr_o,  
    output wire [`CSR_ADDR_WIDTH-1:0] 	    id_ex_csr_waddr_o,  
	output wire [`OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_o,
	output wire [`OP_SYS_INFO_WIDTH-1:0]    id_op_sys_info_o,

    output wire [DATA_WIDTH-1:0]           id_instr_addr_o, // 当前指令地址，供CLINT使用
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o


);

    wire id_ex_rs2_rd_forward;//前递
    wire id_ex_rs1_rd_forward;//前递
    wire id_lsu_rs2_rd_forward;//前递
    wire id_ex_bt_rs1_rd_forward;//前递
    // wire id_mem_rs1_rd_forward;//前递

    reg id_ex_rs2_rd_forward_ff;//前递
    reg id_ex_rs1_rd_forward_ff;//前递
    reg id_lsu_rs2_rd_forward_ff;//前递
    reg id_ex_bt_rs1_rd_forward_ff;//前递
    // reg id_mem_rs1_rd_forward_ff;//前递
    reg [`REGS_ADDR_WIDTH-1:0]     rf_raddr_rs1_ff;
    reg [`REGS_ADDR_WIDTH-1:0]     rf_raddr_rs2_ff;


    wire rs2_rd_hazard;
    wire rs1_rd_hazard;

    wire [4:0]                           rf_raddr_rs1;
    wire [4:0]                           rf_raddr_rs2;
    wire                                 rf_ren_rs1;
    wire                                 rf_ren_rs2;

    wire [4:0]                           rf_waddr_rd;
    wire                                 rf_wen_rd;

    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;

    wire [DATA_WIDTH-1:0]                imm_i;
    wire                                 operand_b_rs_sel;
    wire                                 operand_a_pc_sel;
    wire                                 operand_a_imm_sel;
    wire                                 bt_a_rs_sel;

    reg [DATA_WIDTH-1:0]                id_lsu_rs2_data_ff;

    wire [`OPERATOR_TYPE_WIDTH-1:0]      operator_type;
    reg [`OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;

    wire [DATA_WIDTH-1:0]                operand_a;
    wire [DATA_WIDTH-1:0]                operand_b;
    wire [`OPERATOR_WIDTH-1:0]           operator;


    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [`OPERATOR_WIDTH-1:0]           operator_ff;

    wire [`OP_LSU_INFO_WIDTH-1:0]        operator_lsu;
    reg [`OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
	wire [`CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr;
   
    wire [`CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr;
	wire [`OP_CSR_INFO_WIDTH-1:0]  csr_op_info;

	reg [`CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_ff;

    reg [`CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr_ff; 
	reg [`OP_CSR_INFO_WIDTH-1:0]  csr_op_info_ff;

    wire [`OP_SYS_INFO_WIDTH-1:0]  sys_op_info;
    reg [`OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;
    wire                            operand_b_jump_sel;


    ydrasil_ins_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_ydrasil_ins_decoder (
        .instr_i            (if_id_instr_i),
        .rf_waddr_rd_o      (rf_waddr_rd),
        .rf_raddr_rs1_o     (rf_raddr_rs1),
        .rf_raddr_rs2_o     (rf_raddr_rs2),
        .rf_ren_rs1_o       (rf_ren_rs1),
        .rf_ren_rs2_o       (rf_ren_rs2),
        .rf_wen_rd_o        (rf_wen_rd),
        .imm_i_o            (imm_i),
        .operand_b_rs_sel_o (operand_b_rs_sel),
        .operand_a_pc_sel_o (operand_a_pc_sel),
        .operand_a_imm_sel_o(operand_a_imm_sel),
        .bt_a_rs_sel_o      (bt_a_rs_sel),
        .operand_b_jump_sel_o(operand_b_jump_sel),
        .csr_reg_raddr_o    (csr_reg_raddr),
        // .csr_ex_we_o        (csr_ex_we),
        .csr_ex_waddr_o     (csr_ex_waddr),
        .csr_op_info_o      (csr_op_info),
        .sys_op_info_o      (sys_op_info),
        .operator_o         (operator),
        .operator_lsu_o     (operator_lsu),
        .operator_type_o    (operator_type)
    );


    wire [`OPSEL_INFO_WIDTH-1:0] sel_rs;
    reg [`OPSEL_INFO_WIDTH-1:0] sel_rs_ff;
    assign sel_rs_o = sel_rs_ff;

    assign sel_rs[`ASELRS] = ~(operand_a_pc_sel| operand_a_imm_sel);
    assign sel_rs[`BSELRS] = operand_b_rs_sel;
    assign sel_rs[`BTASELRS] = bt_a_rs_sel;


    assign rf_addr_rs1_o = rf_raddr_rs1;
    assign rf_addr_rs2_o = rf_raddr_rs2;

    // Keep ALU source selection consistent with decoder control outputs.
    assign operand_a     =  operand_a_pc_sel ? if_id_pc_i :
                            operand_a_imm_sel ? imm_i: rf_rdata_rs1_i;
    assign operand_b     = operand_b_jump_sel? 32'h4 :operand_b_rs_sel ? rf_rdata_rs2_i : DATA_WIDTH'(imm_i);


    assign bt_a_operand = bt_a_rs_sel ? rf_rdata_rs1_i : if_id_pc_i;
    assign bt_b_operand = imm_i;

    assign rs2_rd_hazard = (rf_raddr_rs2 != 0) && (rf_raddr_rs2 == rf_waddr_rd_ff) && rf_wen_rd_ff;
    assign rs1_rd_hazard = (rf_raddr_rs1 != 0) && (rf_raddr_rs1 == rf_waddr_rd_ff) && rf_wen_rd_ff;

    assign id_ex_rs2_rd_forward = rs2_rd_hazard && operand_b_rs_sel;
    assign id_ex_rs1_rd_forward = rs1_rd_hazard && (~(operand_a_pc_sel| operand_a_imm_sel)) ;
    assign id_ex_bt_rs1_rd_forward = rs1_rd_hazard && bt_a_rs_sel;
    assign id_lsu_rs2_rd_forward = rs2_rd_hazard ;
    // assign id_lsu_rs1_rd_forward = rs1_rd_hazard ;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            id_ex_rs2_rd_forward_ff <= 1'b0;
            id_ex_rs1_rd_forward_ff <= 1'b0;
            id_lsu_rs2_rd_forward_ff <= 1'b0;
            id_ex_bt_rs1_rd_forward_ff <= 1'b0;
            csr_reg_raddr_ff <= '0;
            // csr_ex_we_ff <= 1'b0;
            csr_ex_waddr_ff <= '0;
            csr_op_info_ff <= '0;
            sys_op_info_ff <= '0;
            id_instr_addr_ff <= '0;
            sel_rs_ff <= '0;
            rf_raddr_rs1_ff <= '0;
            rf_raddr_rs2_ff <= '0;
        end
        else if (flush_id_i) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            operator_lsu_ff     <= '0;
            id_lsu_rs2_data_ff  <= '0;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            id_ex_rs2_rd_forward_ff <= 1'b0;
            id_ex_rs1_rd_forward_ff <= 1'b0;
            id_lsu_rs2_rd_forward_ff <= 1'b0;
            id_ex_bt_rs1_rd_forward_ff <= 1'b0;
            // id_lsu_rs1_rd_forward_ff <= 1'b0;
            csr_reg_raddr_ff <= '0;
            // csr_ex_we_ff <= 1'b0;
            csr_ex_waddr_ff <= '0;
            csr_op_info_ff <= '0;
            sys_op_info_ff <= '0;
            id_instr_addr_ff <= '0;
            sel_rs_ff <= '0;
            rf_raddr_rs1_ff <= '0;
            rf_raddr_rs2_ff <= '0;
        end
        else if (!stall_id_i) begin
            operand_a_ff        <= operand_a;
            operand_b_ff        <= operand_b;
            operator_ff         <= operator;
            operator_type_ff    <= operator_type;
            rf_wen_rd_ff        <= rf_wen_rd;
            rf_waddr_rd_ff      <= rf_waddr_rd;
            operator_lsu_ff     <= operator_lsu;
            id_lsu_rs2_data_ff  <= rf_rdata_rs2_i; // 直接传递寄存器数据，供LSU使用
            bt_a_operand_ff     <= bt_a_operand;
            bt_b_operand_ff     <= bt_b_operand;
            id_ex_rs2_rd_forward_ff <= id_ex_rs2_rd_forward;
            id_ex_rs1_rd_forward_ff <= id_ex_rs1_rd_forward;
            id_lsu_rs2_rd_forward_ff <= id_lsu_rs2_rd_forward;
            id_ex_bt_rs1_rd_forward_ff <= id_ex_bt_rs1_rd_forward;
            csr_reg_raddr_ff <= csr_reg_raddr;
            // csr_ex_we_ff <= csr_ex_we;
            csr_ex_waddr_ff <= csr_ex_waddr;
            csr_op_info_ff <= csr_op_info;
            sys_op_info_ff <= sys_op_info;
            id_instr_addr_ff <= if_id_pc_i;
            sel_rs_ff <= sel_rs;
            rf_raddr_rs1_ff <= rf_raddr_rs1;
            rf_raddr_rs2_ff <= rf_raddr_rs2;
        end
    end

    assign operand_a_o          = operand_a_ff;
    assign operand_b_o          = operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign operator_lsu_o       = operator_lsu_ff;
    assign operator_type_o      = operator_type_ff;
    assign id_lsu_rs2_data_o    = id_lsu_rs2_data_ff; // 直接传递寄存器数据，供LSU使用
    assign bt_a_operand_o       = bt_a_operand_ff;
    assign bt_b_operand_o       = bt_b_operand_ff;
    assign id_ex_rs2_rd_forward_o = id_ex_rs2_rd_forward_ff;
    assign id_ex_rs1_rd_forward_o = id_ex_rs1_rd_forward_ff;
    assign id_lsu_rs2_rd_forward_o = id_lsu_rs2_rd_forward_ff;
    assign id_ex_bt_rs1_rd_forward_o = id_ex_bt_rs1_rd_forward_ff;
    // assign id_lsu_rs1_rd_forward_o = id_lsu_rs1_rd_forward_ff;
    assign  id_csr_raddr_o = csr_reg_raddr_ff;
    // assign  id_ex_csr_we_o = csr_ex_we_ff;
    assign  id_ex_csr_waddr_o = csr_ex_waddr_ff;
    assign  id_op_csr_info_o = csr_op_info_ff;
    assign  id_op_sys_info_o = sys_op_info_ff;
    assign id_instr_addr_o = id_instr_addr_ff;
    assign sel_rs_o = sel_rs_ff;
    assign id_ex_rs1_raddr_o = rf_raddr_rs1_ff;
    assign id_ex_rs2_raddr_o = rf_raddr_rs2_ff;

    assign id_ctrl_rs1_addr_o = rf_raddr_rs1;
    assign id_ctrl_rs2_addr_o = rf_raddr_rs2;

endmodule
