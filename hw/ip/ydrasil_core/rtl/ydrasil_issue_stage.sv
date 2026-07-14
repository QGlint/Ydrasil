
module ydrasil_issue_stage
import ydrasil_pkg::*;
 #(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            stall_id_i,
    input  wire                            bubble_id_i,
    input  wire                            flush_id_i,

    input  wire                            decode_valid_i,
    input  ydrasil_decode_pkt_t            decode_pkt_i,
    output wire                            issue_ready_o,

    // Register file read ports 
    output wire [4:0]                      rf_addr_rs1_o,
    output wire [4:0]                      rf_addr_rs2_o,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs1_i,
    input  wire [DATA_WIDTH-1:0]           rf_rdata_rs2_i,
    input  ydrasil_gpr_fwd_pkt_t           wb_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs1_fwd_i,
    input  ydrasil_gpr_fwd_pkt_t           producer_rs2_fwd_i,
    input  ydrasil_completion_bus_t        completion_bus_i,
    input  ydrasil_hzd_status_pkt_t        hzd_status_i,
    input  producer_id_t                   producer_alloc_id_i,
    input  wire                            producer_alloc_tracked_i,

    // Dispatch to EX   
    // output wire                            alu_valid_o,
    output wire [DATA_WIDTH-1:0]           operand_a_o,
    output wire [DATA_WIDTH-1:0]           operand_b_o,
    output wire [DATA_WIDTH-1:0]           alu_operand_a_o,
    output wire [DATA_WIDTH-1:0]           alu_operand_b_o,
    output wire [DATA_WIDTH-1:0]           bru_operand_a_o,
    output wire [DATA_WIDTH-1:0]           bru_operand_b_o,
    output wire [DATA_WIDTH-1:0]           lsu_operand_a_o,
    output wire [DATA_WIDTH-1:0]           lsu_operand_b_o,
    output wire [DATA_WIDTH-1:0]           mul_operand_a_o,
    output wire [DATA_WIDTH-1:0]           mul_operand_b_o,
    output wire [DATA_WIDTH-1:0]           csr_operand_a_o,
    output wire [DATA_WIDTH-1:0]           csr_operand_b_o,
    output wire [ydrasil_pkg::OPERATOR_WIDTH-1:0]      operator_o, // 统一的ALU操作信息信号

    output wire [DATA_WIDTH-1:0]           bt_a_operand_o,
    output wire [DATA_WIDTH-1:0]           bt_b_operand_o,

    output ydrasil_lsu_req_pkt_t           lsu_req_o,

    output wire [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0] operator_type_o, // 操作类型信号

    output wire                            id_ex_jalr_o,
    output wire                            id_ex_alu_bypass_rs1_o,
    output wire                            id_ex_alu_bypass_rs2_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_target_o,
    output wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_o,
    output wire                            id_ex_branch_eq_o,
    output wire                            id_ex_branch_ge_signed_o,
    output wire                            id_ex_branch_ge_unsigned_o,
    output ydrasil_id_ctrl_pkt_t           id_ctrl_o,

    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	    id_csr_raddr_o,  
    output wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	    id_ex_csr_waddr_o,  
    output wire [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]    id_op_csr_info_o,
    output wire [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]    id_op_sys_info_o,

    output wire [DATA_WIDTH-1:0]           id_instr_addr_o, // 当前指令地址，供CLINT使用
    output wire                            id_fence_i_o,
    output wire                            id_ex_pred_hit_o,
    output wire                            id_ex_pred_taken_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_target_o,
    output wire [1:0]                      id_ex_pred_counter_o,
    output wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_o,
    output wire                            id_ex_valid_o,
    output wire                            id_ex_operand_wait_o,
    output producer_id_t                   id_ex_producer_id_o,
    output wire                            id_ex_producer_tracked_o,
    // Generic writeback information
    output wire                            id_alu_rf_wen_rd_o,
    output wire [4:0]                      id_rf_waddr_rd_o


);

    reg [4:0]                           rf_waddr_rd_ff;
    reg                                 rf_wen_rd_ff;
    producer_id_t                       producer_id_ff;
    reg                                 producer_tracked_ff;

    reg [DATA_WIDTH-1:0]                id_lsu_store_data_ff;
    reg                                 id_lsu_store_data_valid_ff;
    producer_id_t                       id_lsu_store_data_producer_id_ff;
    reg                                 id_lsu_store_data_producer_tracked_ff;
    reg                                 id_ex_rs1_ready_ff;
    producer_id_t                       id_ex_rs1_producer_id_ff;
    reg                                 id_ex_rs1_producer_tracked_ff;
    reg                                 id_ex_rs2_ready_ff;
    producer_id_t                       id_ex_rs2_producer_id_ff;
    reg                                 id_ex_rs2_producer_tracked_ff;
    reg                                 id_ex_operand_a_uses_rs1_ff;
    reg                                 id_ex_operand_b_uses_rs2_ff;
    reg                                 id_ex_bt_a_uses_rs1_ff;

    reg [ydrasil_pkg::OPERATOR_TYPE_WIDTH-1:0]       operator_type_ff;

    wire [DATA_WIDTH-1:0]                operand_a;
    wire [DATA_WIDTH-1:0]                operand_b;
    reg [DATA_WIDTH-1:0]                operand_a_ff;
    reg [DATA_WIDTH-1:0]                operand_b_ff;
    reg [DATA_WIDTH-1:0]                alu_operand_a_ff;
    reg [DATA_WIDTH-1:0]                alu_operand_b_ff;
    reg [DATA_WIDTH-1:0]                bru_operand_a_ff;
    reg [DATA_WIDTH-1:0]                bru_operand_b_ff;
    reg [DATA_WIDTH-1:0]                lsu_operand_a_ff;
    reg [DATA_WIDTH-1:0]                lsu_operand_b_ff;
    reg [DATA_WIDTH-1:0]                mul_operand_a_ff;
    reg [DATA_WIDTH-1:0]                mul_operand_b_ff;
    reg [DATA_WIDTH-1:0]                csr_operand_a_ff;
    reg [DATA_WIDTH-1:0]                csr_operand_b_ff;
    reg [ydrasil_pkg::OPERATOR_WIDTH-1:0]           operator_ff;

    reg [ydrasil_pkg::OP_LSU_INFO_WIDTH-1:0]         operator_lsu_ff;

    wire [DATA_WIDTH-1:0]                bt_a_operand;
    wire [DATA_WIDTH-1:0]                bt_b_operand;
    reg [DATA_WIDTH-1:0]                 bt_a_operand_ff;
    reg [DATA_WIDTH-1:0]                 bt_b_operand_ff;
    reg [DATA_WIDTH-1:0]                 id_instr_addr_ff;
    reg                                  id_ex_jalr_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs1_ff;
    (* max_fanout = 8 *) reg             id_ex_alu_bypass_rs2_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_pc_target_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_branch_next_pc_ff;
    reg                                  id_ex_pred_hit_ff;
    reg                                  id_ex_pred_taken_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_target_ff;
    reg [1:0]                            id_ex_pred_counter_ff;
    reg [DATA_WIDTH-1:0]                 id_ex_pred_bht_index_ff;
    reg                                  id_ex_valid_ff;
    reg                                  id_fence_i_ff;
    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	 csr_reg_raddr_ff;

    reg [ydrasil_pkg::CSR_ADDR_WIDTH-1:0] 	  csr_ex_waddr_ff; 
	reg [ydrasil_pkg::OP_CSR_INFO_WIDTH-1:0]  csr_op_info_ff;

    reg [ydrasil_pkg::OP_SYS_INFO_WIDTH-1:0]   sys_op_info_ff;

    (* extract_enable = "no" *) ydrasil_decode_pkt_t issue_uop_q;
    reg                                issue_uop_valid_q;
    // A physically independent lookup key keeps the wide issue payload out of
    // the distributed producer scoreboard and its retained operand muxes.
    (* keep = "true", max_fanout = 8 *) ydrasil_id_ctrl_pkt_t issue_hzd_key_q;
    ydrasil_id_ctrl_pkt_t decode_hzd_key;
    wire                            id_advance;
    wire                            issue_valid_ff = issue_uop_valid_q;
    wire [DATA_WIDTH-1:0]           issue_pc_ff = issue_uop_q.pc;
    wire                            issue_pred_hit_ff = issue_uop_q.pred_hit;
    wire                            issue_pred_taken_ff = issue_uop_q.pred_taken;
    wire [DATA_WIDTH-1:0]           issue_pred_target_ff = issue_uop_q.pred_target;
    wire [1:0]                      issue_pred_counter_ff = issue_uop_q.pred_counter;
    wire [DATA_WIDTH-1:0]           issue_pred_bht_index_ff = issue_uop_q.pred_bht_index;
    wire [4:0]                      issue_rf_raddr_rs1_ff = issue_uop_q.rs1_addr;
    wire [4:0]                      issue_rf_raddr_rs2_ff = issue_uop_q.rs2_addr;
    wire                            issue_rf_ren_rs1_ff = issue_uop_q.rs1_ren;
    wire                            issue_rf_ren_rs2_ff = issue_uop_q.rs2_ren;
    wire [4:0]                      issue_rf_waddr_rd_ff = issue_uop_q.rd_addr;
    wire                            issue_rf_wen_rd_ff = issue_uop_q.rd_wen;
    wire [DATA_WIDTH-1:0]           issue_imm_ff = issue_uop_q.imm;
    wire                            issue_operand_b_rs_sel_ff = issue_uop_q.operand_b_rs_sel;
    wire                            issue_operand_a_pc_sel_ff = issue_uop_q.operand_a_pc_sel;
    wire                            issue_operand_a_imm_sel_ff = issue_uop_q.operand_a_imm_sel;
    wire                            issue_bt_a_rs_sel_ff = issue_uop_q.bt_a_rs_sel;
    wire                            issue_operand_b_jump_sel_ff = issue_uop_q.operand_b_jump_sel;
    wire [OPERATOR_WIDTH-1:0]       issue_operator_ff = issue_uop_q.operator_info;
    wire [OP_LSU_INFO_WIDTH-1:0]    issue_operator_lsu_ff = issue_uop_q.operator_lsu;
    wire [OPERATOR_TYPE_WIDTH-1:0]  issue_operator_type_ff = issue_uop_q.operator_type;
    wire [CSR_ADDR_WIDTH-1:0]       issue_csr_reg_raddr_ff = issue_uop_q.csr_raddr;
    wire [CSR_ADDR_WIDTH-1:0]       issue_csr_ex_waddr_ff = issue_uop_q.csr_waddr;
    wire [OP_CSR_INFO_WIDTH-1:0]    issue_csr_op_info_ff = issue_uop_q.csr_op_info;
    wire [OP_SYS_INFO_WIDTH-1:0]    issue_sys_op_info_ff = issue_uop_q.sys_op_info;
    wire                            issue_fence_i_ff = issue_uop_q.fence_i;
    always_comb begin
        decode_hzd_key = '0;
        decode_hzd_key.rs1_addr = decode_pkt_i.rs1_addr;
        decode_hzd_key.rs2_addr = decode_pkt_i.rs2_addr;
        decode_hzd_key.rd_addr = decode_pkt_i.rd_addr;
        decode_hzd_key.rs1_ren = decode_pkt_i.rs1_ren;
        decode_hzd_key.rs2_ren = decode_pkt_i.rs2_ren |
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
        decode_hzd_key.rd_wen = (decode_pkt_i.rd_addr != '0) &
            (decode_pkt_i.rd_wen |
             decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD]);
        decode_hzd_key.lsu_req =
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
        decode_hzd_key.store_req =
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE];
        decode_hzd_key.prev_alu_bypass_ok =
            ((decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_ALU] &
              !decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_BITMANIP] &
              !(decode_pkt_i.operator_info[ydrasil_pkg::OP_ALU_SLL] |
                decode_pkt_i.operator_info[ydrasil_pkg::OP_ALU_SRL] |
                decode_pkt_i.operator_info[ydrasil_pkg::OP_ALU_SRA])) |
             decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
             decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] |
             (decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_BJP] &
              decode_pkt_i.rs1_ren & decode_pkt_i.rs2_ren &
              !decode_pkt_i.rd_wen));
        decode_hzd_key.serialize_before =
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_CSR] |
            decode_pkt_i.operator_type[ydrasil_pkg::OPERATOR_TYPE_SYS] |
            decode_pkt_i.fence_i;
    end
