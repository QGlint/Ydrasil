
module ydrasil_ctrl 
import ydrasil_pkg::*;
(

    input wire clk,
    input wire rst_n,
    input wire interrupt_i,

    // from ex
    input wire                          ex_branch_jump_i,
    input wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    
    input wire                          rn_ctrl_block_i,
    input wire                          rn_alloc_stall_i,
    input wire                          id_ctrl_lsu_req_i,
    input wire                          lsu_ctrl_busy_i,
    input wire                          id_frontend_stall_i,
    input wire                          clint_stall_i,
    input wire                          ex_mul_stall_i,
    input wire                          ex_mul_issue_i,
	    input wire                          mul_result_valid_i,
	    input wire                          wb_backpressure_i,

	    input wire                          id_ex_valid_i,
	    input wire                          id_alu_rf_wen_rd_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    id_rf_waddr_rd_i,
	    input wire [3:0]                    id_ex_div_op_i,
	    input wire [OPERATOR_TYPE_WIDTH-1:0] operator_type_i,
	    input wire                          id_ctrl_rs1_ren_i,
	    input wire                          id_ctrl_rs2_ren_i,
	    input wire                          id_ctrl_rd_wen_i,
    input wire [REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    id_ctrl_rd_addr_i,
	    input wire [OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type_i,
	    input wire                          pipe1_issue_valid_i,
	    input wire                          pipe1_rf_wen_rd_issue_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    pipe1_rf_waddr_rd_issue_i,
	    input wire                          id_alu_stable_valid_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    id_alu_stable_addr_i,
	    input wire                          rn_wb_pdst_found_i,
	    input wire [5:0]                    rn_wb_pdst_i,
	    input wire                          rn_lsu_pdst_found_i,
	    input wire [5:0]                    rn_lsu_pdst_i,
	    input wire                          rn_mul_pdst_found_i,
	    input wire [5:0]                    rn_mul_pdst_i,
	    input wire                          rn_pipe1_pdst_found_i,
	    input wire [5:0]                    rn_pipe1_pdst_i,
	    input wire [REGS_DATA_WIDTH-1:0]    alu_result_i,
	    input wire [REGS_DATA_WIDTH-1:0]    lsu_wb_result_i,
	    input wire [REGS_DATA_WIDTH-1:0]    pipe1_wb_data_i,
	    input wire                          pipe1_commit_rf_wen_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    pipe1_commit_arch_rd_i,
	    input wire [REGS_DATA_WIDTH-1:0]    pipe1_commit_data_i,
	    input wire                          wb_rf_wen_rd_i,
	    input wire [REGS_ADDR_WIDTH-1:0]    wb_rf_waddr_rd_i,
	    input wire [REGS_DATA_WIDTH-1:0]    wb_rf_wdata_rd_i,

	    output wire                         scoreboard_stall_o,
	    output wire                         lsu_struct_stall_o,
	    output wire                         ready_issue_allow_o,
	    output wire                         bubble_id_o,
	    output wire                         ex_accept_valid_o,
	    output wire                         id_ex_rd_issue_o,
	    output wire                         pipe1_rd_issue_o,
	    output wire [1:0]                   operator_lsu_type_o,
	    output wire                         rs1_issue_alu_ready_next_o,
    output wire                         rs2_issue_alu_ready_next_o,
    output wire                         rs1_issue_alu_stable_bypass_o,
    output wire                         rs2_issue_alu_stable_bypass_o,
	    output wire                         rs1_issue_alu_stable_issue_bypass_o,
	    output wire                         rs2_issue_alu_stable_issue_bypass_o,
	    output wire                         rs1_branch_ready_next_bypass_o,
	    output wire                         rs2_branch_ready_next_bypass_o,
	    output wire                         prf_wr0_en_o,
	    output wire                         prf_wr1_en_o,
	    output wire [5:0]                   prf_wr0_addr_o,
	    output wire [5:0]                   prf_wr1_addr_o,
	    output wire [REGS_DATA_WIDTH-1:0]   prf_wr0_data_o,
	    output wire [REGS_DATA_WIDTH-1:0]   prf_wr1_data_o,
	    output wire                         rf_wen_rd_o,
	    output wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_o,
	    output wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_o,

	    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         stall_pc_o,
    // output wire                         stall_ex_o,
    // flush
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    // output wire                         flush_mems_o, --- IGNORE ---
    //跳转
    output wire                         branch_jump_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]  branch_target_o

);

	    reg [2:0] mul_inflight_q;
	    reg ex_mul_stall_q;
	    wire mul_inflight;
	    wire decode_bubble_stall;
	    wire id_ex_is_div;
	    wire id_ex_div_first_cycle;

    assign scoreboard_stall_o = rn_ctrl_block_i | rn_alloc_stall_i;
    assign lsu_struct_stall_o = id_ctrl_lsu_req_i & lsu_ctrl_busy_i;
    assign ready_issue_allow_o =
        !lsu_struct_stall_o & !clint_stall_i & !wb_backpressure_i & !ex_mul_stall_i;
    assign bubble_id_o =
        scoreboard_stall_o | lsu_struct_stall_o | clint_stall_i | wb_backpressure_i;

	    assign decode_bubble_stall =
	        bubble_id_o | id_frontend_stall_i;

	    assign mul_inflight = (mul_inflight_q != 3'd0) | ex_mul_issue_i;
	    assign id_ex_is_div =
	        operator_type_i[OPERATOR_TYPE_MUL] & (|id_ex_div_op_i);
	    assign id_ex_div_first_cycle = id_ex_is_div & !ex_mul_stall_q;
	    assign ex_accept_valid_o = id_ex_valid_i & !flush_ex_o;
	    assign id_ex_rd_issue_o =
	        ex_accept_valid_o & (id_rf_waddr_rd_i != '0) & !interrupt_i &
	        (id_alu_rf_wen_rd_i | operator_type_i[OPERATOR_TYPE_LOAD]) &
	        (!id_ex_is_div | id_ex_div_first_cycle);
	    assign pipe1_rd_issue_o =
	        pipe1_issue_valid_i & pipe1_rf_wen_rd_issue_i &
	        (pipe1_rf_waddr_rd_issue_i != '0) & !flush_ex_o & !interrupt_i;
	    assign operator_lsu_type_o[0] =
	        ex_accept_valid_o & operator_type_i[OPERATOR_TYPE_LOAD];
		    assign operator_lsu_type_o[1] =
		        ex_accept_valid_o & operator_type_i[OPERATOR_TYPE_STORE];

	    assign prf_wr0_en_o =
	        rn_wb_pdst_found_i |
	        (!rn_wb_pdst_found_i & rn_lsu_pdst_found_i) |
	        (!rn_wb_pdst_found_i & !rn_lsu_pdst_found_i & rn_mul_pdst_found_i);
	    assign prf_wr0_addr_o =
	        rn_wb_pdst_found_i ? rn_wb_pdst_i :
	        (rn_lsu_pdst_found_i ? rn_lsu_pdst_i : rn_mul_pdst_i);
	    assign prf_wr0_data_o =
	        rn_wb_pdst_found_i ? alu_result_i :
	        (rn_lsu_pdst_found_i ? lsu_wb_result_i : wb_rf_wdata_rd_i);
	    assign prf_wr1_en_o =
	        rn_pipe1_pdst_found_i |
	        (!rn_pipe1_pdst_found_i & rn_wb_pdst_found_i &
	         (rn_lsu_pdst_found_i | rn_mul_pdst_found_i)) |
	        (!rn_pipe1_pdst_found_i & !rn_wb_pdst_found_i &
	         rn_lsu_pdst_found_i & rn_mul_pdst_found_i);
	    assign prf_wr1_addr_o =
	        rn_pipe1_pdst_found_i ? rn_pipe1_pdst_i :
	        (rn_lsu_pdst_found_i ? rn_lsu_pdst_i : rn_mul_pdst_i);
	    assign prf_wr1_data_o =
	        rn_pipe1_pdst_found_i ? pipe1_wb_data_i :
	        (rn_lsu_pdst_found_i ? lsu_wb_result_i : wb_rf_wdata_rd_i);

	    assign rf_wen_rd_o = pipe1_commit_rf_wen_i | wb_rf_wen_rd_i;
	    assign rf_waddr_rd_o =
	        pipe1_commit_rf_wen_i ? pipe1_commit_arch_rd_i : wb_rf_waddr_rd_i;
	    assign rf_wdata_rd_o =
	        pipe1_commit_rf_wen_i ? pipe1_commit_data_i : wb_rf_wdata_rd_i;

		    always_ff @(posedge clk or negedge rst_n) begin
	        if (!rst_n) begin
	            mul_inflight_q <= '0;
	            ex_mul_stall_q <= 1'b0;
	        end else if (interrupt_i) begin
	            mul_inflight_q <= '0;
	            ex_mul_stall_q <= 1'b0;
	        end else begin
	            mul_inflight_q <= mul_inflight_q +
	                (ex_mul_issue_i ? 3'd1 : 3'd0) -
	                (mul_result_valid_i ? 3'd1 : 3'd0);
	            ex_mul_stall_q <= ex_mul_stall_i;
	        end
	    end

	    wire rs1_issue_raw_hzd =
	        id_ex_rd_issue_o & id_ctrl_rs1_ren_i &
	        (id_ctrl_rs1_addr_i == id_rf_waddr_rd_i);
	    wire rs2_issue_raw_hzd =
	        id_ex_rd_issue_o & id_ctrl_rs2_ren_i &
	        (id_ctrl_rs2_addr_i == id_rf_waddr_rd_i);
	    wire rd_issue_raw_hzd =
	        id_ex_rd_issue_o & id_ctrl_rd_wen_i &
	        (id_ctrl_rd_addr_i == id_rf_waddr_rd_i);

	    wire pipe1_issue_rs1_hzd =
	        pipe1_rd_issue_o & id_ctrl_rs1_ren_i &
	        (id_ctrl_rs1_addr_i == pipe1_rf_waddr_rd_issue_i);
	    wire pipe1_issue_rs2_hzd =
	        pipe1_rd_issue_o & id_ctrl_rs2_ren_i &
	        (id_ctrl_rs2_addr_i == pipe1_rf_waddr_rd_issue_i);
	    wire pipe1_issue_rd_hzd =
	        pipe1_rd_issue_o & id_ctrl_rd_wen_i &
	        (id_ctrl_rd_addr_i == pipe1_rf_waddr_rd_issue_i);

	    wire issue_load_producer =
	        id_ex_rd_issue_o & operator_type_i[OPERATOR_TYPE_LOAD];
	    wire issue_alu_producer =
	        id_ex_rd_issue_o & id_alu_rf_wen_rd_i &
	        operator_type_i[OPERATOR_TYPE_ALU];
	    wire issue_mul_div_producer =
	        id_ex_rd_issue_o & operator_type_i[OPERATOR_TYPE_MUL];
    wire issue_branch_load_wait_producer =
        issue_load_producer &
        id_ctrl_operator_type_i[OPERATOR_TYPE_BJP];
    wire issue_waitable_src_producer =
        issue_alu_producer | issue_branch_load_wait_producer;
    wire issue_alu_stable_producer =
        issue_alu_producer &
        !operator_type_i[OPERATOR_TYPE_BJP] &
        !operator_type_i[OPERATOR_TYPE_LOAD] &
        !operator_type_i[OPERATOR_TYPE_STORE] &
        !operator_type_i[OPERATOR_TYPE_CSR] &
        !operator_type_i[OPERATOR_TYPE_SYS] &
        !operator_type_i[OPERATOR_TYPE_MUL] &
        !operator_type_i[OPERATOR_TYPE_BITMANIP];
    wire issue_alu_stable_slot_hit =
        id_alu_stable_valid_i & issue_alu_stable_producer &
        (id_alu_stable_addr_i == id_rf_waddr_rd_i);

    wire rs1_issue_wait_ready_next_raw =
        rs1_issue_raw_hzd & issue_waitable_src_producer;
    wire rs2_issue_wait_ready_next_raw =
        rs2_issue_raw_hzd & issue_waitable_src_producer;
    wire rs1_issue_alu_ready_next_raw =
        rs1_issue_raw_hzd & issue_alu_producer;
    wire rs2_issue_alu_ready_next_raw =
        rs2_issue_raw_hzd & issue_alu_producer;

    wire rs1_issue_hzd = rs1_issue_raw_hzd & !issue_waitable_src_producer;
    wire rs2_issue_hzd = rs2_issue_raw_hzd & !issue_waitable_src_producer;
    wire rd_issue_hzd = rd_issue_raw_hzd & !issue_alu_producer;
    wire issue_src_hzd = rs1_issue_hzd | rs2_issue_hzd;
    wire rs1_pending_stall_eff = 1'b0;
    wire rs2_pending_stall_eff = 1'b0;
    wire rd_waw_stall = 1'b0;
    wire id_ctrl_simple_alu_consumer =
        id_ctrl_operator_type_i[OPERATOR_TYPE_ALU] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_LOAD] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_STORE] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_CSR] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_SYS] &
        !id_ctrl_operator_type_i[OPERATOR_TYPE_MUL];
    wire id_ctrl_branch_consumer =
        id_ctrl_operator_type_i[OPERATOR_TYPE_BJP];

    assign rs1_issue_alu_stable_bypass_o =
        rs1_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
        id_ctrl_simple_alu_consumer &
        !mul_inflight &
        !rs2_pending_stall_eff & !rd_waw_stall &
        !rs2_issue_hzd & !rd_issue_hzd &
        !pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
    assign rs2_issue_alu_stable_bypass_o =
        rs2_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
        id_ctrl_simple_alu_consumer &
        !mul_inflight &
        !rs1_pending_stall_eff & !rd_waw_stall &
        !rs1_issue_hzd & !rd_issue_hzd &
        !pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;

    assign rs1_branch_ready_next_bypass_o =
        rs1_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
        id_ctrl_branch_consumer &
        !mul_inflight &
        !rs2_pending_stall_eff & !rd_waw_stall &
        !rs2_issue_hzd & !rd_issue_hzd &
        !pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;
    assign rs2_branch_ready_next_bypass_o =
        rs2_issue_alu_ready_next_raw & issue_alu_stable_slot_hit &
        id_ctrl_branch_consumer &
        !mul_inflight &
        !rs1_pending_stall_eff & !rd_waw_stall &
        !rs1_issue_hzd & !rd_issue_hzd &
        !pipe1_issue_rs1_hzd & !pipe1_issue_rs2_hzd & !pipe1_issue_rd_hzd;

    assign rs1_issue_alu_stable_issue_bypass_o =
        rs1_issue_alu_stable_bypass_o | rs1_branch_ready_next_bypass_o;
    assign rs2_issue_alu_stable_issue_bypass_o =
        rs2_issue_alu_stable_bypass_o | rs2_branch_ready_next_bypass_o;

    assign rs1_issue_alu_ready_next_o =
        rs1_issue_wait_ready_next_raw &
        !rs1_issue_alu_stable_issue_bypass_o;
    assign rs2_issue_alu_ready_next_o =
        rs2_issue_wait_ready_next_raw &
        !rs2_issue_alu_stable_issue_bypass_o;

    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;

    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o ;
    assign flush_ex_o = branch_jump_o;
    // assign flush_mems_o = 1'b0;
    // assign stall_ex_o = clint_stall_i;
	    assign stall_id_o = ex_mul_stall_i;
	    assign stall_if_o = decode_bubble_stall | ex_mul_stall_i;
	    assign stall_pc_o = ex_mul_stall_i;

`ifndef SYNTHESIS
	    always_ff @(posedge clk) begin
	        if (rst_n && id_ex_is_div && ex_mul_stall_q && id_ex_rd_issue_o) begin
	            $fatal(1, "div/rem rd issue repeated while ID/EX is held");
	        end
	    end
`endif

	endmodule
