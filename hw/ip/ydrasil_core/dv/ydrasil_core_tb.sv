`timescale 1ns/1ns

parameter longint time_end = 100000; 

module ydrasil_core_tb
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
import ydrasil_apb_pkg::*;
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
`define ITCM u_dut.u_ydrasil_mems.u_itcm.u_impl
`define DTCM u_dut.u_ydrasil_mems.u_dtcm.u_impl

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

			ydrasil_axi_lite_m2s_pkt_t axi_m2s;
			ydrasil_axi_lite_s2m_pkt_t axi_s2m;
			ydrasil_irq_pkt_t irq;
		wire [31:0] perip_addr;
		wire        perip_wen;
		wire [3:0]  perip_mask;
		wire [31:0] perip_wdata;
			wire [31:0] perip_rdata;
			logic [1:0] apb_div_q;
			wire apb_clk = apb_div_q[1];

			always_ff @(posedge clk or negedge rst_n) begin
				if (!rst_n)
					apb_div_q <= '0;
				else
					apb_div_q <= apb_div_q + 1'b1;
			end

    // 通用寄存器访问 - 仅用于错误信息显示
    wire [31:0] x3 = u_dut.u_ydrasil_issue_stage.u_registers.registers[3];
    // PC 监控
    // ID and issue are independently buffered.  Use the execution-side PC
    // for tohost detection; the fetch PC can be several instructions ahead.
    wire [31:0] pc = u_dut.u_ydrasil_commit_trace.id_instr_addr;
    wire [31:0] csr_instret = u_dut.u_ydrasil_commit_trace.csr_instret;
    wire [31:0] csr_cyclel = u_dut.u_ydrasil_commit_trace.csr_cyclel;

    integer           r;
    reg     [8*300:1] testcase;

    // 计算ITCM的深度和字节大小
    localparam ITCM_DEPTH = (1 << (ydrasil_pkg::ITCM_ADDR_WIDTH - 1));
    localparam ITCM_BYTE_SIZE = (1 << ydrasil_pkg::ITCM_ADDR_WIDTH) * 4;

    // 创建与ITCM容量相同的临时字节数组
    reg [7:0] prog_mem[0:ITCM_BYTE_SIZE-1];
    integer i;

    // 添加PC监控变量
    reg [31:0] pc_write_to_host_cnt;
    reg [31:0] pc_write_to_host_cycle;
    wire  [31:0] cycle_count = csr_cyclel;
    reg pc_write_to_host_flag;

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
    reg         raw_debug_en;
    reg         lsu_local_debug_en;
    reg         perf_local_debug_en;
    reg         perf_event_scan_en;
    reg         perf_bank_scan_en;
    reg         perf_issue_scan_en;
    reg         perf_refill_scan_en;
    reg         perf_stall_snapshot_en;
    integer     raw_debug_cycle;
    integer     lsu_local_debug_cycle;
    integer     perf_local_debug_cycle;
    integer     perf_local_start;
    integer     perf_local_end;
    integer     perf_issue_scan_count;
    integer     perf_refill_scan_count;
    integer     perf_empty_scan_count;
    integer     perf_stall_snapshot_threshold;
    integer     perf_stall_snapshot_cycles_q;
    reg         perf_stall_snapshot_printed_q;
    integer     perf_stall_snapshot_idx;
    reg         execution_wave_en;
    string      execution_wave_file;
    integer     execution_wave_fd;
    // Optional causal RS trace. Kept separate from execution_wave.csv so the
    // existing v2 schema and its consumers remain byte-compatible.
    reg         execution_causal_en;
    string      execution_causal_file;
    integer     execution_causal_fd;
    integer     execution_wave_start;
    integer     execution_wave_end;
    reg [31:0]  execution_wave_measure_start_pc;
    reg [31:0]  execution_wave_measure_stop_pc;
    reg         execution_wave_measure_filter_en;
    reg         execution_wave_measure_active;
    reg         execution_wave_measure_done;
    integer     execution_causal_idx;
    initial begin
        raw_debug_en = $test$plusargs("raw_debug");
        lsu_local_debug_en = $test$plusargs("lsu_local_debug");
        perf_local_debug_en = $test$plusargs("perf_local_debug");
        perf_event_scan_en = $test$plusargs("perf_event_scan");
        perf_bank_scan_en = $test$plusargs("perf_bank_scan");
        perf_issue_scan_en = $test$plusargs("perf_issue_scan");
        perf_refill_scan_en = $test$plusargs("perf_refill_scan");
        perf_stall_snapshot_en = $test$plusargs("perf_stall_snapshot");
        raw_debug_cycle = 0;
        lsu_local_debug_cycle = 0;
        perf_local_debug_cycle = 0;
        perf_local_start = 0;
        perf_local_end = 32'h7fffffff;
        perf_issue_scan_count = 0;
        perf_refill_scan_count = 0;
        perf_empty_scan_count = 0;
        perf_stall_snapshot_threshold = 64;
        execution_wave_en = 1'b0;
        execution_wave_fd = 0;
        execution_causal_en = 1'b0;
        execution_causal_fd = 0;
        execution_wave_start = 0;
        execution_wave_end = 32'h7fffffff;
        execution_wave_measure_start_pc = '0;
        execution_wave_measure_stop_pc = '0;
        execution_wave_measure_filter_en = 1'b0;
        execution_wave_measure_active = 1'b1;
        execution_wave_measure_done = 1'b0;
        if (!$value$plusargs("perf_local_start=%d", perf_local_start))
            perf_local_start = 0;
        if (!$value$plusargs("perf_local_end=%d", perf_local_end))
            perf_local_end = 32'h7fffffff;
        if (!$value$plusargs("perf_stall_threshold=%d",
                             perf_stall_snapshot_threshold))
            perf_stall_snapshot_threshold = 64;
        if ($value$plusargs("execution_wave=%s", execution_wave_file)) begin
            execution_wave_fd = $fopen(execution_wave_file, "w");
            if (execution_wave_fd == 0)
                $fatal(1, "unable to open execution wave CSV: %s",
                       execution_wave_file);
            execution_wave_en = 1'b1;
            $fdisplay(execution_wave_fd,
                "reset,sample_valid,halted,cycle,instret,fetch_pc,issue_pc0,issue_pc1,issue_tag0,issue_tag1,selected_pc0,selected_pc1,selected_tag0,selected_tag1,ex_pc0,ex_pc1,ex_tag0,ex_tag1,if_valid0,if_valid1,decode_valid0,decode_valid1,dispatch_accept0,dispatch_accept1,rs_valid_mask,rs_dep_mask,rs_order_mask,rs_resource_mask,rs_ready_mask,rs_candidate_mask,rs_selected_mask,select_valid0,select_valid1,select_push,select_head_valid,select_head_pair,select_skid_valid,head0_b_only,operand_accept0,operand_accept1,ex_valid0,ex_valid1,ex_accept0,ex_accept1,retire0,retire1,rob_count,producer_full,lsu_credit,lsu_reserved,lsu_queue_count,lsu_idle,lsu_struct_stall,serialize_stall,mdu_available,flush,redirect,recovery_pending,pipeline_flush,fence_issue,trap_redirect,frontend_queue_count,fetch_req_valid,fetch_resp_valid,pending_redirect,completion_wakeup_mask,alloc_wakeup_mask,select_wakeup_mask,dtcm_wakeup,mdu_wakeup,dep_blocker_mask,alu_credit,p0_credit,p1_credit,physical_exec0,physical_exec1,branch_mispredict,direct_fire,direct_pair,retire_pc0,retire_pc1");
        end
        if ($value$plusargs("execution_causal=%s", execution_causal_file)) begin
            execution_causal_fd = $fopen(execution_causal_file, "w");
            if (execution_causal_fd == 0)
                $fatal(1, "unable to open causal execution CSV: %s",
                       execution_causal_file);
            execution_causal_en = 1'b1;
            $fwrite(execution_causal_fd,
                "reset,sample_valid,halted,cycle,instret,physical_exec0,physical_exec1,ex_accept0,ex_accept1,producer_full,rob_count,rob_head_tag,redirect,branch_mispredict,frontend_queue_count,fetch_req_valid,fetch_resp_valid,pending_redirect,if_valid0,if_valid1,decode_valid0,decode_valid1,dispatch_accept0,dispatch_accept1,select_push,select_head_valid,select_head_pair,select_skid_valid,operand_accept0,operand_accept1,rs_valid_mask,rs_ready_mask,rs_candidate_mask,rs_selected_mask,rs_dep_mask,rs_order_mask,rs_resource_mask,completion_wakeup_mask,alloc_wakeup_mask,select_wakeup_mask,select_head_pc0,select_head_tag0,select_head_pc1,select_head_tag1,operand_pc0,operand_tag0,operand_pc1,operand_tag1,ex_pc0,ex_tag0,ex_pc1,ex_tag1,completion0_valid,completion0_tag,completion1_valid,completion1_tag,completion2_valid,completion2_tag,completion3_valid,completion3_tag,retire0_valid,retire0_tag,retire1_valid,retire1_tag");
            for (execution_causal_idx = 0; execution_causal_idx < 12;
                 execution_causal_idx = execution_causal_idx + 1) begin
                $fwrite(execution_causal_fd,
                ",rs%0d_valid,rs%0d_pc,rs%0d_tag,rs%0d_src0_ready,rs%0d_src1_ready,rs%0d_candidate,rs%0d_selected,rs%0d_src0_tag_valid,rs%0d_src0_prod,rs%0d_src1_tag_valid,rs%0d_src1_prod,rs%0d_memory,rs%0d_store,rs%0d_mul,rs%0d_divrem,rs%0d_serial,rs%0d_order_blocked,rs%0d_bank",
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx,
                    execution_causal_idx, execution_causal_idx);
            end
            $fwrite(execution_causal_fd, "\n");
        end
        if (!$value$plusargs("execution_wave_start=%d", execution_wave_start))
            execution_wave_start = 0;
        if (!$value$plusargs("execution_wave_end=%d", execution_wave_end))
            execution_wave_end = 32'h7fffffff;
        if ($value$plusargs("execution_wave_measure_start_pc=%h",
                            execution_wave_measure_start_pc) &&
            $value$plusargs("execution_wave_measure_stop_pc=%h",
                            execution_wave_measure_stop_pc)) begin
            execution_wave_measure_filter_en = 1'b1;
            execution_wave_measure_active = 1'b0;
            execution_wave_measure_done = 1'b0;
        end
    end

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
    reg [31:0] stall_dependency_count;
    reg [31:0] stall_lsu_struct_count;
    reg [31:0] stall_wb_backpressure_count;
    reg [31:0] stall_clint_count;
    reg [31:0] stall_mul_count;
    reg [31:0] dep_rs1_pending_count;
    reg [31:0] dep_rs2_pending_count;
    reg [31:0] dep_rd_waw_count;
    reg [31:0] dep_issue_rs1_hzd_count;
    reg [31:0] dep_issue_rs2_hzd_count;
    reg [31:0] dep_issue_rd_hzd_count;
    reg [31:0] dep_load_use_count;
    reg [31:0] dep_alu_use_count;
    reg [31:0] dep_mul_div_use_count;
    reg [31:0] dep_branch_src_wait_count;
    reg [31:0] dep_store_addr_wait_count;
    reg [31:0] dep_store_data_wait_count;
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
    reg [31:0] dep_load_to_alu_count;
    reg [31:0] dep_load_to_branch_count;
    reg [31:0] dep_load_to_load_count;
    reg [31:0] dep_load_to_store_count;
    reg [31:0] dep_load_to_mul_count;
    reg [31:0] dep_load_to_other_count;
    reg [31:0] dep_load_rs1_count;
    reg [31:0] dep_load_rs2_count;
    reg [31:0] dep_pending_tail_count;
    reg [31:0] dep_alu_to_alu_count;
    reg [31:0] dep_alu_to_branch_count;
    reg [31:0] dep_alu_to_load_count;
    reg [31:0] dep_alu_to_store_count;
    reg [31:0] dep_alu_to_mul_count;
    reg [31:0] dep_alu_to_other_count;
    reg [31:0] dep_pending_alu_count;
    reg [31:0] dep_pending_load_count;
    reg [31:0] dep_pending_mul_count;
    reg [31:0] dep_pending_other_count;
    reg [31:0] dep_ready_but_stall_count;
    reg [31:0] dep_complete_visible_count;
    reg [31:0] dep_registered_visible_count;
    reg [31:0] mul_tail_slot_release_late_count;
    reg [31:0] mul_tail_ready_late_count;
    reg [31:0] mul_tail_consumer_no_bypass_count;
    reg [31:0] acct_flush_count;
    reg [31:0] acct_mul_hold_count;
    reg [31:0] acct_dependency_count;
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
    reg [31:0] perf_productive_slot_count;
    // Exact lane split for the productive part of the capacity partition.
    // These are slot counts, unlike the cycle-level primary cause counters.
    reg [31:0] perf_executed_slot0_count;
    reg [31:0] perf_executed_slot1_count;
    reg [31:0] perf_ex_branch_drop0_count;
    reg [31:0] perf_ex_branch_drop1_count;
    reg [31:0] perf_ex_mul_drop0_count;
    reg [31:0] perf_ex_mul_drop1_count;
    reg [31:0] perf_ex_empty0_count;
    reg [31:0] perf_ex_empty1_count;
    reg [31:0] perf_ex_empty_reset_count;
    reg [31:0] perf_ex_empty_recovery_count;
    reg [31:0] perf_ex_empty_fence_count;
    reg [31:0] perf_ex_empty_b_only_count;
    reg [31:0] perf_ex_empty_single_head_count;
    reg [31:0] perf_ex_empty_select_refill_count;
    reg [31:0] perf_ex_empty_rs_dependency_count;
    reg [31:0] perf_ex_empty_rs_order_count;
    reg [31:0] perf_ex_empty_rs_resource_count;
    reg [31:0] perf_ex_empty_rs_no_candidate_count;
    reg [31:0] perf_ex_empty_rs_empty_count;
    reg [31:0] perf_ex_empty_frontend_count;
    reg [31:0] perf_ex_empty_other_count;
    reg [31:0] perf_ex_empty_launch_mismatch_count;
    reg [31:0] perf_ex_empty_unmapped_count;
    reg [31:0] perf_ex_valid_hold0_count;
    reg [31:0] perf_ex_valid_hold1_count;
    reg [4:0] perf_src_kind0_q;
    reg [4:0] perf_src_kind1_q;
    reg [31:0] perf_lost_flush_slot_count;
    reg [31:0] perf_lost_mul_hold_slot_count;
    reg [31:0] perf_lost_dependency_slot_count;
    reg [31:0] perf_lost_lsu_struct_slot_count;
    reg [31:0] perf_lost_lsu_serialize_slot_count;
    reg [31:0] perf_lost_producer_full_slot_count;
    reg [31:0] perf_lost_wb_slot_count;
    reg [31:0] perf_lost_clint_slot_count;
    reg [31:0] perf_lost_multi_slot_count;
    reg [31:0] perf_lost_no_if_valid_slot_count;
    reg [31:0] perf_lost_issue_slot_count;
    reg [31:0] perf_lost_other_slot_count;
    reg [31:0] noif_control_redirect_count;
    reg [31:0] noif_predict_redirect_count;
    reg [31:0] noif_fence_refill_count;
    reg [31:0] noif_mem_response_count;
    reg [31:0] noif_fetch_launch_count;
    reg [31:0] noif_pending_redirect_count;
    reg [31:0] noif_other_count;
    // Slot-weighted subcauses for the mutually-exclusive NO_IF_VALID bucket.
    // The existing noif_* counters remain cycle counts for compatibility.
    reg [31:0] perf_noif_control_redirect_slots;
    reg [31:0] perf_noif_predict_redirect_slots;
    reg [31:0] perf_noif_fence_refill_slots;
    reg [31:0] perf_noif_mem_response_slots;
    reg [31:0] perf_noif_fetch_launch_slots;
    reg [31:0] perf_noif_pending_redirect_slots;
    reg [31:0] perf_noif_other_slots;
    reg [31:0] other_issue_refill_count;
    reg [31:0] other_decode_refill_count;
    reg [31:0] decode_refill_after_control_count;
    reg [31:0] decode_refill_after_predict_count;
    reg [31:0] decode_refill_after_fence_count;
    reg [31:0] decode_refill_after_supply_count;
    reg [31:0] other_issue_blocked_count;
    reg [31:0] other_unclassified_count;
    // Slot-weighted subcauses for the mutually-exclusive ISSUE bucket.
    reg [31:0] perf_issue_dependency_slots;
    reg [31:0] perf_issue_lsu_struct_slots;
    reg [31:0] perf_issue_serialize_slots;
    reg [31:0] perf_issue_single_lane_slots;
    reg [31:0] perf_issue_no_execute_slots;
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
    reg [31:0] retire_four_count;
    reg [31:0] dual_issue_count;
    reg [31:0] dual_alu_alu_count;
    reg [31:0] dual_bru_alu_count;
    reg [31:0] dual_lsu_alu_count;
    reg [31:0] dual_muldiv_alu_count;
    reg [31:0] dual_other_count;
    reg [31:0] l0_lookup_count;
    reg [31:0] l0_hit_count;
    reg [31:0] l0_correction_count;
    reg [31:0] bubble_cause_hist [0:31];
    reg [31:0] producer_occ_zero_count;
    reg [31:0] producer_occ_one_count;
    reg [31:0] producer_occ_two_count;
    reg [31:0] producer_both_wait_count;
    reg [31:0] producer_wait_ready_count;
    reg [31:0] producer_both_ready_count;
    reg [31:0] producer_retire_held_count;
    // The backend has one RS/Select stage followed by one Operand stage.
    // Every histogram below is mutually exclusive within its own family.
    reg [31:0] perf_rob_occ_count [0:PRODUCER_NUM];
    reg [31:0] perf_rs_occ_count [0:12];
    reg [31:0] perf_rs_alloc_count [0:2];
    reg [31:0] perf_select_count [0:2];
    reg [31:0] perf_operand_count [0:2];
    reg [31:0] perf_complete_count [0:4];
    reg [31:0] perf_retire_count [0:2];
    reg [31:0] perf_candidate_mask_count [0:15];
    reg [31:0] perf_head_empty_count;
    reg [31:0] perf_head_retire1_count;
    reg [31:0] perf_head_retire2_count;
    reg [31:0] perf_head_complete_visible_count;
    reg [31:0] perf_head_not_issued_count;
    reg [31:0] perf_head_wait_alu_count;
    reg [31:0] perf_head_wait_load_count;
    reg [31:0] perf_head_wait_mdu_count;
    reg [31:0] perf_head_wait_store_count;
    reg [31:0] perf_head_wait_branch_count;
    reg [31:0] perf_head_wait_other_count;
    reg [31:0] perf_head_ni_select_transit_count;
    reg [31:0] perf_head_ni_rs_dependency_count;
    reg [31:0] perf_head_ni_rs_order_count;
    reg [31:0] perf_head_ni_rs_resource_count;
    reg [31:0] perf_head_ni_rs_ready_count;
    reg [31:0] perf_head_ni_absent_count;
    reg [31:0] perf_loss_flush_slots;
    reg [31:0] perf_loss_operand_block_slots;
    reg [31:0] perf_loss_single_bundle_slots;
    reg [31:0] perf_loss_select_refill_slots;
    reg [31:0] perf_loss_rs_dependency_slots;
    reg [31:0] perf_loss_rs_order_slots;
    reg [31:0] perf_loss_rs_resource_slots;
    reg [31:0] perf_loss_rs_other_slots;
    reg [31:0] perf_loss_rob_full_slots;
    reg [31:0] perf_loss_rs_refill_slots;
    reg [31:0] perf_loss_decode_refill_slots;
    reg [31:0] perf_loss_frontend_slots;
    reg [31:0] perf_loss_other_slots;
    // Mutually-exclusive leaves for the three largest backend-loss parents.
    // They are slot-weighted and must sum to their corresponding parent.
    reg [31:0] perf_single_p0_only_slots;
    reg [31:0] perf_single_p1_only_slots;
    reg [31:0] perf_single_alu_only_slots;
    reg [31:0] perf_single_serial_slots;
    reg [31:0] perf_single_other_slots;
    reg [31:0] perf_select_refill_pair_slots;
    reg [31:0] perf_select_refill_p0_slots;
    reg [31:0] perf_select_refill_p1_slots;
    reg [31:0] perf_select_refill_alu_slots;
    reg [31:0] perf_select_refill_serial_slots;
    reg [31:0] perf_select_refill_other_slots;
    reg [31:0] perf_dep_src0_slots;
    reg [31:0] perf_dep_src1_slots;
    reg [31:0] perf_dep_both_src_slots;
    reg [31:0] perf_dep_completion_wakeup_slots;
    reg [31:0] perf_dep_alloc_wakeup_slots;
    reg [31:0] perf_dep_load_slots;
    reg [31:0] perf_dep_mul_slots;
    reg [31:0] perf_dep_branch_slots;
    reg [31:0] perf_dep_other_slots;
    // Independent operation-class and wakeup-source projections of the same
    // three parent loss buckets. Each projection has its own closure check.
    reg [31:0] perf_single_op_alu_slots;
    reg [31:0] perf_single_op_load_slots;
    reg [31:0] perf_single_op_store_slots;
    reg [31:0] perf_single_op_mul_slots;
    reg [31:0] perf_single_op_csr_sys_slots;
    reg [31:0] perf_single_op_other_slots;
    reg [31:0] perf_refill_shape_p0_p1_slots;
    reg [31:0] perf_refill_shape_p0_alu_slots;
    reg [31:0] perf_refill_shape_p1_alu_slots;
    reg [31:0] perf_refill_shape_alu_alu_slots;
    reg [31:0] perf_refill_shape_single_p0_slots;
    reg [31:0] perf_refill_shape_single_p1_slots;
    reg [31:0] perf_refill_shape_single_alu_slots;
    reg [31:0] perf_refill_shape_serial_slots;
    reg [31:0] perf_refill_shape_other_slots;
    reg [31:0] perf_dep_wake_both_slots;
    reg [31:0] perf_dep_wake_mixed_slots;
    reg [31:0] perf_dep_wake_src0_completion_slots;
    reg [31:0] perf_dep_wake_src1_completion_slots;
    reg [31:0] perf_dep_wake_src0_alloc_slots;
    reg [31:0] perf_dep_wake_src1_alloc_slots;
    reg [31:0] perf_dep_wake_none_slots;
    reg [31:0] perf_dep_op_alu_slots;
    reg [31:0] perf_dep_op_load_slots;
    reg [31:0] perf_dep_op_store_slots;
    reg [31:0] perf_dep_op_mul_slots;
    reg [31:0] perf_dep_op_branch_slots;
    reg [31:0] perf_dep_op_other_slots;
    // Orthogonal dependency projection. The mask keeps simultaneous blocker
    // classes coupled instead of forcing them into an arbitrary priority bin.
    // Bits are ALU, LOAD, MDU, OTHER, and stale/missing producer identity.
    reg [31:0] perf_dep_blocker_mask_slots [0:31];
    reg [31:0] perf_dep_blocker_operand_cycles [0:4];
    // Decompose the execution-slot OTHER bucket. These counters are mutually
    // exclusive and are charged only in the final cycle-accounting OTHER arm.
    reg [31:0] perf_other_rob_block_slots;
    reg [31:0] perf_other_rs_bank_block_slots;
    reg [31:0] perf_other_recovery_resync_slots;
    reg [31:0] perf_other_alu_bank_block_slots;
    reg [31:0] perf_other_p0_bank_block_slots;
    reg [31:0] perf_other_p1_bank_block_slots;
    reg [31:0] perf_bank_alu_local_full_slots;
    reg [31:0] perf_bank_alu_credit_stale_slots;
    reg [31:0] perf_bank_p0_local_full_slots;
    reg [31:0] perf_bank_p0_credit_stale_slots;
    reg [31:0] perf_bank_p1_local_full_slots;
    reg [31:0] perf_bank_p1_credit_stale_slots;
    reg [31:0] perf_bank_unclassified_slots;
    reg [31:0] perf_p0_full_dependency_slots;
    reg [31:0] perf_p0_full_order_slots;
    reg [31:0] perf_p0_full_resource_slots;
    reg [31:0] perf_p0_full_ready_release_slots;
    reg [31:0] perf_p0_full_no_candidate_slots;
    // Progressive existential classification of the four resident P0 entries.
    // Unlike the legacy priority bucket, one blocked entry cannot hide a
    // different entry that has already passed dependency or order gating.
    reg [31:0] perf_p0_pipe_selectable_slots;
    reg [31:0] perf_p0_pipe_credit_blocked_slots;
    reg [31:0] perf_p0_pipe_order_blocked_slots;
    reg [31:0] perf_p0_pipe_dependency_blocked_slots;
    // Slot-weighted LSU registered-credit x Select-to-AGU reservation matrix.
    // Index is credit*3+reservation; both protocols are bounded by two.
    reg [31:0] perf_p0_credit_resv_slots [0:8];
    reg [31:0] perf_p0_full_store_mix_slots [0:4];
    reg [31:0] perf_p0_full_blocked_load_slots;
    reg [31:0] perf_p0_full_blocked_store_slots;
    reg [31:0] perf_p0_full_blocked_other_slots;
    reg [31:0] perf_p0_completion_wakeup_cycles;
    reg [31:0] perf_operand_merge_pair_cycles;
    // Entry-weighted wakeup observations. These are intentionally separate
    // from slot-loss counters: a single cycle can wake several RS entries.
    reg [31:0] perf_rs_completion_wakeup_entries;
    reg [31:0] perf_rs_alloc_wakeup_entries;
    reg [31:0] perf_rs_select_wakeup_entries;
    reg [31:0] perf_dtcm_launch_wakeup_events;
    reg [31:0] perf_dtcm_result_wakeup_events;
    reg [31:0] perf_mdu_wakeup_events;
    reg [31:0] perf_replay_wakeup_events;
    reg [31:0] perf_other_rs_pair_limit_slots;
    reg [31:0] perf_other_select_refill_slots;
    reg [31:0] perf_other_rs_dependency_slots;
    reg [31:0] perf_other_rs_order_slots;
    reg [31:0] perf_other_rs_resource_slots;
    reg [31:0] perf_other_rs_no_candidate_slots;
    reg [31:0] perf_other_rs_empty_slots;
    reg [31:0] perf_other_decode_block_slots;
    reg [31:0] perf_other_unclassified_slots;
    reg [31:0] perf_rs_dependency_entry_cycles;
    reg [31:0] perf_rs_order_entry_cycles;
    reg [31:0] perf_rs_resource_entry_cycles;
    reg [31:0] perf_rs_selectable_entry_cycles;
    reg [31:0] perf_rs_bank_full_cycles;
    reg [31:0] perf_rs_pair_bank_limit_cycles;
    reg [31:0] perf_rob_full_cycles;
    reg [31:0] perf_lsu_credit_wait_cycles;
    reg [31:0] perf_lsu_age_repair_cycles;
    reg [31:0] perf_div_credit_wait_cycles;
    reg [31:0] perf_serial_gate_wait_cycles;
    reg [31:0] perf_select_width_limit_cycles;
    reg [31:0] perf_operand_dependency_miss_cycles;
    reg [31:0] perf_recovery_cycles;
    reg [31:0] perf_recovery_resync_cycles;
    reg [31:0] perf_alu_bank_entry_cycles;
    reg [31:0] perf_p0_bank_entry_cycles;
    reg [31:0] perf_p1_bank_entry_cycles;
    reg [31:0] perf_alu_bank_full_cycles;
    reg [31:0] perf_p0_bank_full_cycles;
    reg [31:0] perf_p1_bank_full_cycles;
    reg [31:0] perf_alu_due_select_cycles;
    reg [31:0] perf_dtcm_due_select_cycles;
    reg [31:0] perf_mdu_due_select_cycles;
    reg [31:0] perf_dtcm_local_wake_cycles;
    reg [31:0] perf_mdu_local_wake_cycles;
    reg [31:0] perf_resident_wakeup_entry_cycles;
    reg [31:0] perf_resident_due_select_cycles;
    // Orthogonal backend observations.  The legacy loss counters below are
    // intentionally exclusive; these counters preserve simultaneous causes
    // so an optimization can be evaluated against the actual coupled state.
    reg [31:0] perf_coupling_mask_count [0:255];
    reg [31:0] perf_cpl_bank_dep_count;
    reg [31:0] perf_cpl_bank_rob_count;
    reg [31:0] perf_cpl_bank_resource_count;
    reg [31:0] perf_cpl_bank_select_count;
    reg [31:0] perf_cpl_bank_operand_count;
    reg [31:0] perf_cpl_rob_dep_count;
    reg [31:0] perf_cpl_rob_resource_count;
    reg [31:0] perf_cpl_rob_select_count;
    reg [31:0] perf_cpl_rob_operand_count;
    reg [31:0] perf_cpl_dep_resource_count;
    reg [31:0] perf_cpl_dep_select_count;
    reg [31:0] perf_cpl_dep_operand_count;
    reg [31:0] perf_cpl_resource_select_count;
    reg [31:0] perf_cpl_select_operand_count;
    reg [31:0] perf_cpl_bank_dep_select_count;
    reg [31:0] perf_cpl_bank_rob_select_count;
    reg [31:0] perf_cpl_dep_select_operand_count;
    // Loss-weighted coupling.  The legacy coupling mask is a state
    // observation over all cycles; this mask is charged only when an EX
    // capacity slot was actually lost, and stores both cycle and slot weight.
    localparam integer PERF_LOSS_COUPLING_BITS = 12;
    localparam integer PERF_LOSS_COUPLING_DEPTH =
        (1 << PERF_LOSS_COUPLING_BITS);
    reg [31:0] perf_loss_coupling_cycle_count [0:PERF_LOSS_COUPLING_DEPTH-1];
    reg [31:0] perf_loss_coupling_slot_count [0:PERF_LOSS_COUPLING_DEPTH-1];
    reg [31:0] perf_loss_coupling_cycles;
    reg [31:0] perf_loss_coupling_slots;
    // Select opportunity is kept separate from the exclusive loss tree.  It
    // describes raw bank candidates, the best width allowed by those banks,
    // and the width that crossed the Select/Operand boundary.
    reg [31:0] perf_select_raw_width_count [0:2];
    reg [31:0] perf_select_actual_width_count [0:2];
    reg [31:0] perf_select_raw_shape_count [0:15];
    reg [31:0] perf_select_raw_alu_entries;
    reg [31:0] perf_select_raw_p0_entries;
    reg [31:0] perf_select_raw_p1_entries;
    reg [31:0] perf_select_drop_alu_entries;
    reg [31:0] perf_select_drop_p0_entries;
    reg [31:0] perf_select_drop_p1_entries;
    reg [31:0] perf_select_width_gap_slots;
    reg [31:0] perf_select_pair_capable_single_cycles;
    reg [31:0] perf_select_pair_capable_single_slots;
    reg [31:0] perf_select_width_matrix_cycles [0:2][0:2];
    reg [31:0] perf_select_width_matrix_slots [0:2][0:2];
    reg [31:0] perf_select_gap_recovery_cycles;
    reg [31:0] perf_select_gap_no_push_cycles;
    reg [31:0] perf_select_gap_policy_cycles;
    reg [31:0] perf_select_queue_state_count [0:15];
    reg [31:0] perf_select_hol_pair_cycles;
    reg [31:0] perf_select_hol_pair_lost_slots;
    reg [31:0] perf_select_pair_push_cycles;
    reg [31:0] perf_select_pair_issue_cycles;
    reg [31:0] perf_select_pair_push_single_head_cycles;
    reg [31:0] perf_select_pair_push_single_head_slots;
    reg [31:0] perf_select_refill_head_empty_cycles;
    reg [31:0] perf_select_refill_head_empty_slots;
    reg [31:0] perf_select_refill_head_empty_pair_slots;
    reg [31:0] perf_select_refill_head_empty_single_slots;
    reg [31:0] perf_select_refill_head_empty_uops;
    localparam integer PERF_REFILL_LIFECYCLE_COUNT = 6;
    reg [31:0] perf_select_refill_lifecycle_data_uops
        [0:PERF_REFILL_LIFECYCLE_COUNT-1][0:1];
    // Prior blocker mask uses bits DEP/ORDER/RESOURCE. Indices 8 and 9 are
    // newly allocated/replaced identity and unclassified respectively.
    reg [31:0] perf_select_refill_prior_mask_uops [0:9];
    reg [31:0] perf_select_refill_pending_mask_uops [0:15];
    reg [11:0] perf_refill_prev_valid_q;
    reg [11:0] perf_refill_prev_dep_q;
    reg [11:0] perf_refill_prev_order_q;
    reg [11:0] perf_refill_prev_resource_q;
    reg [11:0] perf_refill_prev_ready_q;
    producer_id_t perf_refill_prev_tag_q [0:11];
    integer perf_refill_lifecycle_idx;
    integer perf_refill_data_idx;
    integer perf_refill_mask_idx;
    integer perf_refill_prior_mask_idx;
    integer perf_refill_prev_idx;
    // Per-bank state is needed to distinguish a genuinely full bank from a
    // bank that is merely selected by the exclusive legacy reason priority.
    reg [31:0] perf_bank_dep_entry_cycles [0:2];
    reg [31:0] perf_bank_order_entry_cycles [0:2];
    reg [31:0] perf_bank_resource_entry_cycles [0:2];
    reg [31:0] perf_bank_ready_entry_cycles [0:2];
    reg [31:0] perf_bank_candidate_entry_cycles [0:2];
    reg [31:0] perf_bank_selected_entry_cycles [0:2];
    // Transaction timing is keyed by the generation-qualified producer ID.
    // It exposes whether the extra pipeline is spent in RS, Operand, FU, or
    // retirement rather than charging the whole delay to one parent bucket.
    localparam integer PERF_LATENCY_BINS = 6;
    reg [31:0] perf_latency_alloc_select [0:PERF_LATENCY_BINS-1];
    reg [31:0] perf_latency_select_operand [0:PERF_LATENCY_BINS-1];
    reg [31:0] perf_latency_operand_ex [0:PERF_LATENCY_BINS-1];
    reg [31:0] perf_latency_alloc_complete [0:PERF_LATENCY_BINS-1];
    reg [31:0] perf_latency_alloc_retire [0:PERF_LATENCY_BINS-1];
    reg [31:0] perf_alloc_cycle_by_id [0:(1 << PRODUCER_ID_WIDTH)-1];
    reg [31:0] perf_select_cycle_by_id [0:(1 << PRODUCER_ID_WIDTH)-1];
    reg [31:0] perf_operand_cycle_by_id [0:(1 << PRODUCER_ID_WIDTH)-1];
    reg perf_alloc_live_by_id [0:(1 << PRODUCER_ID_WIDTH)-1];
    integer perf_lifecycle_id;
    integer perf_lifecycle_bin;
    integer perf_lifecycle_latency;
    integer perf_lifecycle_idx;
    reg [PRODUCER_NUM-1:0] perf_producer_issued_q;
    reg perf_producer_full_q;
    reg perf_p0_bank_block_q;
    integer perf_producer_full_start_q;
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
    integer perf_width_idx;
    integer perf_width_idx2;
    reg [31:0] fe_pred_taken_redirect_count;
    reg [31:0] fe_correct_taken_redirect_count;
    reg [31:0] fe_pred_taken_bubble_count;
    reg [31:0] fe_wrong_dir_flush_count;
    reg        bp_predict_redirect_q;
    reg [31:0] issue_fence_count;
    reg [31:0] issue_slot1_replay_count;
    reg [31:0] issue_slot1_dependency_replay_count;
    reg [31:0] issue_slot1_lsu_replay_count;
    reg [31:0] issue_serialize_wait_count;
    reg [31:0] operandq_occ_count [0:4];

    // Two issue slots are available on every sampled execution cycle.  These
    // signals intentionally count accepted EX instructions, rather than
    // retirement, so a stall/flush is charged to the cycle in which it
    // consumed capacity.
    wire [1:0] perf_executed_slots =
        {1'b0, u_dut.ex_accept_valid} + {1'b0, u_dut.ex_accept_valid1};
    wire [2:0] perf_lost_slots = 3'd2 - {1'b0, perf_executed_slots};
    wire [31:0] perf_lost_slots_ext = {{29{1'b0}}, perf_lost_slots};
    wire [1:0] perf_operand_admit_slots =
        {1'b0, u_dut.u_ydrasil_issue_stage.lane_a_accept} +
        {1'b0, u_dut.u_ydrasil_issue_stage.lane_b_accept};
    wire perf_p0_completion_wakeup_now =
        (|u_dut.u_ydrasil_issue_stage.issue_src0_completion_wakeup[7:4]) ||
        (|u_dut.u_ydrasil_issue_stage.issue_src1_completion_wakeup[7:4]);
    wire perf_rs_completion_wakeup_now =
        (|u_dut.u_ydrasil_issue_stage.issue_src0_completion_wakeup) ||
        (|u_dut.u_ydrasil_issue_stage.issue_src1_completion_wakeup);
    wire perf_rs_alloc_wakeup_now =
        (|u_dut.u_ydrasil_issue_stage.issue_src0_alloc_wakeup) ||
        (|u_dut.u_ydrasil_issue_stage.issue_src1_alloc_wakeup);
    wire [3:0] perf_rs_completion_wakeup_entries_now =
        4'($countones(u_dut.u_ydrasil_issue_stage.
            issue_src0_completion_wakeup | u_dut.u_ydrasil_issue_stage.
            issue_src1_completion_wakeup));
    wire [3:0] perf_rs_alloc_wakeup_entries_now =
        4'($countones(u_dut.u_ydrasil_issue_stage.
            issue_src0_alloc_wakeup | u_dut.u_ydrasil_issue_stage.
            issue_src1_alloc_wakeup));
    wire [3:0] perf_rs_select_wakeup_entries_now =
        4'($countones(u_dut.u_ydrasil_issue_stage.
            issue_src0_fast_main | u_dut.u_ydrasil_issue_stage.
            issue_src0_fast_dual | u_dut.u_ydrasil_issue_stage.
            issue_src1_fast_main | u_dut.u_ydrasil_issue_stage.
            issue_src1_fast_dual));
    wire perf_operand_merge_pair_now =
        u_dut.u_ydrasil_issue_stage.select_skid_merge_pair;
    wire [2:0] perf_operand_lost_slots =
        3'd2 - {1'b0, perf_operand_admit_slots};
    wire [31:0] perf_operand_lost_slots_ext =
        {{29{1'b0}}, perf_operand_lost_slots};
    localparam [4:0] PERF_SRC_RESET = 5'd0;
    localparam [4:0] PERF_SRC_RECOVERY = 5'd1;
    localparam [4:0] PERF_SRC_FENCE = 5'd2;
    localparam [4:0] PERF_SRC_B_ONLY = 5'd3;
    localparam [4:0] PERF_SRC_SINGLE_HEAD = 5'd4;
    localparam [4:0] PERF_SRC_SELECT_REFILL = 5'd5;
    localparam [4:0] PERF_SRC_RS_DEPENDENCY = 5'd6;
    localparam [4:0] PERF_SRC_RS_ORDER = 5'd7;
    localparam [4:0] PERF_SRC_RS_RESOURCE = 5'd8;
    localparam [4:0] PERF_SRC_RS_NO_CANDIDATE = 5'd9;
    localparam [4:0] PERF_SRC_RS_EMPTY = 5'd10;
    localparam [4:0] PERF_SRC_FRONTEND = 5'd11;
    localparam [4:0] PERF_SRC_OTHER = 5'd12;
    localparam [4:0] PERF_SRC_LAUNCH = 5'd13;
    localparam [3:0] PERF_SEL_REASON_OTHER = 4'd0;
    localparam [3:0] PERF_SEL_REASON_SERIAL = 4'd1;
    localparam [3:0] PERF_SEL_REASON_P0 = 4'd2;
    localparam [3:0] PERF_SEL_REASON_P1 = 4'd3;
    localparam [3:0] PERF_SEL_REASON_ALU = 4'd4;
    localparam [3:0] PERF_SEL_REASON_PAIR = 4'd5;
    reg [3:0] perf_select_reason_d;
    reg [3:0] perf_select_reason_q;
    reg [4:0] perf_src_kind0_d;
    reg [4:0] perf_src_kind1_d;
    wire perf_select_head_serial =
        u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
        ((u_dut.u_ydrasil_issue_stage.select_head_uop0_q.op_class ==
          UOP_CLASS_CSR) ||
         (u_dut.u_ydrasil_issue_stage.select_head_uop0_q.op_class ==
          UOP_CLASS_SYS) ||
         u_dut.u_ydrasil_issue_stage.select_head_uop0_q.fence_i);
    wire perf_serial_pending = perf_select_head_serial;
    producer_id_t perf_serial_tag;
    assign perf_serial_tag =
        u_dut.u_ydrasil_issue_stage.select_head_uop0_q.dst.rob_tag;
    wire [INST_ADDR_WIDTH-1:0] perf_serial_pc =
        u_dut.u_ydrasil_issue_stage.select_head_uop0_q.pc;
    wire [1:0] perf_select_buf_count =
        {1'b0, u_dut.u_ydrasil_issue_stage.select_head_valid_q};
    wire [2:0] perf_select_admit_slots =
        (u_dut.u_ydrasil_issue_stage.select_buf_push ?
         (3'd1 + {2'b0, u_dut.u_ydrasil_issue_stage.selected_valid1}) :
         3'd0);
    wire [2:0] perf_complete_slots =
        3'($countones(u_dut.u_ctrl.producer_complete_mask));
    wire [1:0] perf_retire_slots =
        {1'b0, u_dut.commit_pkt.valid} +
        {1'b0, u_dut.commit_pkt1.valid};
    wire [3:0] perf_candidate_mask = {
        |u_dut.u_ydrasil_issue_stage.p1_serial_select_local,
        u_dut.u_ydrasil_issue_stage.p1_select_valid,
        u_dut.u_ydrasil_issue_stage.p0_select_valid,
        u_dut.u_ydrasil_issue_stage.alu_select0_valid};
    wire perf_head_issued_now =
        (u_dut.u_ydrasil_issue_stage.lane_a_accept &&
         (u_dut.u_ydrasil_issue_stage.lane_a_uop.dst.rob_tag ==
          u_dut.u_ctrl.queue_head_id)) ||
        (u_dut.u_ydrasil_issue_stage.lane_b_accept &&
         (u_dut.u_ydrasil_issue_stage.lane_b_uop.dst.rob_tag ==
          u_dut.u_ctrl.queue_head_id));
    wire perf_head_selected_now =
        u_dut.u_ydrasil_issue_stage.select_buf_push &&
        (((u_dut.u_ydrasil_issue_stage.selected_valid0) &&
          (u_dut.u_ydrasil_issue_stage.selected_uop0.dst.rob_tag ==
           u_dut.u_ctrl.queue_head_id)) ||
         ((u_dut.u_ydrasil_issue_stage.selected_valid1) &&
          (u_dut.u_ydrasil_issue_stage.selected_uop1.dst.rob_tag ==
           u_dut.u_ctrl.queue_head_id)));
    wire perf_head_in_select_cell =
        u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
        ((u_dut.u_ydrasil_issue_stage.select_head_uop0_q.dst.rob_tag ==
          u_dut.u_ctrl.queue_head_id) ||
         (u_dut.u_ydrasil_issue_stage.select_head_pair_q &&
          (u_dut.u_ydrasil_issue_stage.select_head_uop1_q.dst.rob_tag ==
           u_dut.u_ctrl.queue_head_id)));
    reg perf_head_rs_found;
    reg perf_head_rs_dependency;
    reg perf_head_rs_order;
    reg perf_head_rs_resource;
    reg perf_head_rs_ready;
    integer perf_head_rs_idx;
    always_comb begin
        perf_head_rs_found = 1'b0;
        perf_head_rs_dependency = 1'b0;
        perf_head_rs_order = 1'b0;
        perf_head_rs_resource = 1'b0;
        perf_head_rs_ready = 1'b0;
        for (perf_head_rs_idx = 0; perf_head_rs_idx < 12;
             perf_head_rs_idx = perf_head_rs_idx + 1) begin
            if (u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                    perf_head_rs_idx] &&
                (u_dut.u_ydrasil_issue_stage.issue_window_q[
                    perf_head_rs_idx].dst.rob_tag ==
                 u_dut.u_ctrl.queue_head_id)) begin
                perf_head_rs_found = 1'b1;
                if (!u_dut.u_ydrasil_issue_stage.
                        issue_src0_ready_for_select[perf_head_rs_idx] ||
                    (!u_dut.u_ydrasil_issue_stage.
                         issue_src1_ready_for_select[perf_head_rs_idx] &&
                     !u_dut.u_ydrasil_issue_stage.issue_store_q[
                         perf_head_rs_idx])) begin
                    perf_head_rs_dependency = 1'b1;
                end else if (u_dut.u_ydrasil_issue_stage.issue_order_blocked[
                                 perf_head_rs_idx]) begin
                    perf_head_rs_order = 1'b1;
                end else if (((perf_head_rs_idx >= 4) &&
                              (perf_head_rs_idx <= 7) &&
                              u_dut.u_ydrasil_issue_stage.issue_memory_q[
                                  perf_head_rs_idx] &&
                              ({1'b0, u_dut.lsu_issue_credit} <=
                               {1'b0, u_dut.u_ydrasil_issue_stage.
                                   lsu_select_reserved_q})) ||
                             ((perf_head_rs_idx >= 8) &&
                              u_dut.u_ydrasil_issue_stage.issue_divrem_q[
                                  perf_head_rs_idx] &&
                              (!u_dut.u_ydrasil_issue_stage.
                                   mdu_div_available_q ||
                               u_dut.u_ydrasil_issue_stage.
                                   div_select_reserved_q)) ||
                             ((perf_head_rs_idx >= 8) &&
                              u_dut.u_ydrasil_issue_stage.issue_serial_q[
                                  perf_head_rs_idx] &&
                              ((u_dut.u_ydrasil_issue_stage.issue_window_q[
                                    perf_head_rs_idx].dst.rob_tag !=
                                u_dut.u_ydrasil_issue_stage.
                                    rob_head_select_q) ||
                               !u_dut.u_ydrasil_issue_stage.
                                   lsu_idle_select_q))) begin
                    perf_head_rs_resource = 1'b1;
                end else begin
                    perf_head_rs_ready = 1'b1;
                end
            end
        end
    end
    reg perf_rs_dependency_wait;
    reg perf_rs_order_wait;
    reg perf_rs_resource_wait;
    reg perf_rs_lsu_credit_wait;
    reg perf_rs_div_credit_wait;
    reg perf_rs_serial_gate_wait;
    reg [3:0] perf_rs_dependency_entries_now;
    reg [3:0] perf_rs_order_entries_now;
    reg [3:0] perf_rs_resource_entries_now;
    reg [3:0] perf_rs_ready_entries_now;
    reg perf_rs_dep_src0_wait_now;
    reg perf_rs_dep_src1_wait_now;
    reg perf_rs_dep_both_src_now;
    reg perf_rs_dep_load_now;
    reg perf_rs_dep_store_now;
    reg perf_rs_dep_mul_now;
    reg perf_rs_dep_branch_now;
    reg perf_rs_dep_both_wakeup_now;
    reg perf_rs_dep_mixed_wakeup_now;
    reg perf_rs_dep_src0_completion_now;
    reg perf_rs_dep_src1_completion_now;
    reg perf_rs_dep_src0_alloc_now;
    reg perf_rs_dep_src1_alloc_now;
    localparam logic [4:0] PERF_DEP_BLOCKER_ALU = 5'b00001;
    localparam logic [4:0] PERF_DEP_BLOCKER_LOAD = 5'b00010;
    localparam logic [4:0] PERF_DEP_BLOCKER_MDU = 5'b00100;
    localparam logic [4:0] PERF_DEP_BLOCKER_OTHER = 5'b01000;
    localparam logic [4:0] PERF_DEP_BLOCKER_STALE = 5'b10000;
    localparam logic [2:0] PERF_DBG_PRODUCER_ALU = 3'd1;
    localparam logic [2:0] PERF_DBG_PRODUCER_LOAD = 3'd2;
    localparam logic [2:0] PERF_DBG_PRODUCER_MDU = 3'd3;
    reg [4:0] perf_rs_dep_blocker_mask_now;
    reg [4:0] perf_dep_blocker_operand_count_now [0:4];
    reg [4:0] perf_dep_blocker_kind_now;
    integer perf_dep_blocker_idx;
    integer perf_rs_reason_idx;

    function automatic logic [4:0] perf_dep_blocker_kind(
        input logic tag_valid,
        input producer_id_t producer_tag
    );
        producer_slot_t producer_slot;
        begin
            producer_slot = producer_tag[PRODUCER_SLOT_WIDTH-1:0];
            if (!tag_valid ||
                !u_dut.u_ctrl.producer_valid_q[producer_slot] ||
                (u_dut.u_ctrl.producer_epoch_q[producer_slot] !=
                 producer_tag[PRODUCER_ID_WIDTH-1])) begin
                perf_dep_blocker_kind = PERF_DEP_BLOCKER_STALE;
            end else begin
                case (u_dut.u_ctrl.dbg_producer_kind_q[producer_slot])
                    PERF_DBG_PRODUCER_ALU:
                        perf_dep_blocker_kind = PERF_DEP_BLOCKER_ALU;
                    PERF_DBG_PRODUCER_LOAD:
                        perf_dep_blocker_kind = PERF_DEP_BLOCKER_LOAD;
                    PERF_DBG_PRODUCER_MDU:
                        perf_dep_blocker_kind = PERF_DEP_BLOCKER_MDU;
                    default:
                        perf_dep_blocker_kind = PERF_DEP_BLOCKER_OTHER;
                endcase
            end
        end
    endfunction

    always_comb begin
        perf_rs_dependency_wait = 1'b0;
        perf_rs_order_wait = 1'b0;
        perf_rs_resource_wait = 1'b0;
        perf_rs_lsu_credit_wait = 1'b0;
        perf_rs_div_credit_wait = 1'b0;
        perf_rs_serial_gate_wait = 1'b0;
        perf_rs_dependency_entries_now = '0;
        perf_rs_order_entries_now = '0;
        perf_rs_resource_entries_now = '0;
        perf_rs_ready_entries_now = '0;
        perf_rs_dep_src0_wait_now = 1'b0;
        perf_rs_dep_src1_wait_now = 1'b0;
        perf_rs_dep_both_src_now = 1'b0;
        perf_rs_dep_load_now = 1'b0;
        perf_rs_dep_store_now = 1'b0;
        perf_rs_dep_mul_now = 1'b0;
        perf_rs_dep_branch_now = 1'b0;
        perf_rs_dep_both_wakeup_now = 1'b0;
        perf_rs_dep_mixed_wakeup_now = 1'b0;
        perf_rs_dep_src0_completion_now = 1'b0;
        perf_rs_dep_src1_completion_now = 1'b0;
        perf_rs_dep_src0_alloc_now = 1'b0;
        perf_rs_dep_src1_alloc_now = 1'b0;
        perf_rs_dep_blocker_mask_now = '0;
        perf_dep_blocker_kind_now = '0;
        for (perf_dep_blocker_idx = 0; perf_dep_blocker_idx < 5;
             perf_dep_blocker_idx = perf_dep_blocker_idx + 1)
            perf_dep_blocker_operand_count_now[perf_dep_blocker_idx] = '0;
        for (perf_rs_reason_idx = 0; perf_rs_reason_idx < 12;
             perf_rs_reason_idx = perf_rs_reason_idx + 1) begin
            if (u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                    perf_rs_reason_idx]) begin
                if (!u_dut.u_ydrasil_issue_stage.issue_src0_ready_for_select[
                        perf_rs_reason_idx] ||
                    (!u_dut.u_ydrasil_issue_stage.issue_src1_ready_for_select[
                         perf_rs_reason_idx] &&
                     !u_dut.u_ydrasil_issue_stage.issue_store_q[
                         perf_rs_reason_idx])) begin
                    perf_rs_dependency_wait = 1'b1;
                    perf_rs_dependency_entries_now =
                        perf_rs_dependency_entries_now + 1'b1;
                    if (!u_dut.u_ydrasil_issue_stage.issue_src0_ready_for_select[
                            perf_rs_reason_idx]) begin
                        perf_rs_dep_src0_wait_now = 1'b1;
                        perf_dep_blocker_kind_now = perf_dep_blocker_kind(
                            u_dut.u_ydrasil_issue_stage.issue_window_q[
                                perf_rs_reason_idx].src0.tag_valid,
                            u_dut.u_ydrasil_issue_stage.issue_window_q[
                                perf_rs_reason_idx].src0.producer_tag);
                        perf_rs_dep_blocker_mask_now =
                            perf_rs_dep_blocker_mask_now |
                            perf_dep_blocker_kind_now;
                        for (perf_dep_blocker_idx = 0;
                             perf_dep_blocker_idx < 5;
                             perf_dep_blocker_idx = perf_dep_blocker_idx + 1)
                            if (perf_dep_blocker_kind_now[perf_dep_blocker_idx])
                                perf_dep_blocker_operand_count_now[
                                    perf_dep_blocker_idx] =
                                    perf_dep_blocker_operand_count_now[
                                        perf_dep_blocker_idx] + 1'b1;
                    end
                    if (!u_dut.u_ydrasil_issue_stage.issue_src1_ready_for_select[
                            perf_rs_reason_idx] &&
                        !u_dut.u_ydrasil_issue_stage.issue_store_q[
                            perf_rs_reason_idx]) begin
                        perf_rs_dep_src1_wait_now = 1'b1;
                        perf_dep_blocker_kind_now = perf_dep_blocker_kind(
                            u_dut.u_ydrasil_issue_stage.issue_window_q[
                                perf_rs_reason_idx].src1.tag_valid,
                            u_dut.u_ydrasil_issue_stage.issue_window_q[
                                perf_rs_reason_idx].src1.producer_tag);
                        perf_rs_dep_blocker_mask_now =
                            perf_rs_dep_blocker_mask_now |
                            perf_dep_blocker_kind_now;
                        for (perf_dep_blocker_idx = 0;
                             perf_dep_blocker_idx < 5;
                             perf_dep_blocker_idx = perf_dep_blocker_idx + 1)
                            if (perf_dep_blocker_kind_now[perf_dep_blocker_idx])
                                perf_dep_blocker_operand_count_now[
                                    perf_dep_blocker_idx] =
                                    perf_dep_blocker_operand_count_now[
                                        perf_dep_blocker_idx] + 1'b1;
                    end
                    if (u_dut.u_ydrasil_issue_stage.issue_memory_q[
                            perf_rs_reason_idx])
                        if (u_dut.u_ydrasil_issue_stage.issue_store_q[
                                perf_rs_reason_idx])
                            perf_rs_dep_store_now = 1'b1;
                        else
                            perf_rs_dep_load_now = 1'b1;
                    else if (u_dut.u_ydrasil_issue_stage.issue_mul_q[
                                 perf_rs_reason_idx])
                        perf_rs_dep_mul_now = 1'b1;
                    else if (u_dut.u_ydrasil_issue_stage.issue_branch_q[
                                 perf_rs_reason_idx])
                        perf_rs_dep_branch_now = 1'b1;

                    // Use the stored ready bits for this projection.  The
                    // *_ready_for_select wires already include the current
                    // wakeup, so looking only at them would hide the exact
                    // wakeup that missed the Select window.
                    if (!u_dut.u_ydrasil_issue_stage.
                            issue_window_src0_ready_q[perf_rs_reason_idx] &&
                        u_dut.u_ydrasil_issue_stage.
                            issue_src0_completion_wakeup[perf_rs_reason_idx])
                        perf_rs_dep_src0_completion_now = 1'b1;
                    if (!u_dut.u_ydrasil_issue_stage.
                            issue_window_src1_ready_q[perf_rs_reason_idx] &&
                        !u_dut.u_ydrasil_issue_stage.issue_store_q[
                            perf_rs_reason_idx] &&
                        u_dut.u_ydrasil_issue_stage.
                            issue_src1_completion_wakeup[perf_rs_reason_idx])
                        perf_rs_dep_src1_completion_now = 1'b1;
                    if (!u_dut.u_ydrasil_issue_stage.
                            issue_window_src0_ready_q[perf_rs_reason_idx] &&
                        u_dut.u_ydrasil_issue_stage.
                            issue_src0_alloc_wakeup[perf_rs_reason_idx])
                        perf_rs_dep_src0_alloc_now = 1'b1;
                    if (!u_dut.u_ydrasil_issue_stage.
                            issue_window_src1_ready_q[perf_rs_reason_idx] &&
                        !u_dut.u_ydrasil_issue_stage.issue_store_q[
                            perf_rs_reason_idx] &&
                        u_dut.u_ydrasil_issue_stage.
                            issue_src1_alloc_wakeup[perf_rs_reason_idx])
                        perf_rs_dep_src1_alloc_now = 1'b1;
                    if ((!u_dut.u_ydrasil_issue_stage.
                             issue_window_src0_ready_q[perf_rs_reason_idx] &&
                         u_dut.u_ydrasil_issue_stage.
                             issue_src0_completion_wakeup[perf_rs_reason_idx]) &&
                        (!u_dut.u_ydrasil_issue_stage.
                             issue_window_src1_ready_q[perf_rs_reason_idx] &&
                         !u_dut.u_ydrasil_issue_stage.issue_store_q[
                             perf_rs_reason_idx] &&
                         u_dut.u_ydrasil_issue_stage.
                             issue_src1_completion_wakeup[perf_rs_reason_idx]))
                        perf_rs_dep_both_wakeup_now = 1'b1;
                    if (((!u_dut.u_ydrasil_issue_stage.
                              issue_window_src0_ready_q[perf_rs_reason_idx] &&
                          u_dut.u_ydrasil_issue_stage.
                              issue_src0_completion_wakeup[perf_rs_reason_idx]) &&
                         (!u_dut.u_ydrasil_issue_stage.
                              issue_window_src1_ready_q[perf_rs_reason_idx] &&
                          !u_dut.u_ydrasil_issue_stage.issue_store_q[
                              perf_rs_reason_idx] &&
                          u_dut.u_ydrasil_issue_stage.
                              issue_src1_alloc_wakeup[perf_rs_reason_idx])) ||
                        ((!u_dut.u_ydrasil_issue_stage.
                              issue_window_src0_ready_q[perf_rs_reason_idx] &&
                          u_dut.u_ydrasil_issue_stage.
                              issue_src0_alloc_wakeup[perf_rs_reason_idx]) &&
                         (!u_dut.u_ydrasil_issue_stage.
                              issue_window_src1_ready_q[perf_rs_reason_idx] &&
                          !u_dut.u_ydrasil_issue_stage.issue_store_q[
                              perf_rs_reason_idx] &&
                          u_dut.u_ydrasil_issue_stage.
                              issue_src1_completion_wakeup[perf_rs_reason_idx])))
                        perf_rs_dep_mixed_wakeup_now = 1'b1;
                end else if (u_dut.u_ydrasil_issue_stage.issue_order_blocked[
                                 perf_rs_reason_idx]) begin
                    perf_rs_order_wait = 1'b1;
                    perf_rs_order_entries_now =
                        perf_rs_order_entries_now + 1'b1;
                end else if ((perf_rs_reason_idx >= 4) &&
                             (perf_rs_reason_idx <= 7) &&
                             u_dut.u_ydrasil_issue_stage.issue_memory_q[
                                 perf_rs_reason_idx] &&
                             ({1'b0, u_dut.lsu_issue_credit} <=
                              ({1'b0, u_dut.u_ydrasil_issue_stage.
                                  lsu_select_reserved_q} +
                               u_dut.u_ydrasil_issue_stage.agu_in_valid_q))) begin
                    perf_rs_resource_wait = 1'b1;
                    perf_rs_lsu_credit_wait = 1'b1;
                    perf_rs_resource_entries_now =
                        perf_rs_resource_entries_now + 1'b1;
                end else if ((perf_rs_reason_idx >= 8) &&
                             u_dut.u_ydrasil_issue_stage.issue_divrem_q[
                                 perf_rs_reason_idx] &&
                             (!u_dut.u_ydrasil_issue_stage.mdu_div_available_q ||
                              u_dut.u_ydrasil_issue_stage.
                                  div_select_reserved_q)) begin
                    perf_rs_resource_wait = 1'b1;
                    perf_rs_div_credit_wait = 1'b1;
                    perf_rs_resource_entries_now =
                        perf_rs_resource_entries_now + 1'b1;
                end else if ((perf_rs_reason_idx >= 8) &&
                             u_dut.u_ydrasil_issue_stage.issue_serial_q[
                                 perf_rs_reason_idx] &&
                             ((u_dut.u_ydrasil_issue_stage.issue_window_q[
                                   perf_rs_reason_idx].dst.rob_tag !=
                               u_dut.u_ydrasil_issue_stage.rob_head_select_q) ||
                              !u_dut.u_ydrasil_issue_stage.lsu_idle_select_q ||
                              perf_serial_pending)) begin
                    perf_rs_resource_wait = 1'b1;
                    perf_rs_serial_gate_wait = 1'b1;
                    perf_rs_resource_entries_now =
                        perf_rs_resource_entries_now + 1'b1;
                end else begin
                    perf_rs_ready_entries_now =
                        perf_rs_ready_entries_now + 1'b1;
                end
            end
        end
        perf_rs_dep_both_src_now = perf_rs_dep_src0_wait_now &&
            perf_rs_dep_src1_wait_now;
    end
    reg perf_p0_dependency_wait;
    reg perf_p0_order_wait;
    reg perf_p0_resource_wait;
    reg perf_p0_ready_wait;
    integer perf_p0_reason_idx;
    // P0 is the memory bank.  Apply the same priority as the RTL candidate
    // predicate so a full-bank loss has one and only one root cause.
    always_comb begin
        perf_p0_dependency_wait = 1'b0;
        perf_p0_order_wait = 1'b0;
        perf_p0_resource_wait = 1'b0;
        perf_p0_ready_wait = 1'b0;
        for (perf_p0_reason_idx = 4; perf_p0_reason_idx < 8;
             perf_p0_reason_idx = perf_p0_reason_idx + 1) begin
            if (u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                    perf_p0_reason_idx]) begin
                if (!u_dut.u_ydrasil_issue_stage.
                        issue_src0_ready_for_select[perf_p0_reason_idx] ||
                    (!u_dut.u_ydrasil_issue_stage.
                         issue_src1_ready_for_select[perf_p0_reason_idx] &&
                     !u_dut.u_ydrasil_issue_stage.issue_store_q[
                         perf_p0_reason_idx]))
                    perf_p0_dependency_wait = 1'b1;
                else if (u_dut.u_ydrasil_issue_stage.issue_order_blocked[
                             perf_p0_reason_idx])
                    perf_p0_order_wait = 1'b1;
                else if (u_dut.u_ydrasil_issue_stage.issue_memory_q[
                             perf_p0_reason_idx] &&
                         ({1'b0, u_dut.lsu_issue_credit} <=
                          {1'b0, u_dut.u_ydrasil_issue_stage.
                              lsu_select_reserved_q}))
                    perf_p0_resource_wait = 1'b1;
                else
                    perf_p0_ready_wait = 1'b1;
            end
        end
    end
    wire perf_rs_bank_full_now =
        u_dut.u_ydrasil_issue_stage.decode_valid_i &&
        u_dut.u_ydrasil_issue_stage.dispatch_ready_i &&
        !u_dut.u_ydrasil_issue_stage.dispatch_slots_available;
    wire perf_rs_pair_bank_limit_now =
        u_dut.u_ydrasil_issue_stage.decode_valid1_i &&
        u_dut.u_ydrasil_issue_stage.dispatch_ready_i &&
        u_dut.u_ydrasil_issue_stage.dispatch_slots_available &&
        !u_dut.u_ydrasil_issue_stage.dispatch_pair_slots_available;
    wire perf_rob_full_now =
        u_dut.u_ydrasil_issue_stage.decode_valid_i &&
        !u_dut.u_ydrasil_issue_stage.dispatch_ready_i;
    // Raw Select opportunity.  The old SELECT_WIDTH predicate compared the
    // number of ready entries with the number already admitted in the same
    // cycle, which made every idle Select cycle look width-limited.  These
    // signals use the actual bank candidate vectors and the actual bundle
    // crossing the Select/Operand boundary.
    wire [2:0] perf_raw_alu_candidate_entries_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.alu_candidate_local));
    wire perf_raw_p0_candidate_now =
        |u_dut.u_ydrasil_issue_stage.p0_candidate_local;
    wire perf_raw_p1_candidate_now =
        |u_dut.u_ydrasil_issue_stage.p1_candidate_local;
    wire perf_raw_serial_candidate_now =
        |u_dut.u_ydrasil_issue_stage.p1_serial_candidate_local;
    wire [2:0] perf_raw_bank_supply_now =
        (perf_raw_alu_candidate_entries_now > 3'd2 ? 3'd2 :
         perf_raw_alu_candidate_entries_now) +
        {2'b0, perf_raw_p0_candidate_now} +
        {2'b0, perf_raw_p1_candidate_now};
    wire [1:0] perf_select_ideal_width_now =
        perf_raw_serial_candidate_now ? 2'd1 :
        (perf_raw_bank_supply_now >= 3'd2 ? 2'd2 :
         perf_raw_bank_supply_now[1:0]);
    wire [1:0] perf_select_actual_width_now =
        u_dut.u_ydrasil_issue_stage.select_buf_push ?
        ({1'b0, u_dut.u_ydrasil_issue_stage.selected_valid0} +
         {1'b0, u_dut.u_ydrasil_issue_stage.selected_valid1}) : 2'd0;
    wire [31:0] perf_select_width_gap_now =
        (perf_select_ideal_width_now > perf_select_actual_width_now) ?
        ({{30{1'b0}}, perf_select_ideal_width_now} -
         {{30{1'b0}}, perf_select_actual_width_now}) : 32'd0;
    wire perf_select_gap_recovery_now =
        (perf_select_width_gap_now != 0) &&
        (u_dut.u_ydrasil_issue_stage.branch_recovery_i ||
         u_dut.u_ydrasil_issue_stage.recovery_pending_q);
    wire perf_select_gap_no_push_now =
        (perf_select_width_gap_now != 0) && !perf_select_gap_recovery_now &&
        !u_dut.u_ydrasil_issue_stage.select_buf_push;
    wire [3:0] perf_select_raw_shape_now = {
        perf_raw_serial_candidate_now, perf_raw_p1_candidate_now,
        perf_raw_p0_candidate_now, (perf_raw_alu_candidate_entries_now != 0)};
    wire [2:0] perf_select_drop_alu_entries_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.alu_candidate_local &
                      ~u_dut.u_ydrasil_issue_stage.issue_select_mask[3:0]));
    wire [2:0] perf_select_drop_p0_entries_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.p0_candidate_local &
                      ~u_dut.u_ydrasil_issue_stage.issue_select_mask[7:4]));
    wire [2:0] perf_select_drop_p1_entries_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.p1_candidate_local &
                      ~u_dut.u_ydrasil_issue_stage.issue_select_mask[11:8]));
    wire perf_select_width_limit_now =
        !u_dut.u_ydrasil_issue_stage.branch_recovery_i &&
        !u_dut.u_ydrasil_issue_stage.recovery_pending_q &&
        (perf_select_ideal_width_now > perf_select_actual_width_now);
    wire perf_operand_dependency_miss_now =
        u_dut.issue_dependency_wait || u_dut.issue_dependency_wait1;
    wire perf_rob_head_wait_now =
        (u_dut.u_ctrl.queue_count_q != '0) &&
        !u_dut.commit_pkt.valid && !u_dut.commit_pkt1.valid &&
        !u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.queue_head_q];
    wire perf_frontend_empty_now = !u_dut.if_id_valid;
    wire perf_lsu_wait_now = perf_rs_lsu_credit_wait ||
        perf_rs_serial_gate_wait ||
        (u_dut.u_ydrasil_load_store_unit.queue_count_q == 2'd2);
    wire perf_fu_wait_now = u_dut.ex_mul_stall;
    // Loss mask bits (LSB first): BANK, ROB_CAP, DEP, ORDER, RESOURCE,
    // SELECT, OPERAND, RECOVERY, FRONTEND, ROB_HEAD, LSU, FU.
    wire [PERF_LOSS_COUPLING_BITS-1:0] perf_loss_coupling_mask_now = {
        perf_fu_wait_now, perf_lsu_wait_now, perf_rob_head_wait_now,
        perf_frontend_empty_now,
        (u_dut.ex_pc_redirect ||
         u_dut.u_ydrasil_issue_stage.recovery_pending_q),
        perf_operand_dependency_miss_now,
        perf_select_width_limit_now,
        (perf_rs_resource_wait || perf_rs_pair_bank_limit_now),
        perf_rs_order_wait, perf_rs_dependency_wait,
        perf_rob_full_now,
        (perf_bank_full_any_now || perf_rs_bank_full_now)
    };
    // Primary cycle-cause partition used by the slot accounting below.  The
    // ordering is intentional: a cycle with several asserted controls is
    // charged once to MULTI_CAUSE, while the remaining arms are exclusive.
    wire perf_cycle_flush = u_dut.flush_ex;
    wire perf_cycle_multi_cause =
        !perf_cycle_flush &&
        ((u_dut.u_ydrasil_commit_trace.dependency_wait &
         (u_dut.u_ydrasil_commit_trace.lsu_struct_stall |
          u_dut.u_ctrl.producer_full_stall |
          u_dut.u_ydrasil_commit_trace.wb_backpressure |
          u_dut.u_ydrasil_commit_trace.clint_stall)) |
        (u_dut.u_ydrasil_commit_trace.lsu_struct_stall &
         (u_dut.u_ctrl.producer_full_stall |
          u_dut.u_ydrasil_commit_trace.wb_backpressure |
          u_dut.u_ydrasil_commit_trace.clint_stall)) |
        (u_dut.u_ctrl.producer_full_stall &
         (u_dut.u_ydrasil_commit_trace.wb_backpressure |
          u_dut.u_ydrasil_commit_trace.clint_stall)) |
        (u_dut.u_ydrasil_commit_trace.wb_backpressure &
         u_dut.u_ydrasil_commit_trace.clint_stall));
    wire perf_cycle_mul_hold = !perf_cycle_flush && u_dut.ex_mul_stall;
    wire perf_cycle_dependency =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause &&
        u_dut.u_ydrasil_commit_trace.dependency_wait;
    wire perf_cycle_lsu_struct =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        u_dut.u_ydrasil_commit_trace.lsu_struct_stall;
    wire perf_cycle_producer_full =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && u_dut.u_ctrl.producer_full_stall;
    wire perf_cycle_wb =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && !perf_cycle_producer_full &&
        u_dut.u_ydrasil_commit_trace.wb_backpressure;
    wire perf_cycle_clint =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && !perf_cycle_producer_full &&
        !perf_cycle_wb && u_dut.u_ydrasil_commit_trace.clint_stall;
    wire perf_cycle_lsu_serialize =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && !perf_cycle_producer_full &&
        !perf_cycle_wb && !perf_cycle_clint && u_dut.issue_serialize_stall;
    wire perf_cycle_no_if_valid =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && !perf_cycle_producer_full &&
        !perf_cycle_wb && !perf_cycle_clint &&
        !perf_cycle_lsu_serialize && !u_dut.if_id_valid;
    wire perf_cycle_issue =
        !perf_cycle_flush && !perf_cycle_mul_hold &&
        !perf_cycle_multi_cause && !perf_cycle_dependency &&
        !perf_cycle_lsu_struct && !perf_cycle_producer_full &&
        !perf_cycle_wb && !perf_cycle_clint &&
        !perf_cycle_lsu_serialize && !perf_cycle_no_if_valid &&
        u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
        u_dut.u_ydrasil_issue_stage.id_advance;
    wire perf_cycle_other =
        !(perf_cycle_flush | perf_cycle_mul_hold | perf_cycle_multi_cause |
          perf_cycle_dependency | perf_cycle_lsu_struct |
          perf_cycle_producer_full | perf_cycle_wb | perf_cycle_clint |
          perf_cycle_lsu_serialize | perf_cycle_no_if_valid | perf_cycle_issue);
    wire [11:0] perf_cycle_cause_onehot = {
        perf_cycle_other, perf_cycle_issue, perf_cycle_no_if_valid,
        perf_cycle_lsu_serialize, perf_cycle_clint, perf_cycle_wb,
        perf_cycle_producer_full, perf_cycle_lsu_struct,
        perf_cycle_dependency, perf_cycle_multi_cause, perf_cycle_mul_hold,
        perf_cycle_flush};
    // Source-side reason snapshot.  It is registered below and consumed one
    // cycle later when the corresponding EX slot is observed.  This keeps
    // front-end/RS attribution on the same transaction as the empty EX slot.
    always_comb begin
        perf_src_kind0_d = PERF_SRC_OTHER;
        perf_src_kind1_d = PERF_SRC_OTHER;
        if (u_dut.u_ydrasil_issue_stage.flush_id_i ||
            u_dut.u_ydrasil_issue_stage.trap_flush_i ||
            u_dut.u_ydrasil_issue_stage.branch_recovery_i ||
            u_dut.u_ydrasil_issue_stage.recovery_pending_q) begin
            perf_src_kind0_d = PERF_SRC_RECOVERY;
            perf_src_kind1_d = PERF_SRC_RECOVERY;
        end else if (!u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid) begin
            if (u_dut.u_ydrasil_issue_stage.select_buf_push) begin
                perf_src_kind0_d = PERF_SRC_SELECT_REFILL;
                perf_src_kind1_d = PERF_SRC_SELECT_REFILL;
            end else if (|u_dut.u_ydrasil_issue_stage.issue_window_valid_q) begin
                if (perf_rs_dependency_wait) begin
                    perf_src_kind0_d = PERF_SRC_RS_DEPENDENCY;
                    perf_src_kind1_d = PERF_SRC_RS_DEPENDENCY;
                end else if (perf_rs_order_wait) begin
                    perf_src_kind0_d = PERF_SRC_RS_ORDER;
                    perf_src_kind1_d = PERF_SRC_RS_ORDER;
                end else if (perf_rs_resource_wait) begin
                    perf_src_kind0_d = PERF_SRC_RS_RESOURCE;
                    perf_src_kind1_d = PERF_SRC_RS_RESOURCE;
                end else begin
                    perf_src_kind0_d = PERF_SRC_RS_NO_CANDIDATE;
                    perf_src_kind1_d = PERF_SRC_RS_NO_CANDIDATE;
                end
            end else if (!u_dut.if_id_valid) begin
                perf_src_kind0_d = PERF_SRC_FRONTEND;
                perf_src_kind1_d = PERF_SRC_FRONTEND;
            end else begin
                perf_src_kind0_d = PERF_SRC_RS_EMPTY;
                perf_src_kind1_d = PERF_SRC_RS_EMPTY;
            end
        end else begin
            if (u_dut.u_ydrasil_issue_stage.lane_a_fu_valid)
                perf_src_kind0_d = PERF_SRC_LAUNCH;
            else if (u_dut.u_ydrasil_issue_stage.lane_a_accept &&
                     u_dut.u_ydrasil_issue_stage.issue_pkt_i.fence_i)
                perf_src_kind0_d = PERF_SRC_FENCE;
            else if (u_dut.u_ydrasil_issue_stage.lane_b_accept)
                perf_src_kind0_d = PERF_SRC_B_ONLY;
            else if (u_dut.u_ydrasil_issue_stage.lane_a_accept)
                perf_src_kind0_d = PERF_SRC_SINGLE_HEAD;
            if (u_dut.u_ydrasil_issue_stage.lane_b_accept)
                perf_src_kind1_d = PERF_SRC_LAUNCH;
            else if (u_dut.u_ydrasil_issue_stage.lane_a_accept)
                perf_src_kind1_d = PERF_SRC_SINGLE_HEAD;
        end
    end

    // Snapshot the producer of each selected Operand bundle.  The snapshot is
    // consumed after the Select/Operand register boundary, so the loss leaves
    // below describe the bundle that actually became a singleton or refill,
    // rather than a live candidate signal from a different cycle.
    always_comb begin
        perf_select_reason_d = PERF_SEL_REASON_OTHER;
        if (|u_dut.u_ydrasil_issue_stage.p1_serial_select_local)
            perf_select_reason_d = PERF_SEL_REASON_SERIAL;
        else if (u_dut.u_ydrasil_issue_stage.selected_valid1)
            perf_select_reason_d = PERF_SEL_REASON_PAIR;
        else if (|u_dut.u_ydrasil_issue_stage.selected0_mask[7:4])
            perf_select_reason_d = PERF_SEL_REASON_P0;
        else if (|u_dut.u_ydrasil_issue_stage.selected0_mask[11:8])
            perf_select_reason_d = PERF_SEL_REASON_P1;
        else if (|u_dut.u_ydrasil_issue_stage.selected0_mask[3:0])
            perf_select_reason_d = PERF_SEL_REASON_ALU;
    end
    function automatic [1:0] perf_empty_kind_slots(input [4:0] kind);
        perf_empty_kind_slots =
            {1'b0, !u_dut.ex_hzd_pkt.valid && (perf_src_kind0_q == kind)} +
            {1'b0, !u_dut.ex_hzd_pkt1.valid && (perf_src_kind1_q == kind)};
    endfunction
    function automatic [1:0] perf_empty_unmapped_slots;
        perf_empty_unmapped_slots =
            {1'b0, !u_dut.ex_hzd_pkt.valid &&
                !((perf_src_kind0_q == PERF_SRC_RESET) ||
                  (perf_src_kind0_q == PERF_SRC_RECOVERY) ||
                  (perf_src_kind0_q == PERF_SRC_FENCE) ||
                  (perf_src_kind0_q == PERF_SRC_B_ONLY) ||
                  (perf_src_kind0_q == PERF_SRC_SINGLE_HEAD) ||
                  (perf_src_kind0_q == PERF_SRC_SELECT_REFILL) ||
                  (perf_src_kind0_q == PERF_SRC_RS_DEPENDENCY) ||
                  (perf_src_kind0_q == PERF_SRC_RS_ORDER) ||
                  (perf_src_kind0_q == PERF_SRC_RS_RESOURCE) ||
                  (perf_src_kind0_q == PERF_SRC_RS_NO_CANDIDATE) ||
                  (perf_src_kind0_q == PERF_SRC_RS_EMPTY) ||
                  (perf_src_kind0_q == PERF_SRC_FRONTEND) ||
                  (perf_src_kind0_q == PERF_SRC_OTHER) ||
                  (perf_src_kind0_q == PERF_SRC_LAUNCH))} +
            {1'b0, !u_dut.ex_hzd_pkt1.valid &&
                !((perf_src_kind1_q == PERF_SRC_RESET) ||
                  (perf_src_kind1_q == PERF_SRC_RECOVERY) ||
                  (perf_src_kind1_q == PERF_SRC_FENCE) ||
                  (perf_src_kind1_q == PERF_SRC_B_ONLY) ||
                  (perf_src_kind1_q == PERF_SRC_SINGLE_HEAD) ||
                  (perf_src_kind1_q == PERF_SRC_SELECT_REFILL) ||
                  (perf_src_kind1_q == PERF_SRC_RS_DEPENDENCY) ||
                  (perf_src_kind1_q == PERF_SRC_RS_ORDER) ||
                  (perf_src_kind1_q == PERF_SRC_RS_RESOURCE) ||
                  (perf_src_kind1_q == PERF_SRC_RS_NO_CANDIDATE) ||
                  (perf_src_kind1_q == PERF_SRC_RS_EMPTY) ||
                  (perf_src_kind1_q == PERF_SRC_FRONTEND) ||
                  (perf_src_kind1_q == PERF_SRC_OTHER) ||
                  (perf_src_kind1_q == PERF_SRC_LAUNCH))};
    endfunction
    wire [1:0] perf_empty_slots_now =
        {1'b0, !u_dut.ex_hzd_pkt.valid} +
        {1'b0, !u_dut.ex_hzd_pkt1.valid};
    wire [1:0] perf_empty_classified_slots_now =
        perf_empty_kind_slots(PERF_SRC_RESET) +
        perf_empty_kind_slots(PERF_SRC_RECOVERY) +
        perf_empty_kind_slots(PERF_SRC_FENCE) +
        perf_empty_kind_slots(PERF_SRC_B_ONLY) +
        perf_empty_kind_slots(PERF_SRC_SINGLE_HEAD) +
        perf_empty_kind_slots(PERF_SRC_SELECT_REFILL) +
        perf_empty_kind_slots(PERF_SRC_RS_DEPENDENCY) +
        perf_empty_kind_slots(PERF_SRC_RS_ORDER) +
        perf_empty_kind_slots(PERF_SRC_RS_RESOURCE) +
        perf_empty_kind_slots(PERF_SRC_RS_NO_CANDIDATE) +
        perf_empty_kind_slots(PERF_SRC_RS_EMPTY) +
        perf_empty_kind_slots(PERF_SRC_FRONTEND) +
        perf_empty_kind_slots(PERF_SRC_OTHER) +
        perf_empty_kind_slots(PERF_SRC_LAUNCH) +
        perf_empty_unmapped_slots();
    wire [2:0] perf_alu_bank_occ_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.issue_window_valid_q[3:0]));
    wire [2:0] perf_p0_bank_occ_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.issue_window_valid_q[7:4]));
    wire [2:0] perf_p1_bank_occ_now =
        3'($countones(u_dut.u_ydrasil_issue_stage.issue_window_valid_q[11:8]));
    wire perf_alu_due_select_now =
        |(u_dut.u_ydrasil_issue_stage.issue_select_mask &
          (u_dut.u_ydrasil_issue_stage.issue_src0_fast_main |
           u_dut.u_ydrasil_issue_stage.issue_src0_fast_dual |
           u_dut.u_ydrasil_issue_stage.issue_src1_fast_main |
           u_dut.u_ydrasil_issue_stage.issue_src1_fast_dual));
    wire perf_dtcm_due_select_now = 1'b0;
    wire perf_mdu_due_select_now = 1'b0;
    wire perf_dtcm_local_wake_now =
        u_dut.u_ydrasil_issue_stage.dtcm_launch_wakeup_valid_i;
    wire perf_mdu_local_wake_now =
        u_dut.u_ydrasil_issue_stage.mdu_due_i.valid &&
        u_dut.u_ydrasil_issue_stage.mdu_due_i.producer_tracked;
    wire [3:0] perf_resident_wakeup_entries_now =
        4'($countones(u_dut.u_ydrasil_issue_stage.issue_src0_alloc_wakeup |
                      u_dut.u_ydrasil_issue_stage.issue_src1_alloc_wakeup));
    wire perf_resident_due_select_now =
        |(u_dut.u_ydrasil_issue_stage.issue_select_mask &
          (u_dut.u_ydrasil_issue_stage.issue_src0_alloc_wakeup |
           u_dut.u_ydrasil_issue_stage.issue_src1_alloc_wakeup));

    // Raw RS masks.  These are deliberately independent predicates; unlike
    // perf_rs_*_wait, an entry can appear in more than one mask and therefore
    // exposes the real coupling between dependency, ordering, and resources.
    reg [11:0] perf_rs_dep_mask_now;
    reg [11:0] perf_rs_order_mask_now;
    reg [11:0] perf_rs_resource_mask_now;
    reg [11:0] perf_rs_ready_mask_now;
    integer perf_rs_mask_idx;
    always_comb begin
        perf_rs_dep_mask_now = '0;
        perf_rs_order_mask_now = '0;
        perf_rs_resource_mask_now = '0;
        perf_rs_ready_mask_now = '0;
        for (perf_rs_mask_idx = 0; perf_rs_mask_idx < 12;
             perf_rs_mask_idx = perf_rs_mask_idx + 1) begin
            if (u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                    perf_rs_mask_idx]) begin
                if (!u_dut.u_ydrasil_issue_stage.
                        issue_src0_ready_for_select[perf_rs_mask_idx] ||
                    (!u_dut.u_ydrasil_issue_stage.
                         issue_src1_ready_for_select[perf_rs_mask_idx] &&
                     !u_dut.u_ydrasil_issue_stage.issue_store_q[
                         perf_rs_mask_idx]))
                    perf_rs_dep_mask_now[perf_rs_mask_idx] = 1'b1;
                if (u_dut.u_ydrasil_issue_stage.issue_order_blocked[
                        perf_rs_mask_idx])
                    perf_rs_order_mask_now[perf_rs_mask_idx] = 1'b1;
                if (((perf_rs_mask_idx >= 4) && (perf_rs_mask_idx <= 7) &&
                     u_dut.u_ydrasil_issue_stage.issue_memory_q[
                         perf_rs_mask_idx] &&
                     ({1'b0, u_dut.lsu_issue_credit} <=
                      {1'b0, u_dut.u_ydrasil_issue_stage.
                          lsu_select_reserved_q})) ||
                    ((perf_rs_mask_idx >= 8) &&
                     u_dut.u_ydrasil_issue_stage.issue_divrem_q[
                         perf_rs_mask_idx] &&
                     (!u_dut.u_ydrasil_issue_stage.mdu_div_available_q ||
                      u_dut.u_ydrasil_issue_stage.div_select_reserved_q)) ||
                    ((perf_rs_mask_idx >= 8) &&
                     u_dut.u_ydrasil_issue_stage.issue_serial_q[
                         perf_rs_mask_idx] &&
                     ((u_dut.u_ydrasil_issue_stage.issue_window_q[
                           perf_rs_mask_idx].dst.rob_tag !=
                       u_dut.u_ydrasil_issue_stage.rob_head_select_q) ||
                      !u_dut.u_ydrasil_issue_stage.lsu_idle_select_q)))
                    perf_rs_resource_mask_now[perf_rs_mask_idx] = 1'b1;
                if (!perf_rs_dep_mask_now[perf_rs_mask_idx] &&
                    !perf_rs_order_mask_now[perf_rs_mask_idx] &&
                    !perf_rs_resource_mask_now[perf_rs_mask_idx])
                    perf_rs_ready_mask_now[perf_rs_mask_idx] = 1'b1;
            end
        end
    end

    wire [15:0] perf_rs_candidate_mask_now = {
        u_dut.u_ydrasil_issue_stage.p1_serial_candidate_local,
        u_dut.u_ydrasil_issue_stage.p1_candidate_local,
        u_dut.u_ydrasil_issue_stage.p0_candidate_local,
        u_dut.u_ydrasil_issue_stage.alu_candidate_local};
    wire [11:0] perf_rs_selected_mask_now =
        u_dut.u_ydrasil_issue_stage.issue_select_mask;
    wire perf_bank_full_any_now =
        (perf_alu_bank_occ_now == 3'd4) ||
        (perf_p0_bank_occ_now == 3'd4) ||
        (perf_p1_bank_occ_now == 3'd4);
    wire perf_select_single_now =
        u_dut.u_ydrasil_issue_stage.select_buf_push &&
        u_dut.u_ydrasil_issue_stage.selected_valid0 &&
        !u_dut.u_ydrasil_issue_stage.selected_valid1;
    wire [3:0] perf_select_queue_state_now = {
        u_dut.u_ydrasil_issue_stage.select_skid_valid_q,
        u_dut.u_ydrasil_issue_stage.select_skid_pair_q,
        u_dut.u_ydrasil_issue_stage.select_head_valid_q,
        u_dut.u_ydrasil_issue_stage.select_head_pair_q
    };
    // A single head plus a pair waiting in skid is the exact bundle HOL case:
    // one selected uop is available but cannot share the already-issued head.
    wire perf_select_hol_pair_now =
        u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
        !u_dut.u_ydrasil_issue_stage.select_head_pair_q &&
        u_dut.u_ydrasil_issue_stage.select_skid_valid_q &&
        u_dut.u_ydrasil_issue_stage.select_skid_pair_q;
    // The queue state after the edge can hide this event: a singleton head
    // may be consumed while a pair is pushed into the freed cell.  The cycle
    // still lost one execution slot before that pair reaches the head.  Count
    // this edge explicitly instead of relying on a persistent skid state.
    wire perf_select_pair_push_single_head_now =
        u_dut.u_ydrasil_issue_stage.select_buf_push &&
        u_dut.u_ydrasil_issue_stage.selected_valid1 &&
        u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
        !u_dut.u_ydrasil_issue_stage.select_head_pair_q;
    wire perf_select_refill_head_empty_now =
        !u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
        u_dut.u_ydrasil_issue_stage.select_buf_push;

    // Refill is a boundary event, not a recoverable-cycle estimate.  Classify
    // each pushed uop by the same entry's state on the preceding cycle and by
    // whether all required operand data already exists in registered storage.
    function automatic logic perf_refill_source_registered(
        input ydrasil_source_desc_t source
    );
        producer_slot_t source_slot;
        integer source_bank_index;
        logic source_value_valid;
        logic source_value_epoch;
        begin
            if (!source.used || (source.arch_addr == '0) || !source.tag_valid) begin
                perf_refill_source_registered = 1'b1;
            end else begin
                source_slot = source.producer_tag[PRODUCER_SLOT_WIDTH-1:0];
                source_bank_index = integer'(
                    source_slot[PRODUCER_SLOT_WIDTH-1:1]);
                if (source_slot[0]) begin
                    source_value_valid = u_dut.u_ydrasil_issue_stage.
                        u_value_file.value_valid_odd_q[source_bank_index];
                    source_value_epoch = u_dut.u_ydrasil_issue_stage.
                        u_value_file.value_epoch_odd_q[source_bank_index];
                end else begin
                    source_value_valid = u_dut.u_ydrasil_issue_stage.
                        u_value_file.value_valid_even_q[source_bank_index];
                    source_value_epoch = u_dut.u_ydrasil_issue_stage.
                        u_value_file.value_epoch_even_q[source_bank_index];
                end
                // An epoch mismatch is also registered-resolvable: Operand
                // legally falls back to the architectural file after reuse.
                perf_refill_source_registered =
                    (source_value_epoch !=
                     source.producer_tag[PRODUCER_ID_WIDTH-1]) ||
                    source_value_valid ||
                    (u_dut.u_ydrasil_issue_stage.
                         dtcm_operand_history_q.valid &&
                     u_dut.u_ydrasil_issue_stage.
                         dtcm_operand_history_q.producer_tracked &&
                     (u_dut.u_ydrasil_issue_stage.
                          dtcm_operand_history_q.producer_id ==
                      source.producer_tag)) ||
                    (u_dut.u_ydrasil_issue_stage.
                         mdu_operand_reservation_q.valid &&
                     u_dut.u_ydrasil_issue_stage.
                         mdu_operand_reservation_q.producer_tracked &&
                     (u_dut.u_ydrasil_issue_stage.
                          mdu_operand_reservation_q.producer_id ==
                      source.producer_tag));
            end
        end
    endfunction

    function automatic logic [3:0] perf_refill_prior_mask(
        input logic [11:0] selected_mask,
        input producer_id_t selected_tag
    );
        integer refill_entry_idx;
        logic selected_entry_seen;
        logic prior_identity_match;
        begin
            // 0..7 are exact DEP/ORDER/RESOURCE masks, 8 is new/replaced,
            // and 9 catches an invalid selection for closure diagnostics.
            perf_refill_prior_mask = 4'd9;
            selected_entry_seen = 1'b0;
            prior_identity_match = 1'b0;
            for (refill_entry_idx = 0; refill_entry_idx < 12;
                 refill_entry_idx = refill_entry_idx + 1) begin
                if (selected_mask[refill_entry_idx]) begin
                    selected_entry_seen = 1'b1;
                    if (perf_refill_prev_valid_q[refill_entry_idx] &&
                        (perf_refill_prev_tag_q[refill_entry_idx] ==
                         selected_tag)) begin
                        prior_identity_match = 1'b1;
                        perf_refill_prior_mask = {
                            1'b0,
                            perf_refill_prev_resource_q[refill_entry_idx],
                            perf_refill_prev_order_q[refill_entry_idx],
                            perf_refill_prev_dep_q[refill_entry_idx]
                        };
                    end
                end
            end
            if (selected_entry_seen && !prior_identity_match)
                perf_refill_prior_mask = 4'd8;
        end
    endfunction

    function automatic logic [3:0] perf_refill_source_pending_class(
        input ydrasil_source_desc_t source
    );
        begin
            perf_refill_source_pending_class = 4'b0;
            if (!perf_refill_source_registered(source)) begin
                case (source.producer_class)
                    RESULT_ALU: perf_refill_source_pending_class = 4'b0001;
                    RESULT_LSU: perf_refill_source_pending_class = 4'b0010;
                    RESULT_MDU: perf_refill_source_pending_class = 4'b0100;
                    default:    perf_refill_source_pending_class = 4'b1000;
                endcase
            end
        end
    endfunction

    function automatic logic [3:0] perf_refill_uop_pending_mask(
        input ydrasil_compact_uop_t uop
    );
        logic [3:0] pending_mask;
        begin
            pending_mask = perf_refill_source_pending_class(uop.src0);
            if (uop.op_class != UOP_CLASS_STORE)
                pending_mask = pending_mask |
                    perf_refill_source_pending_class(uop.src1);
            perf_refill_uop_pending_mask = pending_mask;
        end
    endfunction

    function automatic logic [2:0] perf_refill_lifecycle(
        input logic [11:0] selected_mask,
        input producer_id_t selected_tag
    );
        integer refill_entry_idx;
        logic prior_identity_match;
        begin
            // 0 eligible, 1 dependency, 2 order, 3 resource, 4 new, 5 other.
            perf_refill_lifecycle = 3'd5;
            prior_identity_match = 1'b0;
            for (refill_entry_idx = 0; refill_entry_idx < 12;
                 refill_entry_idx = refill_entry_idx + 1) begin
                if (selected_mask[refill_entry_idx] &&
                    perf_refill_prev_valid_q[refill_entry_idx] &&
                    (perf_refill_prev_tag_q[refill_entry_idx] == selected_tag)) begin
                    prior_identity_match = 1'b1;
                    if (perf_refill_prev_dep_q[refill_entry_idx])
                        perf_refill_lifecycle = 3'd1;
                    else if (perf_refill_prev_order_q[refill_entry_idx])
                        perf_refill_lifecycle = 3'd2;
                    else if (perf_refill_prev_resource_q[refill_entry_idx])
                        perf_refill_lifecycle = 3'd3;
                    else if (perf_refill_prev_ready_q[refill_entry_idx])
                        perf_refill_lifecycle = 3'd0;
                end
            end
            if (!prior_identity_match)
                perf_refill_lifecycle = 3'd4;
        end
    endfunction

    wire [2:0] perf_refill_lifecycle0_now = perf_refill_lifecycle(
        u_dut.u_ydrasil_issue_stage.selected0_mask,
        u_dut.u_ydrasil_issue_stage.selected_uop0.dst.rob_tag);
    wire [2:0] perf_refill_lifecycle1_now = perf_refill_lifecycle(
        u_dut.u_ydrasil_issue_stage.selected1_mask,
        u_dut.u_ydrasil_issue_stage.selected_uop1.dst.rob_tag);
    wire [3:0] perf_refill_pending_mask0_now = perf_refill_uop_pending_mask(
        u_dut.u_ydrasil_issue_stage.selected_uop0);
    wire [3:0] perf_refill_pending_mask1_now = perf_refill_uop_pending_mask(
        u_dut.u_ydrasil_issue_stage.selected_uop1);
    wire [3:0] perf_refill_prior_mask0_now = perf_refill_prior_mask(
        u_dut.u_ydrasil_issue_stage.selected0_mask,
        u_dut.u_ydrasil_issue_stage.selected_uop0.dst.rob_tag);
    wire [3:0] perf_refill_prior_mask1_now = perf_refill_prior_mask(
        u_dut.u_ydrasil_issue_stage.selected1_mask,
        u_dut.u_ydrasil_issue_stage.selected_uop1.dst.rob_tag);
    // Coupling mask bits: BANK, ROB, DEP, ORDER, RESOURCE, SELECT, OPERAND,
    // RECOVERY.  The mask is a state vector, not a one-hot attribution.
    wire [7:0] perf_coupling_mask_now = {
        (u_dut.ex_pc_redirect ||
         u_dut.u_ydrasil_issue_stage.recovery_pending_q),
        perf_operand_dependency_miss_now,
        (perf_select_width_limit_now || perf_select_single_now ||
         perf_select_hol_pair_now),
        (perf_rs_resource_wait || perf_rs_pair_bank_limit_now),
        perf_rs_order_wait,
        perf_rs_dependency_wait,
        perf_rob_full_now,
        (perf_bank_full_any_now || perf_rs_bank_full_now)
    };

    wire [2:0] perf_bank_dep_entries_now [0:2];
    wire [2:0] perf_bank_order_entries_now [0:2];
    wire [2:0] perf_bank_resource_entries_now [0:2];
    wire [2:0] perf_bank_ready_entries_now [0:2];
    wire [2:0] perf_bank_candidate_entries_now [0:2];
    wire [2:0] perf_bank_selected_entries_now [0:2];
    assign perf_bank_dep_entries_now[0] =
        3'($countones(perf_rs_dep_mask_now[3:0]));
    assign perf_bank_dep_entries_now[1] =
        3'($countones(perf_rs_dep_mask_now[7:4]));
    assign perf_bank_dep_entries_now[2] =
        3'($countones(perf_rs_dep_mask_now[11:8]));
    assign perf_bank_order_entries_now[0] =
        3'($countones(perf_rs_order_mask_now[3:0]));
    assign perf_bank_order_entries_now[1] =
        3'($countones(perf_rs_order_mask_now[7:4]));
    assign perf_bank_order_entries_now[2] =
        3'($countones(perf_rs_order_mask_now[11:8]));
    assign perf_bank_resource_entries_now[0] =
        3'($countones(perf_rs_resource_mask_now[3:0]));
    assign perf_bank_resource_entries_now[1] =
        3'($countones(perf_rs_resource_mask_now[7:4]));
    assign perf_bank_resource_entries_now[2] =
        3'($countones(perf_rs_resource_mask_now[11:8]));
    assign perf_bank_ready_entries_now[0] =
        3'($countones(perf_rs_ready_mask_now[3:0]));
    assign perf_bank_ready_entries_now[1] =
        3'($countones(perf_rs_ready_mask_now[7:4]));
    assign perf_bank_ready_entries_now[2] =
        3'($countones(perf_rs_ready_mask_now[11:8]));
    assign perf_bank_candidate_entries_now[0] =
        3'($countones(perf_rs_candidate_mask_now[3:0]));
    assign perf_bank_candidate_entries_now[1] =
        3'($countones(perf_rs_candidate_mask_now[7:4]));
    assign perf_bank_candidate_entries_now[2] =
        3'($countones(perf_rs_candidate_mask_now[11:8]));
    assign perf_bank_selected_entries_now[0] =
        3'($countones(perf_rs_selected_mask_now[3:0]));
    assign perf_bank_selected_entries_now[1] =
        3'($countones(perf_rs_selected_mask_now[7:4]));
    assign perf_bank_selected_entries_now[2] =
        3'($countones(perf_rs_selected_mask_now[11:8]));

    function automatic integer perf_latency_bucket(input integer latency);
        if (latency < 4)
            perf_latency_bucket = 0;
        else if (latency < 8)
            perf_latency_bucket = 1;
        else if (latency < 16)
            perf_latency_bucket = 2;
        else if (latency < 32)
            perf_latency_bucket = 3;
        else if (latency < 64)
            perf_latency_bucket = 4;
        else
            perf_latency_bucket = 5;
    endfunction
    wire        retire0_valid;
    wire [31:0] retire0_pc;
    wire        retire1_valid;
    wire [31:0] retire1_pc;

	ydrasil_core u_dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.axi_m2s_o (axi_m2s),
		.axi_s2m_i (axi_s2m),
		.irq_i     (irq),
        .retire0_valid_o(retire0_valid),
        .retire0_pc_o   (retire0_pc),
        .retire1_valid_o(retire1_valid),
        .retire1_pc_o   (retire1_pc)
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
    logic [(1 << ydrasil_pkg::PRODUCER_ID_WIDTH)-1:0]
        squashed_completion_pending_q;
    integer completion_assert_lane;
    integer completion_assert_other_lane;
    integer completion_squash_slot;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_q <= 1'b0;
            early_clear_q <= 1'b0;
            squashed_completion_pending_q <= '0;
        end else begin
            interrupt_q <= u_dut.u_ydrasil_commit_trace.interrupt;
            early_clear_q <= u_dut.flush_id || u_dut.bubble_id;

            // Fixed-latency EX results may drain after recovery has removed
            // their ROB entries. Keep the killed full tags as tombstones so
            // only those proven stale completions are accepted below.
            if (u_dut.u_ctrl.recovery_event) begin
                for (completion_squash_slot = 0;
                     completion_squash_slot < ydrasil_pkg::PRODUCER_NUM;
                     completion_squash_slot = completion_squash_slot + 1) begin
                    if (u_dut.u_ctrl.producer_valid_q[completion_squash_slot] &&
                        !u_dut.u_ctrl.recovery_live_mask[
                            completion_squash_slot]) begin
                        squashed_completion_pending_q[{
                            u_dut.u_ctrl.producer_epoch_q[
                                completion_squash_slot],
                            ydrasil_pkg::PRODUCER_SLOT_WIDTH'(
                                completion_squash_slot)}] <= 1'b1;
                    end
                end
            end
            if (u_dut.u_ydrasil_commit_trace.interrupt) begin
                for (completion_squash_slot = 0;
                     completion_squash_slot < ydrasil_pkg::PRODUCER_NUM;
                     completion_squash_slot = completion_squash_slot + 1) begin
                    if (u_dut.u_ctrl.producer_valid_q[completion_squash_slot]) begin
                        squashed_completion_pending_q[{
                            u_dut.u_ctrl.producer_epoch_q[
                                completion_squash_slot],
                            ydrasil_pkg::PRODUCER_SLOT_WIDTH'(
                                completion_squash_slot)}] <= 1'b1;
                    end
                end
            end
            if (u_dut.u_ctrl.queue_alloc0)
                squashed_completion_pending_q[
                    u_dut.u_ctrl.producer_alloc_id] <= 1'b0;
            if (u_dut.u_ctrl.queue_alloc1)
                squashed_completion_pending_q[
                    u_dut.u_ctrl.producer_alloc_id1] <= 1'b0;

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

            assert (u_dut.u_ydrasil_issue_stage.u_registers.registers[0] == 32'b0)
                else $fatal(1, "ASSERT_X0_NONZERO value=0x%08h",
                            u_dut.u_ydrasil_issue_stage.u_registers.registers[0]);
            assert (u_dut.u_ydrasil_if_stage.pc_ff[1:0] == 2'b00)
                else $fatal(1, "ASSERT_PC_MISALIGNED pc=0x%08h",
                            u_dut.u_ydrasil_if_stage.pc_ff);
            // The LSU has independent registered DTCM and MMIO backends.
            // Concurrent requests are legal; validate each side below.
            assert (!u_dut.u_ydrasil_commit_trace.dtcm_we || (u_dut.u_ydrasil_commit_trace.dtcm_req && (|u_dut.u_ydrasil_commit_trace.dtcm_wmask)))
                else $fatal(1, "ASSERT_BAD_DTCM_WRITE req=%0b mask=0x%01h addr=0x%08h",
                            u_dut.u_ydrasil_commit_trace.dtcm_req, u_dut.u_ydrasil_commit_trace.dtcm_wmask, u_dut.u_ydrasil_commit_trace.dtcm_addr);
            assert (!u_dut.u_ydrasil_commit_trace.mmio_we || (u_dut.u_ydrasil_commit_trace.mmio_req && (|u_dut.u_ydrasil_commit_trace.mmio_wmask)))
                else $fatal(1, "ASSERT_BAD_MMIO_WRITE req=%0b mask=0x%01h addr=0x%08h",
                            u_dut.u_ydrasil_commit_trace.mmio_req, u_dut.u_ydrasil_commit_trace.mmio_wmask, u_dut.u_ydrasil_commit_trace.mmio_addr);
            assert ((u_dut.flush_if == u_dut.branch_jump) &&
                    (u_dut.flush_id == u_dut.branch_jump) &&
                    (u_dut.flush_ex == u_dut.branch_jump))
                else $fatal(1, "ASSERT_INCOHERENT_FLUSH branch=%0b if=%0b id=%0b ex=%0b",
                            u_dut.branch_jump, u_dut.flush_if,
                            u_dut.flush_id, u_dut.flush_ex);
            if (interrupt_q) begin
                assert (u_dut.u_ctrl.producer_valid_q == '0)
                    else $fatal(1, "ASSERT_TOKEN_AFTER_INTERRUPT valid=0x%0h",
                                u_dut.u_ctrl.producer_valid_q);
                assert (u_dut.u_ydrasil_load_store_unit.queue_count_q == '0)
                    else $fatal(1, "ASSERT_LSU_QUEUE_AFTER_INTERRUPT count=%0d",
                                u_dut.u_ydrasil_load_store_unit.queue_count_q);
            end
            assert (u_dut.u_ydrasil_load_store_unit.queue_count_q <= 2'd2)
                else $fatal(1, "ASSERT_LSU_QUEUE_COUNT count=%0d",
                            u_dut.u_ydrasil_load_store_unit.queue_count_q);
            if (u_dut.u_ydrasil_commit_trace.clint_csr_we) begin
                assert ((u_dut.u_ydrasil_commit_trace.clint_csr_waddr == ydrasil_pkg::CSR_MSTATUS) ||
                        (u_dut.u_ydrasil_commit_trace.clint_csr_waddr == ydrasil_pkg::CSR_MEPC) ||
                        (u_dut.u_ydrasil_commit_trace.clint_csr_waddr == ydrasil_pkg::CSR_MCAUSE) ||
                        (u_dut.u_ydrasil_commit_trace.clint_csr_waddr == ydrasil_pkg::CSR_MTVAL))
                    else $fatal(1, "ASSERT_BAD_TRAP_CSR_WRITE addr=0x%03h data=0x%08h",
                                u_dut.u_ydrasil_commit_trace.clint_csr_waddr, u_dut.u_ydrasil_commit_trace.clint_csr_wdata);
            end
            for (completion_assert_lane = 0;
                 completion_assert_lane < ydrasil_pkg::COMPLETION_LANES;
                 completion_assert_lane = completion_assert_lane + 1) begin
                if (u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].valid &&
                    u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_tracked &&
                    (u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].addr != '0)) begin
                    assert (u_dut.u_ctrl.producer_valid_q[
                                u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id[
                                    ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                            (u_dut.u_ctrl.producer_epoch_q[
                                u_dut.u_ydrasil_commit_trace.completion_bus[
                                    completion_assert_lane].producer_id[
                                        ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] ==
                             u_dut.u_ydrasil_commit_trace.completion_bus[
                                completion_assert_lane].producer_id[
                                    ydrasil_pkg::PRODUCER_ID_WIDTH-1]) ||
                            (u_dut.u_ctrl.producer_alloc_ex &&
                             (u_dut.ex_hzd_pkt.producer_id ==
                              u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id)) ||
                            (u_dut.u_ctrl.producer_alloc_ex1 &&
                             (u_dut.ex_hzd_pkt1.producer_id ==
                              u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id)) ||
                            squashed_completion_pending_q[
                                u_dut.u_ydrasil_commit_trace.completion_bus[
                                    completion_assert_lane].producer_id])
                        else $fatal(1,
                            "ASSERT_COMPLETION_FOR_FREE_TOKEN lane=%0d id=%0d rd=%0d data=0x%08h",
                            completion_assert_lane,
                            u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id,
                            u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].addr,
                            u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].data);
                    squashed_completion_pending_q[
                        u_dut.u_ydrasil_commit_trace.completion_bus[
                            completion_assert_lane].producer_id] <= 1'b0;
                end
                for (completion_assert_other_lane = completion_assert_lane + 1;
                     completion_assert_other_lane < ydrasil_pkg::COMPLETION_LANES;
                     completion_assert_other_lane = completion_assert_other_lane + 1) begin
                    assert (!(u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].valid &&
                              u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_tracked &&
                              (u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].addr != '0) &&
                              u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_other_lane].valid &&
                              u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_other_lane].producer_tracked &&
                              (u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_other_lane].addr != '0) &&
                              (u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id ==
                               u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_other_lane].producer_id)))
                        else $fatal(1,
                            "ASSERT_DUPLICATE_COMPLETION_ID lane_a=%0d lane_b=%0d id=%0d",
                            completion_assert_lane, completion_assert_other_lane,
                            u_dut.u_ydrasil_commit_trace.completion_bus[completion_assert_lane].producer_id);
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
	`endif

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lsu_local_debug_cycle <= 0;
        end else begin
            lsu_local_debug_cycle <= lsu_local_debug_cycle + 1;
            if (lsu_local_debug_en) begin
                if (u_dut.u_ydrasil_issue_stage.lane_a_agu_accept &&
                    ((u_dut.u_ydrasil_issue_stage.lane_a_uop.pc ==
                      32'h80003e9c) ||
                     (u_dut.u_ydrasil_issue_stage.lane_a_uop.pc ==
                      32'h80003fd8)))
                    $display("LSULOC cyc=%0d LOADSEL pc=0x%08h id=%0d src0=%0d/tag=%0b/%0d/ready=%0b epoch=%0b values=ff:0x%08h arf:0x%08h resolved:0x%08h ready=%0b hit=dtcm:%0b/main:%0b/dual:%0b replay=main:%0b/%0d dual:%0b/%0d completion=alu:%0b/%0d/0x%08h dual:%0b/%0d/0x%08h",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.pc,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.dst.rob_tag,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0.arch_addr,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0.tag_valid,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0.producer_tag,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0.ready,
                             u_dut.u_ydrasil_issue_stage.issue_src0_epoch_i,
                             u_dut.u_ydrasil_issue_stage.issue_src0_value_i,
                             u_dut.u_ydrasil_issue_stage.rf_rdata_rs1_i,
                             u_dut.u_ydrasil_issue_stage.lane_a_src0_local,
                             u_dut.u_ydrasil_issue_stage.src0_ready,
                             u_dut.u_ydrasil_issue_stage.slot0_src0_dtcm_hit,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0_bypass ==
                                 BYPASS_LANE0,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src0_bypass ==
                                 BYPASS_LANE1,
                             u_dut.u_ydrasil_issue_stage.select_wakeup_valid_q[0],
                             u_dut.u_ydrasil_issue_stage.select_wakeup_id_q[0],
                             u_dut.u_ydrasil_issue_stage.select_wakeup_valid_q[1],
                             u_dut.u_ydrasil_issue_stage.select_wakeup_id_q[1],
                             u_dut.completion_meta[COMPLETION_ALU].valid,
                             u_dut.completion_meta[COMPLETION_ALU].producer_id,
                             u_dut.completion_data[COMPLETION_ALU],
                             u_dut.completion_meta[COMPLETION_DUAL_ALU].valid,
                             u_dut.completion_meta[COMPLETION_DUAL_ALU].producer_id,
                             u_dut.completion_data[COMPLETION_DUAL_ALU]);
                if ((lsu_local_debug_cycle >= 70190) &&
                    (lsu_local_debug_cycle <= 70225) &&
                    (u_dut.ex_pc_redirect || u_dut.branch_jump || u_dut.flush_ex))
                    $display("LSULOC cyc=%0d BRANCH redirect=%0b jump=%0b flush_ex=%0b target=0x%08h train=%0b/0x%08h/id=%0d/taken=%0b keep=0x%0h sb=%0d/%0b/%0b/%0b/id=%0d/%0d",
                             lsu_local_debug_cycle,
                             u_dut.ex_pc_redirect,
                             u_dut.branch_jump,
                             u_dut.flush_ex,
                             u_dut.ex_pc_redirect_target,
                             u_dut.ex_bp_train_pkt.valid,
                             u_dut.ex_bp_train_pkt.pc,
                             u_dut.ex_bp_train_pkt.producer_id,
                             u_dut.ex_bp_train_pkt.taken,
                             u_dut.u_ctrl.recovery_live_mask,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.retired,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_producer_id);
                if ((lsu_local_debug_cycle >= 70190) &&
                    (lsu_local_debug_cycle <= 70225) &&
                    ((u_dut.commit_pkt.valid &&
                      (u_dut.commit_pkt.pc >= 32'h800030e0) &&
                      (u_dut.commit_pkt.pc <= 32'h800030f4)) ||
                     (u_dut.commit_pkt1.valid &&
                      (u_dut.commit_pkt1.pc >= 32'h800030e0) &&
                      (u_dut.commit_pkt1.pc <= 32'h800030f4))))
                    $display("LSULOC cyc=%0d COMMIT v0=%0b/pc=0x%08h/id=%0d v1=%0b/pc=0x%08h/id=%0d sb=%0d/%0b/%0b/%0b/id=%0d",
                             lsu_local_debug_cycle,
                             u_dut.commit_pkt.valid,
                             u_dut.commit_pkt.pc,
                             u_dut.commit_pkt.producer_id,
                             u_dut.commit_pkt1.valid,
                             u_dut.commit_pkt1.pc,
                             u_dut.commit_pkt1.producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.retired,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.producer_id);
                if (u_dut.u_ydrasil_issue_stage.agu_in_valid_q &&
                    ((u_dut.u_ydrasil_issue_stage.agu_in_operand_a_q +
                      u_dut.u_ydrasil_issue_stage.agu_in_operand_b_q) >=
                     32'h80100c40) &&
                    ((u_dut.u_ydrasil_issue_stage.agu_in_operand_a_q +
                      u_dut.u_ydrasil_issue_stage.agu_in_operand_b_q) <
                     32'h80100e80))
                    $display("LSULOC cyc=%0d AGU pc=0x%08h id=%0d rd=%0d load=%0b store=%0b addr=0x%08h data=0x%08h data_valid=%0b data_id=%0d src1=0x%08h/%0b/%0b/%0d/%0d src_state=%0b/%0b prodpc=0x%08h prodclass=%0d",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_issue_stage.lane_a_pc_q,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.producer_id,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.rd_addr,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_load,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_store,
                             u_dut.u_ydrasil_issue_stage.agu_in_operand_a_q +
                             u_dut.u_ydrasil_issue_stage.agu_in_operand_b_q,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_data,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_data_valid,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_producer_id,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.arch_addr,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.tag_valid,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.ready,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag,
                             u_dut.u_ydrasil_issue_stage.issue_src1_epoch_i,
                             u_dut.u_ctrl.producer_valid_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ctrl.producer_done_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ctrl.producer_pc_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ctrl.producer_result_class_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]]);
                if (u_dut.lsu_req_pkt.valid &&
                    (u_dut.lsu_req_pkt.addr >= 32'h80100c40) &&
                    (u_dut.lsu_req_pkt.addr < 32'h80100e80))
                    $display("LSULOC cyc=%0d REQ id=%0d rd=%0d load=%0b store=%0b addr=0x%08h data=0x%08h mask=0x%0h data_valid=%0b data_id=%0d qcount=%0d scount=%0d",
                             lsu_local_debug_cycle,
                             u_dut.lsu_req_pkt.producer_id,
                             u_dut.lsu_req_pkt.rd_addr,
                             u_dut.lsu_req_pkt.is_load,
                             u_dut.lsu_req_pkt.is_store,
                             u_dut.lsu_req_pkt.addr,
                             u_dut.lsu_req_pkt.store_data,
                             u_dut.lsu_req_pkt.store_mask,
                             u_dut.lsu_req_pkt.store_data_valid,
                             u_dut.lsu_req_pkt.store_producer_id,
                             u_dut.u_ydrasil_load_store_unit.queue_count_q,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q);
                if (u_dut.u_ydrasil_load_store_unit.dtcm_load_fire &&
                    (u_dut.u_ydrasil_load_store_unit.load_launch_addr >=
                     32'h80100c40) &&
                    (u_dut.u_ydrasil_load_store_unit.load_launch_addr <
                     32'h80100e80))
                    $display("LSULOC cyc=%0d LOAD_FIRE id=%0d rd=%0d addr=0x%08h fmask=0x%0h fdata=0x%08h sb0=%0b/%0b/0x%08h/0x%08h/0x%0h sb1=%0b/%0b/0x%08h/0x%08h/0x%0h",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_load_store_unit.load_launch_producer_id,
                             u_dut.u_ydrasil_load_store_unit.load_launch_rd_addr,
                             u_dut.u_ydrasil_load_store_unit.load_launch_addr,
                             u_dut.u_ydrasil_load_store_unit.load_forward_mask,
                             u_dut.u_ydrasil_load_store_unit.load_forward_data,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.addr,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_mask,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.addr,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_data,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_mask);
                if (u_dut.u_ydrasil_load_store_unit.store_buf_enqueue &&
                    (u_dut.u_ydrasil_load_store_unit.active_addr >=
                     32'h80100c40) &&
                    (u_dut.u_ydrasil_load_store_unit.active_addr <
                     32'h80100e80))
                    $display("LSULOC cyc=%0d STORE_BUF_IN id=%0d addr=0x%08h data=0x%08h mask=0x%0h valid=%0b data_id=%0d tracked=%0b scount=%0d deq=%0b",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_load_store_unit.active_producer_id,
                             u_dut.u_ydrasil_load_store_unit.active_addr,
                             u_dut.u_ydrasil_load_store_unit.patched_store_enqueue.store_data,
                             u_dut.u_ydrasil_load_store_unit.patched_store_enqueue.store_mask,
                             u_dut.u_ydrasil_load_store_unit.patched_store_enqueue.store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.patched_store_enqueue.store_producer_id,
                             u_dut.u_ydrasil_load_store_unit.patched_store_enqueue.store_producer_tracked,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q,
                             u_dut.u_ydrasil_load_store_unit.store_buf_dequeue);
                if (u_dut.u_ydrasil_load_store_unit.store_buf_dequeue &&
                    (u_dut.u_ydrasil_load_store_unit.store_buf0_q.addr >=
                     32'h80100c40) &&
                    (u_dut.u_ydrasil_load_store_unit.store_buf0_q.addr <
                     32'h80100e80))
                    $display("LSULOC cyc=%0d STORE_DRAIN id=%0d addr=0x%08h data=0x%08h mask=0x%0h scount=%0d",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.addr,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_mask,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q);
                if (u_dut.u_ydrasil_load_store_unit.load_s1_valid_q)
                    $display("LSULOC cyc=%0d LOAD_RESP id=%0d rd=%0d raw=0x%08h result=0x%08h fmask=0x%0h fdata=0x%08h completion=%0b/0x%08h",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_load_store_unit.load_s1_producer_id_q,
                             u_dut.u_ydrasil_load_store_unit.load_s1_rd_addr_q,
                             u_dut.u_ydrasil_load_store_unit.dtcm_rdata_i,
                             u_dut.u_ydrasil_load_store_unit.dtcm_load_result,
                             u_dut.u_ydrasil_load_store_unit.load_s1_forward_mask_q,
                             u_dut.u_ydrasil_load_store_unit.load_s1_forward_data_q,
                             u_dut.lsu_completion_valid,
                             u_dut.lsu_completion_data);
                if ((u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid &&
                     !u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data_valid) ||
                    (u_dut.u_ydrasil_load_store_unit.store_buf1_q.valid &&
                     !u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_data_valid))
                    $display("LSULOC cyc=%0d WAIT sb0=%0b/%0d/%0d/0x%08h sb1=%0b/%0d/%0d/0x%08h comp=0:%0b/%0d/0x%08h 1:%0b/%0d/0x%08h 2:%0b/%0d/0x%08h 3:%0b/%0d/0x%08h sh=0:%0b/%0d/0x%08h 1:%0b/%0d/0x%08h 2:%0b/%0d/0x%08h 3:%0b/%0d/0x%08h 4:%0b/%0d/0x%08h",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_producer_id,
                             u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_data,
                             u_dut.completion_meta[0].valid,
                             u_dut.completion_meta[0].producer_id,
                             u_dut.completion_data[0],
                             u_dut.completion_meta[1].valid,
                             u_dut.completion_meta[1].producer_id,
                             u_dut.completion_data[1],
                             u_dut.completion_meta[2].valid,
                             u_dut.completion_meta[2].producer_id,
                             u_dut.completion_data[2],
                             u_dut.completion_meta[3].valid,
                             u_dut.completion_meta[3].producer_id,
                             u_dut.completion_data[3],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[0],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[0],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_data_q[0],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[1],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[1],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_data_q[1],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[2],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[2],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_data_q[2],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[3],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[3],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_data_q[3],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[4],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[4],
                             u_dut.u_ydrasil_load_store_unit.completion_shadow_data_q[4]);
                if ((retire0_valid && (retire0_pc >= 32'h80003e80) &&
                     (retire0_pc <= 32'h80004010)) ||
                    (retire1_valid && (retire1_pc >= 32'h80003e80) &&
                     (retire1_pc <= 32'h80004010)))
                    $display("LSULOC cyc=%0d RETIRE v0=%0b pc0=0x%08h v1=%0b pc1=0x%08h",
                             lsu_local_debug_cycle, retire0_valid, retire0_pc,
                             retire1_valid, retire1_pc);
                if ((lsu_local_debug_cycle >= 217700) &&
                    (lsu_local_debug_cycle <= 217750) &&
                    ((u_dut.commit_pkt.valid &&
                      ((u_dut.commit_pkt.pc == 32'h80003fd8) ||
                       (u_dut.commit_pkt.pc == 32'h80003fdc))) ||
                     (u_dut.commit_pkt1.valid &&
                      ((u_dut.commit_pkt1.pc == 32'h80003fd8) ||
                       (u_dut.commit_pkt1.pc == 32'h80003fdc)))))
                    $display("LSULOC cyc=%0d COMMITVAL c0=%0b pc=0x%08h id=%0d wr=%0b rd=%0d val=0x%08h c1=%0b pc=0x%08h id=%0d wr=%0b rd=%0d val=0x%08h slots=%0d/%0d vf=0x%08h/0x%08h x16=0x%08h producer16=%0b/%0d/%0b/%0d",
                             lsu_local_debug_cycle,
                             u_dut.commit_pkt.valid,
                             u_dut.commit_pkt.pc,
                             u_dut.commit_pkt.producer_id,
                             u_dut.commit_pkt.writes_gpr,
                             u_dut.commit_pkt.rd_addr,
                             u_dut.commit_pkt.value,
                             u_dut.commit_pkt1.valid,
                             u_dut.commit_pkt1.pc,
                             u_dut.commit_pkt1.producer_id,
                             u_dut.commit_pkt1.writes_gpr,
                             u_dut.commit_pkt1.rd_addr,
                             u_dut.commit_pkt1.value,
                             u_dut.u_ctrl.queue_head_q,
                             u_dut.u_ctrl.queue_head1,
                             u_dut.u_ydrasil_issue_stage.u_value_file.retire_data0_o,
                             u_dut.u_ydrasil_issue_stage.u_value_file.retire_data1_o,
                             u_dut.u_ydrasil_issue_stage.u_registers.registers[16],
                             u_dut.u_ctrl.latest_valid_q[16],
                             u_dut.u_ctrl.latest_id_q[16],
                             u_dut.u_ctrl.producer_valid_q[
                                 u_dut.u_ctrl.latest_id_q[16][
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ctrl.producer_epoch_q[
                                 u_dut.u_ctrl.latest_id_q[16][
                                     PRODUCER_SLOT_WIDTH-1:0]]);
                if ((lsu_local_debug_cycle >= 10635) &&
                    (lsu_local_debug_cycle <= 10645))
                    $display("LSULOC cyc=%0d DTCM_STORE sel=%0b pc=0x%08h src1=x%0d/tag=%0b/%0d ready=%0b hit=%0b local=0x%08h opres=%0b/%0d/x%0d data=0x%08h inres=%0b/%0d/x%0d resp=0x%08h agu=%0b pc=0x%08h flag=%0b raw=0x%08h out=0x%08h valid=%0b stall=%0b/0x%08h lsucomp=%0b/%0d/0x%08h",
                             lsu_local_debug_cycle,
                             u_dut.u_ydrasil_issue_stage.lane_a_accept,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.pc,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src1.arch_addr,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src1.tag_valid,
                             u_dut.u_ydrasil_issue_stage.lane_a_uop.src1.producer_tag,
                             u_dut.u_ydrasil_issue_stage.lane_a_src1_ready,
                             u_dut.u_ydrasil_issue_stage.lane_a_src1_dtcm_hit,
                             u_dut.u_ydrasil_issue_stage.lane_a_src1_local,
                             u_dut.dtcm_reservation.valid,
                             u_dut.dtcm_reservation.producer_id,
                             u_dut.dtcm_reservation.arch_addr,
                             u_dut.dtcm_resp_data,
                             u_dut.dtcm_reservation.valid,
                             u_dut.dtcm_reservation.producer_id,
                             u_dut.dtcm_reservation.arch_addr,
                             u_dut.dtcm_resp_data,
                             u_dut.u_ydrasil_issue_stage.agu_in_valid_q,
                             u_dut.u_ydrasil_issue_stage.lane_a_pc_q,
                             1'b0,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_data,
                             u_dut.u_ydrasil_issue_stage.agu_in_store_data_o,
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_data_valid,
                             1'b0,
                             32'b0,
                             u_dut.completion_meta[COMPLETION_LSU].valid,
                             u_dut.completion_meta[COMPLETION_LSU].producer_id,
                             u_dut.completion_data[COMPLETION_LSU]);
                if ((lsu_local_debug_cycle >= 304715) &&
                    (lsu_local_debug_cycle <= 304790))
                    $display("LSULOC cyc=%0d MMIO_SERIAL if=%0b/0x%08h disp=%0b/%0b/0x%08h/ser=%0b issue=%0b/0x%08h/fence=%0b/%0d commit=%0b/0x%08h/%0d,%0b/0x%08h/%0d rob=head%0d/id%0d/count%0d/v=0x%0h/r=0x%0h/serial=%0b stall=%0b/%0b/%0b lsu=q%0d/active=%0b/id%0d/ret%0b/head%0b/0x%08h/store=%0b/data=%0b/%0d mmio=fire%0b/busy%0b/req%0b/%0b/0x%08h/0x%08h/rsp%0b sb=%0d",
                             lsu_local_debug_cycle,
                             u_dut.if_id_valid,
                             u_dut.if_id_pc,
                             u_dut.dispatch_ready,
                             u_dut.id_issue_pkt.valid,
                             u_dut.id_issue_pkt.decode.pc,
                             u_dut.id_issue_pkt.ctrl.serialize_before,
                             u_dut.issue_head_compact_uop.valid,
                             u_dut.issue_head_compact_uop.pc,
                             u_dut.id_fence_i,
                             u_dut.issue_fence_tag,
                             u_dut.commit_pkt.valid,
                             u_dut.commit_pkt.pc,
                             u_dut.commit_pkt.producer_id,
                             u_dut.commit_pkt1.valid,
                             u_dut.commit_pkt1.pc,
                             u_dut.commit_pkt1.producer_id,
                             u_dut.u_ctrl.queue_head_q,
                             u_dut.rob_head_id,
                             u_dut.u_ctrl.queue_count_q,
                             u_dut.u_ctrl.producer_valid_q,
                             u_dut.u_ctrl.producer_done_q,
                             u_dut.u_ctrl.serial_pending_q,
                             u_dut.stall_if,
                             u_dut.stall_id,
                             u_dut.bubble_id,
                             u_dut.u_ydrasil_load_store_unit.queue_count_q,
                             u_dut.u_ydrasil_load_store_unit.active_valid,
                             u_dut.u_ydrasil_load_store_unit.active_producer_id,
                             u_dut.u_ydrasil_load_store_unit.active_pkt.retired,
                             u_dut.u_ydrasil_load_store_unit.active_at_rob_head,
                             u_dut.u_ydrasil_load_store_unit.active_addr,
                             u_dut.u_ydrasil_load_store_unit.active_is_store,
                             u_dut.u_ydrasil_load_store_unit.active_store_data_valid,
                             u_dut.u_ydrasil_load_store_unit.active_pkt.store_producer_id,
                             u_dut.u_ydrasil_load_store_unit.mmio_fire,
                             u_dut.u_ydrasil_load_store_unit.mmio_busy,
                             u_dut.mmio_req_pkt.valid,
                             u_dut.mmio_req_pkt.write,
                             u_dut.mmio_req_pkt.addr,
                             u_dut.mmio_req_pkt.wdata,
                             u_dut.mmio_rsp_pkt.valid,
                             u_dut.u_ydrasil_load_store_unit.store_buf_count_q);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            perf_local_debug_cycle <= 0;
            perf_producer_full_q <= 1'b0;
            perf_p0_bank_block_q <= 1'b0;
            perf_producer_full_start_q <= 0;
            perf_issue_scan_count <= 0;
            perf_refill_scan_count <= 0;
        end else begin
            perf_local_debug_cycle <= perf_local_debug_cycle + 1;
            perf_producer_full_q <= u_dut.u_ctrl.producer_full_stall;
            perf_p0_bank_block_q <=
                !u_dut.decode_if_ready && u_dut.dispatch_ready &&
                !u_dut.u_ydrasil_issue_stage.dispatch_slots_available &&
                u_dut.u_ydrasil_issue_stage.dispatch0_p0;
            // Bounded local evidence for the large ISSUE_NO_EXECUTE bucket.
            // This is intentionally observational and cannot affect RTL.
            if (perf_issue_scan_en && perf_cycle_issue &&
                (perf_executed_slots == 2'd0) &&
                (perf_issue_scan_count < 32)) begin
                $display("PERFISSUE cyc=%0d pkt=%0b pair=%0b lane=%0b/%0b accept=%0b/%0b ex=%0b/%0b raw=%0b/%0b br=%0b mul=%0b advance=%0b flush_id=%0b recover=%0b pending=%0b serialize=%0b dep=%0b/%0b src=%0b/%0b/%0b/%0b fence=%0b pc=0x%08h/0x%08h",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid,
                         u_dut.u_ydrasil_issue_stage.issue_pair_execute,
                         u_dut.u_ydrasil_issue_stage.lane_a_valid,
                         u_dut.u_ydrasil_issue_stage.lane_b_valid,
                         u_dut.u_ydrasil_issue_stage.lane_a_accept,
                         u_dut.u_ydrasil_issue_stage.lane_b_accept,
                         u_dut.ex_hzd_pkt.valid,
                         u_dut.ex_hzd_pkt1.valid,
                         u_dut.alu_in_valid,
                         u_dut.dual_alu_valid || u_dut.dual_bit_valid ||
                             u_dut.dual_bru_valid || u_dut.mul_in_valid ||
                             u_dut.csr_in_valid,
                         u_dut.ex_branch_jump,
                         u_dut.ex_mul_stall,
                         u_dut.u_ydrasil_issue_stage.id_advance,
                         u_dut.flush_id,
                         u_dut.u_ydrasil_issue_stage.branch_recovery_i,
                         u_dut.u_ydrasil_issue_stage.recovery_pending_q,
                         u_dut.issue_serialize_stall,
                         u_dut.issue_dependency_wait,
                         u_dut.issue_dependency_wait1,
                         u_dut.u_ydrasil_issue_stage.src0_ready,
                         u_dut.u_ydrasil_issue_stage.src1_ready,
                         u_dut.u_ydrasil_issue_stage.src2_ready,
                         u_dut.u_ydrasil_issue_stage.src3_ready,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.fence_i,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                         u_dut.u_ydrasil_issue_stage.issue_pkt1_i.pc);
                perf_issue_scan_count <= perf_issue_scan_count + 1;
            end
            if (perf_refill_scan_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end) &&
                perf_select_refill_head_empty_now &&
                (perf_operand_lost_slots != '0) &&
                (perf_refill_scan_count < 32)) begin
                $display("PERFREFILL cyc=%0d q=head%0b/pair%0b/skid%0b/%0b push=%0b/width%0d u0=pc0x%08h/tag%0d/sel0x%0h/life%0d/prior0x%0h/pending0x%0h/stored%0b u1=valid%0b/pc0x%08h/tag%0d/sel0x%0h/life%0d/prior0x%0h/pending0x%0h/stored%0b prev=v0x%0h/dep0x%0h/order0x%0h/res0x%0h/ready0x%0h now=v0x%0h/dep0x%0h/order0x%0h/res0x%0h/cand0x%0h alloc=%0b/%0b target=0x%0h/0x%0h ex=%0b/%0b",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.select_head_valid_q,
                         u_dut.u_ydrasil_issue_stage.select_head_pair_q,
                         u_dut.u_ydrasil_issue_stage.select_skid_valid_q,
                         u_dut.u_ydrasil_issue_stage.select_skid_pair_q,
                         u_dut.u_ydrasil_issue_stage.select_buf_push,
                         1 + u_dut.u_ydrasil_issue_stage.selected_valid1,
                         u_dut.u_ydrasil_issue_stage.selected_uop0.pc,
                         u_dut.u_ydrasil_issue_stage.selected_uop0.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.selected0_mask,
                         perf_refill_lifecycle0_now,
                         perf_refill_prior_mask0_now,
                         perf_refill_pending_mask0_now,
                         perf_refill_pending_mask0_now == 4'b0,
                         u_dut.u_ydrasil_issue_stage.selected_valid1,
                         u_dut.u_ydrasil_issue_stage.selected_uop1.pc,
                         u_dut.u_ydrasil_issue_stage.selected_uop1.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.selected1_mask,
                         perf_refill_lifecycle1_now,
                         perf_refill_prior_mask1_now,
                         perf_refill_pending_mask1_now,
                         perf_refill_pending_mask1_now == 4'b0,
                         perf_refill_prev_valid_q,
                         perf_refill_prev_dep_q,
                         perf_refill_prev_order_q,
                         perf_refill_prev_resource_q,
                         perf_refill_prev_ready_q,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q,
                         perf_rs_dep_mask_now,
                         perf_rs_order_mask_now,
                         perf_rs_resource_mask_now,
                         perf_rs_candidate_mask_now,
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_valid_q[0],
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_valid_q[1],
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_target_q[0],
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_target_q[1],
                         u_dut.ex_hzd_pkt.valid,
                         u_dut.ex_hzd_pkt1.valid);
                perf_refill_scan_count <= perf_refill_scan_count + 1;
            end
            if (perf_event_scan_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end) &&
                u_dut.u_ctrl.producer_full_stall && !perf_producer_full_q) begin
                perf_producer_full_start_q <= perf_local_debug_cycle;
                $display("PERFEVT cyc=%0d PRODUCER_FULL_BEGIN head_pc=0x%08h head=%0d count=%0d valid=0x%0h done=0x%0h issued=0x%0h rs=0x%0h",
                         perf_local_debug_cycle,
                         u_dut.u_ctrl.producer_pc_q[u_dut.u_ctrl.queue_head_q],
                         u_dut.u_ctrl.queue_head_id,
                         u_dut.u_ctrl.queue_count_q,
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.producer_done_q,
                         perf_producer_issued_q,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q);
            end
            if (perf_event_scan_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end) &&
                !u_dut.u_ctrl.producer_full_stall && perf_producer_full_q)
                $display("PERFEVT cyc=%0d PRODUCER_FULL_END start=%0d length=%0d retire=%0b/%0b complete=0x%0h",
                         perf_local_debug_cycle,
                         perf_producer_full_start_q,
                         perf_local_debug_cycle - perf_producer_full_start_q,
                         u_dut.commit_pkt.valid,
                         u_dut.commit_pkt1.valid,
                         u_dut.u_ctrl.producer_complete_mask);
            if (perf_bank_scan_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end) &&
                !perf_p0_bank_block_q &&
                !u_dut.decode_if_ready && u_dut.dispatch_ready &&
                !u_dut.u_ydrasil_issue_stage.dispatch_slots_available &&
                u_dut.u_ydrasil_issue_stage.dispatch0_p0)
                $display("PERFBANK cyc=%0d P0_BEGIN dec=%0b/%0b ifready=%0b disp=%0b/%0b room=%0b/%0b d0=%0b/%0b/%0b d1=%0b/%0b/%0b occ=alu%0d/p0%0d/p1%0d free=alu%0d/p0%0d/p1%0d credit=alu%0d/p0%0d/p1%0d release=alu%0d/p0%0d/p1%0d issue=p0%0b/p1s%0b/p1%0b/a0%0b/a1%0b sel=push%0b/%0b/%0b lane=%0b/%0b ex=%0b/%0b",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.decode_valid_i,
                         u_dut.u_ydrasil_issue_stage.decode_valid1_i,
                         u_dut.decode_if_ready,
                         u_dut.dispatch_ready,
                         u_dut.dispatch_two_ready,
                         u_dut.u_ydrasil_issue_stage.dispatch_slots_available,
                         u_dut.u_ydrasil_issue_stage.dispatch_pair_slots_available,
                         u_dut.u_ydrasil_issue_stage.dispatch0_alu,
                         u_dut.u_ydrasil_issue_stage.dispatch0_p0,
                         !u_dut.u_ydrasil_issue_stage.dispatch0_alu &&
                             !u_dut.u_ydrasil_issue_stage.dispatch0_p0,
                         u_dut.u_ydrasil_issue_stage.dispatch1_alu,
                         u_dut.u_ydrasil_issue_stage.dispatch1_p0,
                         !u_dut.u_ydrasil_issue_stage.dispatch1_alu &&
                             !u_dut.u_ydrasil_issue_stage.dispatch1_p0,
                         perf_alu_bank_occ_now,
                         perf_p0_bank_occ_now,
                         perf_p1_bank_occ_now,
                         u_dut.u_ydrasil_issue_stage.alu_free_local,
                         u_dut.u_ydrasil_issue_stage.p0_free_local,
                         u_dut.u_ydrasil_issue_stage.p1_free_local,
                         u_dut.u_ydrasil_issue_stage.alu_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.p1_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.alu_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p1_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_issue_grant,
                         u_dut.u_ydrasil_issue_stage.p1_serial_issue_grant,
                         u_dut.u_ydrasil_issue_stage.p1_issue_grant,
                         u_dut.u_ydrasil_issue_stage.alu0_issue_grant,
                         u_dut.u_ydrasil_issue_stage.alu1_issue_grant,
                         u_dut.u_ydrasil_issue_stage.select_buf_push,
                         u_dut.u_ydrasil_issue_stage.selected_valid0,
                         u_dut.u_ydrasil_issue_stage.selected_valid1,
                         u_dut.u_ydrasil_issue_stage.lane_a_accept,
                         u_dut.u_ydrasil_issue_stage.lane_b_accept,
                         u_dut.ex_accept_valid,
                         u_dut.ex_accept_valid1);
            if (perf_bank_scan_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end) &&
                perf_p0_bank_block_q &&
                (u_dut.decode_if_ready || u_dut.dispatch_ready == 1'b0 ||
                 u_dut.u_ydrasil_issue_stage.dispatch_slots_available ||
                 !u_dut.u_ydrasil_issue_stage.dispatch0_p0))
                $display("PERFBANK cyc=%0d P0_END room=%0b/%0b occ=alu%0d/p0%0d/p1%0d credit=alu%0d/p0%0d/p1%0d release=alu%0d/p0%0d/p1%0d issue=p0%0b/p1s%0b/p1%0b/a0%0b/a1%0b sel=push%0b/%0b/%0b lane=%0b/%0b ex=%0b/%0b",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.dispatch_slots_available,
                         u_dut.u_ydrasil_issue_stage.dispatch_pair_slots_available,
                         perf_alu_bank_occ_now,
                         perf_p0_bank_occ_now,
                         perf_p1_bank_occ_now,
                         u_dut.u_ydrasil_issue_stage.alu_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.p1_free_credit_q,
                         u_dut.u_ydrasil_issue_stage.alu_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p1_release_credit_q,
                         u_dut.u_ydrasil_issue_stage.p0_issue_grant,
                         u_dut.u_ydrasil_issue_stage.p1_serial_issue_grant,
                         u_dut.u_ydrasil_issue_stage.p1_issue_grant,
                         u_dut.u_ydrasil_issue_stage.alu0_issue_grant,
                         u_dut.u_ydrasil_issue_stage.alu1_issue_grant,
                         u_dut.u_ydrasil_issue_stage.select_buf_push,
                         u_dut.u_ydrasil_issue_stage.selected_valid0,
                         u_dut.u_ydrasil_issue_stage.selected_valid1,
                         u_dut.u_ydrasil_issue_stage.lane_a_accept,
                         u_dut.u_ydrasil_issue_stage.lane_b_accept,
                         u_dut.ex_accept_valid,
                         u_dut.ex_accept_valid1);
            if (perf_local_debug_en &&
                (perf_local_debug_cycle >= perf_local_start) &&
                (perf_local_debug_cycle <= perf_local_end)) begin
                $display("PERFLOC cyc=%0d FE if=%0b/0x%08h dec=%0b/%0b disp=%0b/%0b rob=head%0d/pc0x%08h/count%0d/v0x%0h/d0x%0h/issued0x%0h alloc=%0b/%0b retire=%0b/%0b comp=0x%0h RS v=0x%0h src0=0x%0h src1=0x%0h cand=a0x%0h/p00x%0h/p10x%0h/s0x%0h sel=push%0b/%0b/count%0d op=v%0b/pair%0b/pc0x%08h,0x%08h/advance%0b lane=%0b/%0b cids=%0b/%0d,%0b/%0d,%0b/%0d,%0b/%0d",
                         perf_local_debug_cycle,
                         u_dut.if_id_valid,
                         u_dut.if_id_pc,
                         u_dut.id_issue_pkt.valid,
                         u_dut.id_issue_pkt1.valid,
                         u_dut.issue_pipe_push,
                         u_dut.issue_pipe_push_two,
                         u_dut.u_ctrl.queue_head_id,
                         u_dut.u_ctrl.producer_pc_q[u_dut.u_ctrl.queue_head_q],
                         u_dut.u_ctrl.queue_count_q,
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.producer_done_q,
                         perf_producer_issued_q,
                         u_dut.u_ctrl.queue_alloc0,
                         u_dut.u_ctrl.queue_alloc1,
                         u_dut.commit_pkt.valid,
                         u_dut.commit_pkt1.valid,
                         u_dut.u_ctrl.producer_complete_mask,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q,
                         {u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[11],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[10],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[9],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[8],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[7],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[6],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[5],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[4],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[3],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[2],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[1],
                          u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[0]},
                         {u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[11],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[10],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[9],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[8],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[7],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[6],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[5],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[4],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[3],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[2],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[1],
                          u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[0]},
                         u_dut.u_ydrasil_issue_stage.alu_candidate_local,
                         u_dut.u_ydrasil_issue_stage.p0_candidate_local,
                         u_dut.u_ydrasil_issue_stage.p1_candidate_local,
                         u_dut.u_ydrasil_issue_stage.p1_serial_candidate_local,
                         u_dut.u_ydrasil_issue_stage.select_buf_push,
                         u_dut.u_ydrasil_issue_stage.selected_valid1,
                         perf_select_buf_count,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid,
                         u_dut.u_ydrasil_issue_stage.issue_pair_execute,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                         u_dut.u_ydrasil_issue_stage.issue_pkt1_i.pc,
                         u_dut.u_ydrasil_issue_stage.id_advance,
                         u_dut.u_ydrasil_issue_stage.lane_a_accept,
                         u_dut.u_ydrasil_issue_stage.lane_b_accept,
                         u_dut.completion_meta[0].valid,
                         u_dut.completion_meta[0].producer_id,
                         u_dut.completion_meta[1].valid,
                         u_dut.completion_meta[1].producer_id,
                         u_dut.completion_meta[2].valid,
                         u_dut.completion_meta[2].producer_id,
                         u_dut.completion_meta[3].valid,
                         u_dut.completion_meta[3].producer_id);
                $display("PERFEX cyc=%0d raw=alu%0b/%0d dual%0b/%0d lsu%0b/%0d mul%0b/%0d bus=alu%0b/%0d dual%0b/%0d lsu%0b/%0d mul%0b/%0d vfwr=0x%0h lsu=fire%0b/s1%0b/%0d/due%0b/%0d mdu=s2%0b/%0d/s3%0b/%0d/due%0b/%0d/res%0b/%0d br=%0b/%0d done=0x%0h",
                         perf_local_debug_cycle,
                         u_dut.alu_completion_valid,
                         u_dut.alu_completion_producer_id,
                         u_dut.dual_completion_valid,
                         u_dut.dual_completion_producer_id,
                         u_dut.lsu_completion_valid,
                         u_dut.lsu_completion_producer_id,
                         u_dut.mul_rf_wen_rd,
                         u_dut.mul_producer_id,
                         u_dut.completion_meta[COMPLETION_ALU].valid,
                         u_dut.completion_meta[COMPLETION_ALU].producer_id,
                         u_dut.completion_meta[COMPLETION_DUAL_ALU].valid,
                         u_dut.completion_meta[COMPLETION_DUAL_ALU].producer_id,
                         u_dut.completion_meta[COMPLETION_LSU].valid,
                         u_dut.completion_meta[COMPLETION_LSU].producer_id,
                         u_dut.completion_meta[COMPLETION_MUL].valid,
                         u_dut.completion_meta[COMPLETION_MUL].producer_id,
                         {u_dut.u_ydrasil_issue_stage.u_value_file.completion_write3,
                          u_dut.u_ydrasil_issue_stage.u_value_file.completion_write2,
                          u_dut.u_ydrasil_issue_stage.u_value_file.completion_write1,
                          u_dut.u_ydrasil_issue_stage.u_value_file.completion_write0},
                         u_dut.u_ydrasil_load_store_unit.dtcm_load_fire,
                         u_dut.u_ydrasil_load_store_unit.load_s1_valid_q,
                         u_dut.u_ydrasil_load_store_unit.load_s1_producer_id_q,
                         u_dut.dtcm_reservation.valid,
                         u_dut.dtcm_reservation.producer_id,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_producer_id_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s3_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s3_producer_id_q,
                         u_dut.mdu_due.valid,
                         u_dut.mdu_due.producer_id,
                         u_dut.mdu_result_reservation.valid,
                         u_dut.mdu_result_reservation.producer_id,
                         u_dut.ex_bp_train_pkt.valid,
                         u_dut.ex_bp_train_pkt.producer_id,
                         u_dut.u_ctrl.producer_done_q);
                $display("PERFOP cyc=%0d direct=%0b commit=%0b issue=pc0x%08h/tag%0d src0=used%0b/arch%0d/tv%0b/tag%0d/ready%0b/class%0d/bypass%0d/vf%0b:%0b:0x%08h/arf0x%08h/res0x%08h/dv%0b src1=used%0b/arch%0d/tv%0b/tag%0d/ready%0b/class%0d/bypass%0d/vf%0b:%0b:0x%08h/arf0x%08h/res0x%08h/dv%0b alloc=v%0b/%0b/pc0x%08h:%0d,0x%08h:%0d/target0x%0h:0x%0h/resident%0b%0b%0b%0b",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.select_direct_fire,
                         u_dut.u_ydrasil_issue_stage.select_commit,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.used,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.arch_addr,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.tag_valid,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.producer_tag,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.ready,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0.producer_class,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src0_bypass,
                         u_dut.u_ydrasil_issue_stage.issue_src0_value_valid_i,
                         u_dut.u_ydrasil_issue_stage.issue_src0_epoch_i,
                         u_dut.u_ydrasil_issue_stage.issue_src0_value_i,
                         u_dut.u_ydrasil_issue_stage.rf_rdata_rs1_i,
                         u_dut.u_ydrasil_issue_stage.slot0_src0,
                         u_dut.u_ydrasil_issue_stage.slot0_src0_data_valid,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.used,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.arch_addr,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.tag_valid,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.ready,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_class,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1_bypass,
                         u_dut.u_ydrasil_issue_stage.issue_src1_value_valid_i,
                         u_dut.u_ydrasil_issue_stage.issue_src1_epoch_i,
                         u_dut.u_ydrasil_issue_stage.issue_src1_value_i,
                         u_dut.u_ydrasil_issue_stage.rf_rdata_rs2_i,
                         u_dut.u_ydrasil_issue_stage.slot0_src1,
                         u_dut.u_ydrasil_issue_stage.slot0_src1_data_valid,
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_valid_q[0],
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_valid_q[1],
                         u_dut.u_ydrasil_issue_stage.alloc_fast_uop_q[0].pc,
                         u_dut.u_ydrasil_issue_stage.alloc_fast_uop_q[0].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.alloc_fast_uop_q[1].pc,
                         u_dut.u_ydrasil_issue_stage.alloc_fast_uop_q[1].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_target_q[0],
                         u_dut.u_ydrasil_issue_stage.alloc_wakeup_target_q[1],
                         u_dut.u_ydrasil_issue_stage.dispatch_src0_resident,
                         u_dut.u_ydrasil_issue_stage.dispatch_src1_resident,
                         u_dut.u_ydrasil_issue_stage.dispatch_src2_resident,
                         u_dut.u_ydrasil_issue_stage.dispatch_src3_resident);
                $display("PERFLSU cyc=%0d op=valid%0b/agu%0b/tag%0d/load%0b/store%0b/sdata%0b/sprod%0b:%0d ctrl=stall%0b/bubble%0b/flush%0b/recover%0b/redirect%0b/keep%0b ex=req%0b/tag%0d q=count%0d/head%0d/active%0b/tag%0d/load%0b/store%0b/sdata%0b/sprod%0b:%0d/direct%0b/queued%0b/block%0b sb=count%0d/e0%0b/data%0b/tag%0d/sprod%0b:%0d/ret%0b/e1%0b/data%0b/tag%0d/sprod%0b:%0d/ret%0b shadow=v0x%0h/id%0d,%0d,%0d,%0d,%0d",
                         perf_local_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid,
                         u_dut.u_ydrasil_issue_stage.agu_in_valid_q,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.producer_id,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_load,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_store,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_data_valid,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_producer_tracked,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.store_producer_id,
                         u_dut.stall_id,
                         u_dut.bubble_id,
                         u_dut.flush_id,
                         u_dut.ex_pc_redirect,
                         u_dut.ex_pc_redirect,
                         u_dut.u_ctrl.recovery_live_mask[
                             u_dut.u_ydrasil_issue_stage.agu_in_req_q.producer_id[
                                 PRODUCER_SLOT_WIDTH-1:0]],
                         u_dut.lsu_req_pkt.valid,
                         u_dut.lsu_req_pkt.producer_id,
                         u_dut.u_ydrasil_load_store_unit.queue_count_q,
                         u_dut.u_ydrasil_load_store_unit.queue_head_q,
                         u_dut.u_ydrasil_load_store_unit.active_valid,
                         u_dut.u_ydrasil_load_store_unit.active_producer_id,
                         u_dut.u_ydrasil_load_store_unit.active_is_load,
                         u_dut.u_ydrasil_load_store_unit.active_is_store,
                         u_dut.u_ydrasil_load_store_unit.active_store_data_valid,
                         u_dut.u_ydrasil_load_store_unit.active_pkt.store_producer_tracked,
                         u_dut.u_ydrasil_load_store_unit.active_pkt.store_producer_id,
                         1'b0,
                         u_dut.u_ydrasil_load_store_unit.queued_dtcm_load_candidate,
                         u_dut.u_ydrasil_load_store_unit.load_store_data_block,
                         u_dut.u_ydrasil_load_store_unit.store_buf_count_q,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.valid,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_data_valid,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.producer_id,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_producer_tracked,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.store_producer_id,
                         u_dut.u_ydrasil_load_store_unit.store_buf0_q.retired,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.valid,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_data_valid,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.producer_id,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_producer_tracked,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.store_producer_id,
                         u_dut.u_ydrasil_load_store_unit.store_buf1_q.retired,
                         {u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[4],
                          u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[3],
                          u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[2],
                          u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[1],
                          u_dut.u_ydrasil_load_store_unit.completion_shadow_valid_q[0]},
                         u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[0],
                         u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[1],
                         u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[2],
                         u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[3],
                         u_dut.u_ydrasil_load_store_unit.completion_shadow_id_q[4]);
                if (u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid &&
                    (u_dut.u_ydrasil_issue_stage.issue_pkt_i.op_class ==
                     UOP_CLASS_STORE))
                    $display("PERFSTORE cyc=%0d tag=%0d src=%0d ready=%0b state=live%0b/done%0b vf_epoch=%0b vf_match=%0b tracked_late=%0b early=main%0b/dual%0b data=0x%08h",
                             perf_local_debug_cycle,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.dst.rob_tag,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag,
                             u_dut.u_ydrasil_issue_stage.src1_ready,
                             u_dut.u_ctrl.producer_valid_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ctrl.producer_done_q[
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_SLOT_WIDTH-1:0]],
                             u_dut.u_ydrasil_issue_stage.issue_src1_epoch_i,
                             u_dut.u_ydrasil_issue_stage.issue_src1_epoch_i ==
                                 u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1.producer_tag[
                                     PRODUCER_ID_WIDTH-1],
                             u_dut.u_ydrasil_issue_stage.shared_agu_req_d.
                                 store_producer_tracked,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1_bypass ==
                                 BYPASS_LANE0,
                             u_dut.u_ydrasil_issue_stage.issue_pkt_i.src1_bypass ==
                                 BYPASS_LANE1,
                             u_dut.u_ydrasil_issue_stage.slot0_src1_local);
            end
        end
    end

    // A bounded, opt-in forward-progress snapshot.  This is intentionally
    // event driven so a deadlock diagnosis does not require a multi-million
    // line commit trace or waveform.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            perf_stall_snapshot_cycles_q <= 0;
            perf_stall_snapshot_printed_q <= 1'b0;
        end else if (u_dut.commit_pkt.valid || u_dut.commit_pkt1.valid) begin
            perf_stall_snapshot_cycles_q <= 0;
            perf_stall_snapshot_printed_q <= 1'b0;
        end else if (perf_stall_snapshot_en) begin
            if (perf_stall_snapshot_cycles_q < perf_stall_snapshot_threshold)
                perf_stall_snapshot_cycles_q <=
                    perf_stall_snapshot_cycles_q + 1;
            if (!perf_stall_snapshot_printed_q &&
                (perf_stall_snapshot_cycles_q >=
                 (perf_stall_snapshot_threshold - 1))) begin
                perf_stall_snapshot_printed_q <= 1'b1;
                $display("PERF_STALL_SNAPSHOT: CYCLE=%0d NO_RETIRE=%0d ROB_HEAD_ID=%0d ROB_HEAD_SLOT=%0d ROB_HEAD_PC=0x%08h ROB_COUNT=%0d ROB_VALID=0x%0h ROB_DONE=0x%0h ROB_ISSUED=0x%0h",
                         perf_local_debug_cycle,
                         perf_stall_snapshot_threshold,
                         u_dut.u_ctrl.queue_head_id,
                         u_dut.u_ctrl.queue_head_q,
                         u_dut.u_ctrl.producer_pc_q[u_dut.u_ctrl.queue_head_q],
                         u_dut.u_ctrl.queue_count_q,
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.producer_done_q,
                         perf_producer_issued_q);
                $display("PERF_STALL_LSU: CREDIT=%0d RESERVED=%0d QUEUE_COUNT=%0d QUEUE_HEAD=%0d ACTIVE_VALID=%0b ACTIVE_ID=%0d ACTIVE_SLOT=%0d ACTIVE_ADDR=0x%08h ACTIVE_DTCM=%0b ACTIVE_SAFE=%0b SECOND_VALID=%0b SECOND_ID=%0d SECOND_SLOT=%0d SECOND_ADDR=0x%08h SECOND_DTCM=%0b AGE_REPAIR=%0b",
                         u_dut.lsu_issue_credit,
                         u_dut.u_ydrasil_issue_stage.lsu_select_reserved_q,
                         u_dut.u_ydrasil_load_store_unit.queue_count_q,
                         u_dut.u_ydrasil_load_store_unit.queue_head_q,
                         u_dut.u_ydrasil_load_store_unit.active_valid,
                         u_dut.u_ydrasil_load_store_unit.active_pkt.producer_id,
                         u_dut.u_ydrasil_load_store_unit.active_pkt.producer_id[
                             PRODUCER_SLOT_WIDTH-1:0],
                         u_dut.u_ydrasil_load_store_unit.active_pkt.addr,
                         u_dut.u_ydrasil_load_store_unit.active_pkt.addr_is_dtcm,
                         u_dut.u_ydrasil_load_store_unit.active_mmio_order_safe,
                         u_dut.u_ydrasil_load_store_unit.second_pkt.valid,
                         u_dut.u_ydrasil_load_store_unit.second_pkt.producer_id,
                         u_dut.u_ydrasil_load_store_unit.second_pkt.producer_id[
                             PRODUCER_SLOT_WIDTH-1:0],
                         u_dut.u_ydrasil_load_store_unit.second_pkt.addr,
                         u_dut.u_ydrasil_load_store_unit.second_pkt.addr_is_dtcm,
                         u_dut.u_ydrasil_load_store_unit.queue_age_repair);
                for (perf_stall_snapshot_idx = 0;
                     perf_stall_snapshot_idx < 12;
                     perf_stall_snapshot_idx = perf_stall_snapshot_idx + 1) begin
                    if (u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                            perf_stall_snapshot_idx])
                        $display("PERF_STALL_RS: ENTRY=%0d TAG=%0d SLOT=%0d PC=0x%08h SRC_READY=%0b%0b DEP=%0b ORDER=%0b RESOURCE=%0b CANDIDATE=%0b SELECTED=%0b MEMORY=%0b STORE=%0b ORDER_MASK=0x%0h",
                                 perf_stall_snapshot_idx,
                                 u_dut.u_ydrasil_issue_stage.issue_window_q[
                                     perf_stall_snapshot_idx].dst.rob_tag,
                                 u_dut.u_ydrasil_issue_stage.issue_window_q[
                                     perf_stall_snapshot_idx].dst.rob_tag[
                                         PRODUCER_SLOT_WIDTH-1:0],
                                 u_dut.u_ydrasil_issue_stage.issue_window_q[
                                     perf_stall_snapshot_idx].pc,
                                 u_dut.u_ydrasil_issue_stage.
                                     issue_src0_ready_for_select[
                                         perf_stall_snapshot_idx],
                                 u_dut.u_ydrasil_issue_stage.
                                     issue_src1_ready_for_select[
                                         perf_stall_snapshot_idx],
                                 perf_rs_dep_mask_now[perf_stall_snapshot_idx],
                                 perf_rs_order_mask_now[perf_stall_snapshot_idx],
                                 perf_rs_resource_mask_now[
                                     perf_stall_snapshot_idx],
                                 perf_rs_candidate_mask_now[
                                     perf_stall_snapshot_idx],
                                 perf_rs_selected_mask_now[
                                     perf_stall_snapshot_idx],
                                 u_dut.u_ydrasil_issue_stage.issue_memory_q[
                                     perf_stall_snapshot_idx],
                                 u_dut.u_ydrasil_issue_stage.issue_store_q[
                                     perf_stall_snapshot_idx],
                                 u_dut.u_ydrasil_issue_stage.issue_order_mask_q[
                                     perf_stall_snapshot_idx]);
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            raw_debug_cycle <= 0;
        end else if (raw_debug_en && (raw_debug_cycle < 700)) begin
            raw_debug_cycle <= raw_debug_cycle + 1;
            if (u_dut.ex_pc_redirect || u_dut.branch_jump)
                $display("RAWDBG cyc=%0d REDIRECT ex=%0b branch=%0b target=0x%08h head=%0d valid=0x%0h keep=0x%0h",
                         raw_debug_cycle, u_dut.ex_pc_redirect,
                         u_dut.branch_jump, u_dut.ex_pc_redirect_target,
                         u_dut.u_ctrl.queue_head_q,
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.recovery_live_mask);
            if (u_dut.ex_pc_redirect)
                $display("RAWDBG cyc=%0d KILL flush_ex=%0b mul_redirect=%0b mul_keep=0x%0h s2=%0b/%0d",
                         raw_debug_cycle, u_dut.flush_ex,
                         1'b0,
                         {PRODUCER_NUM{1'b0}},
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_producer_id_q);
            if (u_dut.u_ydrasil_issue_stage.lane_b_accept &&
                (u_dut.u_ydrasil_issue_stage.lane_b_uop.op_class == UOP_CLASS_MUL))
                $display("RAWDBG cyc=%0d ACCEPT_MUL pc=0x%08h id=%0d rd=%0d op=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.pc,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.dst.rd_addr,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.subop);
            if (u_dut.u_ydrasil_issue_stage.lane_b_bru_accept)
                $display("RAWDBG cyc=%0d ACCEPT_BR pc=0x%08h id=%0d a=0x%08h b=0x%08h src0=0x%08h src1=0x%08h tags=%0d/%0d dual=0x%08h/0x%08h cmul=%0b/%0d/0x%08h mdu_due=%0b/%0d mdu_res=%0b/%0d bypass=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.pc,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.lane_b_operand_a_capture,
                         u_dut.u_ydrasil_issue_stage.lane_b_operand_b_capture,
                         u_dut.u_ydrasil_issue_stage.lane_b_src0_local,
                         u_dut.u_ydrasil_issue_stage.lane_b_src1_local,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.src0.producer_tag,
                         u_dut.u_ydrasil_issue_stage.lane_b_uop.src1.producer_tag,
                         u_dut.dual_bru_operand_a,
                         u_dut.dual_bru_operand_b,
                         u_dut.completion_meta[COMPLETION_MUL].valid,
                         u_dut.completion_meta[COMPLETION_MUL].producer_id,
                         u_dut.completion_data[COMPLETION_MUL],
                         u_dut.mdu_due.valid, u_dut.mdu_due.producer_id,
                         u_dut.mdu_result_reservation.valid,
                         u_dut.mdu_result_reservation.producer_id,
                         u_dut.mdu_bypass_data);
            if (u_dut.dual_bru_valid)
                $display("RAWDBG cyc=%0d BRU_INPUT pc=0x%08h id=%0d subop=%0d op=0x%0h a=0x%08h b=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.pc,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.producer_id,
                         u_dut.u_ydrasil_issue_stage.dual_bru_payload_q.subop,
                         u_dut.u_ydrasil_issue_stage.lane_b_operator_info,
                         u_dut.dual_bru_operand_a,
                         u_dut.dual_bru_operand_b);
            if (u_dut.mul_in_valid)
                $display("RAWDBG cyc=%0d MUL_INPUT id=%0d rd=%0d op=0x%0h a=0x%08h b=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.producer_id,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.rd_addr,
                         u_dut.mul_in_operator,
                         u_dut.mul_in_operand_a, u_dut.mul_in_operand_b);
            if (u_dut.alu_in_valid)
                $display("RAWDBG cyc=%0d ALU_INPUT pc=0x%08h id=%0d rd=%0d op=0x%0h a=0x%08h b=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.lane_a_pc_q,
                         u_dut.alu_in_producer_id,
                         u_dut.alu_in_rd_addr,
                         u_dut.alu_in_operator,
                         u_dut.alu_in_operand_a,
                         u_dut.alu_in_operand_b);
            if (u_dut.dual_alu_valid)
                $display("RAWDBG cyc=%0d DUAL_ALU_INPUT pc=0x%08h id=%0d rd=%0d op=0x%0h a=0x%08h b=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.pc,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.producer_id,
                         u_dut.u_ydrasil_issue_stage.dual_meta_q.rd_addr,
                         u_dut.u_ydrasil_issue_stage.dual_alu_payload_q.subop,
                         u_dut.dual_alu_operand_a,
                         u_dut.dual_alu_operand_b);
            if (u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s0_valid_q ||
                u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s1_valid_q ||
                u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_valid_q ||
                u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s3_valid_q)
                $display("RAWDBG cyc=%0d MUL_PIPE s0=%0b/%0d s1=%0b/%0d s2=%0b/%0d s3=%0b/%0d",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s0_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s0_producer_id_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s1_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s1_producer_id_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s2_producer_id_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s3_valid_q,
                         u_dut.u_ydrasil_execute_stage.u_main_ex.u_ydrasil_mul.s3_producer_id_q);
            if (u_dut.completion_meta[COMPLETION_MUL].valid ||
                u_dut.completion_meta[COMPLETION_LSU].valid)
                $display("RAWDBG cyc=%0d COMPLETE mul=%0b/%0d/%0d lsu=%0b/%0d/%0d valid=0x%0h done=0x%0h",
                         raw_debug_cycle,
                         u_dut.completion_meta[COMPLETION_MUL].valid,
                         u_dut.completion_meta[COMPLETION_MUL].producer_id,
                         u_dut.completion_rd[COMPLETION_MUL],
                         u_dut.completion_meta[COMPLETION_LSU].valid,
                         u_dut.completion_meta[COMPLETION_LSU].producer_id,
                         u_dut.completion_rd[COMPLETION_LSU],
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.producer_done_q);
            if (u_dut.completion_meta[COMPLETION_ALU].valid ||
                u_dut.completion_meta[COMPLETION_DUAL_ALU].valid)
                $display("RAWDBG cyc=%0d COMPLETE alu=%0b/%0d/%0d dual=%0b/%0d/%0d data=0x%08h/0x%08h",
                         raw_debug_cycle,
                         u_dut.completion_meta[COMPLETION_ALU].valid,
                         u_dut.completion_meta[COMPLETION_ALU].producer_id,
                         u_dut.completion_rd[COMPLETION_ALU],
                         u_dut.completion_meta[COMPLETION_DUAL_ALU].valid,
                         u_dut.completion_meta[COMPLETION_DUAL_ALU].producer_id,
                         u_dut.completion_rd[COMPLETION_DUAL_ALU],
                         u_dut.completion_data[COMPLETION_ALU],
                         u_dut.completion_data[COMPLETION_DUAL_ALU]);
            if (u_dut.u_ydrasil_issue_stage.agu_in_valid_q)
                $display("RAWDBG cyc=%0d LSU_INPUT id=%0d rd=%0d load=%0b store=%0b addr=0x%08h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.producer_id,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.rd_addr,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_load,
                         u_dut.u_ydrasil_issue_stage.agu_in_req_q.is_store,
                         u_dut.u_ydrasil_issue_stage.agu_in_operand_a_q +
                         u_dut.u_ydrasil_issue_stage.agu_in_operand_b_q);
            if (u_dut.u_ydrasil_load_store_unit.dtcm_load_fire ||
                u_dut.u_ydrasil_load_store_unit.load_s1_valid_q ||
                u_dut.ex_pc_redirect)
                $display("RAWDBG cyc=%0d LSU_PIPE req=%0b/%0d fire=%0b direct=%0b queued=%0b s1=%0b/%0d keep=%0b recovery=%0b completion=%0b/%0d",
                         raw_debug_cycle,
                         u_dut.lsu_req_pkt.valid,
                         u_dut.lsu_req_pkt.producer_id,
                         u_dut.u_ydrasil_load_store_unit.dtcm_load_fire,
                         1'b0,
                         u_dut.u_ydrasil_load_store_unit.queued_dtcm_load_fire,
                         u_dut.u_ydrasil_load_store_unit.load_s1_valid_q,
                         u_dut.u_ydrasil_load_store_unit.load_s1_producer_id_q,
                         u_dut.u_ctrl.recovery_live_mask[
                             u_dut.u_ydrasil_load_store_unit.load_s1_producer_id_q[
                                 PRODUCER_SLOT_WIDTH-1:0]],
                         u_dut.ex_pc_redirect,
                         u_dut.lsu_completion_valid,
                         u_dut.lsu_completion_producer_id);
            if (u_dut.id_fence_i ||
                u_dut.u_ydrasil_issue_stage.issue_fence_accept ||
                u_dut.pipeline_flush ||
                perf_serial_pending)
                $display("RAWDBG cyc=%0d FENCE accept=%0b pulse=%0b tag=%0d next=0x%08h pipe_flush=%0b serial=%0b/%0d/%08h head=%0d lsu_idle=%0b",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_fence_accept,
                         u_dut.id_fence_i,
                         u_dut.issue_fence_tag,
                         u_dut.issue_fence_next_pc,
                         u_dut.pipeline_flush,
                         perf_serial_pending,
                         perf_serial_tag,
                         perf_serial_pc,
                         u_dut.rob_head_id,
                         u_dut.lsu_status_pkt.idle);
            if ((raw_debug_cycle >= 190) && (raw_debug_cycle <= 220))
                $display("RAWDBG cyc=%0d IF pc=0x%08h mem=%0b/0x%08h pending=%0b/0x%08h fq=%0d id=%0b/0x%08h instr=0x%08h decode_ready=%0b flush=%0b bp_inv=%0b",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_if_stage.pc_q,
                         u_dut.u_ydrasil_if_stage.mem_req_valid_q,
                         u_dut.u_ydrasil_if_stage.mem_req_pc_q,
                         u_dut.u_ydrasil_if_stage.pending_redirect_valid_q,
                         u_dut.u_ydrasil_if_stage.pending_redirect_target_q,
                         u_dut.u_ydrasil_if_stage.fetchq_count_q,
                         u_dut.if_id_valid,
                         u_dut.if_id_pc,
                         u_dut.if_id_instr,
                         u_dut.decode_if_ready,
                         u_dut.flush_if,
                         u_dut.id_fence_i);
            if ((raw_debug_cycle >= 206) && (raw_debug_cycle <= 235))
                $display("RAWDBG cyc=%0d STATE issue=%0b/%0h/%0d ready=%0b waits=%0b%0b%0b%0b cand=%0b%0b/%0b/%0b qhead=%0d/0x%08h qcnt=%0d commit=%0b%0b disp=%0b valid=0x%0h readyq=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_ready_o,
                         u_dut.u_ydrasil_issue_stage.src0_wait_o,
                         u_dut.u_ydrasil_issue_stage.src1_wait_o,
                         u_dut.u_ydrasil_issue_stage.src2_wait_o,
                         u_dut.u_ydrasil_issue_stage.src3_wait_o,
                         u_dut.u_ydrasil_issue_stage.p0_select_valid,
                         u_dut.u_ydrasil_issue_stage.p1_select_valid,
                         u_dut.u_ydrasil_issue_stage.alu_select0_valid,
                         u_dut.u_ydrasil_issue_stage.alu_select1_valid,
                         u_dut.u_ctrl.queue_head_q,
                         u_dut.u_ctrl.producer_pc_q[u_dut.u_ctrl.queue_head_q],
                         u_dut.u_ctrl.queue_count_q,
                         u_dut.u_ctrl.queue_commit0,
                         u_dut.u_ctrl.queue_commit1,
                         u_dut.u_ydrasil_issue_stage.dispatch_ready_i,
                         u_dut.u_ctrl.producer_valid_q,
                         u_dut.u_ctrl.producer_done_q);
            if ((raw_debug_cycle >= 194) && (raw_debug_cycle <= 205))
                $display("RAWDBG cyc=%0d EXCTRL flush=%0b trap=%0b exv=%0b/%0b alucomp=%0b/%0d/%0d dualcomp=%0b/%0d/%0d",
                         raw_debug_cycle,
                         u_dut.flush_ex,
                         u_dut.trap_ctrl_pkt.redirect,
                         u_dut.ex_accept_valid,
                         u_dut.ex_accept_valid1,
                         u_dut.alu_completion_valid,
                         u_dut.alu_completion_producer_id,
                         u_dut.alu_completion_addr,
                         u_dut.dual_completion_valid,
                         u_dut.dual_completion_producer_id,
                         u_dut.dual_completion_addr);
            if ((raw_debug_cycle >= 208) && (raw_debug_cycle <= 212)) begin
                $display("RAWDBG cyc=%0d RS0 v/r=%0b/%0b%0b pc=0x%08h tag=%0d ord=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[0],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[0],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[0],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[0].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[0].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[0]);
                $display("RAWDBG cyc=%0d RS1 v/r=%0b/%0b%0b pc=0x%08h tag=%0d ord=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[1],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[1],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[1],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[1].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[1].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[1]);
                $display("RAWDBG cyc=%0d RS2 v/r=%0b/%0b%0b pc=0x%08h tag=%0d ord=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[2],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[2],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[2],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[2].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[2].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[2]);
                $display("RAWDBG cyc=%0d RS3 v/r=%0b/%0b%0b pc=0x%08h tag=%0d ord=0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[3],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[3],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[3],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[3].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[3].dst.rob_tag,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[3]);
                $display("RAWDBG cyc=%0d RS4-6 v=0x%0b%0b%0b r0=%0b%0b%0b r1=%0b%0b%0b pc=0x%08h/0x%08h/0x%08h ord=0x%0h/0x%0h/0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[6],
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[5],
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[4],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[6],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[5],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[4],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[6],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[5],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[4],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[4].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[5].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[6].pc,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[4],
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[5],
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[6]);
                $display("RAWDBG cyc=%0d RS7-9 v=0x%0b%0b%0b r0=%0b%0b%0b r1=%0b%0b%0b pc=0x%08h/0x%08h/0x%08h ord=0x%0h/0x%0h/0x%0h",
                         raw_debug_cycle,
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[9],
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[8],
                         u_dut.u_ydrasil_issue_stage.issue_window_valid_q[7],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[9],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[8],
                         u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[7],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[9],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[8],
                         u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[7],
                         u_dut.u_ydrasil_issue_stage.issue_window_q[7].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[8].pc,
                         u_dut.u_ydrasil_issue_stage.issue_window_q[9].pc,
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[7],
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[8],
                         u_dut.u_ydrasil_issue_stage.issue_order_mask_q[9]);
            end
        end
    end
`endif

	`ifndef VERILATOR_CC
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
            $display("[TB] stall dependency=%0b lsu_struct=%0b clint=%0b wb=%0b stall_if=%0b stall_id=%0b bubble_id=%0b id_ex_valid=%0b",
                     u_dut.u_ydrasil_commit_trace.dependency_wait,
                     u_dut.u_ydrasil_commit_trace.lsu_struct_stall,
                     u_dut.u_ydrasil_commit_trace.clint_stall,
                     u_dut.u_ydrasil_commit_trace.wb_backpressure,
                     u_dut.stall_if,
                     u_dut.stall_id,
                     u_dut.bubble_id,
                     u_dut.id_ex_valid);
            $display("[TB] operand rs1=%0d used1=%0b wait1=%0b rs2=%0d used2=%0b wait2=%0b rd=%0d wen=%0b dependency=%0b lsu_req=%0b lsu_busy=%0b",
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rs1_addr,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rs1_ren,
                     u_dut.issue_src0_wait,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rs2_addr,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rs2_ren,
                     u_dut.issue_src1_wait,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rd_addr,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_rd_wen,
                     u_dut.issue_dependency_wait,
                     u_dut.u_ydrasil_commit_trace.id_ctrl_lsu_req,
                     u_dut.u_ydrasil_commit_trace.lsu_ctrl_busy);
            $display("[TB] rs_valid=0x%03h rob_valid=0x%03h ex_accept=%0b id_rd_issue=%0b rf_wen=%0b rf_waddr=%0d alu_wen=%0b alu_waddr=%0d lsu_wen=%0b lsu_waddr=%0d mul_wen=%0b mul_waddr=%0d",
                     u_dut.u_ydrasil_issue_stage.issue_window_valid_q,
                     u_dut.u_ctrl.producer_valid_q,
                     u_dut.ex_accept_valid,
                     u_dut.u_ydrasil_commit_trace.id_ex_rd_issue,
                     u_dut.u_ydrasil_commit_trace.rf_wen_rd,
                     u_dut.u_ydrasil_commit_trace.rf_waddr_rd,
                     u_dut.alu_rf_wen_rd,
                     u_dut.alu_rf_waddr_rd,
                     u_dut.u_ydrasil_commit_trace.lsu_rf_wen_rd,
                     u_dut.u_ydrasil_commit_trace.lsu_rf_waddr_rd,
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
            stall_dependency_count <= 32'b0;
            stall_lsu_struct_count <= 32'b0;
            stall_wb_backpressure_count <= 32'b0;
            stall_clint_count <= 32'b0;
            stall_mul_count <= 32'b0;
            dep_rs1_pending_count <= 32'b0;
            dep_rs2_pending_count <= 32'b0;
            dep_rd_waw_count <= 32'b0;
            dep_issue_rs1_hzd_count <= 32'b0;
            dep_issue_rs2_hzd_count <= 32'b0;
            dep_issue_rd_hzd_count <= 32'b0;
            dep_load_use_count <= 32'b0;
            dep_alu_use_count <= 32'b0;
            dep_mul_div_use_count <= 32'b0;
            dep_branch_src_wait_count <= 32'b0;
            dep_store_addr_wait_count <= 32'b0;
            dep_store_data_wait_count <= 32'b0;
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
            dep_load_to_alu_count <= 32'b0;
            dep_load_to_branch_count <= 32'b0;
            dep_load_to_load_count <= 32'b0;
            dep_load_to_store_count <= 32'b0;
            dep_load_to_mul_count <= 32'b0;
            dep_load_to_other_count <= 32'b0;
            dep_load_rs1_count <= 32'b0;
            dep_load_rs2_count <= 32'b0;
            dep_pending_tail_count <= 32'b0;
            dep_alu_to_alu_count <= 32'b0;
            dep_alu_to_branch_count <= 32'b0;
            dep_alu_to_load_count <= 32'b0;
            dep_alu_to_store_count <= 32'b0;
            dep_alu_to_mul_count <= 32'b0;
            dep_alu_to_other_count <= 32'b0;
            dep_pending_alu_count <= 32'b0;
            dep_pending_load_count <= 32'b0;
            dep_pending_mul_count <= 32'b0;
            dep_pending_other_count <= 32'b0;
            dep_ready_but_stall_count <= 32'b0;
            dep_complete_visible_count <= 32'b0;
            dep_registered_visible_count <= 32'b0;
            mul_tail_slot_release_late_count <= 32'b0;
            mul_tail_ready_late_count <= 32'b0;
            mul_tail_consumer_no_bypass_count <= 32'b0;
            acct_flush_count <= 32'b0;
            acct_mul_hold_count <= 32'b0;
            acct_dependency_count <= 32'b0;
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
            perf_productive_slot_count <= 32'b0;
            perf_executed_slot0_count <= 32'b0;
            perf_executed_slot1_count <= 32'b0;
            perf_ex_branch_drop0_count <= 32'b0;
            perf_ex_branch_drop1_count <= 32'b0;
            perf_ex_mul_drop0_count <= 32'b0;
            perf_ex_mul_drop1_count <= 32'b0;
            perf_ex_empty0_count <= 32'b0;
            perf_ex_empty1_count <= 32'b0;
            perf_ex_empty_reset_count <= 32'b0;
            perf_ex_empty_recovery_count <= 32'b0;
            perf_ex_empty_fence_count <= 32'b0;
            perf_ex_empty_b_only_count <= 32'b0;
            perf_ex_empty_single_head_count <= 32'b0;
            perf_ex_empty_select_refill_count <= 32'b0;
            perf_ex_empty_rs_dependency_count <= 32'b0;
            perf_ex_empty_rs_order_count <= 32'b0;
            perf_ex_empty_rs_resource_count <= 32'b0;
            perf_ex_empty_rs_no_candidate_count <= 32'b0;
            perf_ex_empty_rs_empty_count <= 32'b0;
            perf_ex_empty_frontend_count <= 32'b0;
            perf_ex_empty_other_count <= 32'b0;
            perf_ex_empty_launch_mismatch_count <= 32'b0;
            perf_ex_empty_unmapped_count <= 32'b0;
            perf_ex_valid_hold0_count <= 32'b0;
            perf_ex_valid_hold1_count <= 32'b0;
            perf_src_kind0_q <= PERF_SRC_RESET;
            perf_src_kind1_q <= PERF_SRC_RESET;
            perf_select_reason_q <= PERF_SEL_REASON_OTHER;
            perf_lost_flush_slot_count <= 32'b0;
            perf_lost_mul_hold_slot_count <= 32'b0;
            perf_lost_dependency_slot_count <= 32'b0;
            perf_lost_lsu_struct_slot_count <= 32'b0;
            perf_lost_lsu_serialize_slot_count <= 32'b0;
            perf_lost_producer_full_slot_count <= 32'b0;
            perf_lost_wb_slot_count <= 32'b0;
            perf_lost_clint_slot_count <= 32'b0;
            perf_lost_multi_slot_count <= 32'b0;
            perf_lost_no_if_valid_slot_count <= 32'b0;
            perf_lost_issue_slot_count <= 32'b0;
            perf_lost_other_slot_count <= 32'b0;
            noif_control_redirect_count <= 32'b0;
            noif_predict_redirect_count <= 32'b0;
            noif_fence_refill_count <= 32'b0;
            noif_mem_response_count <= 32'b0;
            noif_fetch_launch_count <= 32'b0;
            noif_pending_redirect_count <= 32'b0;
            noif_other_count <= 32'b0;
            perf_noif_control_redirect_slots <= 32'b0;
            perf_noif_predict_redirect_slots <= 32'b0;
            perf_noif_fence_refill_slots <= 32'b0;
            perf_noif_mem_response_slots <= 32'b0;
            perf_noif_fetch_launch_slots <= 32'b0;
            perf_noif_pending_redirect_slots <= 32'b0;
            perf_noif_other_slots <= 32'b0;
            other_issue_refill_count <= 32'b0;
            other_decode_refill_count <= 32'b0;
            decode_refill_after_control_count <= 32'b0;
            decode_refill_after_predict_count <= 32'b0;
            decode_refill_after_fence_count <= 32'b0;
            decode_refill_after_supply_count <= 32'b0;
            other_issue_blocked_count <= 32'b0;
            other_unclassified_count <= 32'b0;
            perf_issue_dependency_slots <= 32'b0;
            perf_issue_lsu_struct_slots <= 32'b0;
            perf_issue_serialize_slots <= 32'b0;
            perf_issue_single_lane_slots <= 32'b0;
            perf_issue_no_execute_slots <= 32'b0;
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
            retire_four_count <= 32'b0;
            dual_issue_count <= 32'b0;
            dual_alu_alu_count <= 32'b0;
            dual_bru_alu_count <= 32'b0;
            dual_lsu_alu_count <= 32'b0;
            dual_muldiv_alu_count <= 32'b0;
            dual_other_count <= 32'b0;
            l0_lookup_count <= 32'b0;
            l0_hit_count <= 32'b0;
            l0_correction_count <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 32; perf_stat_idx = perf_stat_idx + 1)
                bubble_cause_hist[perf_stat_idx] <= 32'b0;
            producer_occ_zero_count <= 32'b0;
            producer_occ_one_count <= 32'b0;
            producer_occ_two_count <= 32'b0;
            producer_both_wait_count <= 32'b0;
            producer_wait_ready_count <= 32'b0;
            producer_both_ready_count <= 32'b0;
            producer_retire_held_count <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx <= PRODUCER_NUM;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_rob_occ_count[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx <= 12;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_rs_occ_count[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx <= 2;
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_rs_alloc_count[perf_stat_idx] <= 32'b0;
                perf_operand_count[perf_stat_idx] <= 32'b0;
                perf_retire_count[perf_stat_idx] <= 32'b0;
            end
            for (perf_stat_idx = 0; perf_stat_idx <= 2;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_select_count[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx <= 4;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_complete_count[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx <= 15;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_candidate_mask_count[perf_stat_idx] <= 32'b0;
            perf_head_empty_count <= 32'b0;
            perf_head_retire1_count <= 32'b0;
            perf_head_retire2_count <= 32'b0;
            perf_head_complete_visible_count <= 32'b0;
            perf_head_not_issued_count <= 32'b0;
            perf_head_wait_alu_count <= 32'b0;
            perf_head_wait_load_count <= 32'b0;
            perf_head_wait_mdu_count <= 32'b0;
            perf_head_wait_store_count <= 32'b0;
            perf_head_wait_branch_count <= 32'b0;
            perf_head_wait_other_count <= 32'b0;
            perf_head_ni_select_transit_count <= 32'b0;
            perf_head_ni_rs_dependency_count <= 32'b0;
            perf_head_ni_rs_order_count <= 32'b0;
            perf_head_ni_rs_resource_count <= 32'b0;
            perf_head_ni_rs_ready_count <= 32'b0;
            perf_head_ni_absent_count <= 32'b0;
            perf_loss_flush_slots <= 32'b0;
            perf_loss_operand_block_slots <= 32'b0;
            perf_loss_single_bundle_slots <= 32'b0;
            perf_loss_select_refill_slots <= 32'b0;
            perf_loss_rs_dependency_slots <= 32'b0;
            perf_loss_rs_order_slots <= 32'b0;
            perf_loss_rs_resource_slots <= 32'b0;
            perf_loss_rs_other_slots <= 32'b0;
            perf_loss_rob_full_slots <= 32'b0;
            perf_loss_rs_refill_slots <= 32'b0;
            perf_loss_decode_refill_slots <= 32'b0;
            perf_loss_frontend_slots <= 32'b0;
            perf_loss_other_slots <= 32'b0;
            perf_single_p0_only_slots <= 32'b0;
            perf_single_p1_only_slots <= 32'b0;
            perf_single_alu_only_slots <= 32'b0;
            perf_single_serial_slots <= 32'b0;
            perf_single_other_slots <= 32'b0;
            perf_select_refill_pair_slots <= 32'b0;
            perf_select_refill_p0_slots <= 32'b0;
            perf_select_refill_p1_slots <= 32'b0;
            perf_select_refill_alu_slots <= 32'b0;
            perf_select_refill_serial_slots <= 32'b0;
            perf_select_refill_other_slots <= 32'b0;
            perf_dep_src0_slots <= 32'b0;
            perf_dep_src1_slots <= 32'b0;
            perf_dep_both_src_slots <= 32'b0;
            perf_dep_completion_wakeup_slots <= 32'b0;
            perf_dep_alloc_wakeup_slots <= 32'b0;
            perf_dep_load_slots <= 32'b0;
            perf_dep_mul_slots <= 32'b0;
            perf_dep_branch_slots <= 32'b0;
            perf_dep_other_slots <= 32'b0;
            perf_single_op_alu_slots <= 32'b0;
            perf_single_op_load_slots <= 32'b0;
            perf_single_op_store_slots <= 32'b0;
            perf_single_op_mul_slots <= 32'b0;
            perf_single_op_csr_sys_slots <= 32'b0;
            perf_single_op_other_slots <= 32'b0;
            perf_refill_shape_p0_p1_slots <= 32'b0;
            perf_refill_shape_p0_alu_slots <= 32'b0;
            perf_refill_shape_p1_alu_slots <= 32'b0;
            perf_refill_shape_alu_alu_slots <= 32'b0;
            perf_refill_shape_single_p0_slots <= 32'b0;
            perf_refill_shape_single_p1_slots <= 32'b0;
            perf_refill_shape_single_alu_slots <= 32'b0;
            perf_refill_shape_serial_slots <= 32'b0;
            perf_refill_shape_other_slots <= 32'b0;
            perf_dep_wake_both_slots <= 32'b0;
            perf_dep_wake_mixed_slots <= 32'b0;
            perf_dep_wake_src0_completion_slots <= 32'b0;
            perf_dep_wake_src1_completion_slots <= 32'b0;
            perf_dep_wake_src0_alloc_slots <= 32'b0;
            perf_dep_wake_src1_alloc_slots <= 32'b0;
            perf_dep_wake_none_slots <= 32'b0;
            perf_dep_op_alu_slots <= 32'b0;
            perf_dep_op_load_slots <= 32'b0;
            perf_dep_op_store_slots <= 32'b0;
            perf_dep_op_mul_slots <= 32'b0;
            perf_dep_op_branch_slots <= 32'b0;
            perf_dep_op_other_slots <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 32;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_dep_blocker_mask_slots[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 5;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_dep_blocker_operand_cycles[perf_stat_idx] <= 32'b0;
            perf_other_rob_block_slots <= 32'b0;
            perf_other_rs_bank_block_slots <= 32'b0;
            perf_other_recovery_resync_slots <= 32'b0;
            perf_other_alu_bank_block_slots <= 32'b0;
            perf_other_p0_bank_block_slots <= 32'b0;
            perf_other_p1_bank_block_slots <= 32'b0;
            perf_bank_alu_local_full_slots <= 32'b0;
            perf_bank_alu_credit_stale_slots <= 32'b0;
            perf_bank_p0_local_full_slots <= 32'b0;
            perf_bank_p0_credit_stale_slots <= 32'b0;
            perf_bank_p1_local_full_slots <= 32'b0;
            perf_bank_p1_credit_stale_slots <= 32'b0;
            perf_bank_unclassified_slots <= 32'b0;
            perf_p0_full_dependency_slots <= 32'b0;
            perf_p0_full_order_slots <= 32'b0;
            perf_p0_full_resource_slots <= 32'b0;
            perf_p0_full_ready_release_slots <= 32'b0;
            perf_p0_full_no_candidate_slots <= 32'b0;
            perf_p0_pipe_selectable_slots <= 32'b0;
            perf_p0_pipe_credit_blocked_slots <= 32'b0;
            perf_p0_pipe_order_blocked_slots <= 32'b0;
            perf_p0_pipe_dependency_blocked_slots <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 9;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_p0_credit_resv_slots[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 5;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_p0_full_store_mix_slots[perf_stat_idx] <= 32'b0;
            perf_p0_full_blocked_load_slots <= 32'b0;
            perf_p0_full_blocked_store_slots <= 32'b0;
            perf_p0_full_blocked_other_slots <= 32'b0;
            perf_p0_completion_wakeup_cycles <= 32'b0;
            perf_operand_merge_pair_cycles <= 32'b0;
            perf_rs_completion_wakeup_entries <= 32'b0;
            perf_rs_alloc_wakeup_entries <= 32'b0;
            perf_rs_select_wakeup_entries <= 32'b0;
            perf_dtcm_launch_wakeup_events <= 32'b0;
            perf_dtcm_result_wakeup_events <= 32'b0;
            perf_mdu_wakeup_events <= 32'b0;
            perf_replay_wakeup_events <= 32'b0;
            perf_other_rs_pair_limit_slots <= 32'b0;
            perf_other_select_refill_slots <= 32'b0;
            perf_other_rs_dependency_slots <= 32'b0;
            perf_other_rs_order_slots <= 32'b0;
            perf_other_rs_resource_slots <= 32'b0;
            perf_other_rs_no_candidate_slots <= 32'b0;
            perf_other_rs_empty_slots <= 32'b0;
            perf_other_decode_block_slots <= 32'b0;
            perf_other_unclassified_slots <= 32'b0;
            perf_rs_dependency_entry_cycles <= 32'b0;
            perf_rs_order_entry_cycles <= 32'b0;
            perf_rs_resource_entry_cycles <= 32'b0;
            perf_rs_selectable_entry_cycles <= 32'b0;
            perf_rs_bank_full_cycles <= 32'b0;
            perf_rs_pair_bank_limit_cycles <= 32'b0;
            perf_rob_full_cycles <= 32'b0;
            perf_lsu_credit_wait_cycles <= 32'b0;
            perf_lsu_age_repair_cycles <= 32'b0;
            perf_div_credit_wait_cycles <= 32'b0;
            perf_serial_gate_wait_cycles <= 32'b0;
            perf_select_width_limit_cycles <= 32'b0;
            perf_operand_dependency_miss_cycles <= 32'b0;
            perf_recovery_cycles <= 32'b0;
            perf_recovery_resync_cycles <= 32'b0;
            perf_alu_bank_entry_cycles <= 32'b0;
            perf_p0_bank_entry_cycles <= 32'b0;
            perf_p1_bank_entry_cycles <= 32'b0;
            perf_alu_bank_full_cycles <= 32'b0;
            perf_p0_bank_full_cycles <= 32'b0;
            perf_p1_bank_full_cycles <= 32'b0;
            perf_alu_due_select_cycles <= 32'b0;
            perf_dtcm_due_select_cycles <= 32'b0;
            perf_mdu_due_select_cycles <= 32'b0;
            perf_dtcm_local_wake_cycles <= 32'b0;
            perf_mdu_local_wake_cycles <= 32'b0;
            perf_resident_wakeup_entry_cycles <= 32'b0;
            perf_resident_due_select_cycles <= 32'b0;
            perf_cpl_bank_dep_count <= 32'b0;
            perf_cpl_bank_rob_count <= 32'b0;
            perf_cpl_bank_resource_count <= 32'b0;
            perf_cpl_bank_select_count <= 32'b0;
            perf_cpl_bank_operand_count <= 32'b0;
            perf_cpl_rob_dep_count <= 32'b0;
            perf_cpl_rob_resource_count <= 32'b0;
            perf_cpl_rob_select_count <= 32'b0;
            perf_cpl_rob_operand_count <= 32'b0;
            perf_cpl_dep_resource_count <= 32'b0;
            perf_cpl_dep_select_count <= 32'b0;
            perf_cpl_dep_operand_count <= 32'b0;
            perf_cpl_resource_select_count <= 32'b0;
            perf_cpl_select_operand_count <= 32'b0;
            perf_cpl_bank_dep_select_count <= 32'b0;
            perf_cpl_bank_rob_select_count <= 32'b0;
            perf_cpl_dep_select_operand_count <= 32'b0;
            perf_loss_coupling_cycles <= 32'b0;
            perf_loss_coupling_slots <= 32'b0;
            perf_select_raw_alu_entries <= 32'b0;
            perf_select_raw_p0_entries <= 32'b0;
            perf_select_raw_p1_entries <= 32'b0;
            perf_select_drop_alu_entries <= 32'b0;
            perf_select_drop_p0_entries <= 32'b0;
            perf_select_drop_p1_entries <= 32'b0;
            perf_select_width_gap_slots <= 32'b0;
            perf_select_pair_capable_single_cycles <= 32'b0;
            perf_select_pair_capable_single_slots <= 32'b0;
            perf_select_gap_recovery_cycles <= 32'b0;
            perf_select_gap_no_push_cycles <= 32'b0;
            perf_select_gap_policy_cycles <= 32'b0;
            perf_select_hol_pair_cycles <= 32'b0;
            perf_select_hol_pair_lost_slots <= 32'b0;
            perf_select_pair_push_cycles <= 32'b0;
            perf_select_pair_issue_cycles <= 32'b0;
            perf_select_pair_push_single_head_cycles <= 32'b0;
            perf_select_pair_push_single_head_slots <= 32'b0;
            perf_select_refill_head_empty_cycles <= 32'b0;
            perf_select_refill_head_empty_slots <= 32'b0;
            perf_select_refill_head_empty_pair_slots <= 32'b0;
            perf_select_refill_head_empty_single_slots <= 32'b0;
            perf_select_refill_head_empty_uops <= 32'b0;
            for (perf_refill_lifecycle_idx = 0;
                 perf_refill_lifecycle_idx < PERF_REFILL_LIFECYCLE_COUNT;
                 perf_refill_lifecycle_idx =
                     perf_refill_lifecycle_idx + 1)
                for (perf_refill_data_idx = 0; perf_refill_data_idx < 2;
                     perf_refill_data_idx = perf_refill_data_idx + 1)
                    perf_select_refill_lifecycle_data_uops[
                        perf_refill_lifecycle_idx][perf_refill_data_idx] <=
                        32'b0;
            for (perf_refill_prior_mask_idx = 0;
                 perf_refill_prior_mask_idx < 10;
                 perf_refill_prior_mask_idx =
                     perf_refill_prior_mask_idx + 1)
                perf_select_refill_prior_mask_uops[
                    perf_refill_prior_mask_idx] <= 32'b0;
            for (perf_refill_mask_idx = 0; perf_refill_mask_idx < 16;
                 perf_refill_mask_idx = perf_refill_mask_idx + 1)
                perf_select_refill_pending_mask_uops[
                    perf_refill_mask_idx] <= 32'b0;
            perf_refill_prev_valid_q <= '0;
            perf_refill_prev_dep_q <= '0;
            perf_refill_prev_order_q <= '0;
            perf_refill_prev_resource_q <= '0;
            perf_refill_prev_ready_q <= '0;
            for (perf_refill_prev_idx = 0; perf_refill_prev_idx < 12;
                 perf_refill_prev_idx = perf_refill_prev_idx + 1)
                perf_refill_prev_tag_q[perf_refill_prev_idx] <= '0;
            for (perf_stat_idx = 0; perf_stat_idx < PERF_LOSS_COUPLING_DEPTH;
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_loss_coupling_cycle_count[perf_stat_idx] <= 32'b0;
                perf_loss_coupling_slot_count[perf_stat_idx] <= 32'b0;
            end
            for (perf_stat_idx = 0; perf_stat_idx < 256;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_coupling_mask_count[perf_stat_idx] <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 16;
                 perf_stat_idx = perf_stat_idx + 1)
                begin
                    perf_select_queue_state_count[perf_stat_idx] <= 32'b0;
                    perf_select_raw_shape_count[perf_stat_idx] <= 32'b0;
                end
            for (perf_stat_idx = 0; perf_stat_idx < 3;
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_select_raw_width_count[perf_stat_idx] <= 32'b0;
                perf_select_actual_width_count[perf_stat_idx] <= 32'b0;
            end
            for (perf_width_idx = 0; perf_width_idx < 3;
                 perf_width_idx = perf_width_idx + 1)
                for (perf_width_idx2 = 0; perf_width_idx2 < 3;
                     perf_width_idx2 = perf_width_idx2 + 1) begin
                    perf_select_width_matrix_cycles[perf_width_idx][perf_width_idx2] <=
                        32'b0;
                    perf_select_width_matrix_slots[perf_width_idx][perf_width_idx2] <=
                        32'b0;
                end
            for (perf_stat_idx = 0; perf_stat_idx < 3;
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_bank_dep_entry_cycles[perf_stat_idx] <= 32'b0;
                perf_bank_order_entry_cycles[perf_stat_idx] <= 32'b0;
                perf_bank_resource_entry_cycles[perf_stat_idx] <= 32'b0;
                perf_bank_ready_entry_cycles[perf_stat_idx] <= 32'b0;
                perf_bank_candidate_entry_cycles[perf_stat_idx] <= 32'b0;
                perf_bank_selected_entry_cycles[perf_stat_idx] <= 32'b0;
            end
            for (perf_stat_idx = 0; perf_stat_idx < PERF_LATENCY_BINS;
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_latency_alloc_select[perf_stat_idx] <= 32'b0;
                perf_latency_select_operand[perf_stat_idx] <= 32'b0;
                perf_latency_operand_ex[perf_stat_idx] <= 32'b0;
                perf_latency_alloc_complete[perf_stat_idx] <= 32'b0;
                perf_latency_alloc_retire[perf_stat_idx] <= 32'b0;
            end
            for (perf_stat_idx = 0;
                 perf_stat_idx < (1 << PRODUCER_ID_WIDTH);
                 perf_stat_idx = perf_stat_idx + 1) begin
                perf_alloc_cycle_by_id[perf_stat_idx] <= 32'b0;
                perf_select_cycle_by_id[perf_stat_idx] <= 32'b0;
                perf_operand_cycle_by_id[perf_stat_idx] <= 32'b0;
                perf_alloc_live_by_id[perf_stat_idx] <= 1'b0;
            end
            perf_producer_issued_q <= '0;
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
            issue_fence_count <= 32'b0;
            issue_slot1_replay_count <= 32'b0;
            issue_slot1_dependency_replay_count <= 32'b0;
            issue_slot1_lsu_replay_count <= 32'b0;
            issue_serialize_wait_count <= 32'b0;
            for (perf_stat_idx = 0; perf_stat_idx < 5; perf_stat_idx = perf_stat_idx + 1)
                operandq_occ_count[perf_stat_idx] <= 32'b0;
        end else begin
            perf_sample_cycle_count <= perf_sample_cycle_count + 1'b1;
            perf_select_queue_state_count[perf_select_queue_state_now] <=
                perf_select_queue_state_count[perf_select_queue_state_now] + 1'b1;
            perf_select_raw_width_count[perf_select_ideal_width_now] <=
                perf_select_raw_width_count[perf_select_ideal_width_now] + 1'b1;
            perf_select_actual_width_count[perf_select_actual_width_now] <=
                perf_select_actual_width_count[perf_select_actual_width_now] + 1'b1;
            perf_select_width_matrix_cycles[perf_select_ideal_width_now]
                [perf_select_actual_width_now] <=
                perf_select_width_matrix_cycles[perf_select_ideal_width_now]
                    [perf_select_actual_width_now] + 1'b1;
            perf_select_width_matrix_slots[perf_select_ideal_width_now]
                [perf_select_actual_width_now] <=
                perf_select_width_matrix_slots[perf_select_ideal_width_now]
                    [perf_select_actual_width_now] + perf_lost_slots_ext;
            perf_select_raw_shape_count[perf_select_raw_shape_now] <=
                perf_select_raw_shape_count[perf_select_raw_shape_now] + 1'b1;
            perf_select_raw_alu_entries <= perf_select_raw_alu_entries +
                {{29{1'b0}}, perf_raw_alu_candidate_entries_now};
            perf_select_raw_p0_entries <= perf_select_raw_p0_entries +
                {31'b0, perf_raw_p0_candidate_now};
            perf_select_raw_p1_entries <= perf_select_raw_p1_entries +
                {31'b0, perf_raw_p1_candidate_now};
            perf_select_drop_alu_entries <= perf_select_drop_alu_entries +
                {{29{1'b0}}, perf_select_drop_alu_entries_now};
            perf_select_drop_p0_entries <= perf_select_drop_p0_entries +
                {{29{1'b0}}, perf_select_drop_p0_entries_now};
            perf_select_drop_p1_entries <= perf_select_drop_p1_entries +
                {{29{1'b0}}, perf_select_drop_p1_entries_now};
            if (perf_select_ideal_width_now > perf_select_actual_width_now)
                perf_select_width_gap_slots <= perf_select_width_gap_slots +
                    perf_select_width_gap_now;
            if (perf_select_gap_recovery_now)
                perf_select_gap_recovery_cycles <=
                    perf_select_gap_recovery_cycles + 1'b1;
            else if (perf_select_gap_no_push_now)
                perf_select_gap_no_push_cycles <=
                    perf_select_gap_no_push_cycles + 1'b1;
            else if (perf_select_width_gap_now != 0)
                perf_select_gap_policy_cycles <=
                    perf_select_gap_policy_cycles + 1'b1;
            if ((perf_select_ideal_width_now == 2'd2) &&
                (perf_select_actual_width_now == 2'd1)) begin
                perf_select_pair_capable_single_cycles <=
                    perf_select_pair_capable_single_cycles + 1'b1;
                if (perf_lost_slots != '0)
                    perf_select_pair_capable_single_slots <=
                        perf_select_pair_capable_single_slots +
                        perf_lost_slots_ext;
            end
            if (perf_lost_slots != '0) begin
                perf_loss_coupling_cycles <= perf_loss_coupling_cycles + 1'b1;
                perf_loss_coupling_slots <= perf_loss_coupling_slots +
                    perf_lost_slots_ext;
                perf_loss_coupling_cycle_count[perf_loss_coupling_mask_now] <=
                    perf_loss_coupling_cycle_count[perf_loss_coupling_mask_now] + 1'b1;
                perf_loss_coupling_slot_count[perf_loss_coupling_mask_now] <=
                    perf_loss_coupling_slot_count[perf_loss_coupling_mask_now] +
                    perf_lost_slots_ext;
            end
            if (perf_select_hol_pair_now)
                perf_select_hol_pair_cycles <= perf_select_hol_pair_cycles + 1'b1;
            if (perf_select_hol_pair_now && (perf_operand_lost_slots != '0))
                perf_select_hol_pair_lost_slots <=
                    perf_select_hol_pair_lost_slots + perf_operand_lost_slots_ext;
            if (u_dut.u_ydrasil_issue_stage.select_buf_push &&
                u_dut.u_ydrasil_issue_stage.selected_valid1)
                perf_select_pair_push_cycles <= perf_select_pair_push_cycles + 1'b1;
            if (perf_select_pair_push_single_head_now) begin
                perf_select_pair_push_single_head_cycles <=
                    perf_select_pair_push_single_head_cycles + 1'b1;
                perf_select_pair_push_single_head_slots <=
                    perf_select_pair_push_single_head_slots +
                    perf_operand_lost_slots_ext;
            end
            if (perf_select_refill_head_empty_now &&
                (perf_operand_lost_slots != '0)) begin
                perf_select_refill_head_empty_cycles <=
                    perf_select_refill_head_empty_cycles + 1'b1;
                perf_select_refill_head_empty_slots <=
                    perf_select_refill_head_empty_slots +
                    perf_operand_lost_slots_ext;
                perf_select_refill_head_empty_uops <=
                    perf_select_refill_head_empty_uops + 32'd1 +
                    (u_dut.u_ydrasil_issue_stage.selected_valid1 ?
                         32'd1 : 32'd0);
                if (u_dut.u_ydrasil_issue_stage.selected_valid1)
                    perf_select_refill_head_empty_pair_slots <=
                        perf_select_refill_head_empty_pair_slots +
                        perf_operand_lost_slots_ext;
                else
                    perf_select_refill_head_empty_single_slots <=
                        perf_select_refill_head_empty_single_slots +
                        perf_operand_lost_slots_ext;
                for (perf_refill_lifecycle_idx = 0;
                     perf_refill_lifecycle_idx < PERF_REFILL_LIFECYCLE_COUNT;
                     perf_refill_lifecycle_idx =
                         perf_refill_lifecycle_idx + 1)
                    for (perf_refill_data_idx = 0;
                         perf_refill_data_idx < 2;
                         perf_refill_data_idx = perf_refill_data_idx + 1)
                        perf_select_refill_lifecycle_data_uops[
                            perf_refill_lifecycle_idx][perf_refill_data_idx] <=
                            perf_select_refill_lifecycle_data_uops[
                                perf_refill_lifecycle_idx][
                                    perf_refill_data_idx] +
                            (((perf_refill_lifecycle0_now ==
                               3'(perf_refill_lifecycle_idx)) &&
                              ((perf_refill_pending_mask0_now == 4'b0) ==
                               1'(perf_refill_data_idx))) ? 32'd1 : 32'd0) +
                            ((u_dut.u_ydrasil_issue_stage.selected_valid1 &&
                              (perf_refill_lifecycle1_now ==
                               3'(perf_refill_lifecycle_idx)) &&
                              ((perf_refill_pending_mask1_now == 4'b0) ==
                               1'(perf_refill_data_idx))) ? 32'd1 : 32'd0);
                for (perf_refill_prior_mask_idx = 0;
                     perf_refill_prior_mask_idx < 10;
                     perf_refill_prior_mask_idx =
                         perf_refill_prior_mask_idx + 1)
                    perf_select_refill_prior_mask_uops[
                        perf_refill_prior_mask_idx] <=
                        perf_select_refill_prior_mask_uops[
                            perf_refill_prior_mask_idx] +
                        ((perf_refill_prior_mask0_now ==
                          4'(perf_refill_prior_mask_idx)) ? 32'd1 : 32'd0) +
                        ((u_dut.u_ydrasil_issue_stage.selected_valid1 &&
                          (perf_refill_prior_mask1_now ==
                           4'(perf_refill_prior_mask_idx))) ? 32'd1 : 32'd0);
                for (perf_refill_mask_idx = 0;
                     perf_refill_mask_idx < 16;
                     perf_refill_mask_idx = perf_refill_mask_idx + 1)
                    perf_select_refill_pending_mask_uops[
                        perf_refill_mask_idx] <=
                        perf_select_refill_pending_mask_uops[
                            perf_refill_mask_idx] +
                        ((perf_refill_pending_mask0_now ==
                          4'(perf_refill_mask_idx)) ? 32'd1 : 32'd0) +
                        ((u_dut.u_ydrasil_issue_stage.selected_valid1 &&
                          (perf_refill_pending_mask1_now ==
                           4'(perf_refill_mask_idx))) ? 32'd1 : 32'd0);
            end
            if (u_dut.u_ydrasil_issue_stage.select_head_valid_q &&
                u_dut.u_ydrasil_issue_stage.select_head_pair_q)
                perf_select_pair_issue_cycles <= perf_select_pair_issue_cycles + 1'b1;
            perf_refill_prev_valid_q <=
                u_dut.u_ydrasil_issue_stage.issue_window_valid_q;
            perf_refill_prev_dep_q <= perf_rs_dep_mask_now;
            perf_refill_prev_order_q <= perf_rs_order_mask_now;
            perf_refill_prev_resource_q <= perf_rs_resource_mask_now;
            perf_refill_prev_ready_q <= perf_rs_ready_mask_now;
            for (perf_refill_prev_idx = 0; perf_refill_prev_idx < 12;
                 perf_refill_prev_idx = perf_refill_prev_idx + 1)
                perf_refill_prev_tag_q[perf_refill_prev_idx] <=
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        perf_refill_prev_idx].dst.rob_tag;
            // Preserve the simultaneous backend state before the legacy
            // exclusive slot attribution is evaluated.
            perf_coupling_mask_count[perf_coupling_mask_now] <=
                perf_coupling_mask_count[perf_coupling_mask_now] + 1'b1;
            if (perf_coupling_mask_now[0] && perf_coupling_mask_now[2])
                perf_cpl_bank_select_count <= perf_cpl_bank_select_count + 1'b1;
            if (perf_coupling_mask_now[0] && perf_coupling_mask_now[1])
                perf_cpl_bank_rob_count <= perf_cpl_bank_rob_count + 1'b1;
            if (perf_coupling_mask_now[0] && perf_coupling_mask_now[3])
                perf_cpl_bank_resource_count <= perf_cpl_bank_resource_count + 1'b1;
            if (perf_coupling_mask_now[0] && perf_coupling_mask_now[5])
                perf_cpl_bank_dep_count <= perf_cpl_bank_dep_count + 1'b1;
            if (perf_coupling_mask_now[0] && perf_coupling_mask_now[6])
                perf_cpl_bank_operand_count <= perf_cpl_bank_operand_count + 1'b1;
            if (perf_coupling_mask_now[1] && perf_coupling_mask_now[5])
                perf_cpl_rob_dep_count <= perf_cpl_rob_dep_count + 1'b1;
            if (perf_coupling_mask_now[1] && perf_coupling_mask_now[3])
                perf_cpl_rob_resource_count <= perf_cpl_rob_resource_count + 1'b1;
            if (perf_coupling_mask_now[1] && perf_coupling_mask_now[2])
                perf_cpl_rob_select_count <= perf_cpl_rob_select_count + 1'b1;
            if (perf_coupling_mask_now[1] && perf_coupling_mask_now[6])
                perf_cpl_rob_operand_count <= perf_cpl_rob_operand_count + 1'b1;
            if (perf_coupling_mask_now[5] && perf_coupling_mask_now[3])
                perf_cpl_dep_resource_count <= perf_cpl_dep_resource_count + 1'b1;
            if (perf_coupling_mask_now[5] && perf_coupling_mask_now[2])
                perf_cpl_dep_select_count <= perf_cpl_dep_select_count + 1'b1;
            if (perf_coupling_mask_now[5] && perf_coupling_mask_now[6])
                perf_cpl_dep_operand_count <= perf_cpl_dep_operand_count + 1'b1;
            if (perf_coupling_mask_now[3] && perf_coupling_mask_now[2])
                perf_cpl_resource_select_count <= perf_cpl_resource_select_count + 1'b1;
            if (perf_coupling_mask_now[2] && perf_coupling_mask_now[6])
                perf_cpl_select_operand_count <= perf_cpl_select_operand_count + 1'b1;
            if (&{perf_coupling_mask_now[0], perf_coupling_mask_now[5],
                  perf_coupling_mask_now[2]})
                perf_cpl_bank_dep_select_count <= perf_cpl_bank_dep_select_count + 1'b1;
            if (&{perf_coupling_mask_now[0], perf_coupling_mask_now[1],
                  perf_coupling_mask_now[2]})
                perf_cpl_bank_rob_select_count <= perf_cpl_bank_rob_select_count + 1'b1;
            if (&{perf_coupling_mask_now[5], perf_coupling_mask_now[2],
                  perf_coupling_mask_now[6]})
                perf_cpl_dep_select_operand_count <= perf_cpl_dep_select_operand_count + 1'b1;
            for (perf_lifecycle_idx = 0; perf_lifecycle_idx < 3;
                 perf_lifecycle_idx = perf_lifecycle_idx + 1) begin
                perf_bank_dep_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_dep_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_dep_entries_now[perf_lifecycle_idx]};
                perf_bank_order_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_order_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_order_entries_now[perf_lifecycle_idx]};
                perf_bank_resource_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_resource_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_resource_entries_now[perf_lifecycle_idx]};
                perf_bank_ready_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_ready_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_ready_entries_now[perf_lifecycle_idx]};
                perf_bank_candidate_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_candidate_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_candidate_entries_now[perf_lifecycle_idx]};
                perf_bank_selected_entry_cycles[perf_lifecycle_idx] <=
                    perf_bank_selected_entry_cycles[perf_lifecycle_idx] +
                    {{29{1'b0}}, perf_bank_selected_entries_now[perf_lifecycle_idx]};
            end

            // Allocate -> Select -> Operand -> EX -> completion/retire timing.
            // Blocking updates are used only for these DV histograms so two
            // events in one cycle cannot overwrite the same histogram bin.
            if (u_dut.u_ctrl.queue_alloc0) begin
                perf_alloc_cycle_by_id[u_dut.u_ctrl.producer_alloc_id] =
                    perf_sample_cycle_count;
                perf_alloc_live_by_id[u_dut.u_ctrl.producer_alloc_id] = 1'b1;
            end
            if (u_dut.u_ctrl.queue_alloc1) begin
                perf_alloc_cycle_by_id[u_dut.u_ctrl.producer_alloc_id1] =
                    perf_sample_cycle_count;
                perf_alloc_live_by_id[u_dut.u_ctrl.producer_alloc_id1] = 1'b1;
            end
            if (u_dut.u_ydrasil_issue_stage.select_buf_push) begin
                if (u_dut.u_ydrasil_issue_stage.selected_valid0) begin
                    perf_lifecycle_id = int'(u_dut.u_ydrasil_issue_stage.
                        selected_uop0.dst.rob_tag);
                    perf_select_cycle_by_id[perf_lifecycle_id] =
                        perf_sample_cycle_count;
                    if (perf_alloc_live_by_id[perf_lifecycle_id]) begin
                        perf_lifecycle_latency = perf_sample_cycle_count -
                            perf_alloc_cycle_by_id[perf_lifecycle_id];
                        perf_lifecycle_bin = perf_latency_bucket(
                            perf_lifecycle_latency);
                        perf_latency_alloc_select[perf_lifecycle_bin] =
                            perf_latency_alloc_select[perf_lifecycle_bin] + 1'b1;
                    end
                end
                if (u_dut.u_ydrasil_issue_stage.selected_valid1) begin
                    perf_lifecycle_id = int'(u_dut.u_ydrasil_issue_stage.
                        selected_uop1.dst.rob_tag);
                    perf_select_cycle_by_id[perf_lifecycle_id] =
                        perf_sample_cycle_count;
                    if (perf_alloc_live_by_id[perf_lifecycle_id]) begin
                        perf_lifecycle_latency = perf_sample_cycle_count -
                            perf_alloc_cycle_by_id[perf_lifecycle_id];
                        perf_lifecycle_bin = perf_latency_bucket(
                            perf_lifecycle_latency);
                        perf_latency_alloc_select[perf_lifecycle_bin] =
                            perf_latency_alloc_select[perf_lifecycle_bin] + 1'b1;
                    end
                end
            end
            if (u_dut.u_ydrasil_issue_stage.lane_a_accept) begin
                perf_lifecycle_id = int'(u_dut.u_ydrasil_issue_stage.
                    lane_a_uop.dst.rob_tag);
                perf_operand_cycle_by_id[perf_lifecycle_id] =
                    perf_sample_cycle_count;
                if (perf_select_cycle_by_id[perf_lifecycle_id] != 0) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_select_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_select_operand[perf_lifecycle_bin] =
                        perf_latency_select_operand[perf_lifecycle_bin] + 1'b1;
                end
            end
            if (u_dut.u_ydrasil_issue_stage.lane_b_accept) begin
                perf_lifecycle_id = int'(u_dut.u_ydrasil_issue_stage.
                    lane_b_uop.dst.rob_tag);
                perf_operand_cycle_by_id[perf_lifecycle_id] =
                    perf_sample_cycle_count;
                if (perf_select_cycle_by_id[perf_lifecycle_id] != 0) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_select_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_select_operand[perf_lifecycle_bin] =
                        perf_latency_select_operand[perf_lifecycle_bin] + 1'b1;
                end
            end
            if (u_dut.ex_accept_valid) begin
                perf_lifecycle_id = int'(u_dut.ex_hzd_pkt.producer_id);
                if (perf_operand_cycle_by_id[perf_lifecycle_id] != 0) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_operand_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_operand_ex[perf_lifecycle_bin] =
                        perf_latency_operand_ex[perf_lifecycle_bin] + 1'b1;
                end
            end
            if (u_dut.ex_accept_valid1) begin
                perf_lifecycle_id = int'(u_dut.ex_hzd_pkt1.producer_id);
                if (perf_operand_cycle_by_id[perf_lifecycle_id] != 0) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_operand_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_operand_ex[perf_lifecycle_bin] =
                        perf_latency_operand_ex[perf_lifecycle_bin] + 1'b1;
                end
            end
            for (perf_lifecycle_idx = 0;
                 perf_lifecycle_idx < COMPLETION_LANES;
                 perf_lifecycle_idx = perf_lifecycle_idx + 1) begin
                if (u_dut.completion_meta[perf_lifecycle_idx].valid &&
                    u_dut.completion_meta[perf_lifecycle_idx].producer_tracked) begin
                    perf_lifecycle_id = int'(u_dut.completion_meta[
                        perf_lifecycle_idx].producer_id);
                    if (perf_alloc_live_by_id[perf_lifecycle_id]) begin
                        perf_lifecycle_latency = perf_sample_cycle_count -
                            perf_alloc_cycle_by_id[perf_lifecycle_id];
                        perf_lifecycle_bin = perf_latency_bucket(
                            perf_lifecycle_latency);
                        perf_latency_alloc_complete[perf_lifecycle_bin] =
                            perf_latency_alloc_complete[perf_lifecycle_bin] + 1'b1;
                    end
                end
            end
            if (u_dut.commit_pkt.valid) begin
                perf_lifecycle_id = int'(u_dut.commit_pkt.producer_id);
                if (perf_alloc_live_by_id[perf_lifecycle_id]) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_alloc_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_alloc_retire[perf_lifecycle_bin] =
                        perf_latency_alloc_retire[perf_lifecycle_bin] + 1'b1;
                    perf_alloc_live_by_id[perf_lifecycle_id] = 1'b0;
                end
            end
            if (u_dut.commit_pkt1.valid) begin
                perf_lifecycle_id = int'(u_dut.commit_pkt1.producer_id);
                if (perf_alloc_live_by_id[perf_lifecycle_id]) begin
                    perf_lifecycle_latency = perf_sample_cycle_count -
                        perf_alloc_cycle_by_id[perf_lifecycle_id];
                    perf_lifecycle_bin = perf_latency_bucket(
                        perf_lifecycle_latency);
                    perf_latency_alloc_retire[perf_lifecycle_bin] =
                        perf_latency_alloc_retire[perf_lifecycle_bin] + 1'b1;
                    perf_alloc_live_by_id[perf_lifecycle_id] = 1'b0;
                end
            end
            perf_p0_completion_wakeup_cycles <=
                perf_p0_completion_wakeup_cycles +
                {31'b0, perf_p0_completion_wakeup_now};
            perf_operand_merge_pair_cycles <=
                perf_operand_merge_pair_cycles +
                {31'b0, perf_operand_merge_pair_now};
            perf_rs_completion_wakeup_entries <=
                perf_rs_completion_wakeup_entries +
                {{28{1'b0}}, perf_rs_completion_wakeup_entries_now};
            perf_rs_alloc_wakeup_entries <=
                perf_rs_alloc_wakeup_entries +
                {{28{1'b0}}, perf_rs_alloc_wakeup_entries_now};
            perf_rs_select_wakeup_entries <=
                perf_rs_select_wakeup_entries +
                {{28{1'b0}}, perf_rs_select_wakeup_entries_now};
            perf_dtcm_launch_wakeup_events <=
                perf_dtcm_launch_wakeup_events +
                {31'b0, u_dut.u_ydrasil_issue_stage.dtcm_launch_wakeup_valid_i};
            perf_dtcm_result_wakeup_events <=
                perf_dtcm_result_wakeup_events +
                {31'b0, (u_dut.u_ydrasil_issue_stage.dtcm_reservation_i.valid &&
                         u_dut.u_ydrasil_issue_stage.dtcm_reservation_i.
                             producer_tracked)};
            perf_mdu_wakeup_events <= perf_mdu_wakeup_events +
                {31'b0, (u_dut.u_ydrasil_issue_stage.mdu_due_i.valid &&
                         u_dut.u_ydrasil_issue_stage.mdu_due_i.
                             producer_tracked)};
            perf_replay_wakeup_events <= perf_replay_wakeup_events +
                {31'b0,
                 u_dut.u_ydrasil_issue_stage.dtcm_result_replay_valid_q};
            if (perf_issue_scan_en &&
                (perf_empty_slots_now != perf_empty_classified_slots_now) &&
                (perf_empty_scan_count < 16)) begin
                $display("PERFEMPTYGAP cyc=%0d empty=%0d classified=%0d hzd=%0b/%0b q=%0d/%0d issue=%0b/%0b lane=%0b/%0b/%0b/%0b",
                         perf_sample_cycle_count,
                         perf_empty_slots_now,
                         perf_empty_classified_slots_now,
                         u_dut.ex_hzd_pkt.valid,
                         u_dut.ex_hzd_pkt1.valid,
                         perf_src_kind0_q,
                         perf_src_kind1_q,
                         u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid,
                         u_dut.u_ydrasil_issue_stage.issue_pair_execute,
                         u_dut.u_ydrasil_issue_stage.lane_a_accept,
                         u_dut.u_ydrasil_issue_stage.lane_b_accept,
                         u_dut.u_ydrasil_issue_stage.lane_a_fu_valid,
                         u_dut.u_ydrasil_issue_stage.lane_b_valid);
                perf_empty_scan_count <= perf_empty_scan_count + 1;
            end
            assert ($onehot(perf_cycle_cause_onehot))
                else $fatal(1, "PERF_CAUSE_NOT_ONEHOT causes=0x%03h",
                            perf_cycle_cause_onehot);
            perf_productive_slot_count <= perf_productive_slot_count +
                {30'b0, perf_executed_slots};
            if (u_dut.ex_accept_valid)
                perf_executed_slot0_count <= perf_executed_slot0_count + 1'b1;
            else if (u_dut.ex_hzd_pkt.valid && u_dut.ex_branch_jump)
                perf_ex_branch_drop0_count <= perf_ex_branch_drop0_count + 1'b1;
            else if (u_dut.ex_hzd_pkt.valid && u_dut.ex_mul_stall)
                perf_ex_mul_drop0_count <= perf_ex_mul_drop0_count + 1'b1;
            else begin
                if (u_dut.ex_hzd_pkt.valid)
                    perf_ex_valid_hold0_count <= perf_ex_valid_hold0_count + 1'b1;
                perf_ex_empty0_count <= perf_ex_empty0_count + 1'b1;
            end
            if (u_dut.ex_accept_valid1)
                perf_executed_slot1_count <= perf_executed_slot1_count + 1'b1;
            else if (u_dut.ex_hzd_pkt1.valid && u_dut.ex_branch_jump)
                perf_ex_branch_drop1_count <= perf_ex_branch_drop1_count + 1'b1;
            else if (u_dut.ex_hzd_pkt1.valid && u_dut.ex_mul_stall)
                perf_ex_mul_drop1_count <= perf_ex_mul_drop1_count + 1'b1;
            else begin
                if (u_dut.ex_hzd_pkt1.valid)
                    perf_ex_valid_hold1_count <= perf_ex_valid_hold1_count + 1'b1;
                perf_ex_empty1_count <= perf_ex_empty1_count + 1'b1;
            end
            perf_ex_empty_reset_count <= perf_ex_empty_reset_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RESET)};
            perf_ex_empty_recovery_count <= perf_ex_empty_recovery_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RECOVERY)};
            perf_ex_empty_fence_count <= perf_ex_empty_fence_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_FENCE)};
            perf_ex_empty_b_only_count <= perf_ex_empty_b_only_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_B_ONLY)};
            perf_ex_empty_single_head_count <= perf_ex_empty_single_head_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_SINGLE_HEAD)};
            perf_ex_empty_select_refill_count <= perf_ex_empty_select_refill_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_SELECT_REFILL)};
            perf_ex_empty_rs_dependency_count <= perf_ex_empty_rs_dependency_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RS_DEPENDENCY)};
            perf_ex_empty_rs_order_count <= perf_ex_empty_rs_order_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RS_ORDER)};
            perf_ex_empty_rs_resource_count <= perf_ex_empty_rs_resource_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RS_RESOURCE)};
            perf_ex_empty_rs_no_candidate_count <= perf_ex_empty_rs_no_candidate_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RS_NO_CANDIDATE)};
            perf_ex_empty_rs_empty_count <= perf_ex_empty_rs_empty_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_RS_EMPTY)};
            perf_ex_empty_frontend_count <= perf_ex_empty_frontend_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_FRONTEND)};
            perf_ex_empty_other_count <= perf_ex_empty_other_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_OTHER)};
            perf_ex_empty_launch_mismatch_count <=
                perf_ex_empty_launch_mismatch_count +
                {{30{1'b0}}, perf_empty_kind_slots(PERF_SRC_LAUNCH)};
            perf_ex_empty_unmapped_count <= perf_ex_empty_unmapped_count +
                {{30{1'b0}}, perf_empty_unmapped_slots()};
            perf_src_kind0_q <= perf_src_kind0_d;
            perf_src_kind1_q <= perf_src_kind1_d;
            perf_select_reason_q <= perf_select_reason_d;
            perf_rob_occ_count[u_dut.u_ctrl.queue_count_q] <=
                perf_rob_occ_count[u_dut.u_ctrl.queue_count_q] + 1'b1;
            perf_rs_occ_count[$countones(
                u_dut.u_ydrasil_issue_stage.issue_window_valid_q)] <=
                perf_rs_occ_count[$countones(
                    u_dut.u_ydrasil_issue_stage.issue_window_valid_q)] + 1'b1;
            perf_rs_alloc_count[u_dut.u_ctrl.queue_alloc_count] <=
                perf_rs_alloc_count[u_dut.u_ctrl.queue_alloc_count] + 1'b1;
            perf_select_count[perf_select_admit_slots[1:0]] <=
                perf_select_count[perf_select_admit_slots[1:0]] + 1'b1;
            perf_operand_count[perf_operand_admit_slots] <=
                perf_operand_count[perf_operand_admit_slots] + 1'b1;
            perf_complete_count[perf_complete_slots] <=
                perf_complete_count[perf_complete_slots] + 1'b1;
            perf_retire_count[perf_retire_slots] <=
                perf_retire_count[perf_retire_slots] + 1'b1;
            perf_candidate_mask_count[perf_candidate_mask] <=
                perf_candidate_mask_count[perf_candidate_mask] + 1'b1;
            perf_rs_dependency_entry_cycles <=
                perf_rs_dependency_entry_cycles +
                {28'b0, perf_rs_dependency_entries_now};
            for (perf_stat_idx = 0; perf_stat_idx < 5;
                 perf_stat_idx = perf_stat_idx + 1)
                perf_dep_blocker_operand_cycles[perf_stat_idx] <=
                    perf_dep_blocker_operand_cycles[perf_stat_idx] +
                    {{27{1'b0}},
                     perf_dep_blocker_operand_count_now[perf_stat_idx]};
            perf_rs_order_entry_cycles <= perf_rs_order_entry_cycles +
                {28'b0, perf_rs_order_entries_now};
            perf_rs_resource_entry_cycles <=
                perf_rs_resource_entry_cycles +
                {28'b0, perf_rs_resource_entries_now};
            perf_rs_selectable_entry_cycles <=
                perf_rs_selectable_entry_cycles +
                {28'b0, perf_rs_ready_entries_now};
            perf_rs_bank_full_cycles <= perf_rs_bank_full_cycles +
                {31'b0, perf_rs_bank_full_now};
            perf_rs_pair_bank_limit_cycles <=
                perf_rs_pair_bank_limit_cycles +
                {31'b0, perf_rs_pair_bank_limit_now};
            perf_rob_full_cycles <= perf_rob_full_cycles +
                {31'b0, perf_rob_full_now};
            perf_lsu_credit_wait_cycles <= perf_lsu_credit_wait_cycles +
                {31'b0, perf_rs_lsu_credit_wait};
            perf_lsu_age_repair_cycles <= perf_lsu_age_repair_cycles +
                {31'b0,
                 u_dut.u_ydrasil_load_store_unit.queue_age_repair};
            perf_div_credit_wait_cycles <= perf_div_credit_wait_cycles +
                {31'b0, perf_rs_div_credit_wait};
            perf_serial_gate_wait_cycles <= perf_serial_gate_wait_cycles +
                {31'b0, perf_rs_serial_gate_wait};
            perf_select_width_limit_cycles <=
                perf_select_width_limit_cycles +
                {31'b0, perf_select_width_limit_now};
            perf_operand_dependency_miss_cycles <=
                perf_operand_dependency_miss_cycles +
                {31'b0, perf_operand_dependency_miss_now};
            perf_recovery_cycles <= perf_recovery_cycles +
                {31'b0, u_dut.ex_pc_redirect};
            perf_recovery_resync_cycles <= perf_recovery_resync_cycles +
                {31'b0, (u_dut.u_ydrasil_issue_stage.recovery_pending_q ||
                         (u_dut.u_ydrasil_issue_stage.credit_resync_q != '0))};
            perf_alu_bank_entry_cycles <= perf_alu_bank_entry_cycles +
                {29'b0, perf_alu_bank_occ_now};
            perf_p0_bank_entry_cycles <= perf_p0_bank_entry_cycles +
                {29'b0, perf_p0_bank_occ_now};
            perf_p1_bank_entry_cycles <= perf_p1_bank_entry_cycles +
                {29'b0, perf_p1_bank_occ_now};
            perf_alu_bank_full_cycles <= perf_alu_bank_full_cycles +
                {31'b0, perf_alu_bank_occ_now == 3'd4};
            perf_p0_bank_full_cycles <= perf_p0_bank_full_cycles +
                {31'b0, perf_p0_bank_occ_now == 3'd4};
            perf_p1_bank_full_cycles <= perf_p1_bank_full_cycles +
                {31'b0, perf_p1_bank_occ_now == 3'd4};
            perf_alu_due_select_cycles <= perf_alu_due_select_cycles +
                {31'b0, perf_alu_due_select_now};
            perf_dtcm_due_select_cycles <= perf_dtcm_due_select_cycles +
                {31'b0, perf_dtcm_due_select_now};
            perf_mdu_due_select_cycles <= perf_mdu_due_select_cycles +
                {31'b0, perf_mdu_due_select_now};
            perf_dtcm_local_wake_cycles <= perf_dtcm_local_wake_cycles +
                {31'b0, perf_dtcm_local_wake_now};
            perf_mdu_local_wake_cycles <= perf_mdu_local_wake_cycles +
                {31'b0, perf_mdu_local_wake_now};
            perf_resident_wakeup_entry_cycles <=
                perf_resident_wakeup_entry_cycles +
                {28'b0, perf_resident_wakeup_entries_now};
            perf_resident_due_select_cycles <=
                perf_resident_due_select_cycles +
                {31'b0, perf_resident_due_select_now};

            if (u_dut.u_ctrl.queue_count_q == '0) begin
                perf_head_empty_count <= perf_head_empty_count + 1'b1;
            end else if (u_dut.commit_pkt1.valid) begin
                perf_head_retire2_count <= perf_head_retire2_count + 1'b1;
            end else if (u_dut.commit_pkt.valid) begin
                perf_head_retire1_count <= perf_head_retire1_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_complete_mask[
                             u_dut.u_ctrl.queue_head_q]) begin
                perf_head_complete_visible_count <=
                    perf_head_complete_visible_count + 1'b1;
            end else if (!perf_producer_issued_q[
                              u_dut.u_ctrl.queue_head_q] &&
                         !perf_head_issued_now) begin
                perf_head_not_issued_count <=
                    perf_head_not_issued_count + 1'b1;
                if (perf_head_selected_now || perf_head_in_select_cell)
                    perf_head_ni_select_transit_count <=
                        perf_head_ni_select_transit_count + 1'b1;
                else if (perf_head_rs_dependency)
                    perf_head_ni_rs_dependency_count <=
                        perf_head_ni_rs_dependency_count + 1'b1;
                else if (perf_head_rs_order)
                    perf_head_ni_rs_order_count <=
                        perf_head_ni_rs_order_count + 1'b1;
                else if (perf_head_rs_resource)
                    perf_head_ni_rs_resource_count <=
                        perf_head_ni_rs_resource_count + 1'b1;
                else if (perf_head_rs_ready)
                    perf_head_ni_rs_ready_count <=
                        perf_head_ni_rs_ready_count + 1'b1;
                else
                    perf_head_ni_absent_count <=
                        perf_head_ni_absent_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_op_class_q[
                             u_dut.u_ctrl.queue_head_q][2]) begin
                perf_head_wait_branch_count <=
                    perf_head_wait_branch_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_op_class_q[
                             u_dut.u_ctrl.queue_head_q][1]) begin
                perf_head_wait_store_count <=
                    perf_head_wait_store_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_op_class_q[
                             u_dut.u_ctrl.queue_head_q][0]) begin
                perf_head_wait_load_count <=
                    perf_head_wait_load_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_result_class_q[
                             u_dut.u_ctrl.queue_head_q] == RESULT_MDU) begin
                perf_head_wait_mdu_count <=
                    perf_head_wait_mdu_count + 1'b1;
            end else if (u_dut.u_ctrl.producer_result_class_q[
                             u_dut.u_ctrl.queue_head_q] == RESULT_ALU) begin
                perf_head_wait_alu_count <=
                    perf_head_wait_alu_count + 1'b1;
            end else begin
                perf_head_wait_other_count <=
                    perf_head_wait_other_count + 1'b1;
            end

            if (perf_operand_lost_slots != '0) begin
                if (u_dut.flush_ex) begin
                    perf_loss_flush_slots <= perf_loss_flush_slots +
                        perf_operand_lost_slots_ext;
                end else if (u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid &&
                             !u_dut.u_ydrasil_issue_stage.id_advance) begin
                    perf_loss_operand_block_slots <=
                        perf_loss_operand_block_slots +
                        perf_operand_lost_slots_ext;
                end else if (u_dut.u_ydrasil_issue_stage.issue_pkt_i.valid) begin
                    perf_loss_single_bundle_slots <=
                        perf_loss_single_bundle_slots +
                        perf_operand_lost_slots_ext;
                    case (perf_select_reason_q)
                        PERF_SEL_REASON_P0:
                            perf_single_p0_only_slots <=
                                perf_single_p0_only_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_P1:
                            perf_single_p1_only_slots <=
                                perf_single_p1_only_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_ALU:
                            perf_single_alu_only_slots <=
                                perf_single_alu_only_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_SERIAL:
                            perf_single_serial_slots <=
                                perf_single_serial_slots + perf_operand_lost_slots_ext;
                        default:
                            perf_single_other_slots <=
                                perf_single_other_slots + perf_operand_lost_slots_ext;
                    endcase
                    case (u_dut.u_ydrasil_issue_stage.issue_pkt_i.op_class)
                        UOP_CLASS_ALU:
                            perf_single_op_alu_slots <=
                                perf_single_op_alu_slots + perf_operand_lost_slots_ext;
                        UOP_CLASS_LOAD:
                            perf_single_op_load_slots <=
                                perf_single_op_load_slots + perf_operand_lost_slots_ext;
                        UOP_CLASS_STORE:
                            perf_single_op_store_slots <=
                                perf_single_op_store_slots + perf_operand_lost_slots_ext;
                        UOP_CLASS_MUL:
                            perf_single_op_mul_slots <=
                                perf_single_op_mul_slots + perf_operand_lost_slots_ext;
                        UOP_CLASS_CSR, UOP_CLASS_SYS:
                            perf_single_op_csr_sys_slots <=
                                perf_single_op_csr_sys_slots + perf_operand_lost_slots_ext;
                        default:
                            perf_single_op_other_slots <=
                                perf_single_op_other_slots + perf_operand_lost_slots_ext;
                    endcase
                end else if (u_dut.u_ydrasil_issue_stage.select_buf_push) begin
                    perf_loss_select_refill_slots <=
                        perf_loss_select_refill_slots +
                        perf_operand_lost_slots_ext;
                    case (perf_select_reason_d)
                        PERF_SEL_REASON_PAIR:
                            perf_select_refill_pair_slots <=
                                perf_select_refill_pair_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_P0:
                            perf_select_refill_p0_slots <=
                                perf_select_refill_p0_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_P1:
                            perf_select_refill_p1_slots <=
                                perf_select_refill_p1_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_ALU:
                            perf_select_refill_alu_slots <=
                                perf_select_refill_alu_slots + perf_operand_lost_slots_ext;
                        PERF_SEL_REASON_SERIAL:
                            perf_select_refill_serial_slots <=
                                perf_select_refill_serial_slots + perf_operand_lost_slots_ext;
                        default:
                            perf_select_refill_other_slots <=
                                perf_select_refill_other_slots + perf_operand_lost_slots_ext;
                    endcase
                    if (u_dut.u_ydrasil_issue_stage.selected_valid1) begin
                        if ((|(u_dut.u_ydrasil_issue_stage.selected0_mask[7:4])) &&
                            (|(u_dut.u_ydrasil_issue_stage.selected1_mask[11:8])))
                            perf_refill_shape_p0_p1_slots <=
                                perf_refill_shape_p0_p1_slots + perf_operand_lost_slots_ext;
                        else if ((|(u_dut.u_ydrasil_issue_stage.selected0_mask[7:4])) &&
                                 (|(u_dut.u_ydrasil_issue_stage.selected1_mask[3:0])))
                            perf_refill_shape_p0_alu_slots <=
                                perf_refill_shape_p0_alu_slots + perf_operand_lost_slots_ext;
                        else if ((|(u_dut.u_ydrasil_issue_stage.selected0_mask[3:0])) &&
                                 (|(u_dut.u_ydrasil_issue_stage.selected1_mask[11:8])))
                            perf_refill_shape_p1_alu_slots <=
                                perf_refill_shape_p1_alu_slots + perf_operand_lost_slots_ext;
                        else if ((|(u_dut.u_ydrasil_issue_stage.selected0_mask[3:0])) &&
                                 (|(u_dut.u_ydrasil_issue_stage.selected1_mask[3:0])))
                            perf_refill_shape_alu_alu_slots <=
                                perf_refill_shape_alu_alu_slots + perf_operand_lost_slots_ext;
                        else
                            perf_refill_shape_other_slots <=
                                perf_refill_shape_other_slots + perf_operand_lost_slots_ext;
                    end else if (|u_dut.u_ydrasil_issue_stage.p1_serial_select_local) begin
                        perf_refill_shape_serial_slots <=
                            perf_refill_shape_serial_slots + perf_operand_lost_slots_ext;
                    end else if (|(u_dut.u_ydrasil_issue_stage.selected0_mask[7:4])) begin
                        perf_refill_shape_single_p0_slots <=
                            perf_refill_shape_single_p0_slots + perf_operand_lost_slots_ext;
                    end else if (|(u_dut.u_ydrasil_issue_stage.selected0_mask[11:8])) begin
                        perf_refill_shape_single_p1_slots <=
                            perf_refill_shape_single_p1_slots + perf_operand_lost_slots_ext;
                    end else if (|(u_dut.u_ydrasil_issue_stage.selected0_mask[3:0])) begin
                        perf_refill_shape_single_alu_slots <=
                            perf_refill_shape_single_alu_slots + perf_operand_lost_slots_ext;
                    end else begin
                        perf_refill_shape_other_slots <=
                            perf_refill_shape_other_slots + perf_operand_lost_slots_ext;
                    end
                end else if (|u_dut.u_ydrasil_issue_stage.
                                  issue_window_valid_q) begin
                    if (perf_rs_dependency_wait)
                        perf_loss_rs_dependency_slots <=
                            perf_loss_rs_dependency_slots +
                            perf_operand_lost_slots_ext;
                    else if (perf_rs_order_wait)
                        perf_loss_rs_order_slots <=
                            perf_loss_rs_order_slots +
                            perf_operand_lost_slots_ext;
                    else if (perf_rs_resource_wait)
                        perf_loss_rs_resource_slots <=
                            perf_loss_rs_resource_slots +
                            perf_operand_lost_slots_ext;
                    else
                        perf_loss_rs_other_slots <=
                            perf_loss_rs_other_slots +
                            perf_operand_lost_slots_ext;
                    if (perf_rs_dependency_wait) begin
                        if (perf_rs_completion_wakeup_now)
                            perf_dep_completion_wakeup_slots <=
                                perf_dep_completion_wakeup_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_alloc_wakeup_now)
                            perf_dep_alloc_wakeup_slots <=
                                perf_dep_alloc_wakeup_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_both_src_now)
                            perf_dep_both_src_slots <=
                                perf_dep_both_src_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src0_wait_now)
                            perf_dep_src0_slots <=
                                perf_dep_src0_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src1_wait_now)
                            perf_dep_src1_slots <=
                                perf_dep_src1_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_load_now)
                            perf_dep_load_slots <=
                                perf_dep_load_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_mul_now)
                            perf_dep_mul_slots <=
                                perf_dep_mul_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_branch_now)
                            perf_dep_branch_slots <=
                                perf_dep_branch_slots + perf_operand_lost_slots_ext;
                        else
                            perf_dep_other_slots <=
                                perf_dep_other_slots + perf_operand_lost_slots_ext;

                        if (perf_rs_dep_both_wakeup_now)
                            perf_dep_wake_both_slots <=
                                perf_dep_wake_both_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_mixed_wakeup_now)
                            perf_dep_wake_mixed_slots <=
                                perf_dep_wake_mixed_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src0_completion_now)
                            perf_dep_wake_src0_completion_slots <=
                                perf_dep_wake_src0_completion_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src1_completion_now)
                            perf_dep_wake_src1_completion_slots <=
                                perf_dep_wake_src1_completion_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src0_alloc_now)
                            perf_dep_wake_src0_alloc_slots <=
                                perf_dep_wake_src0_alloc_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_src1_alloc_now)
                            perf_dep_wake_src1_alloc_slots <=
                                perf_dep_wake_src1_alloc_slots + perf_operand_lost_slots_ext;
                        else
                            perf_dep_wake_none_slots <=
                                perf_dep_wake_none_slots + perf_operand_lost_slots_ext;

                        perf_dep_blocker_mask_slots[
                            perf_rs_dep_blocker_mask_now] <=
                            perf_dep_blocker_mask_slots[
                                perf_rs_dep_blocker_mask_now] +
                            perf_operand_lost_slots_ext;

                        if (perf_rs_dep_load_now)
                            perf_dep_op_load_slots <=
                                perf_dep_op_load_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_store_now)
                            perf_dep_op_store_slots <=
                                perf_dep_op_store_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_mul_now)
                            perf_dep_op_mul_slots <=
                                perf_dep_op_mul_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dep_branch_now)
                            perf_dep_op_branch_slots <=
                                perf_dep_op_branch_slots + perf_operand_lost_slots_ext;
                        else if (perf_rs_dependency_entries_now != '0)
                            perf_dep_op_alu_slots <=
                                perf_dep_op_alu_slots + perf_operand_lost_slots_ext;
                        else
                            perf_dep_op_other_slots <=
                                perf_dep_op_other_slots + perf_operand_lost_slots_ext;
                    end
                end else if (u_dut.u_ctrl.producer_full_stall) begin
                    perf_loss_rob_full_slots <= perf_loss_rob_full_slots +
                        perf_operand_lost_slots_ext;
                end else if (u_dut.issue_pipe_push ||
                             u_dut.id_issue_pkt.valid) begin
                    perf_loss_rs_refill_slots <= perf_loss_rs_refill_slots +
                        perf_operand_lost_slots_ext;
                end else if (u_dut.if_id_valid) begin
                    perf_loss_decode_refill_slots <=
                        perf_loss_decode_refill_slots +
                        perf_operand_lost_slots_ext;
                end else if (!u_dut.if_id_valid) begin
                    perf_loss_frontend_slots <= perf_loss_frontend_slots +
                        perf_operand_lost_slots_ext;
                end else begin
                    perf_loss_other_slots <= perf_loss_other_slots +
                        perf_operand_lost_slots_ext;
                end
            end

            if (u_dut.ex_hzd_pkt.interrupt_pending) begin
                perf_producer_issued_q <= '0;
            end else if (u_dut.ex_pc_redirect) begin
                perf_producer_issued_q <= perf_producer_issued_q &
                    u_dut.u_ctrl.recovery_live_mask;
            end else begin
                perf_producer_issued_q <= perf_producer_issued_q &
                    u_dut.u_ctrl.producer_valid_q;
                if (u_dut.commit_pkt.valid)
                    perf_producer_issued_q[
                        u_dut.commit_pkt.producer_id[
                            PRODUCER_SLOT_WIDTH-1:0]] <= 1'b0;
                if (u_dut.commit_pkt1.valid)
                    perf_producer_issued_q[
                        u_dut.commit_pkt1.producer_id[
                            PRODUCER_SLOT_WIDTH-1:0]] <= 1'b0;
                if (u_dut.u_ydrasil_issue_stage.lane_a_accept)
                    perf_producer_issued_q[
                        u_dut.u_ydrasil_issue_stage.lane_a_uop.dst.rob_tag[
                            PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
                if (u_dut.u_ydrasil_issue_stage.lane_b_accept)
                    perf_producer_issued_q[
                        u_dut.u_ydrasil_issue_stage.lane_b_uop.dst.rob_tag[
                            PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
                if (u_dut.u_ctrl.queue_alloc0)
                    perf_producer_issued_q[u_dut.u_ctrl.alloc_slot0] <= 1'b0;
                if (u_dut.u_ctrl.queue_alloc1)
                    perf_producer_issued_q[u_dut.u_ctrl.alloc_slot1] <= 1'b0;
            end
            issue_fence_count <= issue_fence_count + {31'b0, u_dut.id_fence_i};
            issue_slot1_replay_count <= issue_slot1_replay_count +
                {31'b0, u_dut.issue_slot1_replay};
            issue_slot1_dependency_replay_count <= issue_slot1_dependency_replay_count +
                {31'b0, (u_dut.issue_slot1_replay && u_dut.issue_dependency_wait1)};
            issue_slot1_lsu_replay_count <= issue_slot1_lsu_replay_count +
                {31'b0, (u_dut.issue_slot1_replay && u_dut.issue_lsu_struct_stall1)};
            issue_serialize_wait_count <= issue_serialize_wait_count +
                {31'b0, u_dut.issue_serialize_stall};
            operandq_occ_count[u_dut.u_ydrasil_commit_trace.issue_pipe_count_q] <=
                operandq_occ_count[u_dut.u_ydrasil_commit_trace.issue_pipe_count_q] + 1'b1;
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
            stall_dependency_count <= stall_dependency_count +
                (u_dut.u_ydrasil_commit_trace.dependency_wait ? 32'd1 : 32'd0);
            stall_lsu_struct_count <= stall_lsu_struct_count +
                (u_dut.u_ydrasil_commit_trace.lsu_struct_stall ? 32'd1 : 32'd0);
            stall_wb_backpressure_count <= stall_wb_backpressure_count +
                (u_dut.u_ydrasil_commit_trace.wb_backpressure ? 32'd1 : 32'd0);
            stall_clint_count <= stall_clint_count +
                (u_dut.u_ydrasil_commit_trace.clint_stall ? 32'd1 : 32'd0);
            stall_mul_count <= stall_mul_count +
                (u_dut.ex_mul_stall ? 32'd1 : 32'd0);
            completion_alu_lsu_q <=
                u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid;
            completion_mul_q <=
                u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid;
            completion_alu_lsu_count <= completion_alu_lsu_count +
                ((u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid) ? 32'd1 : 32'd0);
            completion_alu_mul_count <= completion_alu_mul_count +
                ((u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_lsu_mul_count <= completion_lsu_mul_count +
                ((u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_all_count <= completion_all_count +
                ((u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_alu_lsu_then_mul_count <=
                completion_alu_lsu_then_mul_count +
                ((completion_alu_lsu_q &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_MUL].valid) ? 32'd1 : 32'd0);
            completion_mul_then_alu_lsu_count <=
                completion_mul_then_alu_lsu_count +
                ((completion_mul_q &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_ALU].valid &&
                  u_dut.u_ydrasil_commit_trace.completion_bus[ydrasil_pkg::COMPLETION_LSU].valid) ? 32'd1 : 32'd0);
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
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 32'd1 : 32'd0);
            same_slot_retire_only_count <= same_slot_retire_only_count +
                ((|(u_dut.u_ctrl.producer_retire_q &
                    ~u_dut.u_ctrl.producer_complete_mask &
                    ~(u_dut.u_ctrl.producer_alloc_ex ?
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 32'd1 : 32'd0);
            same_slot_allocate_only_count <= same_slot_allocate_only_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  !u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  !u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]]) ? 32'd1 : 32'd0);
            same_slot_complete_retire_count <= same_slot_complete_retire_count +
                ((|(u_dut.u_ctrl.producer_complete_mask &
                    u_dut.u_ctrl.producer_retire_q &
                    ~(u_dut.u_ctrl.producer_alloc_ex ?
                      (ydrasil_pkg::PRODUCER_NUM'(1) << u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]) : '0))) ? 32'd1 : 32'd0);
            same_slot_retire_allocate_count <= same_slot_retire_allocate_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  !u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]]) ? 32'd1 : 32'd0);
            same_slot_complete_allocate_count <= same_slot_complete_allocate_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  !u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]]) ? 32'd1 : 32'd0);
            same_slot_all_count <= same_slot_all_count +
                ((u_dut.u_ctrl.producer_alloc_ex &&
                  u_dut.u_ctrl.producer_complete_mask[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]] &&
                  u_dut.u_ctrl.producer_retire_q[u_dut.ex_hzd_pkt.producer_id[ydrasil_pkg::PRODUCER_SLOT_WIDTH-1:0]]) ? 32'd1 : 32'd0);
            dep_rs1_pending_count <= dep_rs1_pending_count +
                (u_dut.u_ydrasil_commit_trace.rs1_pending_stall ? 32'd1 : 32'd0);
            dep_rs2_pending_count <= dep_rs2_pending_count +
                (u_dut.u_ydrasil_commit_trace.rs2_pending_stall ? 32'd1 : 32'd0);
            dep_rd_waw_count <= dep_rd_waw_count +
                (u_dut.u_ydrasil_commit_trace.rd_waw_stall ? 32'd1 : 32'd0);
            dep_issue_rs1_hzd_count <= dep_issue_rs1_hzd_count +
                (u_dut.u_ydrasil_commit_trace.rs1_issue_hzd ? 32'd1 : 32'd0);
            dep_issue_rs2_hzd_count <= dep_issue_rs2_hzd_count +
                (u_dut.u_ydrasil_commit_trace.rs2_issue_hzd ? 32'd1 : 32'd0);
            dep_issue_rd_hzd_count <= dep_issue_rd_hzd_count +
                (u_dut.u_ydrasil_commit_trace.rd_issue_hzd ? 32'd1 : 32'd0);
            dep_load_use_count <= dep_load_use_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd) ? 32'd1 : 32'd0);
            dep_alu_use_count <= dep_alu_use_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd) ? 32'd1 : 32'd0);
            dep_mul_div_use_count <= dep_mul_div_use_count +
                ((u_dut.u_ydrasil_commit_trace.issue_mul_div_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd) ? 32'd1 : 32'd0);
            dep_branch_src_wait_count <= dep_branch_src_wait_count +
                ((u_dut.u_ydrasil_commit_trace.dependency_wait &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            dep_store_addr_wait_count <= dep_store_addr_wait_count +
                ((u_dut.u_ydrasil_commit_trace.dependency_wait &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.u_ydrasil_commit_trace.rs1_pending_stall | u_dut.u_ydrasil_commit_trace.rs1_issue_hzd)) ? 32'd1 : 32'd0);
            dep_store_data_wait_count <= dep_store_data_wait_count +
                ((u_dut.u_ydrasil_commit_trace.dependency_wait &&
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.u_ydrasil_commit_trace.rs2_pending_stall | u_dut.u_ydrasil_commit_trace.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            dep_load_to_alu_count <= dep_load_to_alu_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU]) ? 32'd1 : 32'd0);
            dep_load_to_branch_count <= dep_load_to_branch_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            dep_load_to_load_count <= dep_load_to_load_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]) ? 32'd1 : 32'd0);
            dep_load_to_store_count <= dep_load_to_store_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) ? 32'd1 : 32'd0);
            dep_load_to_mul_count <= dep_load_to_mul_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]) ? 32'd1 : 32'd0);
            dep_load_to_other_count <= dep_load_to_other_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  !(u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL])) ? 32'd1 : 32'd0);
            dep_load_rs1_count <= dep_load_rs1_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.rs1_issue_hzd) ? 32'd1 : 32'd0);
            dep_load_rs2_count <= dep_load_rs2_count +
                ((u_dut.u_ydrasil_commit_trace.issue_load_producer & u_dut.u_ydrasil_commit_trace.rs2_issue_hzd) ? 32'd1 : 32'd0);
            dep_pending_tail_count <= dep_pending_tail_count +
                (((u_dut.u_ydrasil_commit_trace.rs1_pending_stall | u_dut.u_ydrasil_commit_trace.rs2_pending_stall) &
                  !(u_dut.u_ydrasil_commit_trace.rs1_issue_hzd | u_dut.u_ydrasil_commit_trace.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            dep_alu_to_alu_count <= dep_alu_to_alu_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU]) ? 32'd1 : 32'd0);
            dep_alu_to_branch_count <= dep_alu_to_branch_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            dep_alu_to_load_count <= dep_alu_to_load_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD]) ? 32'd1 : 32'd0);
            dep_alu_to_store_count <= dep_alu_to_store_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE]) ? 32'd1 : 32'd0);
            dep_alu_to_mul_count <= dep_alu_to_mul_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]) ? 32'd1 : 32'd0);
            dep_alu_to_other_count <= dep_alu_to_other_count +
                ((u_dut.u_ydrasil_commit_trace.issue_alu_producer & u_dut.u_ydrasil_commit_trace.issue_src_hzd &
                  !(u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_ALU] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] |
                    u_dut.u_ydrasil_issue_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL])) ? 32'd1 : 32'd0);
            if ((u_dut.u_ydrasil_commit_trace.rs1_pending_stall | u_dut.u_ydrasil_commit_trace.rs2_pending_stall) &&
                !(u_dut.u_ydrasil_commit_trace.rs1_issue_hzd | u_dut.u_ydrasil_commit_trace.rs2_issue_hzd)) begin
                if ((u_dut.u_ydrasil_commit_trace.rs1_pending_stall && u_dut.issue_head_compact_uop.src0.producer_class == ydrasil_pkg::RESULT_LSU) ||
                    (u_dut.u_ydrasil_commit_trace.rs2_pending_stall && u_dut.issue_head_compact_uop.src1.producer_class == ydrasil_pkg::RESULT_LSU))
                    dep_pending_load_count <= dep_pending_load_count + 1'b1;
                else if ((u_dut.u_ydrasil_commit_trace.rs1_pending_stall && u_dut.issue_head_compact_uop.src0.producer_class == ydrasil_pkg::RESULT_MDU) ||
                         (u_dut.u_ydrasil_commit_trace.rs2_pending_stall && u_dut.issue_head_compact_uop.src1.producer_class == ydrasil_pkg::RESULT_MDU))
                    dep_pending_mul_count <= dep_pending_mul_count + 1'b1;
                else if ((u_dut.u_ydrasil_commit_trace.rs1_pending_stall && u_dut.issue_head_compact_uop.src0.producer_class == ydrasil_pkg::RESULT_ALU) ||
                         (u_dut.u_ydrasil_commit_trace.rs2_pending_stall && u_dut.issue_head_compact_uop.src1.producer_class == ydrasil_pkg::RESULT_ALU))
                    dep_pending_alu_count <= dep_pending_alu_count + 1'b1;
                else
                    dep_pending_other_count <= dep_pending_other_count + 1'b1;
            end
            dep_ready_but_stall_count <= dep_ready_but_stall_count +
                ((u_dut.u_ydrasil_commit_trace.dependency_wait &&
                  ((u_dut.u_ctrl.rs1_has_producer && u_dut.u_ctrl.rs1_producer_done) ||
                   (u_dut.u_ctrl.rs2_has_producer && u_dut.u_ctrl.rs2_producer_done))) ? 32'd1 : 32'd0);
            dep_complete_visible_count <= dep_complete_visible_count +
                (((u_dut.u_ctrl.rs1_has_producer &&
                   u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs1_producer_slot]) ||
                  (u_dut.u_ctrl.rs2_has_producer &&
                   u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs2_producer_slot])) ? 32'd1 : 32'd0);
            dep_registered_visible_count <= dep_registered_visible_count +
                (((u_dut.u_ctrl.rs1_has_producer &&
                   u_dut.u_ctrl.producer_done_q[u_dut.u_ctrl.rs1_producer_slot]) ||
                  (u_dut.u_ctrl.rs2_has_producer &&
                   u_dut.u_ctrl.producer_done_q[u_dut.u_ctrl.rs2_producer_slot])) ? 32'd1 : 32'd0);
            // MUL tail attribution.  A result that cannot find its producer
            // identifies a slot-lifetime problem; a matched but not-yet-ready
            // result identifies Future File ready latency; a matching blocked
            // consumer identifies the remaining missing direct bypass case.
            mul_tail_slot_release_late_count <= mul_tail_slot_release_late_count +
                ((u_dut.mul_result_valid &&
                  !(|u_dut.u_ctrl.producer_complete_mask)) ? 32'd1 : 32'd0);
            mul_tail_ready_late_count <= mul_tail_ready_late_count +
                ((u_dut.mul_result_valid &&
                  (|u_dut.u_ctrl.producer_complete_mask) &&
                  !((u_dut.u_ctrl.rs1_has_producer &&
                     u_dut.u_ctrl.producer_done_q[u_dut.u_ctrl.rs1_producer_slot]) ||
                    (u_dut.u_ctrl.rs2_has_producer &&
                     u_dut.u_ctrl.producer_done_q[u_dut.u_ctrl.rs2_producer_slot]))) ? 32'd1 : 32'd0);
            mul_tail_consumer_no_bypass_count <= mul_tail_consumer_no_bypass_count +
                ((u_dut.mul_result_valid && u_dut.u_ydrasil_commit_trace.dependency_wait &&
                  ((u_dut.u_ctrl.rs1_has_producer &&
                    u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs1_producer_slot]) ||
                   (u_dut.u_ctrl.rs2_has_producer &&
                    u_dut.u_ctrl.producer_complete_mask[u_dut.u_ctrl.rs2_producer_slot]))) ? 32'd1 : 32'd0);

            // Mutually exclusive cycle accounting. Keep this TB-only so it cannot affect RTL.
            if (perf_cycle_flush) begin
                acct_flush_count <= acct_flush_count + 1'b1;
                perf_lost_flush_slot_count <= perf_lost_flush_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_mul_hold) begin
                acct_mul_hold_count <= acct_mul_hold_count + 1'b1;
                perf_lost_mul_hold_slot_count <= perf_lost_mul_hold_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_multi_cause) begin
                acct_multi_cause_count <= acct_multi_cause_count + 1'b1;
                perf_lost_multi_slot_count <= perf_lost_multi_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_dependency) begin
                acct_dependency_count <= acct_dependency_count + 1'b1;
                perf_lost_dependency_slot_count <= perf_lost_dependency_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_lsu_struct) begin
                acct_lsu_struct_count <= acct_lsu_struct_count + 1'b1;
                perf_lost_lsu_struct_slot_count <= perf_lost_lsu_struct_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_producer_full) begin
                acct_producer_full_count <= acct_producer_full_count + 1'b1;
                perf_lost_producer_full_slot_count <= perf_lost_producer_full_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_wb) begin
                acct_wb_count <= acct_wb_count + 1'b1;
                perf_lost_wb_slot_count <= perf_lost_wb_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_clint) begin
                acct_clint_count <= acct_clint_count + 1'b1;
                perf_lost_clint_slot_count <= perf_lost_clint_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_lsu_serialize) begin
                acct_lsu_serialize_count <= acct_lsu_serialize_count + 1'b1;
                perf_lost_lsu_serialize_slot_count <= perf_lost_lsu_serialize_slot_count + perf_lost_slots_ext;
            end else if (perf_cycle_no_if_valid) begin
                acct_no_if_valid_count <= acct_no_if_valid_count + 1'b1;
                perf_lost_no_if_valid_slot_count <= perf_lost_no_if_valid_slot_count + perf_lost_slots_ext;
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
                if (control_refill_active_q)
                    perf_noif_control_redirect_slots <=
                        perf_noif_control_redirect_slots + perf_lost_slots_ext;
                else if (predict_refill_active_q)
                    perf_noif_predict_redirect_slots <=
                        perf_noif_predict_redirect_slots + perf_lost_slots_ext;
                else if (fence_refill_active_q)
                    perf_noif_fence_refill_slots <=
                        perf_noif_fence_refill_slots + perf_lost_slots_ext;
                else if (u_dut.u_ydrasil_if_stage.mem_req_valid_ff)
                    perf_noif_mem_response_slots <=
                        perf_noif_mem_response_slots + perf_lost_slots_ext;
                else if (u_dut.u_ydrasil_if_stage.fetch_issue)
                    perf_noif_fetch_launch_slots <=
                        perf_noif_fetch_launch_slots + perf_lost_slots_ext;
                else if (u_dut.u_ydrasil_if_stage.pending_redirect_valid_ff)
                    perf_noif_pending_redirect_slots <=
                        perf_noif_pending_redirect_slots + perf_lost_slots_ext;
                else
                    perf_noif_other_slots <=
                        perf_noif_other_slots + perf_lost_slots_ext;
            end else if (perf_cycle_issue) begin
                acct_issue_count <= acct_issue_count + 1'b1;
                perf_lost_issue_slot_count <= perf_lost_issue_slot_count + perf_lost_slots_ext;
                if (perf_operand_dependency_miss_now)
                    perf_issue_dependency_slots <=
                        perf_issue_dependency_slots + perf_lost_slots_ext;
                else if (u_dut.issue_lsu_struct_stall ||
                         u_dut.issue_lsu_struct_stall1)
                    perf_issue_lsu_struct_slots <=
                        perf_issue_lsu_struct_slots + perf_lost_slots_ext;
                else if (u_dut.issue_serialize_stall)
                    perf_issue_serialize_slots <=
                        perf_issue_serialize_slots + perf_lost_slots_ext;
                else if (perf_operand_admit_slots == 2'd1)
                    perf_issue_single_lane_slots <=
                        perf_issue_single_lane_slots + perf_lost_slots_ext;
                else
                    perf_issue_no_execute_slots <=
                        perf_issue_no_execute_slots + perf_lost_slots_ext;
            end else begin
                acct_other_count <= acct_other_count + 1'b1;
                perf_lost_other_slot_count <= perf_lost_other_slot_count + perf_lost_slots_ext;
                if (!u_dut.u_ydrasil_issue_stage.issue_valid_ff && u_dut.u_ydrasil_commit_trace.decode_valid)
                    other_issue_refill_count <= other_issue_refill_count + 1'b1;
                else if (!u_dut.u_ydrasil_issue_stage.issue_valid_ff &&
                         !u_dut.u_ydrasil_commit_trace.decode_valid && u_dut.u_ydrasil_commit_trace.decode_if_ready) begin
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

                // The legacy OTHER bucket was hiding several distinct
                // backpressure states. Keep this decomposition in the same
                // mutually-exclusive arm so its sum is exactly OTHER slots.
                if (!u_dut.decode_if_ready) begin
                    if (u_dut.u_ydrasil_issue_stage.credit_resync_q != '0)
                        perf_other_recovery_resync_slots <=
                            perf_other_recovery_resync_slots + perf_lost_slots_ext;
                    else if (!u_dut.dispatch_ready)
                        perf_other_rob_block_slots <=
                            perf_other_rob_block_slots + perf_lost_slots_ext;
                    else if (!u_dut.u_ydrasil_issue_stage.dispatch_slots_available) begin
                        perf_other_rs_bank_block_slots <=
                            perf_other_rs_bank_block_slots + perf_lost_slots_ext;
                        if (u_dut.u_ydrasil_issue_stage.dispatch0_alu) begin
                            perf_other_alu_bank_block_slots <=
                                perf_other_alu_bank_block_slots + perf_lost_slots_ext;
                            if (u_dut.u_ydrasil_issue_stage.alu_free_count == 3'd0)
                                perf_bank_alu_local_full_slots <=
                                    perf_bank_alu_local_full_slots + perf_lost_slots_ext;
                            else if (u_dut.u_ydrasil_issue_stage.alu_effective_credit == 4'd0)
                                perf_bank_alu_credit_stale_slots <=
                                    perf_bank_alu_credit_stale_slots + perf_lost_slots_ext;
                            else
                                perf_bank_unclassified_slots <=
                                    perf_bank_unclassified_slots + perf_lost_slots_ext;
                        end else if (u_dut.u_ydrasil_issue_stage.dispatch0_p0) begin
                            perf_other_p0_bank_block_slots <=
                                perf_other_p0_bank_block_slots + perf_lost_slots_ext;
                            if (u_dut.u_ydrasil_issue_stage.p0_free_count == 3'd0) begin
                                perf_bank_p0_local_full_slots <=
                                    perf_bank_p0_local_full_slots + perf_lost_slots_ext;
                                perf_p0_full_store_mix_slots[$countones(
                                    u_dut.u_ydrasil_issue_stage.issue_store_q[7:4] &
                                    u_dut.u_ydrasil_issue_stage.issue_window_valid_q[7:4])] <=
                                    perf_p0_full_store_mix_slots[$countones(
                                        u_dut.u_ydrasil_issue_stage.issue_store_q[7:4] &
                                        u_dut.u_ydrasil_issue_stage.issue_window_valid_q[7:4])] +
                                    perf_lost_slots_ext;
                                if (u_dut.u_ydrasil_issue_stage.dispatch_compact_uop.op_class ==
                                    UOP_CLASS_LOAD)
                                    perf_p0_full_blocked_load_slots <=
                                        perf_p0_full_blocked_load_slots +
                                        perf_lost_slots_ext;
                                else if (u_dut.u_ydrasil_issue_stage.
                                             dispatch_compact_uop.op_class ==
                                         UOP_CLASS_STORE)
                                    perf_p0_full_blocked_store_slots <=
                                        perf_p0_full_blocked_store_slots +
                                        perf_lost_slots_ext;
                                else
                                    perf_p0_full_blocked_other_slots <=
                                        perf_p0_full_blocked_other_slots +
                                        perf_lost_slots_ext;
                                perf_p0_credit_resv_slots[
                                    (3 * u_dut.lsu_issue_credit) +
                                    u_dut.u_ydrasil_issue_stage.
                                        lsu_select_reserved_q] <=
                                    perf_p0_credit_resv_slots[
                                        (3 * u_dut.lsu_issue_credit) +
                                        u_dut.u_ydrasil_issue_stage.
                                            lsu_select_reserved_q] +
                                    perf_lost_slots_ext;
                                if (u_dut.u_ydrasil_issue_stage.p0_select_valid)
                                    perf_p0_pipe_selectable_slots <=
                                        perf_p0_pipe_selectable_slots +
                                        perf_lost_slots_ext;
                                else if (perf_p0_resource_wait)
                                    perf_p0_pipe_credit_blocked_slots <=
                                        perf_p0_pipe_credit_blocked_slots +
                                        perf_lost_slots_ext;
                                else if (perf_p0_order_wait)
                                    perf_p0_pipe_order_blocked_slots <=
                                        perf_p0_pipe_order_blocked_slots +
                                        perf_lost_slots_ext;
                                else
                                    perf_p0_pipe_dependency_blocked_slots <=
                                        perf_p0_pipe_dependency_blocked_slots +
                                        perf_lost_slots_ext;
                                if (u_dut.u_ydrasil_issue_stage.p0_select_valid)
                                    perf_p0_full_ready_release_slots <=
                                        perf_p0_full_ready_release_slots + perf_lost_slots_ext;
                                else if (perf_p0_dependency_wait)
                                    perf_p0_full_dependency_slots <=
                                        perf_p0_full_dependency_slots + perf_lost_slots_ext;
                                else if (perf_p0_order_wait)
                                    perf_p0_full_order_slots <=
                                        perf_p0_full_order_slots + perf_lost_slots_ext;
                                else if (perf_p0_resource_wait)
                                    perf_p0_full_resource_slots <=
                                        perf_p0_full_resource_slots + perf_lost_slots_ext;
                                else
                                    perf_p0_full_no_candidate_slots <=
                                        perf_p0_full_no_candidate_slots + perf_lost_slots_ext;
                            end
                            else if (u_dut.u_ydrasil_issue_stage.p0_effective_credit == 4'd0)
                                perf_bank_p0_credit_stale_slots <=
                                    perf_bank_p0_credit_stale_slots + perf_lost_slots_ext;
                            else
                                perf_bank_unclassified_slots <=
                                    perf_bank_unclassified_slots + perf_lost_slots_ext;
                        end else begin
                            perf_other_p1_bank_block_slots <=
                                perf_other_p1_bank_block_slots + perf_lost_slots_ext;
                            if (u_dut.u_ydrasil_issue_stage.p1_free_count == 3'd0)
                                perf_bank_p1_local_full_slots <=
                                    perf_bank_p1_local_full_slots + perf_lost_slots_ext;
                            else if (u_dut.u_ydrasil_issue_stage.p1_effective_credit == 4'd0)
                                perf_bank_p1_credit_stale_slots <=
                                    perf_bank_p1_credit_stale_slots + perf_lost_slots_ext;
                            else
                                perf_bank_unclassified_slots <=
                                    perf_bank_unclassified_slots + perf_lost_slots_ext;
                        end
                    end else if (!u_dut.dispatch_two_ready ||
                             !u_dut.u_ydrasil_issue_stage.dispatch_pair_slots_available)
                        perf_other_rs_pair_limit_slots <=
                            perf_other_rs_pair_limit_slots + perf_lost_slots_ext;
                    else
                        perf_other_decode_block_slots <=
                            perf_other_decode_block_slots + perf_lost_slots_ext;
                end else if (u_dut.u_ydrasil_issue_stage.select_buf_push) begin
                    perf_other_select_refill_slots <=
                        perf_other_select_refill_slots + perf_lost_slots_ext;
                end else if (|u_dut.u_ydrasil_issue_stage.issue_window_valid_q) begin
                    if (perf_rs_dependency_wait)
                        perf_other_rs_dependency_slots <=
                            perf_other_rs_dependency_slots + perf_lost_slots_ext;
                    else if (perf_rs_order_wait)
                        perf_other_rs_order_slots <=
                            perf_other_rs_order_slots + perf_lost_slots_ext;
                    else if (perf_rs_resource_wait)
                        perf_other_rs_resource_slots <=
                            perf_other_rs_resource_slots + perf_lost_slots_ext;
                    else
                        perf_other_rs_no_candidate_slots <=
                            perf_other_rs_no_candidate_slots + perf_lost_slots_ext;
                end else if (u_dut.if_id_valid) begin
                    perf_other_rs_empty_slots <=
                        perf_other_rs_empty_slots + perf_lost_slots_ext;
                end else begin
                    perf_other_unclassified_slots <=
                        perf_other_unclassified_slots + perf_lost_slots_ext;
                end
            end

            if (u_dut.u_ydrasil_commit_trace.dependency_wait) begin
                if ((u_dut.u_ydrasil_commit_trace.rs1_issue_hzd | u_dut.u_ydrasil_commit_trace.rs2_issue_hzd |
                     u_dut.u_ydrasil_commit_trace.rs1_pending_stall | u_dut.u_ydrasil_commit_trace.rs2_pending_stall) &&
                    (u_dut.u_ydrasil_commit_trace.rd_issue_hzd | u_dut.u_ydrasil_commit_trace.rd_waw_stall))
                    acct_raw_waw_count <= acct_raw_waw_count + 1'b1;
                else if (u_dut.u_ydrasil_commit_trace.rd_issue_hzd | u_dut.u_ydrasil_commit_trace.rd_waw_stall)
                    acct_waw_only_count <= acct_waw_only_count + 1'b1;
                else
                    acct_raw_only_count <= acct_raw_only_count + 1'b1;
            end

            unique case (u_dut.u_ydrasil_commit_trace.instret_inc_count)
                3'd0: retire_zero_count <= retire_zero_count + 1'b1;
                3'd1: retire_one_count <= retire_one_count + 1'b1;
                3'd2: retire_two_count <= retire_two_count + 1'b1;
                3'd3: retire_three_count <= retire_three_count + 1'b1;
                3'd4: retire_four_count <= retire_four_count + 1'b1;
                default: begin end
            endcase
            if (u_dut.u_ydrasil_commit_trace.issue_pair_execute) begin
                dual_issue_count <= dual_issue_count + 1'b1;
                if ((u_dut.issue_head_compact_uop.op_class ==
                     ydrasil_pkg::UOP_CLASS_BJP) ||
                    (u_dut.issue_head_compact_uop1.op_class ==
                     ydrasil_pkg::UOP_CLASS_BJP))
                    dual_bru_alu_count <= dual_bru_alu_count + 1'b1;
                else if ((u_dut.issue_head_compact_uop.op_class == ydrasil_pkg::UOP_CLASS_LOAD) ||
                         (u_dut.issue_head_compact_uop.op_class == ydrasil_pkg::UOP_CLASS_STORE) ||
                         (u_dut.issue_head_compact_uop1.op_class == ydrasil_pkg::UOP_CLASS_LOAD) ||
                         (u_dut.issue_head_compact_uop1.op_class == ydrasil_pkg::UOP_CLASS_STORE))
                    dual_lsu_alu_count <= dual_lsu_alu_count + 1'b1;
                else if ((u_dut.issue_head_compact_uop.op_class ==
                          ydrasil_pkg::UOP_CLASS_MUL) ||
                         (u_dut.issue_head_compact_uop1.op_class ==
                          ydrasil_pkg::UOP_CLASS_MUL))
                    dual_muldiv_alu_count <= dual_muldiv_alu_count + 1'b1;
                else if ((u_dut.issue_head_compact_uop.op_class == ydrasil_pkg::UOP_CLASS_ALU) ||
                         (u_dut.issue_head_compact_uop.op_class == ydrasil_pkg::UOP_CLASS_BITMANIP))
                    dual_alu_alu_count <= dual_alu_alu_count + 1'b1;
                else
                    dual_other_count <= dual_other_count + 1'b1;
            end
			assert (dual_alu_alu_count + dual_bru_alu_count +
				dual_lsu_alu_count + dual_muldiv_alu_count +
				dual_other_count == dual_issue_count)
				else $fatal(1, "dual-issue resource classification lost a pair");
            if (u_dut.u_ydrasil_if_stage.fetch_issue) begin
                l0_lookup_count <= l0_lookup_count +
                    (u_dut.u_ydrasil_if_stage.fetch_two ? 32'd2 : 32'd1);
                l0_hit_count <= l0_hit_count + {31'b0, u_dut.l0_hit} +
                    (u_dut.u_ydrasil_if_stage.fetch_two ?
                        {31'b0, u_dut.l0_hit1} : 32'd0);
            end
            if (u_dut.u_ydrasil_if_stage.predict_correction_resp) begin
                l0_correction_count <= l0_correction_count + 1'b1;
            end

            bubble_cause_hist[{u_dut.u_ydrasil_commit_trace.clint_stall, u_dut.u_ydrasil_commit_trace.wb_backpressure,
                u_dut.u_ctrl.producer_full_stall, u_dut.u_ydrasil_commit_trace.lsu_struct_stall,
                u_dut.u_ydrasil_commit_trace.dependency_wait}] <=
                bubble_cause_hist[{u_dut.u_ydrasil_commit_trace.clint_stall, u_dut.u_ydrasil_commit_trace.wb_backpressure,
                    u_dut.u_ctrl.producer_full_stall, u_dut.u_ydrasil_commit_trace.lsu_struct_stall,
                    u_dut.u_ydrasil_commit_trace.dependency_wait}] + 1'b1;
            if ($countones(u_dut.u_ctrl.producer_valid_q &
                           ~u_dut.u_ctrl.producer_retire_q) == 0) begin
                producer_occ_zero_count <= producer_occ_zero_count + 1'b1;
            end else if ($countones(u_dut.u_ctrl.producer_valid_q &
                                    ~u_dut.u_ctrl.producer_retire_q) == 1) begin
                producer_occ_one_count <= producer_occ_one_count + 1'b1;
            end else begin
                producer_occ_two_count <= producer_occ_two_count + 1'b1;
                if (|(u_dut.u_ctrl.producer_done_q &
                      u_dut.u_ctrl.producer_valid_q))
                    producer_wait_ready_count <= producer_wait_ready_count + 1'b1;
                else
                    producer_both_wait_count <= producer_both_wait_count + 1'b1;
                if ((u_dut.u_ctrl.producer_done_q &
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
                (u_dut.u_ydrasil_load_store_unit.queue_head_q == 1'b1))
                lsu_head_wrap_count <= lsu_head_wrap_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_enqueue &&
                (u_dut.u_ydrasil_load_store_unit.queue_tail_q == 1'b1))
                lsu_tail_wrap_count <= lsu_tail_wrap_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_empty)
                lsu_queue_empty_count <= lsu_queue_empty_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_count_q == 3)
                lsu_queue_near_full_count <= lsu_queue_near_full_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_full)
                lsu_queue_full_count <= lsu_queue_full_count + 1'b1;
            if (u_dut.u_ydrasil_load_store_unit.queue_dequeue)
                lsu_queue_pop_count <= lsu_queue_pop_count + 1'b1;
            if (u_dut.u_ydrasil_commit_trace.lsu_struct_stall) begin
                if (u_dut.u_ydrasil_load_store_unit.mmio_busy)
                    lsu_struct_mmio_count <= lsu_struct_mmio_count + 1'b1;
                else if (u_dut.u_ydrasil_load_store_unit.active_pkt.is_store &&
                         !u_dut.u_ydrasil_load_store_unit.active_store_data_valid)
                    lsu_struct_pending_store_count <= lsu_struct_pending_store_count + 1'b1;
                else if (u_dut.u_ydrasil_load_store_unit.queue_enqueue)
                    lsu_struct_store_capture_count <= lsu_struct_store_capture_count + 1'b1;
                else
                    lsu_struct_other_count <= lsu_struct_other_count + 1'b1;
            end
            if (u_dut.u_ydrasil_issue_stage.issue_early_alu_valid_ff) begin
                early_arith_count <= early_arith_count +
                    {31'b0, u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[0]};
                early_logic_count <= early_logic_count +
                    {31'b0, u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[1]};
                early_shift_count <= early_shift_count +
                    {31'b0, u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[2]};
                early_pass_count <= early_pass_count +
                    {31'b0, u_dut.u_ydrasil_issue_stage.issue_early_kind_ff[3]};
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

    wire lane0_finish_accept = retire0_valid &&
        (retire0_pc == finish_pc);
    wire lane1_finish_accept = retire1_valid &&
        (retire1_pc == finish_pc);
    wire [1:0] finish_accept_count =
        {1'b0, lane0_finish_accept} + {1'b0, lane1_finish_accept};

    // Count committed write_tohost loop entries on either retire lane. Pairing
    // retire validity with retire PC avoids crossing the EX and ROB stages in
    // the monitor itself.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_write_to_host_cnt   <= 32'b0;
            pc_write_to_host_flag  <= 1'b0;
            pc_write_to_host_cycle <= 32'b0;
        end else if (finish_accept_count != 2'b0) begin
            pc_write_to_host_cnt <= pc_write_to_host_cnt +
                {{30{1'b0}}, finish_accept_count};
            if (!pc_write_to_host_flag) begin
                pc_write_to_host_cycle <= cycle_count;
                pc_write_to_host_flag  <= 1'b1;
            end
        end
    end

    // 测试用例解析与ITCM加载
    initial begin
        if ($value$plusargs("itcm_init=%s", testcase)) begin
            display_testcase_name();
            $display("");

            $readmemh({testcase, ".verilog"}, prog_mem);
            for (i = 0; i < ITCM_DEPTH; i = i + 1) begin
                `ITCM.mem_r[i] = {
                    prog_mem[i*8+7], prog_mem[i*8+6], prog_mem[i*8+5], prog_mem[i*8+4],
                    prog_mem[i*8+3], prog_mem[i*8+2], prog_mem[i*8+1], prog_mem[i*8+0]
                };
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
		$monitor("[TB] time=%0t, rst_n=%b, LED=0x%08h, seg_wdata=0x%08h",
			$time, rst_n, LED, seg_wdata);
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
	logic perip_req_q;
	localparam integer SIM_STDOUT_BUFFER_BYTES = 4096;
	byte sim_stdout_buffer [0:SIM_STDOUT_BUFFER_BYTES-1];
	integer sim_stdout_length;
	integer sim_stdout_flush_idx;
	integer sim_stdout_capture_count;
	logic sim_stdout_apb_setup_q;
	logic sim_stdout_apb_done_q;
	logic sim_stdout_apb_write_q;
	logic [31:0] sim_stdout_apb_addr_q;
	logic [31:0] sim_stdout_apb_wdata_q;
	bit sim_stdout_debug_en;
	bit sim_mmio_debug_en;
	bit sim_apb_wave_debug_en;
	logic sim_axi_req_seen_q;
	integer sim_mmio_stdout_count;
	integer sim_axi_stdout_count;

	wire [31:0] virtual_led_output;
	wire [39:0] virtual_seg_output;
	wire [63:0] virtual_sw_input = 0;
	wire [7:0]  virtual_key_input = 0;
	wire        perip_req = u_mmio_subsystem.apb_req.psel &&
		u_mmio_subsystem.apb_req.penable;
	wire        perip_transfer = perip_req && !perip_req_q;
	assign perip_addr = u_mmio_subsystem.apb_req.paddr;
	assign perip_wen = perip_req && u_mmio_subsystem.apb_req.pwrite;
	assign perip_mask = u_mmio_subsystem.apb_req.pstrb;
	assign perip_wdata = u_mmio_subsystem.apb_req.pwdata;
	assign perip_rdata = u_mmio_subsystem.apb_rsp.prdata;

	initial begin
		finish_on_led = !$test$plusargs("no_finish_on_led");
		finish_on_terminal_led = $test$plusargs("finish_on_terminal_led");
		finish_on_tohost = !$test$plusargs("no_finish_on_tohost");
		perip_debug_en = $test$plusargs("perip_debug");
		sim_stdout_debug_en = $test$plusargs("stdout_debug");
		sim_mmio_debug_en = $test$plusargs("mmio_stdout_debug");
		sim_apb_wave_debug_en = $test$plusargs("apb_wave_debug");
		sim_mmio_stdout_count = 0;
		sim_axi_stdout_count = 0;
		sim_stdout_capture_count = 0;
		finish_pc = `PC_WRITE_TOHOST;
		void'($value$plusargs("finish_pc=%h", finish_pc));
	end

	ydrasil_mmio_subsystem u_mmio_subsystem (
		.axi_clk            (clk),
		.apb_clk            (apb_clk),
		.rst_n              (rst_n),
		.axi_m2s_i          (axi_m2s),
		.axi_s2m_o          (axi_s2m),
		.external_irq_i     (1'b0),
		.irq_o              (irq),
		.virtual_sw_input   (virtual_sw_input),
		.virtual_key_input  (virtual_key_input),
		.virtual_seg_output (virtual_seg_output),
		.virtual_led_output (virtual_led_output)
	);

	assign LED = virtual_led_output;
	assign seg_wdata = u_mmio_subsystem.u_perip_bridge.seg_wdata_q;
	always_ff @(posedge clk) begin
		if (rst)
			perip_req_q <= 1'b0;
		else
			perip_req_q <= perip_req;
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			sim_done <= 1'b0;
			perf_terminal_printed_q <= 1'b0;
		end else if (perip_transfer && perip_wen && (perip_addr == LED_ADDR) &&
		             ((finish_on_led && (perip_wdata != 32'h0)) ||
		              (finish_on_terminal_led &&
		               ((perip_wdata == 32'h078b7323) ||
		                (perip_wdata == 32'h00504f53))))) begin
			sim_done <= 1'b1;
		end

		if (!rst && !perf_terminal_printed_q && perip_transfer && perip_wen &&
		    (perip_addr == LED_ADDR) &&
		    ((perip_wdata == 32'h078b7323) || (perip_wdata == 32'h00504f53))) begin
			perf_terminal_printed_q <= 1'b1;
			print_perf_metrics();
		end

		if (!rst && perip_debug_en && perip_transfer) begin
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

	// Capture stdout from a local APB waveform: latch the payload in SETUP,
	// then retire exactly once in ACCESS when PREADY is observed.  Keeping the
	// setup payload in the APB domain avoids CPU/APB phase races and makes the
	// monitor independent of the bridge's AXI request toggle.
	always_ff @(posedge apb_clk) begin
		if (rst) begin
			sim_stdout_length <= 0;
			sim_stdout_apb_setup_q <= 1'b0;
			sim_stdout_apb_done_q <= 1'b0;
			sim_stdout_apb_write_q <= 1'b0;
			sim_stdout_apb_addr_q <= '0;
			sim_stdout_apb_wdata_q <= '0;
			sim_stdout_capture_count <= 0;
		end else if (u_mmio_subsystem.apb_req.psel &&
		             !u_mmio_subsystem.apb_req.penable) begin
			sim_stdout_apb_setup_q <= 1'b1;
			sim_stdout_apb_done_q <= 1'b0;
			sim_stdout_apb_write_q <= u_mmio_subsystem.apb_req.pwrite;
			sim_stdout_apb_addr_q <= u_mmio_subsystem.apb_req.paddr;
			sim_stdout_apb_wdata_q <= u_mmio_subsystem.apb_req.pwdata;
		end else if (u_mmio_subsystem.apb_req.psel &&
		             u_mmio_subsystem.apb_req.penable &&
		             u_mmio_subsystem.apb_rsp.pready &&
		             sim_stdout_apb_setup_q && !sim_stdout_apb_done_q) begin
			sim_stdout_apb_done_q <= 1'b1;
			if (sim_stdout_apb_write_q &&
			    (sim_stdout_apb_addr_q == SIM_STDOUT_ADDR)) begin
				sim_stdout_capture_count <= sim_stdout_capture_count + 1;
				if (sim_stdout_debug_en)
					$display("[APB-STDOUT] n=%0d addr=0x%08h data=0x%02h",
						sim_stdout_capture_count,
						sim_stdout_apb_addr_q,
						sim_stdout_apb_wdata_q[7:0]);
				if (sim_stdout_apb_wdata_q[7:0] == 8'h0a) begin
				for (sim_stdout_flush_idx = 0;
				     sim_stdout_flush_idx < sim_stdout_length;
				     sim_stdout_flush_idx = sim_stdout_flush_idx + 1)
					$write("%c", sim_stdout_buffer[sim_stdout_flush_idx]);
				$write("\n");
				$fflush();
				sim_stdout_length <= 0;
			end else if (sim_stdout_length < SIM_STDOUT_BUFFER_BYTES) begin
				sim_stdout_buffer[sim_stdout_length] <=
					sim_stdout_apb_wdata_q[7:0];
				sim_stdout_length <= sim_stdout_length + 1;
			end
		end
		end else if (!u_mmio_subsystem.apb_req.psel) begin
			sim_stdout_apb_setup_q <= 1'b0;
			sim_stdout_apb_done_q <= 1'b0;
		end
		if (!rst && sim_apb_wave_debug_en &&
		    u_mmio_subsystem.apb_req.psel)
			$display("[APB-WAVE] setup=%0b access=%0b ready=%0b write=%0b addr=0x%08h data=0x%02h setup_q=%0b done_q=%0b",
				u_mmio_subsystem.apb_req.psel &&
					!u_mmio_subsystem.apb_req.penable,
				u_mmio_subsystem.apb_req.penable,
				u_mmio_subsystem.apb_rsp.pready,
				u_mmio_subsystem.apb_req.pwrite,
				u_mmio_subsystem.apb_req.paddr,
				u_mmio_subsystem.apb_req.pwdata[7:0],
				sim_stdout_apb_setup_q,
				sim_stdout_apb_done_q);
	end

	// Optional source-side probe.  This is intentionally separate from the
	// APB waveform monitor so a missing AXI/LSU store is distinguishable from a
	// testbench sampling error.
	always_ff @(posedge clk) begin
		if (rst) begin
			sim_mmio_stdout_count <= 0;
		end else if (u_dut.u_ydrasil_load_store_unit.mmio_fire &&
		             (u_dut.u_ydrasil_load_store_unit.active_addr ==
		              SIM_STDOUT_ADDR)) begin
			sim_mmio_stdout_count <= sim_mmio_stdout_count + 1;
		end
		if (!rst && sim_mmio_debug_en &&
			u_dut.u_ydrasil_load_store_unit.mmio_fire &&
			(u_dut.u_ydrasil_load_store_unit.active_addr == SIM_STDOUT_ADDR))
			$display("[MMIO-STDOUT] time=%0t addr=0x%08h data=0x%02h producer=%0d",
				$time,
				u_dut.u_ydrasil_load_store_unit.active_addr,
				u_dut.u_ydrasil_load_store_unit.active_aligned_store_data[7:0],
				u_dut.u_ydrasil_load_store_unit.active_producer_id);
		if (!rst && sim_mmio_debug_en &&
			u_dut.u_ydrasil_load_store_unit.mmio_fire)
			$display("[MMIO-STATE] time=%0t req_q=%0b rsp=%0b busy=%0b axi_state=%0d addr=0x%08h data=0x%02h",
				$time,
				u_dut.u_ydrasil_load_store_unit.mmio_req_valid_q,
				u_dut.mmio_rsp_pkt.valid,
				u_dut.u_ydrasil_load_store_unit.mmio_busy,
				u_dut.u_ydrasil_axi_lite_master.state_q,
				u_dut.u_ydrasil_load_store_unit.active_addr,
				u_dut.u_ydrasil_load_store_unit.active_aligned_store_data[7:0]);
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			sim_axi_req_seen_q <= 1'b0;
			sim_axi_stdout_count <= 0;
		end else if (u_mmio_subsystem.u_axi_to_apb.req_toggle_axi_q !=
		             sim_axi_req_seen_q) begin
			sim_axi_req_seen_q <= u_mmio_subsystem.u_axi_to_apb.req_toggle_axi_q;
			if (u_mmio_subsystem.u_axi_to_apb.req_axi_q.write &&
			    (u_mmio_subsystem.u_axi_to_apb.req_axi_q.addr == SIM_STDOUT_ADDR)) begin
				sim_axi_stdout_count <= sim_axi_stdout_count + 1;
				if (sim_stdout_debug_en)
					$display("[AXI-STDOUT] time=%0t n=%0d data=0x%02h",
						$time,
						sim_axi_stdout_count,
						u_mmio_subsystem.u_axi_to_apb.req_axi_q.wdata[7:0]);
			end
		end
	end

    // 对pc_write_to_host_cnt的变化进行监控
    always @(pc_write_to_host_cnt) begin
        if (finish_on_tohost && (pc_write_to_host_cnt >= 32'd1)) begin
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
                for (r = 0; r < 32; r = r + 1) $display("x%2d = 0x%x", r, u_dut.u_ydrasil_issue_stage.u_registers.registers[r]);
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
            $display("PERF_APB_STDOUT_ACCOUNT: MMIO_FIRE=%-d AXI_TOGGLE=%-d APB_ACCESS_READY=%-d MMIO_TO_AXI_LOSS=%-d AXI_TO_APB_LOSS=%-d END_TO_END_LOSS=%-d",
                sim_mmio_stdout_count,
                sim_axi_stdout_count,
                sim_stdout_capture_count,
                sim_mmio_stdout_count - sim_axi_stdout_count,
                sim_axi_stdout_count - sim_stdout_capture_count,
                sim_mmio_stdout_count - sim_stdout_capture_count);
            $display("PERF_STALL: DEPENDENCY=%-d LSU_STRUCT=%-d WB_BACKPRESSURE=%-d CLINT=%-d MUL_DIV=%-d",
                stall_dependency_count,
                stall_lsu_struct_count,
                stall_wb_backpressure_count,
                stall_clint_count,
                stall_mul_count);
            $display("PERF_RS_DEPENDENCY_DETAIL: RS1_PENDING=%-d RS2_PENDING=%-d RD_WAW=%-d ISSUE_RS1_HZD=%-d ISSUE_RS2_HZD=%-d ISSUE_RD_HZD=%-d LOAD_USE=%-d ALU_USE=%-d MUL_DIV_USE=%-d BRANCH_SRC_WAIT=%-d STORE_ADDR_WAIT=%-d STORE_DATA_WAIT=%-d",
                dep_rs1_pending_count,
                dep_rs2_pending_count,
                dep_rd_waw_count,
                dep_issue_rs1_hzd_count,
                dep_issue_rs2_hzd_count,
                dep_issue_rd_hzd_count,
                dep_load_use_count,
                dep_alu_use_count,
                dep_mul_div_use_count,
                dep_branch_src_wait_count,
                dep_store_addr_wait_count,
                dep_store_data_wait_count);
            $display("PERF_LOAD_DETAIL: TO_ALU=%-d TO_BRANCH=%-d TO_LOAD=%-d TO_STORE=%-d TO_MUL=%-d TO_OTHER=%-d RS1=%-d RS2=%-d PENDING_TAIL=%-d",
                dep_load_to_alu_count,
                dep_load_to_branch_count,
                dep_load_to_load_count,
                dep_load_to_store_count,
                dep_load_to_mul_count,
                dep_load_to_other_count,
                dep_load_rs1_count,
                dep_load_rs2_count,
                dep_pending_tail_count);
            $display("PERF_ALU_DETAIL: TO_ALU=%-d TO_BRANCH=%-d TO_LOAD=%-d TO_STORE=%-d TO_MUL=%-d TO_OTHER=%-d",
                dep_alu_to_alu_count,
                dep_alu_to_branch_count,
                dep_alu_to_load_count,
                dep_alu_to_store_count,
                dep_alu_to_mul_count,
                dep_alu_to_other_count);
            $display("PERF_PENDING_DETAIL: ALU=%-d LOAD=%-d MUL=%-d OTHER=%-d READY_BUT_STALL=%-d COMPLETE_VISIBLE=%-d REGISTERED_VISIBLE=%-d",
                dep_pending_alu_count,
                dep_pending_load_count,
                dep_pending_mul_count,
                dep_pending_other_count,
                dep_ready_but_stall_count,
                dep_complete_visible_count,
                dep_registered_visible_count);
            $display("PERF_MUL_TAIL: SLOT_RELEASE_LATE=%-d READY_LATE=%-d CONSUMER_NO_BYPASS=%-d",
                mul_tail_slot_release_late_count, mul_tail_ready_late_count,
                mul_tail_consumer_no_bypass_count);
            $display("PERF_CYCLE_ACCOUNT: FLUSH=%-d MUL_HOLD=%-d DEPENDENCY=%-d LSU_STRUCT=%-d LSU_SERIALIZE=%-d PRODUCER_FULL=%-d WB=%-d CLINT=%-d MULTI=%-d NO_IF_VALID=%-d ISSUE=%-d OTHER=%-d ACCOUNTED=%-d SAMPLE_CYCLES=%-d ARCH_CYCLE_DELTA=%-d",
                acct_flush_count,
                acct_mul_hold_count,
                acct_dependency_count,
                acct_lsu_struct_count,
                acct_lsu_serialize_count,
                acct_producer_full_count,
                acct_wb_count,
                acct_clint_count,
                acct_multi_cause_count,
                acct_no_if_valid_count,
                acct_issue_count,
                acct_other_count,
                acct_flush_count + acct_mul_hold_count + acct_dependency_count +
                    acct_lsu_struct_count + acct_lsu_serialize_count +
                    acct_producer_full_count + acct_wb_count +
                    acct_clint_count + acct_multi_cause_count + acct_no_if_valid_count +
                    acct_issue_count + acct_other_count,
                perf_sample_cycle_count,
                cycle_count - perf_sample_cycle_count);
            $display("PERF_SLOT_ACCOUNT: CAPACITY_SLOTS=%-d PRODUCTIVE_SLOTS=%-d LOST_SLOTS=%-d ACCOUNTED_SLOTS=%-d EXECUTION_CYCLES=%-d SLOT_IPC=%.4f",
                (perf_sample_cycle_count << 1),
                perf_productive_slot_count,
                (perf_sample_cycle_count << 1) - perf_productive_slot_count,
                (perf_sample_cycle_count << 1),
                perf_sample_cycle_count,
                (perf_sample_cycle_count > 0) ?
                    (perf_productive_slot_count * 1.0) / (perf_sample_cycle_count << 1) : 0.0);
            // Exact state of the two physical EX acceptance slots.  This is
            // intentionally independent of front-end/RS signals, which are
            // one or more registered stages away from EX.
            $display("PERF_EX_SLOT_STATE: ACCEPT0=%-d ACCEPT1=%-d BRANCH_DROP0=%-d BRANCH_DROP1=%-d MUL_DROP0=%-d MUL_DROP1=%-d PIPE_EMPTY0=%-d PIPE_EMPTY1=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_executed_slot0_count,
                perf_executed_slot1_count,
                perf_ex_branch_drop0_count,
                perf_ex_branch_drop1_count,
                perf_ex_mul_drop0_count,
                perf_ex_mul_drop1_count,
                perf_ex_empty0_count,
                perf_ex_empty1_count,
                perf_executed_slot0_count + perf_executed_slot1_count +
                    perf_ex_branch_drop0_count + perf_ex_branch_drop1_count +
                    perf_ex_mul_drop0_count + perf_ex_mul_drop1_count +
                    perf_ex_empty0_count + perf_ex_empty1_count,
                (perf_sample_cycle_count << 1));
            $display("PERF_EX_EMPTY_CAUSE: RESET_PIPE=%-d RECOVERY=%-d FENCE=%-d B_ONLY=%-d SINGLE_HEAD=%-d SELECT_REFILL=%-d RS_DEPENDENCY=%-d RS_ORDER=%-d RS_RESOURCE=%-d RS_NO_CANDIDATE=%-d RS_EMPTY=%-d FRONTEND_EMPTY=%-d LAUNCH_MISMATCH=%-d OTHER=%-d UNMAPPED=%-d UNACCOUNTED_SNAPSHOT=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_ex_empty_reset_count,
                perf_ex_empty_recovery_count,
                perf_ex_empty_fence_count,
                perf_ex_empty_b_only_count,
                perf_ex_empty_single_head_count,
                perf_ex_empty_select_refill_count,
                perf_ex_empty_rs_dependency_count,
                perf_ex_empty_rs_order_count,
                perf_ex_empty_rs_resource_count,
                perf_ex_empty_rs_no_candidate_count,
                perf_ex_empty_rs_empty_count,
                perf_ex_empty_frontend_count,
                perf_ex_empty_launch_mismatch_count,
                perf_ex_empty_other_count,
                perf_ex_empty_unmapped_count,
                (perf_ex_empty0_count + perf_ex_empty1_count) -
                    (perf_ex_empty_reset_count + perf_ex_empty_recovery_count +
                     perf_ex_empty_fence_count + perf_ex_empty_b_only_count +
                     perf_ex_empty_single_head_count +
                     perf_ex_empty_select_refill_count +
                     perf_ex_empty_rs_dependency_count + perf_ex_empty_rs_order_count +
                     perf_ex_empty_rs_resource_count +
                     perf_ex_empty_rs_no_candidate_count + perf_ex_empty_rs_empty_count +
                     perf_ex_empty_frontend_count + perf_ex_empty_launch_mismatch_count +
                     perf_ex_empty_other_count + perf_ex_empty_unmapped_count),
                perf_ex_empty_reset_count + perf_ex_empty_recovery_count +
                    perf_ex_empty_fence_count + perf_ex_empty_b_only_count +
                    perf_ex_empty_single_head_count +
                    perf_ex_empty_select_refill_count +
                    perf_ex_empty_rs_dependency_count + perf_ex_empty_rs_order_count +
                    perf_ex_empty_rs_resource_count +
                    perf_ex_empty_rs_no_candidate_count +
                    perf_ex_empty_rs_empty_count + perf_ex_empty_frontend_count +
                    perf_ex_empty_launch_mismatch_count + perf_ex_empty_other_count +
                    perf_ex_empty_unmapped_count +
                    ((perf_ex_empty0_count + perf_ex_empty1_count) -
                     (perf_ex_empty_reset_count + perf_ex_empty_recovery_count +
                      perf_ex_empty_fence_count + perf_ex_empty_b_only_count +
                      perf_ex_empty_single_head_count +
                      perf_ex_empty_select_refill_count +
                      perf_ex_empty_rs_dependency_count + perf_ex_empty_rs_order_count +
                      perf_ex_empty_rs_resource_count +
                      perf_ex_empty_rs_no_candidate_count + perf_ex_empty_rs_empty_count +
                      perf_ex_empty_frontend_count + perf_ex_empty_launch_mismatch_count +
                perf_ex_empty_other_count + perf_ex_empty_unmapped_count)),
                perf_ex_empty0_count + perf_ex_empty1_count);
            $display("PERF_EX_VALID_HOLD: LANE0=%-d LANE1=%-d TOTAL=%-d",
                perf_ex_valid_hold0_count,
                perf_ex_valid_hold1_count,
                perf_ex_valid_hold0_count + perf_ex_valid_hold1_count);
            // Complete mutually-exclusive partition of both execution slots
            // in every sampled cycle.  Unlike PERF_BACKEND_LOSS, this line
            // includes front-end, issue, and no-execute slots as well.
            $display("PERF_SLOT_REASON: EXECUTED=%-d FLUSH=%-d MUL_HOLD=%-d MULTI_CAUSE=%-d DEPENDENCY=%-d LSU_STRUCT=%-d PRODUCER_FULL=%-d WB=%-d CLINT=%-d LSU_SERIALIZE=%-d NO_IF_VALID=%-d ISSUE=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_productive_slot_count,
                perf_lost_flush_slot_count,
                perf_lost_mul_hold_slot_count,
                perf_lost_multi_slot_count,
                perf_lost_dependency_slot_count,
                perf_lost_lsu_struct_slot_count,
                perf_lost_producer_full_slot_count,
                perf_lost_wb_slot_count,
                perf_lost_clint_slot_count,
                perf_lost_lsu_serialize_slot_count,
                perf_lost_no_if_valid_slot_count,
                perf_lost_issue_slot_count,
                perf_lost_other_slot_count,
                perf_productive_slot_count +
                    perf_lost_flush_slot_count +
                    perf_lost_mul_hold_slot_count +
                    perf_lost_multi_slot_count +
                    perf_lost_dependency_slot_count +
                    perf_lost_lsu_struct_slot_count +
                    perf_lost_producer_full_slot_count +
                    perf_lost_wb_slot_count + perf_lost_clint_slot_count +
                    perf_lost_lsu_serialize_slot_count +
                    perf_lost_no_if_valid_slot_count +
                    perf_lost_issue_slot_count + perf_lost_other_slot_count,
                (perf_sample_cycle_count << 1));
            // Leaf partition of the complete two-slot capacity.  Parent
            // buckets above are useful for a high-level view, but this line
            // deliberately expands every diagnostic family and never counts
            // an RS-bank parent together with its bank children.
            $display("PERF_SLOT_LEAF: EXECUTED_SLOT0=%-d EXECUTED_SLOT1=%-d FLUSH=%-d MUL_HOLD=%-d MULTI_CAUSE=%-d DEPENDENCY=%-d LSU_STRUCT=%-d PRODUCER_FULL=%-d WB=%-d CLINT=%-d LSU_SERIALIZE=%-d NOIF_CONTROL_REDIRECT=%-d NOIF_PREDICT_REDIRECT=%-d NOIF_FENCE_REFILL=%-d NOIF_MEM_RESPONSE=%-d NOIF_FETCH_LAUNCH=%-d NOIF_PENDING_REDIRECT=%-d NOIF_OTHER=%-d ISSUE_SINGLE_LANE=%-d ISSUE_NO_EXECUTE=%-d ROB_BLOCK=%-d RECOVERY_RESYNC=%-d ALU_LOCAL_FULL=%-d ALU_CREDIT_STALE=%-d P0_LOCAL_FULL=%-d P0_CREDIT_STALE=%-d P1_LOCAL_FULL=%-d P1_CREDIT_STALE=%-d RS_BANK_UNCLASSIFIED=%-d RS_PAIR_LIMIT=%-d SELECT_REFILL=%-d RS_DEPENDENCY=%-d RS_ORDER=%-d RS_RESOURCE=%-d RS_NO_CANDIDATE=%-d RS_EMPTY=%-d DECODE_BLOCK=%-d OTHER_UNCLASSIFIED=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_executed_slot0_count,
                perf_executed_slot1_count,
                perf_lost_flush_slot_count,
                perf_lost_mul_hold_slot_count,
                perf_lost_multi_slot_count,
                perf_lost_dependency_slot_count,
                perf_lost_lsu_struct_slot_count,
                perf_lost_producer_full_slot_count,
                perf_lost_wb_slot_count,
                perf_lost_clint_slot_count,
                perf_lost_lsu_serialize_slot_count,
                perf_noif_control_redirect_slots,
                perf_noif_predict_redirect_slots,
                perf_noif_fence_refill_slots,
                perf_noif_mem_response_slots,
                perf_noif_fetch_launch_slots,
                perf_noif_pending_redirect_slots,
                perf_noif_other_slots,
                perf_issue_single_lane_slots,
                perf_issue_no_execute_slots,
                perf_other_rob_block_slots,
                perf_other_recovery_resync_slots,
                perf_bank_alu_local_full_slots,
                perf_bank_alu_credit_stale_slots,
                perf_bank_p0_local_full_slots,
                perf_bank_p0_credit_stale_slots,
                perf_bank_p1_local_full_slots,
                perf_bank_p1_credit_stale_slots,
                perf_bank_unclassified_slots,
                perf_other_rs_pair_limit_slots,
                perf_other_select_refill_slots,
                perf_other_rs_dependency_slots,
                perf_other_rs_order_slots,
                perf_other_rs_resource_slots,
                perf_other_rs_no_candidate_slots,
                perf_other_rs_empty_slots,
                perf_other_decode_block_slots,
                perf_other_unclassified_slots,
                perf_executed_slot0_count + perf_executed_slot1_count +
                    perf_lost_flush_slot_count + perf_lost_mul_hold_slot_count +
                    perf_lost_multi_slot_count + perf_lost_dependency_slot_count +
                    perf_lost_lsu_struct_slot_count +
                    perf_lost_producer_full_slot_count + perf_lost_wb_slot_count +
                    perf_lost_clint_slot_count + perf_lost_lsu_serialize_slot_count +
                    perf_noif_control_redirect_slots + perf_noif_predict_redirect_slots +
                    perf_noif_fence_refill_slots + perf_noif_mem_response_slots +
                    perf_noif_fetch_launch_slots + perf_noif_pending_redirect_slots +
                    perf_noif_other_slots + perf_issue_single_lane_slots +
                    perf_issue_no_execute_slots + perf_other_rob_block_slots +
                    perf_other_recovery_resync_slots +
                    perf_bank_alu_local_full_slots + perf_bank_alu_credit_stale_slots +
                    perf_bank_p0_local_full_slots + perf_bank_p0_credit_stale_slots +
                    perf_bank_p1_local_full_slots + perf_bank_p1_credit_stale_slots +
                    perf_bank_unclassified_slots + perf_other_rs_pair_limit_slots +
                    perf_other_select_refill_slots + perf_other_rs_dependency_slots +
                    perf_other_rs_order_slots + perf_other_rs_resource_slots +
                    perf_other_rs_no_candidate_slots + perf_other_rs_empty_slots +
                    perf_other_decode_block_slots + perf_other_unclassified_slots,
                (perf_sample_cycle_count << 1));
            $display("PERF_SLOT_LOSS: FLUSH=%-d MUL_HOLD=%-d DEPENDENCY=%-d LSU_STRUCT=%-d LSU_SERIALIZE=%-d PRODUCER_FULL=%-d WB=%-d CLINT=%-d MULTI=%-d NO_IF_VALID=%-d ISSUE=%-d OTHER=%-d",
                perf_lost_flush_slot_count,
                perf_lost_mul_hold_slot_count,
                perf_lost_dependency_slot_count,
                perf_lost_lsu_struct_slot_count,
                perf_lost_lsu_serialize_slot_count,
                perf_lost_producer_full_slot_count,
                perf_lost_wb_slot_count,
                perf_lost_clint_slot_count,
                perf_lost_multi_slot_count,
                perf_lost_no_if_valid_slot_count,
                perf_lost_issue_slot_count,
                perf_lost_other_slot_count);
            $display("PERF_NOIF_SLOT_DETAIL: CONTROL_REDIRECT=%-d PREDICT_REDIRECT=%-d FENCE_REFILL=%-d MEM_RESPONSE=%-d FETCH_LAUNCH=%-d PENDING_REDIRECT=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_noif_control_redirect_slots,
                perf_noif_predict_redirect_slots,
                perf_noif_fence_refill_slots,
                perf_noif_mem_response_slots,
                perf_noif_fetch_launch_slots,
                perf_noif_pending_redirect_slots,
                perf_noif_other_slots,
                perf_noif_control_redirect_slots +
                    perf_noif_predict_redirect_slots +
                    perf_noif_fence_refill_slots +
                    perf_noif_mem_response_slots +
                    perf_noif_fetch_launch_slots +
                    perf_noif_pending_redirect_slots + perf_noif_other_slots,
                perf_lost_no_if_valid_slot_count);
            $display("PERF_ISSUE_SLOT_DETAIL: DEPENDENCY=%-d LSU_STRUCT=%-d LSU_SERIALIZE=%-d SINGLE_LANE=%-d NO_EXECUTE=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_issue_dependency_slots,
                perf_issue_lsu_struct_slots,
                perf_issue_serialize_slots,
                perf_issue_single_lane_slots,
                perf_issue_no_execute_slots,
                perf_issue_dependency_slots + perf_issue_lsu_struct_slots +
                    perf_issue_serialize_slots +
                    perf_issue_single_lane_slots + perf_issue_no_execute_slots,
                perf_lost_issue_slot_count);
            $display("PERF_OTHER_SLOT_DETAIL: ROB_BLOCK=%-d RECOVERY_RESYNC=%-d RS_BANK_BLOCK=%-d ALU_BANK_BLOCK=%-d P0_BANK_BLOCK=%-d P1_BANK_BLOCK=%-d RS_PAIR_LIMIT=%-d SELECT_REFILL=%-d RS_DEPENDENCY=%-d RS_ORDER=%-d RS_RESOURCE=%-d RS_NO_CANDIDATE=%-d RS_EMPTY=%-d DECODE_BLOCK=%-d UNCLASSIFIED=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_other_rob_block_slots,
                perf_other_recovery_resync_slots,
                perf_other_rs_bank_block_slots,
                perf_other_alu_bank_block_slots,
                perf_other_p0_bank_block_slots,
                perf_other_p1_bank_block_slots,
                perf_other_rs_pair_limit_slots,
                perf_other_select_refill_slots,
                perf_other_rs_dependency_slots,
                perf_other_rs_order_slots,
                perf_other_rs_resource_slots,
                perf_other_rs_no_candidate_slots,
                perf_other_rs_empty_slots,
                perf_other_decode_block_slots,
                perf_other_unclassified_slots,
                perf_other_rob_block_slots +
                    perf_other_recovery_resync_slots +
                    perf_other_rs_bank_block_slots +
                    perf_other_rs_pair_limit_slots +
                    perf_other_select_refill_slots +
                    perf_other_rs_dependency_slots +
                    perf_other_rs_order_slots +
                    perf_other_rs_resource_slots +
                    perf_other_rs_no_candidate_slots +
                    perf_other_rs_empty_slots +
                    perf_other_decode_block_slots +
                    perf_other_unclassified_slots,
                perf_lost_other_slot_count);
            $display("PERF_BANK_BLOCK_DETAIL: ALU_LOCAL_FULL=%-d ALU_CREDIT_STALE=%-d P0_LOCAL_FULL=%-d P0_CREDIT_STALE=%-d P1_LOCAL_FULL=%-d P1_CREDIT_STALE=%-d UNCLASSIFIED=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_bank_alu_local_full_slots,
                perf_bank_alu_credit_stale_slots,
                perf_bank_p0_local_full_slots,
                perf_bank_p0_credit_stale_slots,
                perf_bank_p1_local_full_slots,
                perf_bank_p1_credit_stale_slots,
                perf_bank_unclassified_slots,
                perf_bank_alu_local_full_slots +
                    perf_bank_alu_credit_stale_slots +
                    perf_bank_p0_local_full_slots +
                    perf_bank_p0_credit_stale_slots +
                    perf_bank_p1_local_full_slots +
                    perf_bank_p1_credit_stale_slots +
                    perf_bank_unclassified_slots,
                perf_other_rs_bank_block_slots);
            $display("PERF_P0_FULL_DETAIL: DEPENDENCY=%-d ORDER=%-d RESOURCE=%-d READY_RELEASE=%-d NO_CANDIDATE=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_p0_full_dependency_slots,
                perf_p0_full_order_slots,
                perf_p0_full_resource_slots,
                perf_p0_full_ready_release_slots,
                perf_p0_full_no_candidate_slots,
                perf_p0_full_dependency_slots + perf_p0_full_order_slots +
                    perf_p0_full_resource_slots +
                    perf_p0_full_ready_release_slots +
                perf_p0_full_no_candidate_slots,
                perf_bank_p0_local_full_slots);
            $display("PERF_P0_FULL_PIPELINE: SELECTABLE=%-d CREDIT_BLOCKED=%-d ORDER_BLOCKED=%-d DEPENDENCY_BLOCKED=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_p0_pipe_selectable_slots,
                perf_p0_pipe_credit_blocked_slots,
                perf_p0_pipe_order_blocked_slots,
                perf_p0_pipe_dependency_blocked_slots,
                perf_p0_pipe_selectable_slots +
                    perf_p0_pipe_credit_blocked_slots +
                    perf_p0_pipe_order_blocked_slots +
                    perf_p0_pipe_dependency_blocked_slots,
                perf_bank_p0_local_full_slots);
            $display("PERF_P0_CREDIT_RESV_MATRIX: C0_R0=%-d C0_R1=%-d C0_R2=%-d C1_R0=%-d C1_R1=%-d C1_R2=%-d C2_R0=%-d C2_R1=%-d C2_R2=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_p0_credit_resv_slots[0],
                perf_p0_credit_resv_slots[1],
                perf_p0_credit_resv_slots[2],
                perf_p0_credit_resv_slots[3],
                perf_p0_credit_resv_slots[4],
                perf_p0_credit_resv_slots[5],
                perf_p0_credit_resv_slots[6],
                perf_p0_credit_resv_slots[7],
                perf_p0_credit_resv_slots[8],
                perf_p0_credit_resv_slots[0] +
                    perf_p0_credit_resv_slots[1] +
                    perf_p0_credit_resv_slots[2] +
                    perf_p0_credit_resv_slots[3] +
                    perf_p0_credit_resv_slots[4] +
                    perf_p0_credit_resv_slots[5] +
                    perf_p0_credit_resv_slots[6] +
                    perf_p0_credit_resv_slots[7] +
                    perf_p0_credit_resv_slots[8],
                perf_bank_p0_local_full_slots);
            $display("PERF_P0_FULL_RESIDENT_MIX: STORE0=%-d STORE1=%-d STORE2=%-d STORE3=%-d STORE4=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_p0_full_store_mix_slots[0],
                perf_p0_full_store_mix_slots[1],
                perf_p0_full_store_mix_slots[2],
                perf_p0_full_store_mix_slots[3],
                perf_p0_full_store_mix_slots[4],
                perf_p0_full_store_mix_slots[0] +
                    perf_p0_full_store_mix_slots[1] +
                    perf_p0_full_store_mix_slots[2] +
                    perf_p0_full_store_mix_slots[3] +
                    perf_p0_full_store_mix_slots[4],
                perf_bank_p0_local_full_slots);
            $display("PERF_P0_FULL_BLOCKED_OP: LOAD=%-d STORE=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_p0_full_blocked_load_slots,
                perf_p0_full_blocked_store_slots,
                perf_p0_full_blocked_other_slots,
                perf_p0_full_blocked_load_slots +
                    perf_p0_full_blocked_store_slots +
                    perf_p0_full_blocked_other_slots,
                perf_bank_p0_local_full_slots);
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
            $display("PERF_HAZARD_ACCOUNT: RAW_ONLY=%-d WAW_ONLY=%-d RAW_WAW=%-d RETIRE_0=%-d RETIRE_1=%-d RETIRE_2=%-d RETIRE_3=%-d RETIRE_4=%-d",
                acct_raw_only_count,
                acct_waw_only_count,
                acct_raw_waw_count,
                retire_zero_count,
                retire_one_count,
                retire_two_count,
                retire_three_count,
                retire_four_count);
            $display("PERF_DUAL_ISSUE: PAIRS=%-d ALU_ALU=%-d BRU_ALU=%-d LSU_ALU=%-d MULDIV_ALU=%-d OTHER=%-d",
                dual_issue_count, dual_alu_alu_count, dual_bru_alu_count,
                dual_lsu_alu_count, dual_muldiv_alu_count, dual_other_count);
            $display("PERF_L0_BTB: LOOKUP=%-d HIT=%-d CORRECTION=%-d",
                l0_lookup_count, l0_hit_count, l0_correction_count);
            $display("PERF_ISSUE_STAGE: FENCE=%-d SLOT1_REPLAY=%-d SLOT1_DEP_REPLAY=%-d SLOT1_LSU_REPLAY=%-d SERIALIZE_WAIT=%-d OQ0=%-d OQ1=%-d OQ2=%-d OQ3=%-d OQ4=%-d",
                issue_fence_count,
                issue_slot1_replay_count,
                issue_slot1_dependency_replay_count,
                issue_slot1_lsu_replay_count,
                issue_serialize_wait_count,
                operandq_occ_count[0],
                operandq_occ_count[1],
                operandq_occ_count[2],
                operandq_occ_count[3],
                operandq_occ_count[4]);
            $display("PERF_CAUSE_HIST: NONE=%-d DEP=%-d LSU=%-d LSU_DEP=%-d PF=%-d PF_DEP=%-d PF_LSU=%-d PF_LSU_DEP=%-d WB_ANY=%-d CLINT_ANY=%-d",
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
            $display("PERF_ROB_OCCUPANCY: O0=%-d O1=%-d O2=%-d O3=%-d O4=%-d O5=%-d O6=%-d O7=%-d O8=%-d O9=%-d O10=%-d O11=%-d O12=%-d ACCOUNTED=%-d SAMPLE=%-d",
                perf_rob_occ_count[0], perf_rob_occ_count[1],
                perf_rob_occ_count[2], perf_rob_occ_count[3],
                perf_rob_occ_count[4], perf_rob_occ_count[5],
                perf_rob_occ_count[6], perf_rob_occ_count[7],
                perf_rob_occ_count[8], perf_rob_occ_count[9],
                perf_rob_occ_count[10], perf_rob_occ_count[11],
                perf_rob_occ_count[12],
                perf_rob_occ_count[0] + perf_rob_occ_count[1] +
                    perf_rob_occ_count[2] + perf_rob_occ_count[3] +
                    perf_rob_occ_count[4] + perf_rob_occ_count[5] +
                    perf_rob_occ_count[6] + perf_rob_occ_count[7] +
                    perf_rob_occ_count[8] + perf_rob_occ_count[9] +
                    perf_rob_occ_count[10] + perf_rob_occ_count[11] +
                    perf_rob_occ_count[12],
                perf_sample_cycle_count);
            $display("PERF_RS_OCCUPANCY: O0=%-d O1=%-d O2=%-d O3=%-d O4=%-d O5=%-d O6=%-d O7=%-d O8=%-d O9=%-d O10=%-d O11=%-d O12=%-d ACCOUNTED=%-d SAMPLE=%-d",
                perf_rs_occ_count[0], perf_rs_occ_count[1],
                perf_rs_occ_count[2], perf_rs_occ_count[3],
                perf_rs_occ_count[4], perf_rs_occ_count[5],
                perf_rs_occ_count[6], perf_rs_occ_count[7],
                perf_rs_occ_count[8], perf_rs_occ_count[9],
                perf_rs_occ_count[10], perf_rs_occ_count[11],
                perf_rs_occ_count[12],
                perf_rs_occ_count[0] + perf_rs_occ_count[1] +
                    perf_rs_occ_count[2] + perf_rs_occ_count[3] +
                    perf_rs_occ_count[4] + perf_rs_occ_count[5] +
                    perf_rs_occ_count[6] + perf_rs_occ_count[7] +
                    perf_rs_occ_count[8] + perf_rs_occ_count[9] +
                    perf_rs_occ_count[10] + perf_rs_occ_count[11] +
                    perf_rs_occ_count[12],
                perf_sample_cycle_count);
            $display("PERF_PIPE_FLOW: RS_ALLOC0=%-d RS_ALLOC1=%-d RS_ALLOC2=%-d SELECT0=%-d SELECT1=%-d SELECT2=%-d OPERAND0=%-d OPERAND1=%-d OPERAND2=%-d COMPLETE0=%-d COMPLETE1=%-d COMPLETE2=%-d COMPLETE3=%-d COMPLETE4=%-d RETIRE0=%-d RETIRE1=%-d RETIRE2=%-d SAMPLE=%-d",
                perf_rs_alloc_count[0], perf_rs_alloc_count[1],
                perf_rs_alloc_count[2], perf_select_count[0],
                perf_select_count[1], perf_select_count[2],
                perf_operand_count[0], perf_operand_count[1],
                perf_operand_count[2],
                perf_complete_count[0], perf_complete_count[1],
                perf_complete_count[2], perf_complete_count[3],
                perf_complete_count[4], perf_retire_count[0],
                perf_retire_count[1], perf_retire_count[2],
                perf_sample_cycle_count);
            $display("PERF_CONTROL_DECOUPLE: DEP_TOKEN_ENTRY_CYCLES=%-d ORDER_TOKEN_ENTRY_CYCLES=%-d RESOURCE_ENTRY_CYCLES=%-d SELECTABLE_ENTRY_CYCLES=%-d RS_BANK_FULL=%-d RS_PAIR_BANK_LIMIT=%-d ROB_FULL=%-d LSU_CREDIT=%-d DIV_CREDIT=%-d SERIAL_GATE=%-d SELECT_WIDTH=%-d OPERAND_DEP_MISS=%-d RECOVERY=%-d RECOVERY_RESYNC=%-d",
                perf_rs_dependency_entry_cycles,
                perf_rs_order_entry_cycles,
                perf_rs_resource_entry_cycles,
                perf_rs_selectable_entry_cycles,
                perf_rs_bank_full_cycles,
                perf_rs_pair_bank_limit_cycles,
                perf_rob_full_cycles,
                perf_lsu_credit_wait_cycles,
                perf_div_credit_wait_cycles,
                perf_serial_gate_wait_cycles,
                perf_select_width_limit_cycles,
                perf_operand_dependency_miss_cycles,
                perf_recovery_cycles,
                perf_recovery_resync_cycles);
            $display("PERF_LOCAL_CONTROL: ALU_ENTRY_CYCLES=%-d P0_ENTRY_CYCLES=%-d P1_ENTRY_CYCLES=%-d ALU_FULL=%-d P0_FULL=%-d P1_FULL=%-d ALU_DUE_SELECT=%-d DTCM_DUE_SELECT=%-d MDU_DUE_SELECT=%-d DTCM_LOCAL_WAKE=%-d MDU_LOCAL_WAKE=%-d RESIDENT_WAKE_ENTRIES=%-d RESIDENT_DUE_SELECT=%-d P0_COMPLETION_WAKEUP=%-d OPERAND_MERGE_PAIR=%-d",
                perf_alu_bank_entry_cycles,
                perf_p0_bank_entry_cycles,
                perf_p1_bank_entry_cycles,
                perf_alu_bank_full_cycles,
                perf_p0_bank_full_cycles,
                perf_p1_bank_full_cycles,
                perf_alu_due_select_cycles,
                perf_dtcm_due_select_cycles,
                perf_mdu_due_select_cycles,
                perf_dtcm_local_wake_cycles,
                perf_mdu_local_wake_cycles,
                perf_resident_wakeup_entry_cycles,
                perf_resident_due_select_cycles,
                perf_p0_completion_wakeup_cycles,
                perf_operand_merge_pair_cycles);
            $display("PERF_RS_BANK_STATE: ALU_DEP=%-d P0_DEP=%-d P1_DEP=%-d ALU_ORDER=%-d P0_ORDER=%-d P1_ORDER=%-d ALU_RESOURCE=%-d P0_RESOURCE=%-d P1_RESOURCE=%-d ALU_READY=%-d P0_READY=%-d P1_READY=%-d ALU_CANDIDATE=%-d P0_CANDIDATE=%-d P1_CANDIDATE=%-d ALU_SELECTED=%-d P0_SELECTED=%-d P1_SELECTED=%-d",
                perf_bank_dep_entry_cycles[0], perf_bank_dep_entry_cycles[1],
                perf_bank_dep_entry_cycles[2],
                perf_bank_order_entry_cycles[0], perf_bank_order_entry_cycles[1],
                perf_bank_order_entry_cycles[2],
                perf_bank_resource_entry_cycles[0],
                perf_bank_resource_entry_cycles[1],
                perf_bank_resource_entry_cycles[2],
                perf_bank_ready_entry_cycles[0], perf_bank_ready_entry_cycles[1],
                perf_bank_ready_entry_cycles[2],
                perf_bank_candidate_entry_cycles[0],
                perf_bank_candidate_entry_cycles[1],
                perf_bank_candidate_entry_cycles[2],
                perf_bank_selected_entry_cycles[0],
                perf_bank_selected_entry_cycles[1],
                perf_bank_selected_entry_cycles[2]);
            $display("PERF_COUPLING_PAIR: BANK_DEP=%-d BANK_ROB=%-d BANK_RESOURCE=%-d BANK_SELECT=%-d BANK_OPERAND=%-d ROB_DEP=%-d ROB_RESOURCE=%-d ROB_SELECT=%-d ROB_OPERAND=%-d DEP_RESOURCE=%-d DEP_SELECT=%-d DEP_OPERAND=%-d RESOURCE_SELECT=%-d SELECT_OPERAND=%-d BANK_DEP_SELECT=%-d BANK_ROB_SELECT=%-d DEP_SELECT_OPERAND=%-d",
                perf_cpl_bank_dep_count, perf_cpl_bank_rob_count,
                perf_cpl_bank_resource_count, perf_cpl_bank_select_count,
                perf_cpl_bank_operand_count, perf_cpl_rob_dep_count,
                perf_cpl_rob_resource_count, perf_cpl_rob_select_count,
                perf_cpl_rob_operand_count, perf_cpl_dep_resource_count,
                perf_cpl_dep_select_count, perf_cpl_dep_operand_count,
                perf_cpl_resource_select_count, perf_cpl_select_operand_count,
                perf_cpl_bank_dep_select_count,
                perf_cpl_bank_rob_select_count,
                perf_cpl_dep_select_operand_count);
            $display("PERF_SELECT_QUEUE: HOL_SINGLE_HEAD_PAIR_SKID_CYCLES=%-d HOL_LOST_SLOTS=%-d PAIR_PUSH_CYCLES=%-d PAIR_HEAD_ISSUE_CYCLES=%-d PAIR_PUSH_BEHIND_SINGLE_HEAD_CYCLES=%-d PAIR_PUSH_BEHIND_SINGLE_HEAD_SLOTS=%-d STATE_EMPTY=%-d STATE_HEAD_SINGLE=%-d STATE_HEAD_PAIR=%-d STATE_SINGLE_SINGLE=%-d STATE_SINGLE_PAIR=%-d STATE_PAIR_SINGLE=%-d STATE_PAIR_PAIR=%-d",
                perf_select_hol_pair_cycles,
                perf_select_hol_pair_lost_slots,
                perf_select_pair_push_cycles,
                perf_select_pair_issue_cycles,
                perf_select_pair_push_single_head_cycles,
                perf_select_pair_push_single_head_slots,
                perf_select_queue_state_count[0],
                perf_select_queue_state_count[2],
                perf_select_queue_state_count[3],
                perf_select_queue_state_count[10],
                perf_select_queue_state_count[14],
                perf_select_queue_state_count[11],
                perf_select_queue_state_count[15]);
            $display("PERF_SELECT_REFILL_BOUNDARY: HEAD_EMPTY_PUSH_CYCLES=%-d HEAD_EMPTY_PUSH_SLOTS=%-d HEAD_EMPTY_PAIR_SLOTS=%-d HEAD_EMPTY_SINGLE_SLOTS=%-d PUSHED_UOPS=%-d",
                perf_select_refill_head_empty_cycles,
                perf_select_refill_head_empty_slots,
                perf_select_refill_head_empty_pair_slots,
                perf_select_refill_head_empty_single_slots,
                perf_select_refill_head_empty_uops);
            $display("PERF_SELECT_REFILL_LIFECYCLE_DATA: ELIGIBLE_PENDING=%-d ELIGIBLE_STORED=%-d DEPENDENCY_PENDING=%-d DEPENDENCY_STORED=%-d ORDER_PENDING=%-d ORDER_STORED=%-d RESOURCE_PENDING=%-d RESOURCE_STORED=%-d NEW_PENDING=%-d NEW_STORED=%-d OTHER_PENDING=%-d OTHER_STORED=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_select_refill_lifecycle_data_uops[0][0],
                perf_select_refill_lifecycle_data_uops[0][1],
                perf_select_refill_lifecycle_data_uops[1][0],
                perf_select_refill_lifecycle_data_uops[1][1],
                perf_select_refill_lifecycle_data_uops[2][0],
                perf_select_refill_lifecycle_data_uops[2][1],
                perf_select_refill_lifecycle_data_uops[3][0],
                perf_select_refill_lifecycle_data_uops[3][1],
                perf_select_refill_lifecycle_data_uops[4][0],
                perf_select_refill_lifecycle_data_uops[4][1],
                perf_select_refill_lifecycle_data_uops[5][0],
                perf_select_refill_lifecycle_data_uops[5][1],
                perf_select_refill_lifecycle_data_uops[0][0] +
                    perf_select_refill_lifecycle_data_uops[0][1] +
                    perf_select_refill_lifecycle_data_uops[1][0] +
                    perf_select_refill_lifecycle_data_uops[1][1] +
                    perf_select_refill_lifecycle_data_uops[2][0] +
                    perf_select_refill_lifecycle_data_uops[2][1] +
                    perf_select_refill_lifecycle_data_uops[3][0] +
                    perf_select_refill_lifecycle_data_uops[3][1] +
                    perf_select_refill_lifecycle_data_uops[4][0] +
                    perf_select_refill_lifecycle_data_uops[4][1] +
                    perf_select_refill_lifecycle_data_uops[5][0] +
                    perf_select_refill_lifecycle_data_uops[5][1],
                perf_select_refill_head_empty_uops);
            $write("PERF_SELECT_REFILL_PRIOR_MASK:");
            for (perf_stat_idx = 0; perf_stat_idx < 8;
                 perf_stat_idx = perf_stat_idx + 1)
                $write(" M%0d=%0d", perf_stat_idx,
                       perf_select_refill_prior_mask_uops[perf_stat_idx]);
            $display(" NEW=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_select_refill_prior_mask_uops[8],
                perf_select_refill_prior_mask_uops[9],
                perf_select_refill_prior_mask_uops[0] +
                    perf_select_refill_prior_mask_uops[1] +
                    perf_select_refill_prior_mask_uops[2] +
                    perf_select_refill_prior_mask_uops[3] +
                    perf_select_refill_prior_mask_uops[4] +
                    perf_select_refill_prior_mask_uops[5] +
                    perf_select_refill_prior_mask_uops[6] +
                    perf_select_refill_prior_mask_uops[7] +
                    perf_select_refill_prior_mask_uops[8] +
                    perf_select_refill_prior_mask_uops[9],
                perf_select_refill_head_empty_uops);
            $write("PERF_SELECT_REFILL_PENDING_MASK:");
            for (perf_stat_idx = 0; perf_stat_idx < 16;
                 perf_stat_idx = perf_stat_idx + 1)
                $write(" M%0d=%0d", perf_stat_idx,
                       perf_select_refill_pending_mask_uops[perf_stat_idx]);
            $display(" ACCOUNTED=%-d EXPECTED=%-d",
                perf_select_refill_pending_mask_uops[0] +
                    perf_select_refill_pending_mask_uops[1] +
                    perf_select_refill_pending_mask_uops[2] +
                    perf_select_refill_pending_mask_uops[3] +
                    perf_select_refill_pending_mask_uops[4] +
                    perf_select_refill_pending_mask_uops[5] +
                    perf_select_refill_pending_mask_uops[6] +
                    perf_select_refill_pending_mask_uops[7] +
                    perf_select_refill_pending_mask_uops[8] +
                    perf_select_refill_pending_mask_uops[9] +
                    perf_select_refill_pending_mask_uops[10] +
                    perf_select_refill_pending_mask_uops[11] +
                    perf_select_refill_pending_mask_uops[12] +
                    perf_select_refill_pending_mask_uops[13] +
                    perf_select_refill_pending_mask_uops[14] +
                    perf_select_refill_pending_mask_uops[15],
                perf_select_refill_head_empty_uops);
            $write("PERF_COUPLING_MASK:");
            for (perf_stat_idx = 0; perf_stat_idx < 256;
                 perf_stat_idx = perf_stat_idx + 1)
                if (perf_coupling_mask_count[perf_stat_idx] != 0)
                    $write(" M%0d=%0d", perf_stat_idx,
                           perf_coupling_mask_count[perf_stat_idx]);
            $display("");
            $display("PERF_SELECT_OPPORTUNITY: RAW_W0=%-d RAW_W1=%-d RAW_W2=%-d ACTUAL_W0=%-d ACTUAL_W1=%-d ACTUAL_W2=%-d RAW_ALU_ENTRIES=%-d RAW_P0_CYCLES=%-d RAW_P1_CYCLES=%-d DROP_ALU_ENTRIES=%-d DROP_P0_ENTRIES=%-d DROP_P1_ENTRIES=%-d WIDTH_GAP_SLOTS=%-d PAIR_CAPABLE_SINGLE_CYCLES=%-d PAIR_CAPABLE_SINGLE_LOST_SLOTS=%-d GAP_RECOVERY_CYCLES=%-d GAP_NO_PUSH_CYCLES=%-d GAP_POLICY_CYCLES=%-d",
                perf_select_raw_width_count[0],
                perf_select_raw_width_count[1],
                perf_select_raw_width_count[2],
                perf_select_actual_width_count[0],
                perf_select_actual_width_count[1],
                perf_select_actual_width_count[2],
                perf_select_raw_alu_entries,
                perf_select_raw_p0_entries,
                perf_select_raw_p1_entries,
                perf_select_drop_alu_entries,
                perf_select_drop_p0_entries,
                perf_select_drop_p1_entries,
                perf_select_width_gap_slots,
                perf_select_pair_capable_single_cycles,
                perf_select_pair_capable_single_slots,
                perf_select_gap_recovery_cycles,
                perf_select_gap_no_push_cycles,
                perf_select_gap_policy_cycles);
            $write("PERF_SELECT_WIDTH_MATRIX_CYCLES:");
            for (perf_width_idx = 0; perf_width_idx < 3;
                 perf_width_idx = perf_width_idx + 1)
                for (perf_width_idx2 = 0; perf_width_idx2 < 3;
                     perf_width_idx2 = perf_width_idx2 + 1)
                    if (perf_select_width_matrix_cycles[perf_width_idx][perf_width_idx2] != 0)
                        $write(" M%0d%0d=%0d", perf_width_idx, perf_width_idx2,
                               perf_select_width_matrix_cycles[perf_width_idx][perf_width_idx2]);
            $display("");
            $write("PERF_SELECT_WIDTH_MATRIX_SLOTS:");
            for (perf_width_idx = 0; perf_width_idx < 3;
                 perf_width_idx = perf_width_idx + 1)
                for (perf_width_idx2 = 0; perf_width_idx2 < 3;
                     perf_width_idx2 = perf_width_idx2 + 1)
                    if (perf_select_width_matrix_slots[perf_width_idx][perf_width_idx2] != 0)
                        $write(" M%0d%0d=%0d", perf_width_idx, perf_width_idx2,
                               perf_select_width_matrix_slots[perf_width_idx][perf_width_idx2]);
            $display("");
            $write("PERF_SELECT_RAW_SHAPE:");
            for (perf_stat_idx = 0; perf_stat_idx < 16;
                 perf_stat_idx = perf_stat_idx + 1)
                if (perf_select_raw_shape_count[perf_stat_idx] != 0)
                    $write(" M%0d=%0d", perf_stat_idx,
                           perf_select_raw_shape_count[perf_stat_idx]);
            $display("");
            $display("PERF_LOSS_COUPLING: CYCLES=%-d SLOTS=%-d MASK_BITS=%-d",
                perf_loss_coupling_cycles, perf_loss_coupling_slots,
                PERF_LOSS_COUPLING_BITS);
            $write("PERF_LOSS_COUPLING_MASK_CYCLES:");
            for (perf_stat_idx = 0;
                 perf_stat_idx < PERF_LOSS_COUPLING_DEPTH;
                 perf_stat_idx = perf_stat_idx + 1)
                if (perf_loss_coupling_cycle_count[perf_stat_idx] != 0)
                    $write(" M%0d=%0d", perf_stat_idx,
                           perf_loss_coupling_cycle_count[perf_stat_idx]);
            $display("");
            $write("PERF_LOSS_COUPLING_MASK_SLOTS:");
            for (perf_stat_idx = 0;
                 perf_stat_idx < PERF_LOSS_COUPLING_DEPTH;
                 perf_stat_idx = perf_stat_idx + 1)
                if (perf_loss_coupling_slot_count[perf_stat_idx] != 0)
                    $write(" M%0d=%0d", perf_stat_idx,
                           perf_loss_coupling_slot_count[perf_stat_idx]);
            $display("");
            $display("PERF_LATENCY_ALLOC_SELECT: B0_3=%-d B4_7=%-d B8_15=%-d B16_31=%-d B32_63=%-d B64P=%-d",
                perf_latency_alloc_select[0], perf_latency_alloc_select[1],
                perf_latency_alloc_select[2], perf_latency_alloc_select[3],
                perf_latency_alloc_select[4], perf_latency_alloc_select[5]);
            $display("PERF_LATENCY_SELECT_OPERAND: B0_3=%-d B4_7=%-d B8_15=%-d B16_31=%-d B32_63=%-d B64P=%-d",
                perf_latency_select_operand[0], perf_latency_select_operand[1],
                perf_latency_select_operand[2], perf_latency_select_operand[3],
                perf_latency_select_operand[4], perf_latency_select_operand[5]);
            $display("PERF_LATENCY_OPERAND_EX: B0_3=%-d B4_7=%-d B8_15=%-d B16_31=%-d B32_63=%-d B64P=%-d",
                perf_latency_operand_ex[0], perf_latency_operand_ex[1],
                perf_latency_operand_ex[2], perf_latency_operand_ex[3],
                perf_latency_operand_ex[4], perf_latency_operand_ex[5]);
            $display("PERF_LATENCY_ALLOC_COMPLETE: B0_3=%-d B4_7=%-d B8_15=%-d B16_31=%-d B32_63=%-d B64P=%-d",
                perf_latency_alloc_complete[0], perf_latency_alloc_complete[1],
                perf_latency_alloc_complete[2], perf_latency_alloc_complete[3],
                perf_latency_alloc_complete[4], perf_latency_alloc_complete[5]);
            $display("PERF_LATENCY_ALLOC_RETIRE: B0_3=%-d B4_7=%-d B8_15=%-d B16_31=%-d B32_63=%-d B64P=%-d",
                perf_latency_alloc_retire[0], perf_latency_alloc_retire[1],
                perf_latency_alloc_retire[2], perf_latency_alloc_retire[3],
                perf_latency_alloc_retire[4], perf_latency_alloc_retire[5]);
            $display("PERF_WAKEUP: COMPLETION_ENTRIES=%-d ALLOC_ENTRIES=%-d SELECT_ENTRIES=%-d DTCM_LAUNCH=%-d DTCM_RESULT=%-d MDU_RESULT=%-d REPLAY=%-d P0_COMPLETION_CYCLES=%-d",
                perf_rs_completion_wakeup_entries,
                perf_rs_alloc_wakeup_entries,
                perf_rs_select_wakeup_entries,
                perf_dtcm_launch_wakeup_events,
                perf_dtcm_result_wakeup_events,
                perf_mdu_wakeup_events,
                perf_replay_wakeup_events,
                perf_p0_completion_wakeup_cycles);
            $display("PERF_ROB_HEAD_STATE: EMPTY=%-d RETIRE1=%-d RETIRE2=%-d COMPLETE_VISIBLE=%-d NOT_ISSUED=%-d WAIT_ALU=%-d WAIT_LOAD=%-d WAIT_MDU=%-d WAIT_STORE=%-d WAIT_BRANCH=%-d WAIT_OTHER=%-d ACCOUNTED=%-d SAMPLE=%-d",
                perf_head_empty_count, perf_head_retire1_count,
                perf_head_retire2_count, perf_head_complete_visible_count,
                perf_head_not_issued_count, perf_head_wait_alu_count,
                perf_head_wait_load_count, perf_head_wait_mdu_count,
                perf_head_wait_store_count, perf_head_wait_branch_count,
                perf_head_wait_other_count,
                perf_head_empty_count + perf_head_retire1_count +
                    perf_head_retire2_count +
                    perf_head_complete_visible_count +
                    perf_head_not_issued_count + perf_head_wait_alu_count +
                    perf_head_wait_load_count + perf_head_wait_mdu_count +
                    perf_head_wait_store_count +
                    perf_head_wait_branch_count +
                    perf_head_wait_other_count,
                perf_sample_cycle_count);
            $display("PERF_ROB_HEAD_NOT_ISSUED: SELECT_TRANSIT=%-d RS_DEP=%-d RS_ORDER=%-d RS_RESOURCE=%-d RS_READY_NOT_PICKED=%-d ABSENT=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_head_ni_select_transit_count,
                perf_head_ni_rs_dependency_count,
                perf_head_ni_rs_order_count,
                perf_head_ni_rs_resource_count,
                perf_head_ni_rs_ready_count,
                perf_head_ni_absent_count,
                perf_head_ni_select_transit_count +
                    perf_head_ni_rs_dependency_count +
                    perf_head_ni_rs_order_count +
                    perf_head_ni_rs_resource_count +
                    perf_head_ni_rs_ready_count +
                    perf_head_ni_absent_count,
                perf_head_not_issued_count);
            $display("PERF_BACKEND_LOSS: FLUSH=%-d OPERAND_BLOCK=%-d SINGLE_BUNDLE=%-d SELECT_REFILL=%-d RS_DEPENDENCY=%-d RS_ORDER=%-d RS_RESOURCE=%-d RS_OTHER=%-d ROB_FULL=%-d RS_REFILL=%-d DECODE_REFILL=%-d FRONTEND=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_loss_flush_slots, perf_loss_operand_block_slots,
                perf_loss_single_bundle_slots,
                perf_loss_select_refill_slots,
                perf_loss_rs_dependency_slots, perf_loss_rs_order_slots,
                perf_loss_rs_resource_slots, perf_loss_rs_other_slots,
                perf_loss_rob_full_slots, perf_loss_rs_refill_slots,
                perf_loss_decode_refill_slots, perf_loss_frontend_slots,
                perf_loss_other_slots,
                perf_loss_flush_slots + perf_loss_operand_block_slots +
                    perf_loss_single_bundle_slots +
                    perf_loss_select_refill_slots +
                    perf_loss_rs_dependency_slots +
                    perf_loss_rs_order_slots +
                    perf_loss_rs_resource_slots + perf_loss_rs_other_slots +
                    perf_loss_rob_full_slots + perf_loss_rs_refill_slots +
                    perf_loss_decode_refill_slots +
                    perf_loss_frontend_slots + perf_loss_other_slots,
                (perf_sample_cycle_count << 1) - perf_operand_count[1] -
                    (perf_operand_count[2] << 1));
            $display("PERF_SINGLE_BUNDLE_DETAIL: P0_ONLY=%-d P1_ONLY=%-d ALU_ONLY=%-d SERIAL=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_single_p0_only_slots,
                perf_single_p1_only_slots,
                perf_single_alu_only_slots,
                perf_single_serial_slots,
                perf_single_other_slots,
                perf_single_p0_only_slots + perf_single_p1_only_slots +
                    perf_single_alu_only_slots + perf_single_serial_slots +
                    perf_single_other_slots,
                perf_loss_single_bundle_slots);
            $display("PERF_SELECT_REFILL_DETAIL: PAIR=%-d P0_SINGLE=%-d P1_SINGLE=%-d ALU_SINGLE=%-d SERIAL=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_select_refill_pair_slots,
                perf_select_refill_p0_slots,
                perf_select_refill_p1_slots,
                perf_select_refill_alu_slots,
                perf_select_refill_serial_slots,
                perf_select_refill_other_slots,
                perf_select_refill_pair_slots + perf_select_refill_p0_slots +
                    perf_select_refill_p1_slots + perf_select_refill_alu_slots +
                    perf_select_refill_serial_slots + perf_select_refill_other_slots,
                perf_loss_select_refill_slots);
            $display("PERF_RS_DEPENDENCY_DETAIL2: SRC0=%-d SRC1=%-d BOTH_SRC=%-d COMPLETION_WAKE=%-d ALLOC_WAKE=%-d LOAD=%-d MUL=%-d BRANCH=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_dep_src0_slots,
                perf_dep_src1_slots,
                perf_dep_both_src_slots,
                perf_dep_completion_wakeup_slots,
                perf_dep_alloc_wakeup_slots,
                perf_dep_load_slots,
                perf_dep_mul_slots,
                perf_dep_branch_slots,
                perf_dep_other_slots,
                perf_dep_src0_slots + perf_dep_src1_slots + perf_dep_both_src_slots +
                    perf_dep_completion_wakeup_slots + perf_dep_alloc_wakeup_slots +
                    perf_dep_load_slots + perf_dep_mul_slots + perf_dep_branch_slots +
                    perf_dep_other_slots,
                perf_loss_rs_dependency_slots);
            $display("PERF_SINGLE_BUNDLE_OP: ALU=%-d LOAD=%-d STORE=%-d MUL=%-d CSR_SYS=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_single_op_alu_slots,
                perf_single_op_load_slots,
                perf_single_op_store_slots,
                perf_single_op_mul_slots,
                perf_single_op_csr_sys_slots,
                perf_single_op_other_slots,
                perf_single_op_alu_slots + perf_single_op_load_slots +
                    perf_single_op_store_slots + perf_single_op_mul_slots +
                    perf_single_op_csr_sys_slots + perf_single_op_other_slots,
                perf_loss_single_bundle_slots);
            $display("PERF_SELECT_REFILL_SHAPE: P0_P1=%-d P0_ALU=%-d P1_ALU=%-d ALU_ALU=%-d SINGLE_P0=%-d SINGLE_P1=%-d SINGLE_ALU=%-d SERIAL=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_refill_shape_p0_p1_slots,
                perf_refill_shape_p0_alu_slots,
                perf_refill_shape_p1_alu_slots,
                perf_refill_shape_alu_alu_slots,
                perf_refill_shape_single_p0_slots,
                perf_refill_shape_single_p1_slots,
                perf_refill_shape_single_alu_slots,
                perf_refill_shape_serial_slots,
                perf_refill_shape_other_slots,
                perf_refill_shape_p0_p1_slots + perf_refill_shape_p0_alu_slots +
                    perf_refill_shape_p1_alu_slots + perf_refill_shape_alu_alu_slots +
                    perf_refill_shape_single_p0_slots + perf_refill_shape_single_p1_slots +
                    perf_refill_shape_single_alu_slots + perf_refill_shape_serial_slots +
                    perf_refill_shape_other_slots,
                perf_loss_select_refill_slots);
            $display("PERF_RS_DEPENDENCY_WAKE: BOTH=%-d MIXED=%-d SRC0_COMPLETION=%-d SRC1_COMPLETION=%-d SRC0_ALLOC=%-d SRC1_ALLOC=%-d NONE=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_dep_wake_both_slots,
                perf_dep_wake_mixed_slots,
                perf_dep_wake_src0_completion_slots,
                perf_dep_wake_src1_completion_slots,
                perf_dep_wake_src0_alloc_slots,
                perf_dep_wake_src1_alloc_slots,
                perf_dep_wake_none_slots,
                perf_dep_wake_both_slots + perf_dep_wake_mixed_slots +
                    perf_dep_wake_src0_completion_slots +
                    perf_dep_wake_src1_completion_slots +
                    perf_dep_wake_src0_alloc_slots + perf_dep_wake_src1_alloc_slots +
                    perf_dep_wake_none_slots,
                perf_loss_rs_dependency_slots);
            $display("PERF_RS_DEPENDENCY_OP: ALU=%-d LOAD=%-d STORE=%-d MUL=%-d BRANCH=%-d OTHER=%-d ACCOUNTED=%-d EXPECTED=%-d",
                perf_dep_op_alu_slots,
                perf_dep_op_load_slots,
                perf_dep_op_store_slots,
                perf_dep_op_mul_slots,
                perf_dep_op_branch_slots,
                perf_dep_op_other_slots,
                perf_dep_op_alu_slots + perf_dep_op_load_slots +
                    perf_dep_op_store_slots + perf_dep_op_mul_slots +
                    perf_dep_op_branch_slots + perf_dep_op_other_slots,
                perf_loss_rs_dependency_slots);
            $display("PERF_RS_DEP_BLOCKER_OPERANDS: ALU=%-d LOAD=%-d MDU=%-d OTHER=%-d STALE=%-d TOTAL=%-d",
                perf_dep_blocker_operand_cycles[0],
                perf_dep_blocker_operand_cycles[1],
                perf_dep_blocker_operand_cycles[2],
                perf_dep_blocker_operand_cycles[3],
                perf_dep_blocker_operand_cycles[4],
                perf_dep_blocker_operand_cycles[0] +
                    perf_dep_blocker_operand_cycles[1] +
                    perf_dep_blocker_operand_cycles[2] +
                    perf_dep_blocker_operand_cycles[3] +
                    perf_dep_blocker_operand_cycles[4]);
            $display("PERF_RS_DEP_BLOCKER_MASK_SLOTS: M0=%-d M1=%-d M2=%-d M3=%-d M4=%-d M5=%-d M6=%-d M7=%-d M8=%-d M9=%-d M10=%-d M11=%-d M12=%-d M13=%-d M14=%-d M15=%-d M16=%-d M17=%-d M18=%-d M19=%-d M20=%-d M21=%-d M22=%-d M23=%-d M24=%-d M25=%-d M26=%-d M27=%-d M28=%-d M29=%-d M30=%-d M31=%-d",
                perf_dep_blocker_mask_slots[0],
                perf_dep_blocker_mask_slots[1],
                perf_dep_blocker_mask_slots[2],
                perf_dep_blocker_mask_slots[3],
                perf_dep_blocker_mask_slots[4],
                perf_dep_blocker_mask_slots[5],
                perf_dep_blocker_mask_slots[6],
                perf_dep_blocker_mask_slots[7],
                perf_dep_blocker_mask_slots[8],
                perf_dep_blocker_mask_slots[9],
                perf_dep_blocker_mask_slots[10],
                perf_dep_blocker_mask_slots[11],
                perf_dep_blocker_mask_slots[12],
                perf_dep_blocker_mask_slots[13],
                perf_dep_blocker_mask_slots[14],
                perf_dep_blocker_mask_slots[15],
                perf_dep_blocker_mask_slots[16],
                perf_dep_blocker_mask_slots[17],
                perf_dep_blocker_mask_slots[18],
                perf_dep_blocker_mask_slots[19],
                perf_dep_blocker_mask_slots[20],
                perf_dep_blocker_mask_slots[21],
                perf_dep_blocker_mask_slots[22],
                perf_dep_blocker_mask_slots[23],
                perf_dep_blocker_mask_slots[24],
                perf_dep_blocker_mask_slots[25],
                perf_dep_blocker_mask_slots[26],
                perf_dep_blocker_mask_slots[27],
                perf_dep_blocker_mask_slots[28],
                perf_dep_blocker_mask_slots[29],
                perf_dep_blocker_mask_slots[30],
                perf_dep_blocker_mask_slots[31]);
            $display("PERF_SELECT_CANDIDATES: M0=%-d M1=%-d M2=%-d M3=%-d M4=%-d M5=%-d M6=%-d M7=%-d M8=%-d M9=%-d M10=%-d M11=%-d M12=%-d M13=%-d M14=%-d M15=%-d",
                perf_candidate_mask_count[0],
                perf_candidate_mask_count[1],
                perf_candidate_mask_count[2],
                perf_candidate_mask_count[3],
                perf_candidate_mask_count[4],
                perf_candidate_mask_count[5],
                perf_candidate_mask_count[6],
                perf_candidate_mask_count[7],
                perf_candidate_mask_count[8],
                perf_candidate_mask_count[9],
                perf_candidate_mask_count[10],
                perf_candidate_mask_count[11],
                perf_candidate_mask_count[12],
                perf_candidate_mask_count[13],
                perf_candidate_mask_count[14],
                perf_candidate_mask_count[15]);
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
            $display("PERF_LSU_STB: LOOKUP=%-d HIT=%-d BLOCK=%-d DRAIN=%-d",
                u_dut.u_ydrasil_load_store_unit.perf_stb_lookup_q,
                u_dut.u_ydrasil_load_store_unit.perf_stb_hit_q,
                u_dut.u_ydrasil_load_store_unit.perf_stb_block_q,
                u_dut.u_ydrasil_load_store_unit.perf_stb_drain_q);
            $display("PERF_LSU_AGE_REPAIR: CYCLES=%-d",
                perf_lsu_age_repair_cycles);
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

`ifndef SYNTHESIS
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            execution_wave_measure_active <=
                !execution_wave_measure_filter_en;
            execution_wave_measure_done <= 1'b0;
        end else if (execution_wave_measure_filter_en) begin
            if ((u_dut.ex_accept_valid &&
                 (u_dut.id_instr_addr == execution_wave_measure_start_pc)) ||
                (u_dut.ex_accept_valid1 &&
                 (u_dut.dual_id_ex_pc == execution_wave_measure_start_pc)) ||
                (retire0_valid &&
                 (retire0_pc == execution_wave_measure_start_pc)) ||
                (retire1_valid &&
                 (retire1_pc == execution_wave_measure_start_pc))) begin
                execution_wave_measure_active <= 1'b1;
                execution_wave_measure_done <= 1'b0;
            end else if ((u_dut.ex_accept_valid &&
                          (u_dut.id_instr_addr ==
                           execution_wave_measure_stop_pc)) ||
                         (u_dut.ex_accept_valid1 &&
                          (u_dut.dual_id_ex_pc ==
                           execution_wave_measure_stop_pc)) ||
                         (retire0_valid &&
                      (retire0_pc == execution_wave_measure_stop_pc)) ||
                         (retire1_valid &&
                          (retire1_pc == execution_wave_measure_stop_pc))) begin
                execution_wave_measure_active <= 1'b0;
                execution_wave_measure_done <= 1'b1;
            end
        end
    end

    // Compact full-run waveform probe.  This is deliberately CSV rather than
    // a full hierarchical dump so a complete CoreMark run stays small enough
    // to scan for representative execution bubbles.
    always @(posedge clk) begin
        if (execution_wave_en && rst_n &&
            (cycle_count >= execution_wave_start) &&
            (cycle_count <= execution_wave_end)) begin
            $fwrite(execution_wave_fd,
                "%0d,%0d,%0d,%0d,%0d,0x%08h,0x%08h,0x%08h,%0d,%0d,0x%08h,0x%08h,%0d,%0d,0x%08h,0x%08h,%0d,%0d,",
                !rst_n,
                rst_n && execution_wave_measure_active,
                execution_wave_measure_filter_en ?
                    execution_wave_measure_done : pc_write_to_host_flag,
                cycle_count, instruction_count,
                u_dut.if_id_pc,
                u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                u_dut.u_ydrasil_issue_stage.issue_pkt1_i.pc,
                u_dut.u_ydrasil_issue_stage.issue_pkt_i.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.issue_pkt1_i.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.selected_uop0.pc,
                u_dut.u_ydrasil_issue_stage.selected_uop1.pc,
                u_dut.u_ydrasil_issue_stage.selected_uop0.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.selected_uop1.dst.rob_tag,
                u_dut.id_instr_addr, u_dut.dual_id_ex_pc,
                u_dut.alu_in_valid ? u_dut.alu_in_producer_id :
                    u_dut.agu_in_req.producer_id,
                u_dut.dual_meta.producer_id);
            $fwrite(execution_wave_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,0x%03h,0x%03h,0x%03h,0x%03h,0x%03h,0x%04h,0x%03h,",
                u_dut.if_id_valid, u_dut.if_id1_valid,
                u_dut.id_issue_pkt.valid, u_dut.id_issue_pkt1.valid,
                u_dut.u_ydrasil_issue_stage.dispatch_accept_o,
                u_dut.u_ydrasil_issue_stage.dispatch_accept1_o,
                u_dut.u_ydrasil_issue_stage.issue_window_valid_q,
                perf_rs_dep_mask_now, perf_rs_order_mask_now,
                perf_rs_resource_mask_now, perf_rs_ready_mask_now,
                perf_rs_candidate_mask_now, perf_rs_selected_mask_now);
            $fwrite(execution_wave_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
                u_dut.u_ydrasil_issue_stage.selected_valid0,
                u_dut.u_ydrasil_issue_stage.selected_valid1,
                u_dut.u_ydrasil_issue_stage.select_buf_push,
                u_dut.u_ydrasil_issue_stage.select_head_valid_q,
                u_dut.u_ydrasil_issue_stage.select_head_pair_q,
                u_dut.u_ydrasil_issue_stage.select_skid_valid_q,
                u_dut.u_ydrasil_issue_stage.head0_b_only,
                u_dut.u_ydrasil_issue_stage.lane_a_accept,
                u_dut.u_ydrasil_issue_stage.lane_b_accept,
                u_dut.alu_in_valid || u_dut.agu_in_valid,
                u_dut.ex_hzd_pkt1.valid,
                (u_dut.alu_in_valid && u_dut.ex_accept_valid) ||
                    (u_dut.agu_in_valid && u_dut.lsu_req_pkt.valid),
                u_dut.ex_accept_valid1,
                u_dut.commit_pkt.valid, u_dut.commit_pkt1.valid);
            $fwrite(execution_wave_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
                u_dut.u_ctrl.queue_count_q,
                u_dut.u_ctrl.producer_full_stall,
                u_dut.lsu_issue_credit,
                u_dut.u_ydrasil_issue_stage.lsu_select_reserved_q,
                u_dut.u_ydrasil_load_store_unit.queue_count_q,
                u_dut.lsu_status_pkt.idle,
                u_dut.issue_lsu_struct_stall,
                u_dut.issue_serialize_stall,
                u_dut.mdu_div_available,
                u_dut.flush_ex, u_dut.ex_pc_redirect,
                u_dut.u_ydrasil_issue_stage.recovery_pending_q,
                u_dut.pipeline_flush, u_dut.id_fence_i,
                u_dut.trap_ctrl_pkt.redirect,
                u_dut.u_ydrasil_if_stage.fetchq_count_q,
                u_dut.u_ydrasil_if_stage.mem_req_valid_q,
                u_dut.u_ydrasil_if_stage.mem_resp_valid,
                u_dut.u_ydrasil_if_stage.pending_redirect_valid_q);
            $fwrite(execution_wave_fd,
                "0x%03h,0x%03h,0x%03h,%0d,%0d,0x%02h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0x%08h,0x%08h\n",
                u_dut.u_ydrasil_issue_stage.issue_src0_completion_wakeup |
                    u_dut.u_ydrasil_issue_stage.issue_src1_completion_wakeup,
                u_dut.u_ydrasil_issue_stage.issue_src0_alloc_wakeup |
                    u_dut.u_ydrasil_issue_stage.issue_src1_alloc_wakeup,
                u_dut.u_ydrasil_issue_stage.issue_src0_fast_main |
                    u_dut.u_ydrasil_issue_stage.issue_src0_fast_dual |
                    u_dut.u_ydrasil_issue_stage.issue_src1_fast_main |
                    u_dut.u_ydrasil_issue_stage.issue_src1_fast_dual,
                u_dut.u_ydrasil_issue_stage.dtcm_launch_wakeup_valid_i,
                u_dut.u_ydrasil_issue_stage.mdu_due_i.valid,
                perf_rs_dep_blocker_mask_now,
                u_dut.u_ydrasil_issue_stage.alu_free_credit_q,
                u_dut.u_ydrasil_issue_stage.p0_free_credit_q,
                u_dut.u_ydrasil_issue_stage.p1_free_credit_q,
                u_dut.alu_in_valid || u_dut.agu_in_valid,
                u_dut.dual_alu_valid || u_dut.dual_bit_valid ||
                    u_dut.dual_bru_valid || u_dut.mul_in_valid ||
                    u_dut.csr_in_valid,
                u_dut.ex_branch_mispredict,
                u_dut.u_ydrasil_issue_stage.select_direct_fire,
                u_dut.u_ydrasil_issue_stage.select_direct_fire &&
                    u_dut.u_ydrasil_issue_stage.selected_valid1,
                retire0_pc, retire1_pc);
        end
    end

    // Optional per-entry trace for causal (rather than aggregate-mask)
    // attribution. This is a TB-only observer and is completely dormant
    // unless +execution_causal=<path> is supplied.
    always @(posedge clk) begin
        if (execution_causal_en && rst_n &&
            (cycle_count >= execution_wave_start) &&
            (cycle_count <= execution_wave_end)) begin
            $fwrite(execution_causal_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0x%03h,0x%03h,0x%0h,0x%03h,0x%03h,0x%03h,0x%03h,0x%03h,0x%03h,0x%03h",
                !rst_n,
                rst_n && execution_wave_measure_active,
                execution_wave_measure_filter_en ?
                    execution_wave_measure_done : pc_write_to_host_flag,
                cycle_count, instruction_count,
                u_dut.alu_in_valid || u_dut.agu_in_valid,
                u_dut.dual_alu_valid || u_dut.dual_bit_valid ||
                    u_dut.dual_bru_valid || u_dut.mul_in_valid ||
                    u_dut.csr_in_valid,
                u_dut.ex_accept_valid, u_dut.ex_accept_valid1,
                u_dut.u_ctrl.producer_full_stall,
                u_dut.u_ctrl.queue_count_q,
                u_dut.u_ctrl.queue_head_id,
                u_dut.ex_pc_redirect, u_dut.ex_branch_mispredict,
                u_dut.u_ydrasil_if_stage.fetchq_count_q,
                u_dut.u_ydrasil_if_stage.mem_req_valid_q,
                u_dut.u_ydrasil_if_stage.mem_resp_valid,
                u_dut.u_ydrasil_if_stage.pending_redirect_valid_q,
                u_dut.if_id_valid, u_dut.if_id1_valid,
                u_dut.id_issue_pkt.valid, u_dut.id_issue_pkt1.valid,
                u_dut.u_ydrasil_issue_stage.dispatch_accept_o,
                u_dut.u_ydrasil_issue_stage.dispatch_accept1_o,
                u_dut.u_ydrasil_issue_stage.select_buf_push,
                u_dut.u_ydrasil_issue_stage.select_head_valid_q,
                u_dut.u_ydrasil_issue_stage.select_head_pair_q,
                u_dut.u_ydrasil_issue_stage.select_skid_valid_q,
                u_dut.u_ydrasil_issue_stage.lane_a_accept,
                u_dut.u_ydrasil_issue_stage.lane_b_accept,
                u_dut.u_ydrasil_issue_stage.issue_window_valid_q,
                perf_rs_ready_mask_now,
                perf_rs_candidate_mask_now,
                perf_rs_selected_mask_now,
                perf_rs_dep_mask_now,
                perf_rs_order_mask_now,
                perf_rs_resource_mask_now,
                u_dut.u_ydrasil_issue_stage.issue_src0_completion_wakeup |
                    u_dut.u_ydrasil_issue_stage.issue_src1_completion_wakeup,
                u_dut.u_ydrasil_issue_stage.issue_src0_alloc_wakeup |
                    u_dut.u_ydrasil_issue_stage.issue_src1_alloc_wakeup,
                u_dut.u_ydrasil_issue_stage.issue_src0_fast_main |
                u_dut.u_ydrasil_issue_stage.issue_src0_fast_dual |
                    u_dut.u_ydrasil_issue_stage.issue_src1_fast_main |
                    u_dut.u_ydrasil_issue_stage.issue_src1_fast_dual);
            $fwrite(execution_causal_fd,
                ",0x%08h,%0d,0x%08h,%0d,0x%08h,%0d,0x%08h,%0d,0x%08h,%0d,0x%08h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                u_dut.u_ydrasil_issue_stage.select_head_uop0_q.pc,
                u_dut.u_ydrasil_issue_stage.select_head_uop0_q.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.select_head_uop1_q.pc,
                u_dut.u_ydrasil_issue_stage.select_head_uop1_q.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.issue_pkt_i.pc,
                u_dut.u_ydrasil_issue_stage.issue_pkt_i.dst.rob_tag,
                u_dut.u_ydrasil_issue_stage.issue_pkt1_i.pc,
                u_dut.u_ydrasil_issue_stage.issue_pkt1_i.dst.rob_tag,
                u_dut.id_instr_addr,
                u_dut.alu_in_valid ? u_dut.alu_in_producer_id :
                    u_dut.agu_in_req.producer_id,
                u_dut.dual_id_ex_pc, u_dut.dual_meta.producer_id,
                u_dut.completion_meta[0].valid,
                u_dut.completion_meta[0].producer_id,
                u_dut.completion_meta[1].valid,
                u_dut.completion_meta[1].producer_id,
                u_dut.completion_meta[2].valid,
                u_dut.completion_meta[2].producer_id,
                u_dut.completion_meta[3].valid,
                u_dut.completion_meta[3].producer_id,
                u_dut.commit_pkt.valid, u_dut.commit_pkt.producer_id,
                u_dut.commit_pkt1.valid, u_dut.commit_pkt1.producer_id);
            for (execution_causal_idx = 0; execution_causal_idx < 12;
                 execution_causal_idx = execution_causal_idx + 1) begin
                $fwrite(execution_causal_fd,
                    ",%0d,0x%08h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                    u_dut.u_ydrasil_issue_stage.issue_window_valid_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].pc,
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].dst.rob_tag,
                    u_dut.u_ydrasil_issue_stage.issue_window_src0_ready_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_window_src1_ready_q[
                        execution_causal_idx],
                    (execution_causal_idx < 4) ?
                        u_dut.u_ydrasil_issue_stage.alu_candidate_local[
                            execution_causal_idx] :
                    (execution_causal_idx < 8) ?
                        u_dut.u_ydrasil_issue_stage.p0_candidate_local[
                            execution_causal_idx-4] :
                        (u_dut.u_ydrasil_issue_stage.p1_candidate_local[
                            execution_causal_idx-8] ||
                         u_dut.u_ydrasil_issue_stage.p1_serial_candidate_local[
                            execution_causal_idx-8]),
                    u_dut.u_ydrasil_issue_stage.issue_select_mask[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].src0.tag_valid,
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].src0.producer_tag,
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].src1.tag_valid,
                    u_dut.u_ydrasil_issue_stage.issue_window_q[
                        execution_causal_idx].src1.producer_tag,
                    u_dut.u_ydrasil_issue_stage.issue_memory_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_store_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_mul_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_divrem_q[
                        execution_causal_idx],
                    u_dut.u_ydrasil_issue_stage.issue_serial_q[
                        execution_causal_idx],
                    |(u_dut.u_ydrasil_issue_stage.issue_order_mask_q[
                        execution_causal_idx] &
                      ~u_dut.u_ydrasil_issue_stage.issued_slot_mask_q),
                    (execution_causal_idx < 4) ? 0 :
                    (execution_causal_idx < 8) ? 1 : 2);
            end
            $fwrite(execution_causal_fd, "\n");
        end
    end

    final begin
        if (execution_wave_fd != 0)
            $fclose(execution_wave_fd);
        if (execution_causal_fd != 0)
            $fclose(execution_causal_fd);
    end
`endif



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