`ifndef SYNTHESIS
    // Retain zero-valued observability points used by the coverage testbench.
    // The former issue-stage early ALU is intentionally removed from hardware.
    wire issue_early_alu_valid_ff = 1'b0;
    wire [5:0] issue_early_kind_ff = '0;
    wire [REGS_ADDR_WIDTH-1:0] issue_early_alu_addr_ff = '0;
    wire rs1_issue_early_alu_fwd = 1'b0;
    wire rs2_issue_early_alu_fwd = 1'b0;
    wire issue_simple_alu_op = 1'b0;
`endif
    assign id_advance = !stall_id_i && !bubble_id_i;
    // The slot is an elastic ownership boundary. It can replace a dispatched
    // uop in the same cycle, preserving one-uop-per-cycle throughput.
    assign issue_ready_o = !issue_uop_valid_q || id_advance;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_uop_q <= '0;
            issue_uop_valid_q <= 1'b0;
            issue_hzd_key_q <= '0;
        end else if (flush_id_i) begin
            issue_uop_valid_q <= 1'b0;
        end else if (issue_ready_o) begin
            issue_uop_valid_q <= decode_valid_i;
            if (decode_valid_i)
                issue_uop_q <= decode_pkt_i;
            if (decode_valid_i)
                issue_hzd_key_q <= decode_hzd_key;
        end
    end

    assign rf_addr_rs1_o = issue_rf_raddr_rs1_ff;
    assign rf_addr_rs2_o = issue_rf_raddr_rs2_ff;

    // Keep ALU source selection consistent with decoder control outputs.
    wire rs1_wb_fwd =
        wb_fwd_i.valid &&
        issue_rf_ren_rs1_ff &&
        (issue_rf_raddr_rs1_ff != '0) &&
        (issue_rf_raddr_rs1_ff == wb_fwd_i.addr);
    wire rs2_wb_fwd =
        wb_fwd_i.valid &&
        (issue_rf_ren_rs2_ff | issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) &&
        (issue_rf_raddr_rs2_ff != '0) &&
        (issue_rf_raddr_rs2_ff == wb_fwd_i.addr);
    wire issue_plain_alu_op =
        issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] &&
        !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BITMANIP];
    wire issue_shift_alu_op = issue_operator_ff[ydrasil_pkg::OP_ALU_SLL] |
        issue_operator_ff[ydrasil_pkg::OP_ALU_SRL] |
        issue_operator_ff[ydrasil_pkg::OP_ALU_SRA];
