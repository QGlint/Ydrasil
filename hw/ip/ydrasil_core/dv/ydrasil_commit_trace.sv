`timescale 1ns/1ns

module ydrasil_commit_trace
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,
    input ydrasil_commit_pkt_t retire_i,
    input ydrasil_commit_pkt_t retire1_i,
    output wire retire0_valid_o,
    output wire [INST_ADDR_WIDTH-1:0] retire0_pc_o,
    output wire retire1_valid_o,
    output wire [INST_ADDR_WIDTH-1:0] retire1_pc_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_predict_pc_o,
    output wire dbg_bp_predict_hit_o,
    output wire dbg_bp_predict_taken_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_predict_target_o,
    output wire [1:0] dbg_bp_predict_counter_o,
    output wire dbg_bp_resolve_valid_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_resolve_pc_o,
    output wire dbg_bp_actual_taken_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_actual_target_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_actual_next_pc_o,
    output wire dbg_bp_pred_hit_o,
    output wire dbg_bp_pred_taken_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_pred_target_o,
    output wire [1:0] dbg_bp_pred_counter_o,
    output wire [INST_ADDR_WIDTH-1:0] dbg_bp_pred_next_pc_o,
    output wire dbg_bp_mispredict_o
);
    bit trace_en;
    ydrasil_completion_bus_t completion_bus;

    // All custom observability stays below this DV-only instance. These
    // hierarchical reads do not add RTL fanout or enter synthesis.
    wire [INST_ADDR_WIDTH-1:0] id_instr_addr =
        $root.ydrasil_core_tb.u_dut.id_instr_addr;
    wire [BUS_ADDR_WIDTH-1:0] dtcm_addr =
        $root.ydrasil_core_tb.u_dut.dtcm_store_valid ?
        $root.ydrasil_core_tb.u_dut.dtcm_store_addr :
        $root.ydrasil_core_tb.u_dut.dtcm_load_addr;
    wire dtcm_we =
        $root.ydrasil_core_tb.u_dut.dtcm_store_valid;
    wire dtcm_req =
        $root.ydrasil_core_tb.u_dut.dtcm_load_valid |
        $root.ydrasil_core_tb.u_dut.dtcm_store_valid;
    wire [3:0] dtcm_wmask =
        $root.ydrasil_core_tb.u_dut.dtcm_store_mask;
    wire [BUS_ADDR_WIDTH-1:0] mmio_addr =
        $root.ydrasil_core_tb.u_dut.mmio_req_pkt.addr;
    wire mmio_we = $root.ydrasil_core_tb.u_dut.mmio_req_pkt.write;
    wire mmio_req = $root.ydrasil_core_tb.u_dut.mmio_req_pkt.valid;
    wire [3:0] mmio_wmask =
        $root.ydrasil_core_tb.u_dut.mmio_req_pkt.wmask;

    wire scoreboard_stall =
        $root.ydrasil_core_tb.u_dut.issue_scoreboard_stall;
    wire lsu_struct_stall =
        $root.ydrasil_core_tb.u_dut.issue_lsu_struct_stall;
    wire rs1_pending_stall =
        $root.ydrasil_core_tb.u_dut.issue_src0_wait;
    wire rs2_pending_stall =
        $root.ydrasil_core_tb.u_dut.issue_src1_wait;
    wire rs1_issue_hzd = rs1_pending_stall;
    wire rs2_issue_hzd = rs2_pending_stall;
    wire rd_waw_stall = 1'b0;
    wire rd_issue_hzd = 1'b0;
    wire issue_src_hzd = rs1_pending_stall || rs2_pending_stall;
    wire issue_load_producer =
        (rs1_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src0.producer_class == RESULT_LSU)) ||
        (rs2_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src1.producer_class == RESULT_LSU));
    wire issue_alu_producer =
        (rs1_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src0.producer_class == RESULT_ALU)) ||
        (rs2_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src1.producer_class == RESULT_ALU));
    wire issue_mul_div_producer =
        (rs1_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src0.producer_class == RESULT_MDU)) ||
        (rs2_pending_stall &&
         ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src1.producer_class == RESULT_MDU));

    wire [REGS_ADDR_WIDTH-1:0] id_ctrl_rs1_addr =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src0.arch_addr;
    wire [REGS_ADDR_WIDTH-1:0] id_ctrl_rs2_addr =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src1.arch_addr;
    wire id_ctrl_rs1_ren =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src0.used;
    wire id_ctrl_rs2_ren =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.src1.used;
    wire [REGS_ADDR_WIDTH-1:0] id_ctrl_rd_addr =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.dst.rd_addr;
    wire id_ctrl_rd_wen =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.dst.writes_gpr;
    wire id_ctrl_lsu_req =
        ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.op_class == UOP_CLASS_LOAD) ||
        ($root.ydrasil_core_tb.u_dut.issue_head_compact_uop.op_class == UOP_CLASS_STORE);
    wire [REGS_NUM-1:0] gpr_pending_for_hazard =
        $root.ydrasil_core_tb.u_dut.gpr_pending_q;
    wire [REGS_NUM-1:0] gpr_pending_clear_mask = '0;
    wire [REGS_NUM-1:0] gpr_pending_issue_mask =
        $root.ydrasil_core_tb.u_dut.gpr_pending_q;
    wire id_ex_rd_issue =
        $root.ydrasil_core_tb.u_dut.ex_accept_valid &&
        $root.ydrasil_core_tb.u_dut.ex_hzd_pkt.producer_tracked;
    wire [1:0] select_buf_count =
        {1'b0, $root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.
            select_head_valid_q} +
        {1'b0, $root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.
            select_skid_valid_q};
    wire select_bundle0_pair =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.select_head_pair_q;
    wire select_bundle1_pair =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.select_skid_pair_q;
    wire [2:0] select_buf_uop_count =
        ($root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.
            select_head_valid_q ?
         (3'd1 + {2'b0, select_bundle0_pair}) : 3'd0) +
        ($root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.
            select_skid_valid_q ?
         (3'd1 + {2'b0, select_bundle1_pair}) : 3'd0);
    wire [3:0] issue_pending_uop_count = {1'b0, select_buf_uop_count};
    wire [2:0] issue_pipe_count_q = (issue_pending_uop_count >= 4) ?
        3'd4 : issue_pending_uop_count[2:0];
    wire issue_pair_execute =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_issue_stage.issue_pair_execute;

    wire decode_valid =
        $root.ydrasil_core_tb.u_dut.issue_head_compact_uop.valid;
    wire decode_if_ready = $root.ydrasil_core_tb.u_dut.decode_if_ready;
    wire wb_backpressure = 1'b0;
    wire rf_wen_rd = 1'b0;
    wire [REGS_ADDR_WIDTH-1:0] rf_waddr_rd = '0;
    wire lsu_rf_wen_rd =
        $root.ydrasil_core_tb.u_dut.lsu_completion_valid;
    wire [REGS_ADDR_WIDTH-1:0] lsu_rf_waddr_rd =
        $root.ydrasil_core_tb.u_dut.lsu_completion_addr;
    wire clint_stall = $root.ydrasil_core_tb.u_dut.trap_ctrl_pkt.stall;
    wire interrupt = $root.ydrasil_core_tb.u_dut.trap_ctrl_pkt.redirect;
    wire clint_csr_we =
        $root.ydrasil_core_tb.u_dut.trap_csr_write_pkt.valid;
    wire [CSR_ADDR_WIDTH-1:0] clint_csr_waddr =
        $root.ydrasil_core_tb.u_dut.trap_csr_write_pkt.addr;
    wire [REGS_DATA_WIDTH-1:0] clint_csr_wdata =
        $root.ydrasil_core_tb.u_dut.trap_csr_write_pkt.data;
    wire [2:0] instret_inc_count = {2'b0, retire_i.valid} +
        {2'b0, retire1_i.valid};
    wire [31:0] csr_instret =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_csr_stage.
            u_registers_csr.instret[31:0];
    wire [31:0] csr_cyclel =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_csr_stage.
            u_registers_csr.cycle[31:0];
    wire lsu_ctrl_busy =
        $root.ydrasil_core_tb.u_dut.lsu_status_pkt.busy;

    genvar completion_lane;
    generate
        for (completion_lane = 0; completion_lane < COMPLETION_LANES;
             completion_lane++) begin : g_completion_probe
            assign completion_bus[completion_lane].valid =
                $root.ydrasil_core_tb.u_dut.completion_meta[completion_lane].valid;
            assign completion_bus[completion_lane].producer_id =
                $root.ydrasil_core_tb.u_dut.completion_meta[completion_lane].producer_id;
            assign completion_bus[completion_lane].producer_tracked =
                $root.ydrasil_core_tb.u_dut.completion_meta[completion_lane].producer_tracked;
            assign completion_bus[completion_lane].addr =
                $root.ydrasil_core_tb.u_dut.completion_rd[completion_lane];
            assign completion_bus[completion_lane].data =
                $root.ydrasil_core_tb.u_dut.completion_data[completion_lane];
        end
    endgenerate

    assign retire0_valid_o = retire_i.valid;
    assign retire0_pc_o = retire_i.pc;
    assign retire1_valid_o = retire1_i.valid;
    assign retire1_pc_o = retire1_i.pc;
    assign dbg_bp_predict_pc_o = $root.ydrasil_core_tb.u_dut.bp_lookup_pc;
    assign dbg_bp_predict_hit_o =
        $root.ydrasil_core_tb.u_dut.bp_bram_predict_hit;
    assign dbg_bp_predict_taken_o =
        $root.ydrasil_core_tb.u_dut.bp_bram_predict_taken;
    assign dbg_bp_predict_target_o =
        $root.ydrasil_core_tb.u_dut.bp_bram_predict_target;
    assign dbg_bp_predict_counter_o =
        $root.ydrasil_core_tb.u_dut.bp_bram_predict_counter;
    assign dbg_bp_resolve_valid_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_resolve_valid;
    assign dbg_bp_resolve_pc_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_resolve_pc;
    assign dbg_bp_actual_taken_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_actual_taken;
    assign dbg_bp_actual_target_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_actual_target;
    assign dbg_bp_actual_next_pc_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_actual_next_pc;
    assign dbg_bp_pred_hit_o = $root.ydrasil_core_tb.u_dut.dbg_bp_pred_hit;
    assign dbg_bp_pred_taken_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_pred_taken;
    assign dbg_bp_pred_target_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_pred_target;
    assign dbg_bp_pred_counter_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_pred_counter;
    assign dbg_bp_pred_next_pc_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_pred_next_pc;
    assign dbg_bp_mispredict_o =
        $root.ydrasil_core_tb.u_dut.dbg_bp_mispredict;

    wire retire0_pc_is_dtcm =
        (retire_i.pc >= DTCM_BASE_ADDR) &&
        (retire_i.pc < (DTCM_BASE_ADDR +
         ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
    wire retire1_pc_is_dtcm =
        (retire1_i.pc >= DTCM_BASE_ADDR) &&
        (retire1_i.pc < (DTCM_BASE_ADDR +
         ((32'd1 << DTCM_ADDR_WIDTH) << 2)));
    wire [INST_DATA_WIDTH-1:0] retire0_trace_instr = retire0_pc_is_dtcm ?
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_dtcm.u_impl.mem_r[
            retire_i.pc[DTCM_ADDR_WIDTH+1:2]] : retire_i.pc[2] ?
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_itcm.u_impl.mem_r[
            retire_i.pc[ITCM_ADDR_WIDTH+1:3]][63:32] :
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_itcm.u_impl.mem_r[
            retire_i.pc[ITCM_ADDR_WIDTH+1:3]][31:0];
    wire [INST_DATA_WIDTH-1:0] retire1_trace_instr = retire1_pc_is_dtcm ?
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_dtcm.u_impl.mem_r[
            retire1_i.pc[DTCM_ADDR_WIDTH+1:2]] : retire1_i.pc[2] ?
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_itcm.u_impl.mem_r[
            retire1_i.pc[ITCM_ADDR_WIDTH+1:3]][63:32] :
        $root.ydrasil_core_tb.u_dut.u_ydrasil_mems.u_itcm.u_impl.mem_r[
            retire1_i.pc[ITCM_ADDR_WIDTH+1:3]][31:0];

    task automatic print_register_commit;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        begin
            if (trace_en && (waddr != '0)) begin
                $display("core   0: 0x%08h (0x%08h) unknown", pc, instr);
                $display("3 0x%08h (0x%08h) x%0d 0x%08h",
                    pc, instr, waddr, wdata);
            end
        end
    endtask

    initial trace_en = $test$plusargs("commit_trace");

    always @(posedge clk) begin
        if (rst_n) begin
            if (retire_i.valid && retire_i.writes_gpr)
                print_register_commit(retire_i.pc, retire0_trace_instr,
                    retire_i.rd_addr, retire_i.value);
            if (retire1_i.valid && retire1_i.writes_gpr)
                print_register_commit(retire1_i.pc, retire1_trace_instr,
                    retire1_i.rd_addr, retire1_i.value);
        end
    end
endmodule
