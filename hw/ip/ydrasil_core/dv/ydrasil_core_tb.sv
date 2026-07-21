`timescale 1ns/1ns

parameter longint time_end = 100000; 

module ydrasil_core_tb
(
`ifdef VERILATOR_CC
    input clk,
    input rst_n
`endif

);
string itcmfile;
string dtcmfile;
// ToHost程序地址,用于监控测试是否结束
`define PC_WRITE_TOHOST 32'h80000040
// ITCM 访问路径
`define ITCM u_dut.u_ydrasil_mems.u_itcm.u_irom
`define DTCM u_dut.u_ydrasil_mems.u_dtcm.u_dram

longint time_out;
longint sv_timeout;
initial begin
    if ($value$plusargs("itcmfile=%s", itcmfile)) begin
      $display("Loading memory from %s", itcmfile);
      $readmemh(itcmfile, `ITCM.mem_r);
    end else begin
      $display("No itcmfile provided");
    end

    if ($value$plusargs("dtcmfile=%s", dtcmfile)) begin
      $display("Loading memory from %s", dtcmfile);
      $readmemh(dtcmfile, `DTCM.mem_r);
    end else begin
      $display("No dtcmfile provided");
    end

    if ($value$plusargs("sv_timeout=%d", time_out))begin
        sv_timeout = time_out;
    end else begin
        sv_timeout = time_end;
    end
end



`ifndef VERILATOR_CC
	logic        clk;
	logic        rst_n;
`endif

	logic [31:0] perip_addr;
	logic        perip_wen;
	logic [3:0]  perip_mask;
	logic [31:0] perip_wdata;
	logic [31:0] perip_rdata;

    // 通用寄存器访问 - 仅用于错误信息显示
    wire [31:0] x3 = u_dut.u_ydrasil_registers.registers[3];
    // PC 监控
    wire [31:0] pc = u_dut.u_ydrasil_if_stage.pc_ff;
    wire [31:0] csr_instret = u_dut.u_ydrasil_registers_csr.instret[31:0];
    wire [31:0] csr_cyclel = u_dut.u_ydrasil_registers_csr.cycle[31:0];

    integer           r;
    reg     [8*300:1] testcase;

    // 计算ITCM的深度和字节大小
    localparam ITCM_DEPTH = (1 << (ydrasil_pkg::ITCM_ADDR_WIDTH));  // ITCM中的字数
    localparam ITCM_BYTE_SIZE = ITCM_DEPTH * 4;  // 总字节数

    // 创建与ITCM容量相同的临时字节数组
    reg [7:0] prog_mem[0:ITCM_BYTE_SIZE-1];
    integer i;

    // 添加PC监控变量
    reg [31:0] pc_write_to_host_cnt;
    reg [31:0] pc_write_to_host_cycle;
    wire  [31:0] cycle_count = csr_cyclel;
    reg pc_write_to_host_flag;
    reg [31:0] last_pc;

    // 添加指令计数和IPC计算相关变量
    wire [31:0] instruction_count = csr_instret; // Use CSR instret as the retired instruction count.
    real ipc;
    real bp_accuracy;

`ifndef SYNTHESIS
    wire [31:0] dbg_bp_predict_pc;
    wire        dbg_bp_predict_hit;
    wire        dbg_bp_predict_taken;
    wire [31:0] dbg_bp_predict_target;
    wire [1:0]  dbg_bp_predict_counter;
    wire        dbg_bp_resolve_valid;
    wire [31:0] dbg_bp_resolve_pc;
    wire        dbg_bp_actual_taken;
    wire [31:0] dbg_bp_actual_target;
    wire [31:0] dbg_bp_actual_next_pc;
    wire        dbg_bp_pred_hit;
    wire        dbg_bp_pred_taken;
    wire [31:0] dbg_bp_pred_target;
    wire [1:0]  dbg_bp_pred_counter;
    wire [31:0] dbg_bp_pred_next_pc;
    wire        dbg_bp_mispredict;

    wire bp_branch_valid = dbg_bp_resolve_valid;
    wire bp_pred_hit = dbg_bp_pred_hit;
    wire bp_pred_taken = dbg_bp_pred_hit & dbg_bp_pred_taken;
    wire bp_actual_taken = dbg_bp_actual_taken;
    wire bp_mispredict = dbg_bp_mispredict;
    wire bp_dir_mispredict = bp_pred_taken ^ bp_actual_taken;
    wire bp_target_mispredict =
        bp_actual_taken & bp_pred_taken & (dbg_bp_pred_target != dbg_bp_actual_target);
    wire bp_btb_miss_taken = bp_actual_taken & !dbg_bp_pred_hit;
    wire bp_correct_taken =
        bp_actual_taken & bp_pred_taken & (dbg_bp_pred_target == dbg_bp_actual_target);
    wire bp_correct_not_taken = !bp_actual_taken & !bp_pred_taken;
`else
    wire bp_branch_valid = 1'b0;
    wire bp_pred_hit = 1'b0;
    wire bp_pred_taken = 1'b0;
    wire bp_actual_taken = 1'b0;
    wire bp_mispredict = 1'b0;
    wire bp_dir_mispredict = 1'b0;
    wire bp_target_mispredict = 1'b0;
    wire bp_btb_miss_taken = 1'b0;
    wire bp_correct_taken = 1'b0;
    wire bp_correct_not_taken = 1'b0;
`endif
`ifndef SYNTHESIS
    bit bp_trace_en;
    bit bp_fetch_trace_en;
`endif
    reg [31:0] bp_branch_count;
    reg [31:0] bp_hit_count;
    reg [31:0] bp_taken_count;
    reg [31:0] bp_actual_taken_count;
    reg [31:0] bp_actual_not_taken_count;
    reg [31:0] bp_mispredict_count;
    reg [31:0] bp_dir_mispredict_count;
    reg [31:0] bp_target_mispredict_count;
    reg [31:0] bp_btb_miss_taken_count;
    reg [31:0] bp_correct_taken_count;
    reg [31:0] bp_correct_not_taken_count;
    reg [31:0] stall_scoreboard_count;
    reg [31:0] stall_lsu_struct_count;
    reg [31:0] stall_wb_backpressure_count;
    reg [31:0] stall_clint_count;
    reg [31:0] stall_mul_count;
    reg [31:0] sb_rs1_pending_count;
    reg [31:0] sb_rs2_pending_count;
    reg [31:0] sb_rd_waw_count;
    reg [31:0] sb_issue_rs1_hzd_count;
    reg [31:0] sb_issue_rs2_hzd_count;
    reg [31:0] sb_issue_rd_hzd_count;
    reg [31:0] sb_load_use_count;
    reg [31:0] sb_alu_use_count;
    reg [31:0] sb_mul_div_use_count;
    reg [31:0] sb_branch_src_wait_count;
    reg [31:0] sb_store_addr_wait_count;
    reg [31:0] sb_store_data_wait_count;
    reg [31:0] completion_alu_lsu_count;
    reg [31:0] completion_alu_mul_count;
    reg [31:0] completion_lsu_mul_count;
    reg [31:0] completion_all_count;
    reg [31:0] completion_alu_lsu_then_mul_count;
    reg [31:0] completion_mul_then_alu_lsu_count;
    reg        completion_alu_lsu_q;
    reg        completion_mul_q;
    reg [31:0] lifecycle_complete_only_count;
    reg [31:0] lifecycle_retire_only_count;
    reg [31:0] lifecycle_allocate_only_count;
    reg [31:0] lifecycle_complete_retire_count;
    reg [31:0] lifecycle_retire_allocate_count;
    reg [31:0] lifecycle_complete_allocate_count;
    reg [31:0] lifecycle_all_count;
    reg [31:0] same_slot_complete_only_count;
    reg [31:0] same_slot_retire_only_count;
    reg [31:0] same_slot_allocate_only_count;
    reg [31:0] same_slot_complete_retire_count;
    reg [31:0] same_slot_retire_allocate_count;
    reg [31:0] same_slot_complete_allocate_count;
    reg [31:0] same_slot_all_count;
    reg [31:0] sb_load_to_alu_count;
    reg [31:0] sb_load_to_branch_count;
    reg [31:0] sb_load_to_load_count;
    reg [31:0] sb_load_to_store_count;
    reg [31:0] sb_load_to_mul_count;
    reg [31:0] sb_load_to_other_count;
    reg [31:0] sb_load_rs1_count;
    reg [31:0] sb_load_rs2_count;
    reg [31:0] sb_pending_tail_count;
    reg [31:0] sb_alu_to_alu_count;
    reg [31:0] sb_alu_to_branch_count;
    reg [31:0] sb_alu_to_load_count;
    reg [31:0] sb_alu_to_store_count;
    reg [31:0] sb_alu_to_mul_count;
    reg [31:0] sb_alu_to_other_count;
    reg [31:0] sb_pending_alu_count;
    reg [31:0] sb_pending_load_count;
    reg [31:0] sb_pending_mul_count;
    reg [31:0] sb_pending_other_count;
    reg [31:0] sb_ready_but_stall_count;
    reg [31:0] sb_complete_visible_count;
    reg [31:0] sb_registered_visible_count;
    reg [31:0] acct_flush_count;
    reg [31:0] acct_mul_hold_count;
    reg [31:0] acct_scoreboard_count;
    reg [31:0] acct_lsu_struct_count;
    reg [31:0] acct_lsu_serialize_count;
    reg [31:0] acct_producer_full_count;
    reg [31:0] acct_wb_count;
    reg [31:0] acct_clint_count;
    reg [31:0] acct_multi_cause_count;
    reg [31:0] acct_no_if_valid_count;
    reg [31:0] acct_issue_count;
    reg [31:0] acct_other_count;
    reg [31:0] perf_sample_cycle_count;
    reg [31:0] noif_control_redirect_count;
    reg [31:0] noif_predict_redirect_count;
    reg [31:0] noif_fence_refill_count;
    reg [31:0] noif_mem_response_count;
    reg [31:0] noif_fetch_launch_count;
    reg [31:0] noif_pending_redirect_count;
    reg [31:0] noif_other_count;
    reg [31:0] other_issue_refill_count;
    reg [31:0] other_decode_refill_count;
    reg [31:0] decode_refill_after_control_count;
    reg [31:0] decode_refill_after_predict_count;
    reg [31:0] decode_refill_after_fence_count;
    reg [31:0] decode_refill_after_supply_count;
    reg [31:0] other_issue_blocked_count;
    reg [31:0] other_unclassified_count;
    reg        control_refill_active_q;
    reg        predict_refill_active_q;
    reg        fence_refill_active_q;
    reg [31:0] acct_raw_only_count;
    reg [31:0] acct_waw_only_count;
    reg [31:0] acct_raw_waw_count;
    reg [31:0] retire_zero_count;
    reg [31:0] retire_one_count;
    reg [31:0] retire_two_count;
    reg [31:0] retire_three_count;
    reg [31:0] bubble_cause_hist [0:31];
    reg [31:0] producer_occ_zero_count;
    reg [31:0] producer_occ_one_count;
    reg [31:0] producer_occ_two_count;
    reg [31:0] producer_both_wait_count;
    reg [31:0] producer_wait_ready_count;
    reg [31:0] producer_both_ready_count;
    reg [31:0] producer_retire_held_count;
    reg [31:0] producer_normal_drain_count;
    reg [31:0] producer_flush_drain_count;
    reg [31:0] producer_trap_free_count;
    reg        producer_nonempty_q;
    reg        producer_flush_q;
    reg [31:0] lsu_head_wrap_count;
    reg [31:0] lsu_tail_wrap_count;
    reg [31:0] lsu_queue_empty_count;
    reg [31:0] lsu_queue_near_full_count;
    reg [31:0] lsu_queue_full_count;
    reg [31:0] lsu_queue_pop_count;
    reg [31:0] lsu_struct_mmio_count;
    reg [31:0] lsu_struct_pending_store_count;
    reg [31:0] lsu_struct_store_capture_count;
    reg [31:0] lsu_struct_other_count;
    reg [31:0] early_arith_count;
    reg [31:0] early_logic_count;
    reg [31:0] early_shift_count;
    reg [31:0] early_pass_count;
    reg [31:0] early_rs1_fwd_count;
    reg [31:0] early_rs2_fwd_count;
    reg [31:0] early_both_fwd_count;
    reg [31:0] early_to_alu_count;
    reg [31:0] early_to_load_count;
    reg [31:0] early_to_store_count;
    reg [31:0] early_completion_source_count;
    reg [31:0] early_stall_hold_count;
    reg [31:0] early_flush_clear_count;
    reg [31:0] early_bubble_clear_count;
    reg [31:0] non_early_alu_count;
    integer perf_stat_idx;
    reg [31:0] fe_pred_taken_redirect_count;
    reg [31:0] fe_correct_taken_redirect_count;
    reg [31:0] fe_pred_taken_bubble_count;
    reg [31:0] fe_wrong_dir_flush_count;
    reg        bp_predict_redirect_q;

	ydrasil_core u_dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.perip_addr (perip_addr),
		.perip_wen  (perip_wen),
		.perip_mask (perip_mask),
		.perip_wdata(perip_wdata),
		.perip_rdata(perip_rdata)
`ifndef SYNTHESIS
        ,.dbg_bp_predict_pc_o(dbg_bp_predict_pc)
        ,.dbg_bp_predict_hit_o(dbg_bp_predict_hit)
        ,.dbg_bp_predict_taken_o(dbg_bp_predict_taken)
        ,.dbg_bp_predict_target_o(dbg_bp_predict_target)
        ,.dbg_bp_predict_counter_o(dbg_bp_predict_counter)
        ,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid)
        ,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc)
        ,.dbg_bp_actual_taken_o(dbg_bp_actual_taken)
        ,.dbg_bp_actual_target_o(dbg_bp_actual_target)
        ,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc)
        ,.dbg_bp_pred_hit_o(dbg_bp_pred_hit)
        ,.dbg_bp_pred_taken_o(dbg_bp_pred_taken)
        ,.dbg_bp_pred_target_o(dbg_bp_pred_target)
        ,.dbg_bp_pred_counter_o(dbg_bp_pred_counter)
        ,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc)
        ,.dbg_bp_mispredict_o(dbg_bp_mispredict)