`ifndef SYNTHESIS
    wire rs1_completion_fwd;
    wire rs2_completion_fwd;
`endif
    reg held_store_wake_valid;
    reg [DATA_WIDTH-1:0] held_store_wake_data;
    reg issue_store_wake_valid;
    reg [DATA_WIDTH-1:0] issue_store_wake_data;
    reg held_rs1_wake_valid;
    reg [DATA_WIDTH-1:0] held_rs1_wake_data;
    reg held_rs2_wake_valid;
    reg [DATA_WIDTH-1:0] held_rs2_wake_data;
    reg issue_rs1_wake_valid;
    reg [DATA_WIDTH-1:0] issue_rs1_wake_data;
    reg issue_rs2_wake_valid;
    reg [DATA_WIDTH-1:0] issue_rs2_wake_data;
    integer held_store_lane;
    always_comb begin
        held_store_wake_valid = 1'b0;
        held_store_wake_data = '0;
        issue_store_wake_valid = 1'b0;
        issue_store_wake_data = '0;
        held_rs1_wake_valid = 1'b0;
        held_rs1_wake_data = '0;
        held_rs2_wake_valid = 1'b0;
        held_rs2_wake_data = '0;
        issue_rs1_wake_valid = 1'b0;
        issue_rs1_wake_data = '0;
        issue_rs2_wake_valid = 1'b0;
        issue_rs2_wake_data = '0;
        for (held_store_lane = 0; held_store_lane < COMPLETION_LANES;
             held_store_lane = held_store_lane + 1) begin
            if (id_ex_valid_ff && id_ex_rs1_producer_tracked_ff &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 id_ex_rs1_producer_id_ff)) begin
                held_rs1_wake_valid = 1'b1;
                held_rs1_wake_data = completion_bus_i[held_store_lane].data;
            end
            if (id_ex_valid_ff && id_ex_rs2_producer_tracked_ff &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 id_ex_rs2_producer_id_ff)) begin
                held_rs2_wake_valid = 1'b1;
                held_rs2_wake_data = completion_bus_i[held_store_lane].data;
            end
            if (id_ex_valid_ff &&
                operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                !id_lsu_store_data_valid_ff &&
                id_lsu_store_data_producer_tracked_ff &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 id_lsu_store_data_producer_id_ff)) begin
                held_store_wake_valid = 1'b1;
                held_store_wake_data = completion_bus_i[held_store_lane].data;
            end
            if (issue_valid_ff &&
                issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                (!hzd_status_i.issue_store_data_ready |
                 hzd_status_i.prev_alu_bypass_rs2) &&
                hzd_status_i.store_data_producer_tracked &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 hzd_status_i.store_data_producer_id)) begin
                issue_store_wake_valid = 1'b1;
                issue_store_wake_data = completion_bus_i[held_store_lane].data;
            end
            if (issue_valid_ff &&
                (hzd_status_i.issue_rs1_wait |
                 hzd_status_i.prev_alu_bypass_rs1) &&
                hzd_status_i.issue_rs1_producer_tracked &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 hzd_status_i.issue_rs1_producer_id)) begin
                issue_rs1_wake_valid = 1'b1;
                issue_rs1_wake_data = completion_bus_i[held_store_lane].data;
            end
            if (issue_valid_ff &&
                (hzd_status_i.issue_rs2_wait |
                 hzd_status_i.prev_alu_bypass_rs2) &&
                hzd_status_i.issue_rs2_producer_tracked &&
                completion_bus_i[held_store_lane].valid &&
                completion_bus_i[held_store_lane].producer_tracked &&
                (completion_bus_i[held_store_lane].producer_id ==
                 hzd_status_i.issue_rs2_producer_id)) begin
                issue_rs2_wake_valid = 1'b1;
                issue_rs2_wake_data = completion_bus_i[held_store_lane].data;
            end
        end
    end