`endif
	);

`ifndef SYNTHESIS
    logic interrupt_q;
    logic early_clear_q;
    integer completion_assert_lane;
    integer completion_assert_other_lane;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_q <= 1'b0;
            early_clear_q <= 1'b0;
        end else begin
            interrupt_q <= u_dut.interrupt;
            early_clear_q <= u_dut.flush_id || u_dut.bubble_id;

            if (u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff) begin
                assert ($onehot(u_dut.u_ydrasil_issue_stage.issue_early_kind_ff))
                    else $fatal(1, "ASSERT_EARLY_KIND_NOT_ONEHOT kind=0x%0h",
                                u_dut.u_ydrasil_issue_stage.issue_early_kind_ff);
                assert (u_dut.u_ydrasil_issue_stage.issue_early_alu_addr_ff != '0)
                    else $fatal(1, "ASSERT_EARLY_TRACKS_X0");
            end else begin
                assert (u_dut.u_ydrasil_issue_stage.issue_early_kind_ff == '0)
                    else $fatal(1, "ASSERT_EARLY_KIND_WITHOUT_VALID kind=0x%0h",
                                u_dut.u_ydrasil_issue_stage.issue_early_kind_ff);
            end
            if (early_clear_q) begin
                assert (!u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff &&
                        (u_dut.u_ydrasil_issue_stage.issue_early_kind_ff == '0))
                    else $fatal(1, "ASSERT_EARLY_NOT_CLEARED valid=%0b kind=0x%0h",
                                u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff,
                                u_dut.u_ydrasil_issue_stage.issue_early_kind_ff);
            end

            assert (u_dut.u_ydrasil_registers.registers[0] == 32'b0)
                else $fatal(1, "ASSERT_X0_NONZERO value=0x%08h",
                            u_dut.u_ydrasil_registers.registers[0]);
            assert (u_dut.u_ydrasil_if_stage.pc_ff[1:0] == 2'b00)
                else $fatal(1, "ASSERT_PC_MISALIGNED pc=0x%08h",
                            u_dut.u_ydrasil_if_stage.pc_ff);
            assert (!u_dut.gpr_pending_q[0])
                else $fatal(1, "ASSERT_SCOREBOARD_TRACKS_X0 pending=0x%08h",
                            u_dut.gpr_pending_q);
            assert (!(u_dut.dtcm_req && u_dut.mmio_req))
                else $fatal(1, "ASSERT_DUAL_DATA_TARGET addr=0x%08h",
                            u_dut.ex_lsu_mem_addr);
            assert (!u_dut.dtcm_we || (u_dut.dtcm_req && (|u_dut.dtcm_wmask)))
                else $fatal(1, "ASSERT_BAD_DTCM_WRITE req=%0b mask=0x%01h addr=0x%08h",
                            u_dut.dtcm_req, u_dut.dtcm_wmask, u_dut.dtcm_addr);
            assert (!u_dut.mmio_we || (u_dut.mmio_req && (|u_dut.mmio_wmask)))
                else $fatal(1, "ASSERT_BAD_MMIO_WRITE req=%0b mask=0x%01h addr=0x%08h",
                            u_dut.mmio_req, u_dut.mmio_wmask, u_dut.mmio_addr);
            assert ((u_dut.flush_if == u_dut.branch_jump) &&
                    (u_dut.flush_id == u_dut.branch_jump) &&
                    (u_dut.flush_ex == u_dut.branch_jump))
                else $fatal(1, "ASSERT_INCOHERENT_FLUSH branch=%0b if=%0b id=%0b ex=%0b",
                            u_dut.branch_jump, u_dut.flush_if,
                            u_dut.flush_id, u_dut.flush_ex);
            if (interrupt_q) begin
                assert (u_dut.gpr_pending_q == '0)
                    else $fatal(1, "ASSERT_PENDING_AFTER_INTERRUPT pending=0x%08h",
                                u_dut.gpr_pending_q);
                assert (u_dut.u_ctrl.producer_valid_q == '0)
                    else $fatal(1, "ASSERT_TOKEN_AFTER_INTERRUPT valid=0x%0h",
                                u_dut.u_ctrl.producer_valid_q);
                assert (u_dut.u_ydrasil_load_store_unit.queue_count_q == '0)
                    else $fatal(1, "ASSERT_LSU_QUEUE_AFTER_INTERRUPT count=%0d",
                                u_dut.u_ydrasil_load_store_unit.queue_count_q);
            end
            assert (u_dut.u_ydrasil_load_store_unit.queue_count_q <= 4)
                else $fatal(1, "ASSERT_LSU_QUEUE_COUNT count=%0d",
                            u_dut.u_ydrasil_load_store_unit.queue_count_q);
            if (u_dut.clint_csr_we) begin
                assert ((u_dut.clint_csr_waddr == ydrasil_pkg::CSR_MSTATUS) ||
                        (u_dut.clint_csr_waddr == ydrasil_pkg::CSR_MEPC) ||
                        (u_dut.clint_csr_waddr == ydrasil_pkg::CSR_MCAUSE))
                    else $fatal(1, "ASSERT_BAD_TRAP_CSR_WRITE addr=0x%03h data=0x%08h",
                                u_dut.clint_csr_waddr, u_dut.clint_csr_wdata);
            end
            for (completion_assert_lane = 0;
                 completion_assert_lane < ydrasil_pkg::COMPLETION_LANES;
                 completion_assert_lane = completion_assert_lane + 1) begin
                if (u_dut.completion_bus[completion_assert_lane].valid &&
                    u_dut.completion_bus[completion_assert_lane].producer_tracked &&
                    (u_dut.completion_bus[completion_assert_lane].addr != '0)) begin
                    assert (u_dut.u_ctrl.producer_valid_q[
                                u_dut.completion_bus[completion_assert_lane].producer_id] ||
                            (u_dut.u_ctrl.producer_alloc_ex &&
                             (u_dut.ex_hzd_pkt.producer_id ==
                              u_dut.completion_bus[completion_assert_lane].producer_id)))
                        else $fatal(1,
                            "ASSERT_COMPLETION_FOR_FREE_TOKEN lane=%0d id=%0d rd=%0d data=0x%08h",
                            completion_assert_lane,
                            u_dut.completion_bus[completion_assert_lane].producer_id,
                            u_dut.completion_bus[completion_assert_lane].addr,
                            u_dut.completion_bus[completion_assert_lane].data);
                end
                for (completion_assert_other_lane = completion_assert_lane + 1;
                     completion_assert_other_lane < ydrasil_pkg::COMPLETION_LANES;
                     completion_assert_other_lane = completion_assert_other_lane + 1) begin
                    assert (!(u_dut.completion_bus[completion_assert_lane].valid &&
                              u_dut.completion_bus[completion_assert_lane].producer_tracked &&
                              (u_dut.completion_bus[completion_assert_lane].addr != '0) &&
                              u_dut.completion_bus[completion_assert_other_lane].valid &&
                              u_dut.completion_bus[completion_assert_other_lane].producer_tracked &&
                              (u_dut.completion_bus[completion_assert_other_lane].addr != '0) &&
                              (u_dut.completion_bus[completion_assert_lane].producer_id ==
                               u_dut.completion_bus[completion_assert_other_lane].producer_id)))
                        else $fatal(1,
                            "ASSERT_DUPLICATE_COMPLETION_ID lane_a=%0d lane_b=%0d id=%0d",
                            completion_assert_lane, completion_assert_other_lane,
                            u_dut.completion_bus[completion_assert_lane].producer_id);
                end
            end
        end
    end
`endif

`ifndef SYNTHESIS
    initial begin
        bp_trace_en = $test$plusargs("bp_trace");
        bp_fetch_trace_en = $test$plusargs("bp_fetch_trace");
    end
`endif

`ifndef VERILATOR_CC
	initial begin
		clk = 1'b0;
		forever #10 clk = ~clk;
	end

	initial begin
		rst_n = 1'b0;
		repeat (10) @(posedge clk);
		rst_n = 1'b1;
	end
`endif

	wire rst;
	assign rst = ~rst_n;

	always_ff @(posedge clk) begin
        if($time >= sv_timeout) begin
            $display("[TB] timeout reached, finish simulation");
            $display("[TB] timeout pc=0x%08h cycle=%0d instret=%0d", pc, cycle_count, instruction_count);
            $display("[TB] stall scoreboard=%0b lsu_struct=%0b clint=%0b wb=%0b stall_if=%0b stall_id=%0b bubble_id=%0b id_ex_valid=%0b",
                     u_dut.scoreboard_stall,
                     u_dut.lsu_struct_stall,
                     u_dut.clint_stall,
                     u_dut.wb_backpressure,
                     u_dut.stall_if,
                     u_dut.stall_id,
                     u_dut.bubble_id,
                     u_dut.id_ex_valid);
            $display("[TB] id_ctrl rs1=%0d ren1=%0b pend1=%0b rs2=%0d ren2=%0b pend2=%0b rd=%0d wen=%0b pend_rd=%0b lsu_req=%0b lsu_busy=%0b",
                     u_dut.id_ctrl_rs1_addr,
                     u_dut.id_ctrl_rs1_ren,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rs1_addr],
                     u_dut.id_ctrl_rs2_addr,
                     u_dut.id_ctrl_rs2_ren,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rs2_addr],
                     u_dut.id_ctrl_rd_addr,
                     u_dut.id_ctrl_rd_wen,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rd_addr],
                     u_dut.id_ctrl_lsu_req,
                     u_dut.lsu_ctrl_busy);
            $display("[TB] pending=0x%08h clear=0x%08h issue=0x%08h ex_accept=%0b id_rd_issue=%0b rf_wen=%0b rf_waddr=%0d alu_wen=%0b alu_waddr=%0d lsu_wen=%0b lsu_waddr=%0d mul_wen=%0b mul_waddr=%0d",
                     u_dut.gpr_pending_q,
                     u_dut.gpr_pending_clear_mask,
                     u_dut.gpr_pending_issue_mask,
                     u_dut.ex_accept_valid,
                     u_dut.id_ex_rd_issue,
                     u_dut.rf_wen_rd,
                     u_dut.rf_waddr_rd,
                     u_dut.alu_rf_wen_rd,
                     u_dut.alu_rf_waddr_rd,
                     u_dut.lsu_rf_wen_rd,
                     u_dut.lsu_rf_waddr_rd,
                     u_dut.mul_rf_wen_rd,
                     u_dut.mul_rf_waddr_rd);
            print_perf_metrics();
            $finish;
        end
        if(sim_done) begin
            print_perf_metrics();
            $finish; 
        end
	end

    // 周期计数器 - 保持同步实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_pc           <= 32'b0;
            bp_branch_count <= 32'b0;
            bp_hit_count <= 32'b0;
            bp_taken_count <= 32'b0;
            bp_actual_taken_count <= 32'b0;
            bp_actual_not_taken_count <= 32'b0;
            bp_mispredict_count <= 32'b0;
            bp_dir_mispredict_count <= 32'b0;
            bp_target_mispredict_count <= 32'b0;
            bp_btb_miss_taken_count <= 32'b0;
            bp_correct_taken_count <= 32'b0;
            bp_correct_not_taken_count <= 32'b0;
            stall_scoreboard_count <= 32'b0;
            stall_lsu_struct_count <= 32'b0;
            stall_wb_backpressure_count <= 32'b0;
            stall_clint_count <= 32'b0;
            stall_mul_count <= 32'b0;
            sb_rs1_pending_count <= 32'b0;
            sb_rs2_pending_count <= 32'b0;
            sb_rd_waw_count <= 32'b0;
            sb_issue_rs1_hzd_count <= 32'b0;
            sb_issue_rs2_hzd_count <= 32'b0;
            sb_issue_rd_hzd_count <= 32'b0;
            sb_load_use_count <= 32'b0;
            sb_alu_use_count <= 32'b0;
            sb_mul_div_use_count <= 32'b0;
            sb_branch_src_wait_count <= 32'b0;
            sb_store_addr_wait_count <= 32'b0;
            sb_store_data_wait_count <= 32'b0;
            completion_alu_lsu_count <= 32'b0;
            completion_alu_mul_count <= 32'b0;
            completion_lsu_mul_count <= 32'b0;
            completion_all_count <= 32'b0;
            completion_alu_lsu_then_mul_count <= 32'b0;
            completion_mul_then_alu_lsu_count <= 32'b0;
            completion_alu_lsu_q <= 1'b0;
            completion_mul_q <= 1'b0;
            lifecycle_complete_only_count <= 32'b0;
            lifecycle_retire_only_count <= 32'b0;
            lifecycle_allocate_only_count <= 32'b0;
            lifecycle_complete_retire_count <= 32'b0;
            lifecycle_retire_allocate_count <= 32'b0;
            lifecycle_complete_allocate_count <= 32'b0;
            lifecycle_all_count <= 32'b0;
            same_slot_complete_only_count <= 32'b0;
            same_slot_retire_only_count <= 32'b0;
            same_slot_allocate_only_count <= 32'b0;
            same_slot_complete_retire_count <= 32'b0;
            same_slot_retire_allocate_count <= 32'b0;
            same_slot_complete_allocate_count <= 32'b0;
            same_slot_all_count <= 32'b0;
            sb_load_to_alu_count <= 32'b0;
            sb_load_to_branch_count <= 32'b0;
            sb_load_to_load_count <= 32'b0;
            sb_load_to_store_count <= 32'b0;
            sb_load_to_mul_count <= 32'b0;
            sb_load_to_other_count <= 32'b0;
            sb_load_rs1_count <= 32'b0;
            sb_load_rs2_count <= 32'b0;
            sb_pending_tail_count <= 32'b0;
            sb_alu_to_alu_count <= 32'b0;
            sb_alu_to_branch_count <= 32'b0;
            sb_alu_to_load_count <= 32'b0;
            sb_alu_to_store_count <= 32'b0;
            sb_alu_to_mul_count <= 32'b0;
            sb_alu_to_other_count <= 32'b0;
            sb_pending_alu_count <= 32'b0;
            sb_pending_load_count <= 32'b0;
            sb_pending_mul_count <= 32'b0;
            sb_pending_other_count <= 32'b0;
            sb_ready_but_stall_count <= 32'b0;
            sb_complete_visible_count <= 32'b0;
            sb_registered_visible_count <= 32'b0;
            acct_flush_count <= 32'b0;
            acct_mul_hold_count <= 32'b0;
            acct_scoreboard_count <= 32'b0;
            acct_lsu_struct_count <= 32'b0;
            acct_lsu_serialize_count <= 32'b0;
            acct_producer_full_count <= 32'b0;
            acct_wb_count <= 32'b0;
            acct_clint_count <= 32'b0;
            acct_multi_cause_count <= 32'b0;
            acct_no_if_valid_count <= 32'b0;
            acct_issue_count <= 32'b0;
            acct_other_count <= 32'b0;
            perf_sample_cycle_count <= 32'b0;
            noif_control_redirect_count <= 32'b0;
            noif_predict_redirect_count <= 32'b0;
            noif_fence_refill_count <= 32'b0;
            noif_mem_response_count <= 32'b0;
            noif_fetch_launch_count <= 32'b0;
            noif_pending_redirect_count <= 32'b0;
            noif_other_count <= 32'b0;
            other_issue_refill_count <= 32'b0;
            other_decode_refill_count <= 32'b0;
            decode_refill_after_control_count <= 32'b0;
            decode_refill_after_predict_count <= 32'b0;
            decode_refill_after_fence_count <= 32'b0;
            decode_refill_after_supply_count <= 32'b0;
            other_issue_blocked_count <= 32'b0;
            other_unclassified_count <= 32'b0;
            control_refill_active_q <= 1'b0;
            predict_refill_active_q <= 1'b0;
            fence_refill_active_q <= 1'b0;
            acct_raw_only_count <= 32'b0;
            acct_waw_only_count <= 32'b0;
            acct_raw_waw_count <= 32'b0;
            retire_zero_count <= 32'b0;
            retire_one_count <= 32'b0;
            retire_two_count <= 32'b0;
            retire_three_count <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 32; perf_stat_idx = perf_stat_idx + 1)
                bubble_cause_hist[perf_stat_idx] <= 32'b0;
            producer_occ_zero_count <= 32'b0;
            producer_occ_one_count <= 32'b0;
            producer_occ_two_count <= 32'b0;
            producer_both_wait_count <= 32'b0;
            producer_wait_ready_count <= 32'b0;
            producer_both_ready_count <= 32'b0;
            producer_retire_held_count <= 32'b0;
            producer_normal_drain_count <= 32'b0;
            producer_flush_drain_count <= 32'b0;
            producer_trap_free_count <= 32'b0;
            producer_nonempty_q <= 1'b0;
            producer_flush_q <= 1'b0;
            lsu_head_wrap_count <= 32'b0;
            lsu_tail_wrap_count <= 32'b0;
            lsu_queue_empty_count <= 32'b0;
            lsu_queue_near_full_count <= 32'b0;
            lsu_queue_full_count <= 32'b0;
            lsu_queue_pop_count <= 32'b0;
            lsu_struct_mmio_count <= 32'b0;
            lsu_struct_pending_store_count <= 32'b0;
            lsu_struct_store_capture_count <= 32'b0;
            lsu_struct_other_count <= 32'b0;
            early_arith_count <= 32'b0;
            early_logic_count <= 32'b0;
            early_shift_count <= 32'b0;
            early_pass_count <= 32'b0;
            early_rs1_fwd_count <= 32'b0;
            early_rs2_fwd_count <= 32'b0;
            early_both_fwd_count <= 32'b0;
            early_to_alu_count <= 32'b0;
            early_to_load_count <= 32'b0;
            early_to_store_count <= 32'b0;
            early_completion_source_count <= 32'b0;
            early_stall_hold_count <= 32'b0;
            early_flush_clear_count <= 32'b0;
            early_bubble_clear_count <= 32'b0;
            non_early_alu_count <= 32'b0;
            fe_pred_taken_redirect_count <= 32'b0;
            fe_correct_taken_redirect_count <= 32'b0;
            fe_pred_taken_bubble_count <= 32'b0;
            fe_wrong_dir_flush_count <= 32'b0;
            bp_predict_redirect_q <= 1'b0;
        end else begin
            perf_sample_cycle_count <= perf_sample_cycle_count + 1'b1;
            bp_predict_redirect_q <= u_dut.u_ydrasil_if_stage.bp_predict_redirect;
            if (u_dut.branch_jump)
                control_refill_active_q <= 1'b1;
            else if (u_dut.if_id_valid)
                control_refill_active_q <= 1'b0;
            if (u_dut.u_ydrasil_if_stage.bp_predict_redirect)
                predict_refill_active_q <= 1'b1;
            else if (u_dut.if_id_valid)
                predict_refill_active_q <= 1'b0;
            if (u_dut.id_fence_i)
                fence_refill_active_q <= 1'b1;
            else if (u_dut.if_id_valid)
                fence_refill_active_q <= 1'b0;
            last_pc     <= pc;
            if (bp_branch_valid) begin
                bp_branch_count <= bp_branch_count + 1;
                bp_hit_count <= bp_hit_count + (bp_pred_hit ? 32'd1 : 32'd0);
                bp_taken_count <= bp_taken_count + (bp_pred_taken ? 32'd1 : 32'd0);
                bp_actual_taken_count <= bp_actual_taken_count + (bp_actual_taken ? 32'd1 : 32'd0);
                bp_actual_not_taken_count <= bp_actual_not_taken_count + (!bp_actual_taken ? 32'd1 : 32'd0);
                bp_mispredict_count <= bp_mispredict_count + (bp_mispredict ? 32'd1 : 32'd0);
                bp_dir_mispredict_count <= bp_dir_mispredict_count + (bp_dir_mispredict ? 32'd1 : 32'd0);
                bp_target_mispredict_count <= bp_target_mispredict_count + (bp_target_mispredict ? 32'd1 : 32'd0);
                bp_btb_miss_taken_count <= bp_btb_miss_taken_count + (bp_btb_miss_taken ? 32'd1 : 32'd0);
                bp_correct_taken_count <= bp_correct_taken_count + (bp_correct_taken ? 32'd1 : 32'd0);
                bp_correct_not_taken_count <= bp_correct_not_taken_count + (bp_correct_not_taken ? 32'd1 : 32'd0);
                fe_correct_taken_redirect_count <= fe_correct_taken_redirect_count + (bp_correct_taken ? 32'd1 : 32'd0);
                fe_wrong_dir_flush_count <= fe_wrong_dir_flush_count + (bp_dir_mispredict ? 32'd1 : 32'd0);
`ifndef SYNTHESIS
                if (bp_trace_en) begin
                    $display("BP_TRACE: cycle=%0d pc=0x%08h pred_hit=%0b pred_taken=%0b actual_taken=%0b pred_target=0x%08h actual_target=0x%08h pred_next=0x%08h actual_next=0x%08h counter=%0d mispredict=%0b dir_mispredict=%0b target_mispredict=%0b",
                        cycle_count,
                        dbg_bp_resolve_pc,
                        dbg_bp_pred_hit,
                        bp_pred_taken,
                        dbg_bp_actual_taken,
                        dbg_bp_pred_target,
                        dbg_bp_actual_target,
                        dbg_bp_pred_next_pc,
                        dbg_bp_actual_next_pc,
                        dbg_bp_pred_counter,
                        dbg_bp_mispredict,
                        bp_dir_mispredict,
                        bp_target_mispredict);
                end
`endif
            end
`ifndef SYNTHESIS
            if (bp_fetch_trace_en && dbg_bp_predict_hit) begin
                $display("BP_FETCH_TRACE: cycle=%0d pc=0x%08h hit=%0b taken=%0b target=0x%08h counter=%0d",
                    cycle_count,
                    dbg_bp_predict_pc,
                    dbg_bp_predict_hit,
                    dbg_bp_predict_taken,
                    dbg_bp_predict_target,
                    dbg_bp_predict_counter);
            end
`endif
            stall_scoreboard_count <= stall_scoreboard_count +
                (u_dut.scoreboard_stall ? 32'd1 : 32'd0);
            stall_lsu_struct_count <= stall_lsu_struct_count +
                (u_dut.lsu_struct_stall ? 32'd1 : 32'd0);
            stall_wb_backpressure_count <= stall_wb_backpressure_count +
                (u_dut.wb_backpressure ? 32'd1 : 32'd0);
            stall_clint_count <= stall_clint_count +
                (u_dut.clint_stall ? 32'd1 : 32'd0);
            stall_mul_count <= stall_mul_count +
                (u_dut.ex_mul_stall ? 32'd1 : 32'd0);
            completion_alu_lsu_q <=
                u_dut.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                u_dut.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid;
            completion_mul_q <=
                u_dut.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid;
            completion_alu_lsu_count <= completion_alu_lsu_count +
                ((u_dut.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid) ? 32'd1 : 32'd0);
            completion_alu_mul_count <= completion_alu_mul_count +
                ((u_dut.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_lsu_mul_count <= completion_lsu_mul_count +
                ((u_dut.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_all_count <= completion_all_count +
                ((u_dut.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_alu_lsu_then_mul_count <=
                completion_alu_lsu_then_mul_count +
                ((completion_alu_lsu_q &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_mul_then_alu_lsu_count <=
                completion_mul_then_alu_lsu_count +
                ((completion_mul_q &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid) ? 32'd1 : 32'd0);
            unique case ({|u_dut.u_ctrl.producer_complete_mask,
                          |u_dut.u_ctrl.producer_retire_q,
                          u_dut.u_ctrl.producer_alloc_ex})
                3'b100: lifecycle_complete_only_count <= lifecycle_complete_only_count + 1'b1;
                3'b010: lifecycle_retire_only_count <= lifecycle_retire_only_count + 1'b1;
                3'b001: lifecycle_allocate_only_count <= lifecycle_allocate_only_count + 1'b1;
                3'b110: lifecycle_complete_retire_count <= lifecycle_complete_retire_count + 1'b1;
                3'b011: lifecycle_retire_allocate_count <= lifecycle_retire_allocate_count + 1'b1;
                3'b101: lifecycle_complete_allocate_count <= lifecycle_complete_allocate_count + 1'b1;
                3'b111: lifecycle_all_count <= lifecycle_all_count + 1'b1;
                default: begin end
            endcase
            same_slot_complete_only_count <= same_slot_complete_only_count +
                ((|(u_dut.u_ctrl.producer_complete_mask &
                    ~u_dut.u_ctrl.producer_retire_q &
                    ~(u_dut.u_ctrl.producer_alloc_ex ?
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 1'b1 : 1'b0);
            same_slot_retire_only_count <= same_slot_retire_only_count +
                ((|(u_dut.u_ctrl.producer_retire_q &
                    ~u_dut.u_ctrl.producer_complete_mask &
                    ~(u_dut.u_ctrl.producer_alloc_ex ?
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 1'b1 : 1'b0);
            same_slot_allocate_only_count <= same_slot_allocate_only_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  !u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  !u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id]) ? 1'b1 : 1'b0);
            same_slot_complete_retire_count <= same_slot_complete_retire_count +
                ((|(u_dut.u_ctrl.producer_complete_mask &
                    u_dut.u_ctrl.producer_retire_q &
                    ~(u_dut.u_ctrl.producer_alloc_ex ?
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 1'b1 : 1'b0);
            same_slot_retire_allocate_count <= same_slot_retire_allocate_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id] &&
                  !u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]]) ? 1'b1 : 1'b0);
            same_slot_complete_allocate_count <= same_slot_complete_allocate_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  !u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id]) ? 1'b1 : 1'b0);
            same_slot_all_count <= same_slot_all_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id]) ? 1'b1 : 1'b0);
            sb_rs1_pending_count <= sb_rs1_pending_count +
                (u_dut.rs1_pending_stall ? 32'd1 : 32'd0);
            sb_rs2_pending_count <= sb_rs2_pending_count +
                (u_dut.rs2_pending_stall ? 32'd1 : 32'd0);
            sb_rd_waw_count <= sb_rd_waw_count +
                (u_dut.rd_waw_stall ? 32'd1 : 32'd0);
            sb_issue_rs1_hzd_count <= sb_issue_rs1_hzd_count +
                (u_dut.rs1_issue_hzd ? 32'd1 : 32'd0);
            sb_issue_rs2_hzd_count <= sb_issue_rs2_hzd_count +
                (u_dut.rs2_issue_hzd ? 32'd1 : 32'd0);
            sb_issue_rd_hzd_count <= sb_issue_rd_hzd_count +
                (u_dut.rd_issue_hzd ? 32'd1 : 32'd0);
            sb_load_use_count <= sb_load_use_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_alu_use_count <= sb_alu_use_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_mul_div_use_count <= sb_mul_div_use_count +
                ((u_dut.issue_mul_div_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_branch_src_wait_count <= sb_branch_src_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            sb_store_addr_wait_count <= sb_store_addr_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs1_pending_stall | u_dut.rs1_issue_hzd)) ? 32'd1 : 32'd0);
            sb_store_data_wait_count <= sb_store_data_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs2_pending_stall | u_dut.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            sb_load_to_alu_count <= sb_load_to_alu_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU]) ? 32'd1 : 32'd0);
            sb_load_to_branch_count <= sb_load_to_branch_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            sb_load_to_load_count <= sb_load_to_load_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]) ? 32'd1 : 32'd0);
            sb_load_to_store_count <= sb_load_to_store_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) ? 32'd1 : 32'd0);
            sb_load_to_mul_count <= sb_load_to_mul_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]) ? 32'd1 : 32'd0);
            sb_load_to_other_count <= sb_load_to_other_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd &
                  !(u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL])) ? 32'd1 : 32'd0);
            sb_load_rs1_count <= sb_load_rs1_count +
                ((u_dut.issue_load_producer & u_dut.rs1_issue_hzd) ? 32'd1 : 32'd0);
            sb_load_rs2_count <= sb_load_rs2_count +
                ((u_dut.issue_load_producer & u_dut.rs2_issue_hzd) ? 32'd1 : 32'd0);
            sb_pending_tail_count <= sb_pending_tail_count +
                (((u_dut.rs1_pending_stall | u_dut.rs2_pending_stall) &
                  !(u_dut.rs1_issue_hzd | u_dut.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            sb_alu_to_alu_count <= sb_alu_to_alu_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU]) ? 32'd1 : 32'd0);
            sb_alu_to_branch_count <= sb_alu_to_branch_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            sb_alu_to_load_count <= sb_alu_to_load_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]) ? 32'd1 : 32'd0);
            sb_alu_to_store_count <= sb_alu_to_store_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) ? 32'd1 : 32'd0);
            sb_alu_to_mul_count <= sb_alu_to_mul_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]) ? 32'd1 : 32'd0);
            sb_alu_to_other_count <= sb_alu_to_other_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd &
                  !(u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL])) ? 32'd1 : 32'd0);
            if ((u_dut.rs1_pending_stall | u_dut.rs2_pending_stall) &&
                !(u_dut.rs1_issue_hzd | u_dut.rs2_issue_hzd)) begin
                if ((u_dut.rs1_pending_stall && u_dut.u_ctrl.dbg_rs1_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_LOAD) ||
                    (u_dut.rs2_pending_stall && u_dut.u_ctrl.dbg_rs2_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_LOAD))
                    sb_pending_load_count <= sb_pending_load_count + 1'b1;
                else if ((u_dut.rs1_pending_stall && u_dut.u_ctrl.dbg_rs1_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_MUL) ||
                         (u_dut.rs2_pending_stall && u_dut.u_ctrl.dbg_rs2_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_MUL))
                    sb_pending_mul_count <= sb_pending_mul_count + 1'b1;
                else if ((u_dut.rs1_pending_stall && u_dut.u_ctrl.dbg_rs1_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_ALU) ||
                         (u_dut.rs2_pending_stall && u_dut.u_ctrl.dbg_rs2_producer_kind == u_dut.u_ctrl.DBG_PRODUCER_ALU))
                    sb_pending_alu_count <= sb_pending_alu_count + 1'b1;
                else
                    sb_pending_other_count <= sb_pending_other_count + 1'b1;
            end
            sb_ready_but_stall_count <= sb_ready_but_stall_count +
                ((u_dut.scoreboard_stall &&
                  ((u_dut.u_ctrl.rs1_has_producer && u_dut.u_ctrl.rs1_producer_ready) ||
                   (u_dut.u_ctrl.rs2_has_producer && u_dut.u_ctrl.rs2_producer_ready))) ? 32'd1 : 32'd0);
            sb_complete_visible_count <= sb_complete_visible_count +
                (((u_dut.u_ctrl.rs1_has_producer &&
                   u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs1_producer_slot]) ||
                  (u_dut.u_ctrl.rs2_has_producer &&
                   u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs2_producer_slot])) ? 32'd1 : 32'd0);
            sb_registered_visible_count <= sb_registered_visible_count +
                (((u_dut.u_ctrl.rs1_has_producer &&
                   u_dut.u_ctrl.producer_ready_q[u_dut.u_ctrl.rs1_producer_slot]) ||
                  (u_dut.u_ctrl.rs2_has_producer &&
                   u_dut.u_ctrl.producer_ready_q[u_dut.u_ctrl.rs2_producer_slot])) ? 32'd1 : 32'd0);

            // Mutually exclusive cycle accounting. Keep this TB-only so it cannot affect RTL.
            if (u_dut.flush_ex) begin
                acct_flush_count <= acct_flush_count + 1'b1;
            end else if (u_dut.ex_mul_stall) begin
                acct_mul_hold_count <= acct_mul_hold_count + 1'b1;
            end else if ((u_dut.scoreboard_stall &
                          (u_dut.lsu_struct_stall | u_dut.u_ctrl.producer_full_stall |
                           u_dut.wb_backpressure | u_dut.clint_stall)) |
                         (u_dut.lsu_struct_stall &
                          (u_dut.u_ctrl.producer_full_stall | u_dut.wb_backpressure |
                           u_dut.clint_stall)) |
                         (u_dut.u_ctrl.producer_full_stall &
                          (u_dut.wb_backpressure | u_dut.clint_stall)) |
                         (u_dut.wb_backpressure & u_dut.clint_stall)) begin
                acct_multi_cause_count <= acct_multi_cause_count + 1'b1;
            end else if (u_dut.scoreboard_stall) begin
                acct_scoreboard_count <= acct_scoreboard_count + 1'b1;
            end else if (u_dut.lsu_struct_stall) begin
                acct_lsu_struct_count <= acct_lsu_struct_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_full_stall) begin
                acct_producer_full_count <= acct_producer_full_count + 1'b1;
            end else if (u_dut.wb_backpressure) begin
                acct_wb_count <= acct_wb_count + 1'b1;
            end else if (u_dut.clint_stall) begin
                acct_clint_count <= acct_clint_count + 1'b1;
            end else if (u_dut.u_ctrl.lsu_serialize_stall) begin
                acct_lsu_serialize_count <= acct_lsu_serialize_count + 1'b1;
            end else if (!u_dut.if_id_valid) begin
                acct_no_if_valid_count <= acct_no_if_valid_count + 1'b1;
                if (control_refill_active_q)
                    noif_control_redirect_count <= noif_control_redirect_count + 1'b1;
                else if (predict_refill_active_q)
                    noif_predict_redirect_count <= noif_predict_redirect_count + 1'b1;
                else if (fence_refill_active_q)
                    noif_fence_refill_count <= noif_fence_refill_count + 1'b1;
                else if (u_dut.u_ydrasil_if_stage.mem_req_valid_ff)
                    noif_mem_response_count <= noif_mem_response_count + 1'b1;
                else if (u_dut.u_ydrasil_if_stage.fetch_issue)
                    noif_fetch_launch_count <= noif_fetch_launch_count + 1'b1;
                else if (u_dut.u_ydrasil_if_stage.pending_redirect_valid_ff)
                    noif_pending_redirect_count <= noif_pending_redirect_count + 1'b1;
                else
                    noif_other_count <= noif_other_count + 1'b1;
            end else if (u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
                         u_dut.u_ydrasil_issue_stage.id_advance) begin
                acct_issue_count <= acct_issue_count + 1'b1;
            end else begin
                acct_other_count <= acct_other_count + 1'b1;
                if (!u_dut.u_ydrasil_issue_stage.issue_valid_ff && u_dut.decode_valid)
                    other_issue_refill_count <= other_issue_refill_count + 1'b1;
                else if (!u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
                         !u_dut.decode_valid && u_dut.decode_if_ready) begin
                    other_decode_refill_count <= other_decode_refill_count + 1'b1;
                    if (control_refill_active_q)
                        decode_refill_after_control_count <= decode_refill_after_control_count + 1'b1;
                    else if (predict_refill_active_q)
                        decode_refill_after_predict_count <= decode_refill_after_predict_count + 1'b1;
                    else if (fence_refill_active_q)
                        decode_refill_after_fence_count <= decode_refill_after_fence_count + 1'b1;
                    else
                        decode_refill_after_supply_count <= decode_refill_after_supply_count + 1'b1;
                end
                else if (u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
                         !u_dut.u_ydrasil_issue_stage.id_advance)
                    other_issue_blocked_count <= other_issue_blocked_count + 1'b1;
                else
                    other_unclassified_count <= other_unclassified_count + 1'b1;
            end

            if (u_dut.scoreboard_stall) begin
                if ((u_dut.rs1_issue_hzd | u_dut.rs2_issue_hzd |
                     u_dut.rs1_pending_stall | u_dut.rs2_pending_stall) &&
                    (u_dut.rd_issue_hzd | u_dut.rd_waw_stall))
                    acct_raw_waw_count <= acct_raw_waw_count + 1'b1;
                else if (u_dut.rd_issue_hzd | u_dut.rd_waw_stall)
                    acct_waw_only_count <= acct_waw_only_count + 1'b1;
                else
                    acct_raw_only_count <= acct_raw_only_count + 1'b1;
            end

            unique case (u_dut.instret_inc_count)
                2'd0: retire_zero_count <= retire_zero_count + 1'b1;
                2'd1: retire_one_count <= retire_one_count + 1'b1;
                2'd2: retire_two_count <= retire_two_count + 1'b1;
                2'd3: retire_three_count <= retire_three_count + 1'b1;
            endcase

            bubble_cause_hist[{u_dut.clint_stall, u_dut.wb_backpressure,
                u_dut.u_ctrl.producer_full_stall, u_dut.lsu_struct_stall,
                u_dut.scoreboard_stall}] <=
                bubble_cause_hist[{u_dut.clint_stall, u_dut.wb_backpressure,
                    u_dut.u_ctrl.producer_full_stall, u_dut.lsu_struct_stall,
                    u_dut.scoreboard_stall}] + 1'b1;
            if ($countones(u_dut.u_ctrl.producer_valid_q &
                           ~u_dut.u_ctrl.producer_retire_q) == 0) begin
                producer_occ_zero_count <= producer_occ_zero_count + 1'b1;
            end else if ($countones(u_dut.u_ctrl.producer_valid_q &
                                    ~u_dut.u_ctrl.producer_retire_q) == 1) begin
                producer_occ_one_count <= producer_occ_one_count + 1'b1;
            end else begin
                producer_occ_two_count <= producer_occ_two_count + 1'b1;
                if (|(u_dut.u_ctrl.producer_ready_q &
                      u_dut.u_ctrl.producer_valid_q))
                    producer_wait_ready_count <= producer_wait_ready_count + 1'b1;
                else
                    producer_both_wait_count <= producer_both_wait_count + 1'b1;
                if ((u_dut.u_ctrl.producer_ready_q &
                     u_dut.u_ctrl.producer_valid_q) == u_dut.u_ctrl.producer_valid_q)
                    producer_both_ready_count <= producer_both_ready_count + 1'b1;
            end
            if (|u_dut.u_ctrl.producer_retire_q)
                producer_retire_held_count <= producer_retire_held_count + 1'b1;
            producer_nonempty_q <= |u_dut.u_ctrl.producer_valid_q;
            producer_flush_q <= u_dut.flush_ex;
            if (producer_nonempty_q && !(|u_dut.u_ctrl.producer_valid_q)) begin
                if (producer_flush_q)
                    producer_flush_drain_count <= producer_flush_drain_count + 1'b1;
                else if (!interrupt_q)
                    producer_normal_drain_count <= producer_normal_drain_count + 1'b1;
            end
            if (interrupt_q && !(|u_dut.u_ctrl.producer_valid_q))
                producer_trap_free_count <= producer_trap_free_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_dequeue &&
                (u_dut.u_ydrasil_load_store_unit.queue_head_q == 2'd3))
                lsu_head_wrap_count <= lsu_head_wrap_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_enqueue &&
                (u_dut.u_ydrasil_load_store_unit.queue_tail_q == 2'd3))
                lsu_tail_wrap_count <= lsu_tail_wrap_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_empty)
                lsu_queue_empty_count <= lsu_queue_empty_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_count_q == 3)
                lsu_queue_near_full_count <= lsu_queue_near_full_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_full)
                lsu_queue_full_count <= lsu_queue_full_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_dequeue)
                lsu_queue_pop_count <= lsu_queue_pop_count + 1'b1;
            if (u_dut.lsu_struct_stall) begin
                if (u_dut.u_ydrasil_load_store_unit.mmio_busy)
                    lsu_struct_mmio_count <= lsu_struct_mmio_count + 1'b1;
                else if (u_dut.u_ydrasil_load_store_unit.active_is_store &&
                         !u_dut.u_ydrasil_load_store_unit.active_store_data_valid)
                    lsu_struct_pending_store_count <= lsu_struct_pending_store_count + 1'b1;
                else if (u_dut.u_ydrasil_load_store_unit.queue_enqueue)
                    lsu_struct_store_capture_count <= lsu_struct_store_capture_count + 1'b1;
                else
                    lsu_struct_other_count <= lsu_struct_other_count + 1'b1;
            end
            if (u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff) begin
                early_arith_count <= early_arith_count +
                    u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[0];
                early_logic_count <= early_logic_count +
                    u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[1];
                early_shift_count <= early_shift_count +
                    u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[2];
                early_pass_count <= early_pass_count +
                    u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[3];
            end
            if (u_dut.u_ydrasil_issue_stage.rs1_issue_early_alu_fwd)
                early_rs1_fwd_count <= early_rs1_fwd_count + 1'b1;
            if (u_dut.u_ydrasil_issue_stage.rs2_issue_early_alu_fwd)
                early_rs2_fwd_count <= early_rs2_fwd_count + 1'b1;
            if (u_dut.u_ydrasil_issue_stage.rs1_issue_early_alu_fwd &&
                u_dut.u_ydrasil_issue_stage.rs2_issue_early_alu_fwd)
                early_both_fwd_count <= early_both_fwd_count + 1'b1;
            if (u_dut.u_ydrasil_issue_stage.rs1_issue_early_alu_fwd ||
                u_dut.u_ydrasil_issue_stage.rs2_issue_early_alu_fwd) begin
                if (u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[
                    ydrasil_pkg::OPERATOR_TYPE_ALU])
                    early_to_alu_count <= early_to_alu_count + 1'b1;
                if (u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[
                    ydrasil_pkg::OPERATOR_TYPE_LOAD])
                    early_to_load_count <= early_to_load_count + 1'b1;
                if (u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[
                    ydrasil_pkg::OPERATOR_TYPE_STORE])
                    early_to_store_count <= early_to_store_count + 1'b1;
            end
            if (u_dut.u_ydrasil_issue_stage.issue_simple_alu_op &&
                (u_dut.u_ydrasil_issue_stage.rs1_completion_fwd ||
                 u_dut.u_ydrasil_issue_stage.rs2_completion_fwd))
                early_completion_source_count <= early_completion_source_count + 1'b1;
            if (!u_dut.u_ydrasil_issue_stage.id_advance &&
                u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff)
                early_stall_hold_count <= early_stall_hold_count + 1'b1;
            if (u_dut.flush_id)
                early_flush_clear_count <= early_flush_clear_count + 1'b1;
            if (u_dut.bubble_id)
                early_bubble_clear_count <= early_bubble_clear_count + 1'b1;
            if (u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
                u_dut.u_ydrasil_issue_stage.id_advance &&
                u_dut.u_ydrasil_issue_stage.issue_plain_alu_op &&
                !u_dut.u_ydrasil_issue_stage.issue_simple_alu_op)
                non_early_alu_count <= non_early_alu_count + 1'b1;
            fe_pred_taken_redirect_count <= fe_pred_taken_redirect_count +
                (u_dut.u_ydrasil_if_stage.bp_predict_redirect ? 32'd1 : 32'd0);
            fe_pred_taken_bubble_count <= fe_pred_taken_bubble_count +
                ((bp_predict_redirect_q && !u_dut.u_ydrasil_if_stage.if_id_valid_o) ? 32'd1 : 32'd0);
        end
    end

    // PC监控逻辑
    always @(pc) begin
        if (pc == finish_pc && pc != last_pc) begin
            pc_write_to_host_cnt = pc_write_to_host_cnt + 1'b1;
            if (pc_write_to_host_flag == 1'b0) begin
                pc_write_to_host_cycle = cycle_count;
                pc_write_to_host_flag  = 1'b1;
            end
        end
    end

    // 添加异步复位逻辑
    always @(negedge rst_n) begin
        if (!rst_n) begin
            pc_write_to_host_cnt   = 32'b0;
            pc_write_to_host_flag  = 1'b0;
            pc_write_to_host_cycle = 32'b0;
        end
    end

    // 测试用例解析与ITCM加载
    initial begin
        if ($value$plusargs("itcm_init=%s", testcase)) begin
            display_testcase_name();
            $display("");

            $readmemh({testcase, ".verilog"}, prog_mem);
            for (i = 0; i < ITCM_DEPTH; i = i + 1) begin
                `ITCM.mem_r[i] = {prog_mem[i*4+3], prog_mem[i*4+2], prog_mem[i*4+1], prog_mem[i*4+0]};
            end
            $display("Successfully loaded instructions to ITCM");
            $display("ITCM 0x00: %h", `ITCM.mem_r[0]);
            $display("ITCM 0x01: %h", `ITCM.mem_r[1]);
            $display("ITCM 0x02: %h", `ITCM.mem_r[2]);
            $display("ITCM 0x03: %h", `ITCM.mem_r[3]);
            $display("ITCM 0x04: %h", `ITCM.mem_r[4]);
        end else begin
            $display("No itcm_init defined, use default ITCM init.");
        end
    end

	initial begin
		if ($test$plusargs("tb_monitor")) begin
			$monitor("[TB] time=%0t, rst_n=%b, LED=0x%08h, seg_wdata=0x%08h",
				$time, rst_n, LED, seg_wdata);
		end
	end

	initial begin
		if(pc == 32'h800001b4) begin
			$display("PC = 0x800001b4,time = %0t", $time);
		end
	end


	localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
	localparam SEG_ADDR  = 32'h8020_0020;  // seg
	localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
	localparam CNT_ADDR  = 32'h8020_0050;  // counter
	localparam SIM_STDOUT_ADDR = 32'h8020_0060;  // tb-only stdout
	localparam SIM_DUMP_ADDR   = 32'h8020_0064;  // tb-only dump control

	wire [31:0] LED;
	wire [31:0] seg_wdata;
	logic sim_done;
	logic perf_terminal_printed_q;
	bit finish_on_led;
	bit finish_on_terminal_led;
	bit finish_on_tohost;
	bit perip_debug_en;
	logic [31:0] finish_pc;

	wire [31:0] virtual_led_output;
	wire [39:0] virtual_seg_output;
	wire [63:0] virtual_sw_input = 0;
	wire [7:0]  virtual_key_input = 0;
	wire        perip_req = u_dut.mmio_req;

	initial begin
		finish_on_led = !$test$plusargs("no_finish_on_led");
		finish_on_terminal_led = $test$plusargs("finish_on_terminal_led");
		finish_on_tohost = !$test$plusargs("no_finish_on_tohost");
		perip_debug_en = $test$plusargs("perip_debug");
		finish_pc = `PC_WRITE_TOHOST;
		void'($value$plusargs("finish_pc=%h", finish_pc));
	end

	perip_bridge bridge_inst (
		.clk                (clk),
		.cnt_clk            (clk),
		.rst                (rst),
		.perip_addr         (perip_addr),
		.perip_wdata        (perip_wdata),
		.perip_wen          (perip_wen),
		.perip_mask         (perip_mask),
		.perip_rdata        (perip_rdata),
		.virtual_sw_input   (virtual_sw_input),
		.virtual_key_input  (virtual_key_input),
		.virtual_seg_output (virtual_seg_output),
		.virtual_led_output (virtual_led_output)
	);

	assign LED = virtual_led_output;
	assign seg_wdata = bridge_inst.seg_wdata;

	always_ff @(posedge clk) begin
		if (rst) begin
			sim_done <= 1'b0;
			perf_terminal_printed_q <= 1'b0;
		end else if (perip_wen && (perip_addr == LED_ADDR) &&
		             ((finish_on_led && (perip_wdata != 32'h0)) ||
		              (finish_on_terminal_led &&
		               ((perip_wdata == 32'h078b7323) ||
		                (perip_wdata == 32'h00504f53))))) begin
			sim_done <= 1'b1;
		end

		if (!rst && !perf_terminal_printed_q && perip_wen && (perip_addr == LED_ADDR) &&
		    ((perip_wdata == 32'h078b7323) || (perip_wdata == 32'h00504f53))) begin
			perf_terminal_printed_q <= 1'b1;
			print_perf_metrics();
		end

		if (!rst && perip_req && perip_wen && (perip_addr == SIM_STDOUT_ADDR)) begin
			$write("%c", perip_wdata[7:0]);
		end

		if (!rst && perip_debug_en && perip_req) begin
			if (perip_wen) begin
				case (perip_addr)
					LED_ADDR: $display("[PERIP] time=%0t LED write 0x%08h", $time, perip_wdata);
					SEG_ADDR: $display("[PERIP] time=%0t SEG write 0x%08h", $time, perip_wdata);
					CNT_ADDR: $display("[PERIP] time=%0t CNT write 0x%08h", $time, perip_wdata);
					SIM_DUMP_ADDR: $display("[PERIP] time=%0t SIM dump write 0x%08h", $time, perip_wdata);
					default: ;
				endcase
			end else if (perip_addr == CNT_ADDR) begin
				$display("[PERIP] time=%0t CNT read rdata=0x%08h", $time, perip_rdata);
			end
		end
	end

    // 对pc_write_to_host_cnt的变化进行监控
    always @(pc_write_to_host_cnt) begin
        if (finish_on_tohost && (pc_write_to_host_cnt == 32'd8)) begin
            ipc = (instruction_count > 0 && cycle_count > 0) ? (instruction_count * 1.0) / cycle_count : 0.0;
            bp_accuracy = (bp_branch_count > 0) ?
                ((bp_branch_count - bp_mispredict_count) * 100.0) / bp_branch_count : 0.0;

            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~ Test Result Summary ~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $write("~TESTCASE: ");
            display_testcase_name();
            $display("~");
            $display("~~~~~~~~~~~~~~Total cycle_count value: %d ~~~~~~~~~~~~~", cycle_count);
            $display("~~~~~The test ending reached at cycle: %d ~~~~~~~~~~~~~", pc_write_to_host_cycle);
            $display("~~~~~~~~~~Total instructions executed: %d ~~~~~~~~~~~~~", instruction_count);
            $display("~~~~~~~~~~~~~~~~~~ IPC value: %.4f ~~~~~~~~~~~~~~~~~~", ipc);
            $display("~~~~ Branch predictor: branches=%0d hits=%0d predicted_taken=%0d mispredicts=%0d accuracy=%.2f%% ~~~~",
                bp_branch_count, bp_hit_count, bp_taken_count, bp_mispredict_count, bp_accuracy);
            $display("~~~~ BP detail: actual_taken=%0d not_taken=%0d dir_mispredict=%0d target_mispredict=%0d btb_miss_taken=%0d correct_taken=%0d correct_not_taken=%0d ~~~~",
                bp_actual_taken_count,
                bp_actual_not_taken_count,
                bp_dir_mispredict_count,
                bp_target_mispredict_count,
                bp_btb_miss_taken_count,
                bp_correct_taken_count,
                bp_correct_not_taken_count);
            $display("~~~~~~~~~~~~~~~The final x3 Reg value: %d ~~~~~~~~~~~~~", x3);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

            if (x3 == 1) begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
                $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("fail testnum = %2d", x3);
                for (r = 0; r < 32; r = r + 1) $display("x%2d = 0x%x", r, u_dut.u_ydrasil_registers.registers[r]);
            end
            print_perf_metrics();
            $finish;
        end
    end

    task automatic print_perf_metrics;
        real perf_ipc;
        real perf_bp_accuracy;
        begin
            perf_ipc = (instruction_count > 0 && cycle_count > 0) ?
                (instruction_count * 1.0) / cycle_count : 0.0;
            perf_bp_accuracy = (bp_branch_count > 0) ?
                ((bp_branch_count - bp_mispredict_count) * 100.0) / bp_branch_count : 0.0;

            $display("PERF_METRIC: CYCLES=%-d INSTS=%-d IPC=%.4f",
                cycle_count, instruction_count, perf_ipc);
            $display("PERF_STALL: SCOREBOARD=%-d LSU_STRUCT=%-d WB_BACKPRESSURE=%-d CLINT=%-d MUL_DIV=%-d",
                stall_scoreboard_count,
                stall_lsu_struct_count,
                stall_wb_backpressure_count,
                stall_clint_count,
                stall_mul_count);
            $display("PERF_SCOREBOARD_DETAIL: RS1_PENDING=%-d RS2_PENDING=%-d RD_WAW=%-d ISSUE_RS1_HZD=%-d ISSUE_RS2_HZD=%-d ISSUE_RD_HZD=%-d LOAD_USE=%-d ALU_USE=%-d MUL_DIV_USE=%-d BRANCH_SRC_WAIT=%-d STORE_ADDR_WAIT=%-d STORE_DATA_WAIT=%-d",
                sb_rs1_pending_count,
                sb_rs2_pending_count,
                sb_rd_waw_count,
                sb_issue_rs1_hzd_count,
                sb_issue_rs2_hzd_count,
                sb_issue_rd_hzd_count,
                sb_load_use_count,
                sb_alu_use_count,
                sb_mul_div_use_count,
                sb_branch_src_wait_count,
                sb_store_addr_wait_count,
                sb_store_data_wait_count);
            $display("PERF_LOAD_DETAIL: TO_ALU=%-d TO_BRANCH=%-d TO_LOAD=%-d TO_STORE=%-d TO_MUL=%-d TO_OTHER=%-d RS1=%-d RS2=%-d PENDING_TAIL=%-d",
                sb_load_to_alu_count,
                sb_load_to_branch_count,
                sb_load_to_load_count,
                sb_load_to_store_count,
                sb_load_to_mul_count,
                sb_load_to_other_count,
                sb_load_rs1_count,
                sb_load_rs2_count,
                sb_pending_tail_count);
            $display("PERF_ALU_DETAIL: TO_ALU=%-d TO_BRANCH=%-d TO_LOAD=%-d TO_STORE=%-d TO_MUL=%-d TO_OTHER=%-d",
                sb_alu_to_alu_count,
                sb_alu_to_branch_count,
                sb_alu_to_load_count,
                sb_alu_to_store_count,
                sb_alu_to_mul_count,
                sb_alu_to_other_count);
            $display("PERF_PENDING_DETAIL: ALU=%-d LOAD=%-d MUL=%-d OTHER=%-d READY_BUT_STALL=%-d COMPLETE_VISIBLE=%-d REGISTERED_VISIBLE=%-d",
                sb_pending_alu_count,
                sb_pending_load_count,
                sb_pending_mul_count,
                sb_pending_other_count,
                sb_ready_but_stall_count,
                sb_complete_visible_count,
                sb_registered_visible_count);
            $display("PERF_CYCLE_ACCOUNT: FLUSH=%-d MUL_HOLD=%-d SCOREBOARD=%-d LSU_STRUCT=%-d LSU_SERIALIZE=%-d PRODUCER_FULL=%-d WB=%-d CLINT=%-d MULTI=%-d NO_IF_VALID=%-d ISSUE=%-d OTHER=%-d ACCOUNTED=%-d SAMPLE_CYCLES=%-d ARCH_CYCLE_DELTA=%-d",
                acct_flush_count,
                acct_mul_hold_count,
                acct_scoreboard_count,
                acct_lsu_struct_count,
                acct_lsu_serialize_count,
                acct_producer_full_count,
                acct_wb_count,
                acct_clint_count,
                acct_multi_cause_count,
                acct_no_if_valid_count,
                acct_issue_count,
                acct_other_count,
                acct_flush_count + acct_mul_hold_count + acct_scoreboard_count +
                    acct_lsu_struct_count + acct_lsu_serialize_count +
                    acct_producer_full_count + acct_wb_count +
                    acct_clint_count + acct_multi_cause_count + acct_no_if_valid_count +
                    acct_issue_count + acct_other_count,
                perf_sample_cycle_count,
                cycle_count - perf_sample_cycle_count);
            $display("PERF_NOIF_DETAIL: CONTROL_REDIRECT=%-d PREDICT_REDIRECT=%-d FENCE_REFILL=%-d MEM_RESPONSE=%-d FETCH_LAUNCH=%-d PENDING_REDIRECT=%-d OTHER=%-d",
                noif_control_redirect_count,
                noif_predict_redirect_count,
                noif_fence_refill_count,
                noif_mem_response_count,
                noif_fetch_launch_count,
                noif_pending_redirect_count,
                noif_other_count);
            $display("PERF_OTHER_DETAIL: ISSUE_REFILL=%-d DECODE_REFILL=%-d ISSUE_BLOCKED=%-d OTHER=%-d",
                other_issue_refill_count,
                other_decode_refill_count,
                other_issue_blocked_count,
                other_unclassified_count);
            $display("PERF_DECODE_REFILL_DETAIL: AFTER_CONTROL=%-d AFTER_PREDICT=%-d AFTER_FENCE=%-d AFTER_SUPPLY=%-d",
                decode_refill_after_control_count,
                decode_refill_after_predict_count,
                decode_refill_after_fence_count,
                decode_refill_after_supply_count);
            $display("PERF_HAZARD_ACCOUNT: RAW_ONLY=%-d WAW_ONLY=%-d RAW_WAW=%-d RETIRE_0=%-d RETIRE_1=%-d RETIRE_2=%-d RETIRE_3=%-d",
                acct_raw_only_count,
                acct_waw_only_count,
                acct_raw_waw_count,
                retire_zero_count,
                retire_one_count,
                retire_two_count,
                retire_three_count);
            $display("PERF_CAUSE_HIST: NONE=%-d SB=%-d LSU=%-d LSU_SB=%-d PF=%-d PF_SB=%-d PF_LSU=%-d PF_LSU_SB=%-d WB_ANY=%-d CLINT_ANY=%-d",
                bubble_cause_hist[0], bubble_cause_hist[1], bubble_cause_hist[2],
                bubble_cause_hist[3], bubble_cause_hist[4], bubble_cause_hist[5],
                bubble_cause_hist[6], bubble_cause_hist[7],
                bubble_cause_hist[8] + bubble_cause_hist[9] + bubble_cause_hist[10] +
                    bubble_cause_hist[11] + bubble_cause_hist[12] + bubble_cause_hist[13] +
                    bubble_cause_hist[14] + bubble_cause_hist[15],
                bubble_cause_hist[16] + bubble_cause_hist[17] + bubble_cause_hist[18] +
                    bubble_cause_hist[19] + bubble_cause_hist[20] + bubble_cause_hist[21] +
                    bubble_cause_hist[22] + bubble_cause_hist[23] + bubble_cause_hist[24] +
                    bubble_cause_hist[25] + bubble_cause_hist[26] + bubble_cause_hist[27] +
                    bubble_cause_hist[28] + bubble_cause_hist[29] + bubble_cause_hist[30] +
                    bubble_cause_hist[31]);
            $display("PERF_CAUSE_HIST_FULL: H00=%-d H01=%-d H02=%-d H03=%-d H04=%-d H05=%-d H06=%-d H07=%-d H08=%-d H09=%-d H10=%-d H11=%-d H12=%-d H13=%-d H14=%-d H15=%-d H16=%-d H17=%-d H18=%-d H19=%-d H20=%-d H21=%-d H22=%-d H23=%-d H24=%-d H25=%-d H26=%-d H27=%-d H28=%-d H29=%-d H30=%-d H31=%-d",
                bubble_cause_hist[0], bubble_cause_hist[1],
                bubble_cause_hist[2], bubble_cause_hist[3],
                bubble_cause_hist[4], bubble_cause_hist[5],
                bubble_cause_hist[6], bubble_cause_hist[7],
                bubble_cause_hist[8], bubble_cause_hist[9],
                bubble_cause_hist[10], bubble_cause_hist[11],
                bubble_cause_hist[12], bubble_cause_hist[13],
                bubble_cause_hist[14], bubble_cause_hist[15],
                bubble_cause_hist[16], bubble_cause_hist[17],
                bubble_cause_hist[18], bubble_cause_hist[19],
                bubble_cause_hist[20], bubble_cause_hist[21],
                bubble_cause_hist[22], bubble_cause_hist[23],
                bubble_cause_hist[24], bubble_cause_hist[25],
                bubble_cause_hist[26], bubble_cause_hist[27],
                bubble_cause_hist[28], bubble_cause_hist[29],
                bubble_cause_hist[30], bubble_cause_hist[31]);
            $display("PERF_PRODUCER_STATE: OCC0=%-d OCC1=%-d OCC2=%-d BOTH_WAIT=%-d WAIT_READY=%-d BOTH_READY=%-d RETIRE_HELD=%-d",
                producer_occ_zero_count,
                producer_occ_one_count,
                producer_occ_two_count,
                producer_both_wait_count,
                producer_wait_ready_count,
                producer_both_ready_count,
                producer_retire_held_count);
            $display("PERF_LSU_STRUCT_DETAIL: MMIO=%-d PENDING_STORE=%-d STORE_CAPTURE=%-d OTHER=%-d",
                lsu_struct_mmio_count,
                lsu_struct_pending_store_count,
                lsu_struct_store_capture_count,
                lsu_struct_other_count);
            $display("PERF_FRONTEND: PRED_TAKEN_REDIRECT=%-d CORRECT_TAKEN_REDIRECT=%-d PRED_TAKEN_BUBBLE=%-d WRONG_DIR_FLUSH=%-d BTB_MISS_TAKEN=%-d",
                fe_pred_taken_redirect_count,
                fe_correct_taken_redirect_count,
                fe_pred_taken_bubble_count,
                fe_wrong_dir_flush_count,
                bp_btb_miss_taken_count);
            $display("PERF_BRANCH: BRANCHES=%-d HITS=%-d PRED_TAKEN=%-d MISPRED=%-d ACC=%.2f",
                bp_branch_count, bp_hit_count, bp_taken_count, bp_mispredict_count, perf_bp_accuracy);
            $display("PERF_BP_ACC: ACC=%.2f", perf_bp_accuracy);
            $display("PERF_BP_DETAIL: TAKEN=%-d NOT_TAKEN=%-d DIR_MISPRED=%-d TARGET_MISPRED=%-d BTB_MISS_TAKEN=%-d CORRECT_TAKEN=%-d CORRECT_NOT_TAKEN=%-d",
                bp_actual_taken_count,
                bp_actual_not_taken_count,
                bp_dir_mispredict_count,
                bp_target_mispredict_count,
                bp_btb_miss_taken_count,
                bp_correct_taken_count,
                bp_correct_not_taken_count);
            $display("PERF_LSU_HOT: LOOKUP=%-d HIT=%-d FILL=%-d STORE_UPDATE=%-d",
                u_dut.u_ydrasil_load_store_unit.perf_hot_lookup_q,
                u_dut.u_ydrasil_load_store_unit.perf_hot_hit_q,
                u_dut.u_ydrasil_load_store_unit.perf_hot_fill_q,
                u_dut.u_ydrasil_load_store_unit.perf_hot_store_update_q);
            $display("EARLY_ALU_COVER: ARITH=%-d LOGIC=%-d SHIFT=%-d PASS=%-d NON_EARLY=%-d",
                early_arith_count, early_logic_count, early_shift_count,
                early_pass_count, non_early_alu_count);
            $display("EARLY_ALU_FWD_COVER: RS1=%-d RS2=%-d BOTH=%-d TO_ALU=%-d TO_LOAD=%-d TO_STORE=%-d COMPLETION_SRC=%-d",
                early_rs1_fwd_count, early_rs2_fwd_count,
                early_both_fwd_count, early_to_alu_count,
                early_to_load_count, early_to_store_count,
                early_completion_source_count);
            $display("EARLY_ALU_STATE_COVER: STALL_HOLD=%-d FLUSH_CLEAR=%-d BUBBLE_CLEAR=%-d",
                early_stall_hold_count, early_flush_clear_count,
                early_bubble_clear_count);
            $display("BROADCAST_COVER: ALU_LSU=%-d ALU_MUL=%-d LSU_MUL=%-d ALL=%-d",
                completion_alu_lsu_count, completion_alu_mul_count,
                completion_lsu_mul_count, completion_all_count);
            $display("BROADCAST_SEQUENCE_COVER: ALU_LSU_THEN_MUL=%-d MUL_THEN_ALU_LSU=%-d",
                completion_alu_lsu_then_mul_count,
                completion_mul_then_alu_lsu_count);
            $display("TOKEN_LIFECYCLE_COVER: C=%-d R=%-d A=%-d CR=%-d RA=%-d CA=%-d CRA=%-d",
                lifecycle_complete_only_count, lifecycle_retire_only_count,
                lifecycle_allocate_only_count, lifecycle_complete_retire_count,
                lifecycle_retire_allocate_count, lifecycle_complete_allocate_count,
                lifecycle_all_count);
            $display("TOKEN_SAME_SLOT_COVER: C=%-d R=%-d A=%-d CR=%-d RA=%-d CA=%-d CRA=%-d",
                same_slot_complete_only_count, same_slot_retire_only_count,
                same_slot_allocate_only_count, same_slot_complete_retire_count,
                same_slot_retire_allocate_count, same_slot_complete_allocate_count,
                same_slot_all_count);
            $display("TOKEN_FREE_COVER: NORMAL_DRAIN=%-d FLUSH_DRAIN=%-d TRAP_FREE=%-d",
                producer_normal_drain_count, producer_flush_drain_count,
                producer_trap_free_count);
            $display("LSU_QUEUE_COVER: HEAD_WRAP=%-d TAIL_WRAP=%-d EMPTY=%-d NEAR_FULL=%-d FULL=%-d POP=%-d",
                lsu_head_wrap_count, lsu_tail_wrap_count,
                lsu_queue_empty_count, lsu_queue_near_full_count,
                lsu_queue_full_count,
                lsu_queue_pop_count);
        end
    endtask

    // 添加一个任务来显示处理过的testcase名称
    task automatic display_testcase_name;
        integer i;
        reg [7:0] ch;
        reg printing;

        printing = 0;
        for (i = 300; i >= 1; i = i - 1) begin
            ch = testcase[i*8-:8];
            if (!printing && ch != " " && ch != 8'h00 && ch != 8'h20) begin
                printing = 1;
            end
            if (printing && (ch == 8'h00 || ch == 8'h0A)) begin
                printing = 0;
                break;
            end
            if (printing && ch >= 8'h20) begin
                $write("%c", ch);
            end
        end
    endtask



	initial begin
`ifdef VERILATOR_SV
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`elsif IVERILOG_VCD
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`endif
	end

endmodule