`ifndef SYNTHESIS
    assign rs1_completion_fwd = issue_rs1_wake_valid;
    assign rs2_completion_fwd = issue_rs2_wake_valid;
`endif
    wire [DATA_WIDTH-1:0] issue_rs1_data = issue_rs1_wake_valid ?
        issue_rs1_wake_data : producer_rs1_fwd_i.valid ?
        producer_rs1_fwd_i.data : rs1_wb_fwd ? wb_fwd_i.data : rf_rdata_rs1_i;
    (* keep = "true" *) wire [DATA_WIDTH-1:0] issue_rs2_data = issue_rs2_wake_valid ?
        issue_rs2_wake_data : producer_rs2_fwd_i.valid ?
        producer_rs2_fwd_i.data : rs2_wb_fwd ? wb_fwd_i.data : rf_rdata_rs2_i;
    // Keep the delayed-store wake mux physically separate from the ordinary
    // rs2 operand mux. Their readiness contracts differ after dispatch.
    (* keep = "true" *) wire [DATA_WIDTH-1:0] issue_store_data =
        issue_store_wake_valid ? issue_store_wake_data :
        producer_rs2_fwd_i.valid ? producer_rs2_fwd_i.data :
        rs2_wb_fwd ? wb_fwd_i.data : rf_rdata_rs2_i;
    assign operand_a = issue_operand_a_pc_sel_ff ? issue_pc_ff :
        issue_operand_a_imm_sel_ff ? issue_imm_ff : issue_rs1_data;
    assign operand_b = issue_operand_b_jump_sel_ff ? 32'h4 :
        issue_operand_b_rs_sel_ff ? issue_rs2_data : issue_imm_ff;
    assign bt_a_operand = issue_bt_a_rs_sel_ff ? issue_rs1_data : issue_pc_ff;
    assign bt_b_operand = issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_branch_pc_target = issue_pc_ff + issue_imm_ff;
    wire [DATA_WIDTH-1:0] issue_branch_next_pc = issue_pc_ff + 32'd4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_ff        <= '0;
            operand_b_ff        <= '0;
            alu_operand_a_ff    <= '0;
            alu_operand_b_ff    <= '0;
            bru_operand_a_ff    <= '0;
            bru_operand_b_ff    <= '0;
            lsu_operand_a_ff    <= '0;
            lsu_operand_b_ff    <= '0;
            mul_operand_a_ff    <= '0;
            mul_operand_b_ff    <= '0;
            csr_operand_a_ff    <= '0;
            csr_operand_b_ff    <= '0;
            operator_ff         <= '0;
            operator_type_ff    <= '0;
            rf_wen_rd_ff        <= '0;
            rf_waddr_rd_ff      <= '0;
            producer_id_ff      <= '0;
            producer_tracked_ff <= 1'b0;
            operator_lsu_ff     <= '0;
            id_lsu_store_data_ff <= '0;
            id_lsu_store_data_valid_ff <= 1'b0;
            id_lsu_store_data_producer_id_ff <= '0;
            id_lsu_store_data_producer_tracked_ff <= 1'b0;
            id_ex_rs1_ready_ff <= 1'b1;
            id_ex_rs1_producer_id_ff <= '0;
            id_ex_rs1_producer_tracked_ff <= 1'b0;
            id_ex_rs2_ready_ff <= 1'b1;
            id_ex_rs2_producer_id_ff <= '0;
            id_ex_rs2_producer_tracked_ff <= 1'b0;
            id_ex_operand_a_uses_rs1_ff <= 1'b0;
            id_ex_operand_b_uses_rs2_ff <= 1'b0;
            id_ex_bt_a_uses_rs1_ff <= 1'b0;
            bt_a_operand_ff     <= '0;
            bt_b_operand_ff     <= '0;
            csr_reg_raddr_ff <= '0;
            // csr_ex_we_ff <= 1'b0;
            csr_ex_waddr_ff <= '0;
            csr_op_info_ff <= '0;
            sys_op_info_ff <= '0;
            id_instr_addr_ff <= '0;
            id_ex_jalr_ff <= 1'b0;
            id_ex_alu_bypass_rs1_ff <= 1'b0;
            id_ex_alu_bypass_rs2_ff <= 1'b0;
            id_ex_branch_pc_target_ff <= '0;
            id_ex_branch_next_pc_ff <= '0;
            id_ex_pred_hit_ff <= 1'b0;
            id_ex_pred_taken_ff <= 1'b0;
            id_ex_pred_target_ff <= '0;
            id_ex_pred_counter_ff <= 2'b01;
            id_ex_pred_bht_index_ff <= '0;
            id_ex_valid_ff <= 1'b0;
            id_fence_i_ff <= 1'b0;
        end else begin
            if (!stall_id_i) begin
                operand_a_ff        <= operand_a;
                operand_b_ff        <= operand_b;
                alu_operand_a_ff    <= operand_a;
                alu_operand_b_ff    <= operand_b;
                bru_operand_a_ff    <= operand_a;
                bru_operand_b_ff    <= operand_b;
                lsu_operand_a_ff    <= operand_a;
                lsu_operand_b_ff    <= operand_b;
                mul_operand_a_ff    <= operand_a;
                mul_operand_b_ff    <= operand_b;
                csr_operand_a_ff    <= operand_a;
                csr_operand_b_ff    <= operand_b;
                operator_ff         <= issue_operator_ff;
                operator_type_ff    <= issue_operator_type_ff;
                rf_wen_rd_ff        <= issue_rf_wen_rd_ff;
                rf_waddr_rd_ff      <= issue_rf_waddr_rd_ff;
                producer_id_ff      <= producer_alloc_id_i;
                producer_tracked_ff <= producer_alloc_tracked_i;
                operator_lsu_ff     <= issue_operator_lsu_ff;
                // Register raw store data here; lane alignment belongs after the
                // ID/LSU boundary so the RF read path does not also include the
                // LSU address adder and byte-lane mux.
                id_lsu_store_data_ff <= issue_store_data;
                id_lsu_store_data_valid_ff <=
                    !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    (hzd_status_i.issue_store_data_ready &
                     !hzd_status_i.prev_alu_bypass_rs2) |
                    issue_store_wake_valid;
                id_lsu_store_data_producer_id_ff <=
                    hzd_status_i.store_data_producer_id;
                id_lsu_store_data_producer_tracked_ff <=
                    hzd_status_i.store_data_producer_tracked &
                    (hzd_status_i.store_data_wait |
                     hzd_status_i.prev_alu_bypass_rs2) &
                    !issue_store_wake_valid;
                id_ex_rs1_ready_ff <= !hzd_status_i.issue_rs1_wait |
                    issue_rs1_wake_valid;
                id_ex_rs1_producer_id_ff <=
                    hzd_status_i.issue_rs1_producer_id;
                id_ex_rs1_producer_tracked_ff <=
                    (hzd_status_i.issue_rs1_wait |
                     hzd_status_i.prev_alu_bypass_rs1) &
                    hzd_status_i.issue_rs1_producer_tracked &
                    !issue_rs1_wake_valid;
                // Store data has its own non-blocking token carried to LSU.
                id_ex_rs2_ready_ff <=
                    issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    !hzd_status_i.issue_rs2_wait | issue_rs2_wake_valid;
                id_ex_rs2_producer_id_ff <=
                    hzd_status_i.issue_rs2_producer_id;
                id_ex_rs2_producer_tracked_ff <=
                    !issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &
                    (hzd_status_i.issue_rs2_wait |
                     hzd_status_i.prev_alu_bypass_rs2) &
                    hzd_status_i.issue_rs2_producer_tracked &
                    !issue_rs2_wake_valid;
                id_ex_operand_a_uses_rs1_ff <= issue_rf_ren_rs1_ff &
                    !issue_operand_a_pc_sel_ff & !issue_operand_a_imm_sel_ff;
                id_ex_operand_b_uses_rs2_ff <= issue_rf_ren_rs2_ff &
                    issue_operand_b_rs_sel_ff;
                id_ex_bt_a_uses_rs1_ff <= issue_bt_a_rs_sel_ff;
                bt_a_operand_ff     <= bt_a_operand;
                bt_b_operand_ff     <= bt_b_operand;
                csr_reg_raddr_ff <= issue_csr_reg_raddr_ff;
                // csr_ex_we_ff <= csr_ex_we;
                csr_ex_waddr_ff <= issue_csr_ex_waddr_ff;
                csr_op_info_ff <= issue_csr_op_info_ff;
                sys_op_info_ff <= issue_sys_op_info_ff;
                id_instr_addr_ff <= issue_pc_ff;
                id_ex_jalr_ff <= issue_bt_a_rs_sel_ff;
                id_ex_alu_bypass_rs1_ff <= issue_valid_ff & hzd_status_i.prev_alu_bypass_rs1;
                id_ex_alu_bypass_rs2_ff <= issue_valid_ff & hzd_status_i.prev_alu_bypass_rs2;
                id_ex_branch_pc_target_ff <= issue_branch_pc_target;
                id_ex_branch_next_pc_ff <= issue_branch_next_pc;
                id_ex_pred_hit_ff <= issue_pred_hit_ff;
                id_ex_pred_taken_ff <= issue_pred_taken_ff;
                id_ex_pred_target_ff <= issue_pred_target_ff;
                id_ex_pred_counter_ff <= issue_pred_counter_ff;
                id_ex_pred_bht_index_ff <= issue_pred_bht_index_ff;
            end else if (stall_id_i && !flush_id_i) begin
                // Completion wakes retained operands at the clock boundary.
                // EX cannot observe completion data until the following cycle.
                // A previous-ALU bypass is valid for only the first cycle in
                // ID/EX. If this packet is held, consume the token and wait
                // for the same producer's registered completion instead of
                // observing a later value on the rolling ALU bypass register.
                if (id_ex_alu_bypass_rs1_ff) begin
                    id_ex_alu_bypass_rs1_ff <= 1'b0;
                    id_ex_rs1_ready_ff <= 1'b0;
                end
                if (id_ex_alu_bypass_rs2_ff) begin
                    id_ex_alu_bypass_rs2_ff <= 1'b0;
                    if (!operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE])
                        id_ex_rs2_ready_ff <= 1'b0;
                end
                if (held_rs1_wake_valid) begin
                    id_ex_rs1_ready_ff <= 1'b1;
                    id_ex_rs1_producer_tracked_ff <= 1'b0;
                    if (id_ex_operand_a_uses_rs1_ff) begin
                        operand_a_ff <= held_rs1_wake_data;
                        alu_operand_a_ff <= held_rs1_wake_data;
                        bru_operand_a_ff <= held_rs1_wake_data;
                        lsu_operand_a_ff <= held_rs1_wake_data;
                        mul_operand_a_ff <= held_rs1_wake_data;
                        csr_operand_a_ff <= held_rs1_wake_data;
                    end
                    if (id_ex_bt_a_uses_rs1_ff)
                        bt_a_operand_ff <= held_rs1_wake_data;
                end
                if (held_rs2_wake_valid) begin
                    id_ex_rs2_ready_ff <= 1'b1;
                    id_ex_rs2_producer_tracked_ff <= 1'b0;
                    if (id_ex_operand_b_uses_rs2_ff) begin
                        operand_b_ff <= held_rs2_wake_data;
                        alu_operand_b_ff <= held_rs2_wake_data;
                        bru_operand_b_ff <= held_rs2_wake_data;
                        lsu_operand_b_ff <= held_rs2_wake_data;
                        mul_operand_b_ff <= held_rs2_wake_data;
                        csr_operand_b_ff <= held_rs2_wake_data;
                    end
                end
                if (held_store_wake_valid) begin
                    id_lsu_store_data_ff <= held_store_wake_data;
                    id_lsu_store_data_valid_ff <= 1'b1;
                    id_lsu_store_data_producer_tracked_ff <= 1'b0;
                end
            end

            if (flush_id_i) begin
                id_ex_valid_ff <= 1'b0;
                id_ex_rs1_ready_ff <= 1'b1;
                id_ex_rs1_producer_tracked_ff <= 1'b0;
                id_ex_rs2_ready_ff <= 1'b1;
                id_ex_rs2_producer_tracked_ff <= 1'b0;
                id_ex_alu_bypass_rs1_ff <= 1'b0;
                id_ex_alu_bypass_rs2_ff <= 1'b0;
                id_fence_i_ff <= 1'b0;
            end else if (id_advance) begin
                id_ex_valid_ff <= issue_valid_ff;
                id_fence_i_ff <= issue_valid_ff & issue_fence_i_ff;
            end else if (stall_id_i) begin
                // A backend replay holds the complete ID/EX packet. Do not let
                // a simultaneous decode bubble clear only its valid/bypass bits.
                id_ex_valid_ff <= id_ex_valid_ff;
                id_fence_i_ff <= id_fence_i_ff;
            end else if (bubble_id_i) begin
                id_ex_valid_ff <= 1'b0;
                // The invalid bit already suppresses the complete ID/EX
                // packet. Leave payload controls on their normal update path
                // so scoreboard bubble generation is not part of their D cone.
                id_fence_i_ff <= 1'b0;
            end else begin
                id_fence_i_ff <= 1'b0;
            end
        end
    end

    // Completion only updates these retained operands at a clock boundary.
    // No completion tag/data path is allowed to continue into an EX datapath.
    assign operand_a_o = operand_a_ff;
    assign operand_b_o = operand_b_ff;
    assign alu_operand_a_o = alu_operand_a_ff;
    assign alu_operand_b_o = alu_operand_b_ff;
    assign bru_operand_a_o = bru_operand_a_ff;
    assign bru_operand_b_o = bru_operand_b_ff;
    assign lsu_operand_a_o = lsu_operand_a_ff;
    assign lsu_operand_b_o = lsu_operand_b_ff;
    assign mul_operand_a_o = mul_operand_a_ff;
    assign mul_operand_b_o = mul_operand_b_ff;
    assign csr_operand_a_o = csr_operand_a_ff;
    assign csr_operand_b_o = csr_operand_b_ff;
    assign operator_o           = operator_ff;
    assign id_alu_rf_wen_rd_o   = rf_wen_rd_ff;
    assign id_rf_waddr_rd_o     = rf_waddr_rd_ff;
    assign operator_type_o      = operator_type_ff;
    assign lsu_req_o.valid = id_ex_valid_ff &
        (operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
         operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]);
    assign lsu_req_o.is_load = operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD];
    assign lsu_req_o.is_store = operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE];
    assign lsu_req_o.op = operator_lsu_ff;
    // EX supplies the address after applying its local previous-ALU bypass.
    assign lsu_req_o.addr = '0;
    assign lsu_req_o.addr_is_dtcm = 1'b0;
    assign lsu_req_o.rd_addr = rf_waddr_rd_ff;
    assign lsu_req_o.producer_id = producer_id_ff;
    assign lsu_req_o.producer_tracked = producer_tracked_ff;
    assign lsu_req_o.store_data = id_lsu_store_data_ff;
    assign lsu_req_o.store_mask = '0;
    assign lsu_req_o.store_data_valid = id_lsu_store_data_valid_ff;
    assign lsu_req_o.store_data_producer_id = id_lsu_store_data_producer_id_ff;
    assign lsu_req_o.store_data_producer_tracked =
        id_lsu_store_data_producer_tracked_ff;
    assign bt_a_operand_o       = bt_a_operand_ff;
    assign bt_b_operand_o       = bt_b_operand_ff;
    assign  id_csr_raddr_o = csr_reg_raddr_ff;
    // assign  id_ex_csr_we_o = csr_ex_we_ff;
    assign  id_ex_csr_waddr_o = csr_ex_waddr_ff;
    assign  id_op_csr_info_o = csr_op_info_ff;
    assign  id_op_sys_info_o = sys_op_info_ff;
    assign id_instr_addr_o = id_instr_addr_ff;
    assign id_ex_jalr_o = id_ex_jalr_ff;
    assign id_ex_alu_bypass_rs1_o = id_ex_alu_bypass_rs1_ff;
    assign id_ex_alu_bypass_rs2_o = id_ex_alu_bypass_rs2_ff;
    assign id_ex_branch_target_o = id_ex_branch_pc_target_ff;
    assign id_ex_branch_next_pc_o = id_ex_branch_next_pc_ff;
    // Branch comparisons are local to EX so decode/issue does not carry a
    // register-file/producer mux through three comparators.
    assign id_ex_branch_eq_o = 1'b0;
    assign id_ex_branch_ge_signed_o = 1'b0;
    assign id_ex_branch_ge_unsigned_o = 1'b0;
    assign id_fence_i_o = id_fence_i_ff;
    assign id_ex_pred_hit_o = id_ex_pred_hit_ff;
    assign id_ex_pred_taken_o = id_ex_pred_taken_ff;
    assign id_ex_pred_target_o = id_ex_pred_target_ff;
    assign id_ex_pred_counter_o = id_ex_pred_counter_ff;
    assign id_ex_pred_bht_index_o = id_ex_pred_bht_index_ff;
    assign id_ex_valid_o = id_ex_valid_ff;
    assign id_ex_operand_wait_o = id_ex_valid_ff &
        (!id_ex_rs1_ready_ff | !id_ex_rs2_ready_ff);
    assign id_ex_producer_id_o = producer_id_ff;
    assign id_ex_producer_tracked_o = producer_tracked_ff;

    assign id_ctrl_o.rs1_addr = issue_hzd_key_q.rs1_addr;
    assign id_ctrl_o.rs2_addr = issue_hzd_key_q.rs2_addr;
    assign id_ctrl_o.rd_addr = issue_hzd_key_q.rd_addr;
    assign id_ctrl_o.rs1_ren = issue_valid_ff & issue_hzd_key_q.rs1_ren;
    assign id_ctrl_o.rs2_ren = issue_valid_ff & issue_hzd_key_q.rs2_ren;
    assign id_ctrl_o.rd_wen = issue_valid_ff & issue_hzd_key_q.rd_wen;
    assign id_ctrl_o.lsu_req = issue_valid_ff & issue_hzd_key_q.lsu_req;
    assign id_ctrl_o.store_req = issue_valid_ff & issue_hzd_key_q.store_req;
    assign id_ctrl_o.prev_alu_bypass_ok = issue_valid_ff &
        issue_hzd_key_q.prev_alu_bypass_ok;
    assign id_ctrl_o.serialize_before = issue_valid_ff &
        issue_hzd_key_q.serialize_before;

endmodule
