module ydrasil_ctrl
import ydrasil_pkg::*;
(
    input wire clk,
    input wire rst_n,
    input wire ex_branch_jump_i,
    input wire [INST_ADDR_WIDTH-1:0] ex_branch_target_i,
    input ydrasil_ex_hzd_pkt_t ex_hzd_i,
    input ydrasil_id_ctrl_pkt_t id_ctrl_i,
    input ydrasil_id_ctrl_pkt_t decode_ctrl_i,
    input ydrasil_completion_bus_t completion_bus_i,
    input ydrasil_lsu_status_pkt_t lsu_status_i,
    input wire clint_stall_i,
    input wire ex_mul_stall_i,
    input wire wb_backpressure_i,
    input wire rf_wen_rd_i,
    input wire [REGS_ADDR_WIDTH-1:0] rf_waddr_rd_i,
    input wire [REGS_DATA_WIDTH-1:0] rf_wdata_rd_i,
    input producer_id_t rf_producer_id_i,
    input wire rf_producer_tracked_i,

    output ydrasil_hzd_status_pkt_t hzd_status_o,
    output ydrasil_gpr_fwd_pkt_t wb_fwd_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs1_fwd_o,
    output ydrasil_gpr_fwd_pkt_t producer_rs2_fwd_o,
    output ydrasil_issue_dep_pkt_t decode_dep_o,
    output wire [REGS_NUM-1:0] gpr_pending_o,
    output wire ex_accept_valid_o,
    output producer_id_t producer_alloc_id_o,
    output wire producer_alloc_tracked_o,
    output wire rf_write_commit_o,
    output wire [REGS_NUM-1:0] rf_write_wen_o,
    output wire stall_if_o,
    output wire stall_id_o,
    output wire stall_pc_o,
    output wire bubble_id_o,
    output wire flush_if_o,
    output wire flush_id_o,
    output wire flush_ex_o,
    output wire branch_jump_o,
    output wire [INST_ADDR_WIDTH-1:0] branch_target_o
);

    reg [PRODUCER_NUM-1:0] producer_valid_q;
    reg [PRODUCER_NUM-1:0] producer_ready_q;
    reg [REGS_ADDR_WIDTH-1:0] producer_rd_q [0:PRODUCER_NUM-1];
    (* max_fanout = 8 *) reg [REGS_DATA_WIDTH-1:0] producer_value_q [0:PRODUCER_NUM-1];
    producer_id_t producer_tag_q [0:PRODUCER_NUM-1];
    (* extract_enable = "no" *) reg [REGS_NUM-1:0] latest_valid_q;
    (* max_fanout = 8, extract_enable = "no" *) reg [REGS_NUM-1:0] latest_valid_rs1_q;
    (* max_fanout = 8, extract_enable = "no" *) reg [REGS_NUM-1:0] latest_valid_rs2_q;
    (* max_fanout = 8 *) producer_id_t latest_id_q [0:REGS_NUM-1];
    (* max_fanout = 8 *) producer_id_t latest_id_rs1_q [0:REGS_NUM-1];
    (* max_fanout = 8 *) producer_id_t latest_id_rs2_q [0:REGS_NUM-1];
    ydrasil_gpr_fwd_pkt_t wb_fwd_q;

`ifndef SYNTHESIS
    localparam logic [2:0] DBG_PRODUCER_ALU = 3'd1;
    localparam logic [2:0] DBG_PRODUCER_LOAD = 3'd2;
    localparam logic [2:0] DBG_PRODUCER_MUL = 3'd3;
    localparam logic [2:0] DBG_PRODUCER_OTHER = 3'd4;
    logic [2:0] dbg_producer_kind_q [0:PRODUCER_NUM-1];
`endif

    wire ex_is_load = ex_hzd_i.operator_type[OPERATOR_TYPE_LOAD];
    wire ex_is_alu = ex_hzd_i.operator_type[OPERATOR_TYPE_ALU];
    wire ex_is_bitmanip = ex_hzd_i.operator_type[OPERATOR_TYPE_BITMANIP];
    wire id_ex_rd_issue = ex_accept_valid_o && (ex_hzd_i.rd_addr != '0) &&
        !ex_hzd_i.interrupt && (ex_hzd_i.alu_rf_wen || ex_is_load);

    wire id_ex_prev_alu_bypassable = ex_accept_valid_o && ex_hzd_i.alu_rf_wen &&
        (ex_hzd_i.rd_addr != '0) && !ex_hzd_i.interrupt && ex_is_alu &&
        !ex_is_bitmanip &&
        (ex_hzd_i.operator_info[OP_ALU_ADD]  |
         ex_hzd_i.operator_info[OP_ALU_SUB]  |
         ex_hzd_i.operator_info[OP_ALU_SLT]  |
         ex_hzd_i.operator_info[OP_ALU_SLTU] |
         ex_hzd_i.operator_info[OP_ALU_XOR]  |
         ex_hzd_i.operator_info[OP_ALU_OR]   |
         ex_hzd_i.operator_info[OP_ALU_AND]  |
         ex_hzd_i.operator_info[OP_ALU_SLL]  |
         ex_hzd_i.operator_info[OP_ALU_SRL]  |
         ex_hzd_i.operator_info[OP_ALU_SRA]  |
         ex_hzd_i.operator_info[OP_ALU_LUI]  |
         ex_hzd_i.operator_info[OP_ALU_AUIPC]);
    wire id_ex_prev_alu_lsu_bypassable = id_ex_prev_alu_bypassable &&
        (ex_hzd_i.operator_info[OP_ALU_ADD]  |
         ex_hzd_i.operator_info[OP_ALU_SUB]  |
         ex_hzd_i.operator_info[OP_ALU_SLT]  |
         ex_hzd_i.operator_info[OP_ALU_SLTU] |
         ex_hzd_i.operator_info[OP_ALU_XOR]  |
         ex_hzd_i.operator_info[OP_ALU_OR]   |
         ex_hzd_i.operator_info[OP_ALU_AND]  |
         ex_hzd_i.operator_info[OP_ALU_LUI]  |
         ex_hzd_i.operator_info[OP_ALU_AUIPC]);
    wire id_ex_prev_alu_consumer_bypassable = id_ctrl_i.lsu_req ?
        id_ex_prev_alu_lsu_bypassable : id_ex_prev_alu_bypassable;
    wire prev_alu_bypass_rs1 = id_ex_prev_alu_consumer_bypassable &&
        id_ctrl_i.prev_alu_bypass_ok && id_ctrl_i.rs1_ren &&
        (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire prev_alu_bypass_rs2 = id_ex_prev_alu_consumer_bypassable &&
        id_ctrl_i.prev_alu_bypass_ok && id_ctrl_i.rs2_ren &&
        (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);
    reg [PRODUCER_NUM-1:0] producer_complete_mask;
    wire [PRODUCER_NUM-1:0] producer_wb_retire_mask;
    wire producer_alloc_ex;
    producer_slot_t completion_slot [0:COMPLETION_LANES-1];
    wire producer_slot_t rf_producer_slot =
        rf_producer_id_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t ex_producer_slot =
        ex_hzd_i.producer_id[PRODUCER_SLOT_WIDTH-1:0];
    genvar completion_slot_idx;
    generate
        for (completion_slot_idx = 0; completion_slot_idx < COMPLETION_LANES;
             completion_slot_idx = completion_slot_idx + 1) begin : g_completion_slot
            assign completion_slot[completion_slot_idx] =
                completion_bus_i[completion_slot_idx].producer_id[
                    PRODUCER_SLOT_WIDTH-1:0];
        end
    endgenerate
    integer complete_lane;
    always_comb begin
        producer_complete_mask = '0;
        for (complete_lane = 0; complete_lane < COMPLETION_LANES;
             complete_lane = complete_lane + 1) begin
            if (completion_bus_i[complete_lane].valid &&
                completion_bus_i[complete_lane].producer_tracked &&
                producer_valid_q[completion_slot[complete_lane]] &&
                (producer_tag_q[completion_slot[complete_lane]] ==
                 completion_bus_i[complete_lane].producer_id))
                producer_complete_mask[completion_slot[complete_lane]] = 1'b1;
        end
    end

    genvar complete_idx;
    generate
        for (complete_idx = 0; complete_idx < PRODUCER_NUM; complete_idx++) begin : g_retire
            assign producer_wb_retire_mask[complete_idx] = rf_wen_rd_i &&
                rf_producer_tracked_i &&
                producer_valid_q[complete_idx] &&
                (rf_producer_slot == producer_slot_t'(complete_idx)) &&
                (producer_tag_q[complete_idx] == rf_producer_id_i);
        end
    endgenerate

    wire [PRODUCER_NUM-1:0] producer_retire_q = producer_wb_retire_mask;
    wire [PRODUCER_NUM-1:0] producer_occupied =
        producer_valid_q & ~producer_wb_retire_mask;
    assign producer_alloc_ex = id_ex_rd_issue && ex_hzd_i.producer_tracked;
    wire [PRODUCER_NUM-1:0] producer_occupied_after_ex = producer_occupied |
        (producer_alloc_ex ?
         (PRODUCER_NUM'(1) << ex_producer_slot) : '0);
    wire producer_full_stall = (&producer_occupied_after_ex) && id_ctrl_i.rd_wen;

    reg [PRODUCER_ID_WIDTH-1:0] producer_alloc_id;
    integer alloc_idx;
    always_comb begin
        producer_alloc_id = '0;
        for (alloc_idx = PRODUCER_NUM-1; alloc_idx >= 0; alloc_idx = alloc_idx - 1)
            if (!producer_occupied_after_ex[alloc_idx])
                producer_alloc_id = {
                    ~producer_tag_q[alloc_idx][PRODUCER_ID_WIDTH-1],
                    producer_slot_t'(alloc_idx)};
    end

    producer_id_t rs1_producer_id;
    producer_id_t rs2_producer_id;
    producer_slot_t rs1_producer_slot;
    producer_slot_t rs2_producer_slot;
    assign rs1_producer_id = id_ctrl_i.rs1_producer_id;
    assign rs2_producer_id = id_ctrl_i.rs2_producer_id;
    assign rs1_producer_slot = rs1_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    assign rs2_producer_slot = rs2_producer_id[PRODUCER_SLOT_WIDTH-1:0];
    (* max_fanout = 4 *) wire rs1_has_producer = id_ctrl_i.rs1_ren &&
        id_ctrl_i.rs1_producer_tracked && producer_valid_q[rs1_producer_slot] &&
        (producer_tag_q[rs1_producer_slot] == rs1_producer_id);
    (* max_fanout = 4 *) wire rs2_has_producer = id_ctrl_i.rs2_ren &&
        id_ctrl_i.rs2_producer_tracked && producer_valid_q[rs2_producer_slot] &&
        (producer_tag_q[rs2_producer_slot] == rs2_producer_id);
`ifndef SYNTHESIS
    wire [2:0] dbg_rs1_producer_kind = rs1_has_producer ?
        dbg_producer_kind_q[rs1_producer_slot] : 3'd0;
    wire [2:0] dbg_rs2_producer_kind = rs2_has_producer ?
        dbg_producer_kind_q[rs2_producer_slot] : 3'd0;
`endif
    // The complete generation tag remains in latest_id, so an older WAW
    // producer cannot wake a newer mapping that reuses the same slot.
    wire rs1_producer_ready = rs1_has_producer &&
        producer_ready_q[rs1_producer_slot];
    wire rs2_producer_ready = rs2_has_producer &&
        producer_ready_q[rs2_producer_slot];

    wire decode_rs1_ex_match = id_ex_rd_issue && ex_hzd_i.producer_tracked &&
        decode_ctrl_i.rs1_ren &&
        (decode_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire decode_rs2_ex_match = id_ex_rd_issue && ex_hzd_i.producer_tracked &&
        decode_ctrl_i.rs2_ren &&
        (decode_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);
    wire decode_rs1_issue_match = id_ctrl_i.rd_wen &&
        decode_ctrl_i.rs1_ren &&
        (decode_ctrl_i.rs1_addr == id_ctrl_i.rd_addr);
    wire decode_rs2_issue_match = id_ctrl_i.rd_wen &&
        decode_ctrl_i.rs2_ren &&
        (decode_ctrl_i.rs2_addr == id_ctrl_i.rd_addr);

    always_comb begin
        decode_dep_o = '0;
        if (decode_ctrl_i.rs1_ren &&
            latest_valid_rs1_q[decode_ctrl_i.rs1_addr]) begin
            decode_dep_o.rs1_producer_id =
                latest_id_rs1_q[decode_ctrl_i.rs1_addr];
            decode_dep_o.rs1_producer_tracked = 1'b1;
        end
        if (decode_ctrl_i.rs2_ren &&
            latest_valid_rs2_q[decode_ctrl_i.rs2_addr]) begin
            decode_dep_o.rs2_producer_id =
                latest_id_rs2_q[decode_ctrl_i.rs2_addr];
            decode_dep_o.rs2_producer_tracked = 1'b1;
        end
        if (decode_rs1_ex_match) begin
            decode_dep_o.rs1_producer_id = ex_hzd_i.producer_id;
            decode_dep_o.rs1_producer_tracked = 1'b1;
        end
        if (decode_rs2_ex_match) begin
            decode_dep_o.rs2_producer_id = ex_hzd_i.producer_id;
            decode_dep_o.rs2_producer_tracked = 1'b1;
        end
        if (decode_rs1_issue_match) begin
            decode_dep_o.rs1_producer_id = producer_alloc_id;
            decode_dep_o.rs1_producer_tracked = 1'b1;
        end
        if (decode_rs2_issue_match) begin
            decode_dep_o.rs2_producer_id = producer_alloc_id;
            decode_dep_o.rs2_producer_tracked = 1'b1;
        end
    end

    wire rs1_ex_match = id_ex_rd_issue && id_ctrl_i.rs1_ren &&
        (id_ctrl_i.rs1_addr == ex_hzd_i.rd_addr);
    wire rs2_ex_match = id_ex_rd_issue && id_ctrl_i.rs2_ren &&
        (id_ctrl_i.rs2_addr == ex_hzd_i.rd_addr);
    wire rs1_issue_hzd = rs1_ex_match && !prev_alu_bypass_rs1;
    wire rs2_issue_hzd = rs2_ex_match && !prev_alu_bypass_rs2;
    wire rd_issue_hzd = 1'b0;
    wire rs1_pending_stall = rs1_has_producer && !rs1_producer_ready;
    wire rs2_pending_stall = rs2_has_producer && !rs2_producer_ready;
    wire rd_waw_stall = 1'b0;
    wire store_data_wait = id_ctrl_i.store_req &&
        (rs2_issue_hzd | rs2_pending_stall);
    producer_id_t store_data_producer_id;
    assign store_data_producer_id = rs2_ex_match ? ex_hzd_i.producer_id :
        rs2_producer_id;
    wire store_data_producer_tracked = id_ctrl_i.store_req &&
        (rs2_ex_match | rs2_has_producer);
    wire rs2_blocking_hzd = !id_ctrl_i.store_req &&
        (rs2_issue_hzd | rs2_pending_stall);
    wire scoreboard_stall = rs1_issue_hzd | rs1_pending_stall |
        rs2_blocking_hzd;
    wire lsu_struct_stall = id_ctrl_i.lsu_req && lsu_status_i.busy;
    wire lsu_serialize_stall = id_ctrl_i.serialize_before && !lsu_status_i.idle;
    // RAW dependencies are retained in the ID/EX operand station.  They no
    // longer hold the issue slot or propagate a combinational stall to IF.
    // The registered AGU packet is the LSU backpressure boundary.  It may
    // absorb the one request allowed by the queue's depth-1 busy threshold;
    // agu_req_stall then holds ID/EX.  An additional issue-side LSU bubble is
    // redundant and creates a queue-count-to-issue-slot control path.
    wire decode_bubble_stall = lsu_serialize_stall | producer_full_stall |
        clint_stall_i | wb_backpressure_i;

    assign rf_write_commit_o = !rf_wen_rd_i || !rf_producer_tracked_i ||
        (latest_valid_q[rf_waddr_rd_i] &&
         (latest_id_q[rf_waddr_rd_i] == rf_producer_id_i));

    // Predecode the committed write per GPR.  Keeping the fixed latest-id
    // comparison beside each enable avoids a dynamic lookup followed by a
    // second address decode on the register-file write-enable path.
    assign rf_write_wen_o[0] = 1'b0;
    genvar rf_write_idx;
    generate
        for (rf_write_idx = 1; rf_write_idx < REGS_NUM;
             rf_write_idx = rf_write_idx + 1) begin : g_rf_write_wen
            assign rf_write_wen_o[rf_write_idx] = rf_wen_rd_i &&
                (rf_waddr_rd_i == REGS_ADDR_WIDTH'(rf_write_idx)) &&
                (!rf_producer_tracked_i ||
                 (latest_valid_q[rf_write_idx] &&
                  (latest_id_q[rf_write_idx] == rf_producer_id_i)));
        end
    endgenerate
    assign ex_accept_valid_o = ex_hzd_i.valid && !ex_branch_jump_i;
    assign producer_alloc_id_o = producer_alloc_id;
    assign producer_alloc_tracked_o = id_ctrl_i.rd_wen;
    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;
    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_ex_o = branch_jump_o;
    assign stall_id_o = ex_mul_stall_i;
    assign stall_if_o = decode_bubble_stall | ex_mul_stall_i;
    assign stall_pc_o = decode_bubble_stall | ex_mul_stall_i;
    assign bubble_id_o = decode_bubble_stall;

    // Only retained producer-table values may cross into issue operands.
    assign producer_rs1_fwd_o.valid = rs1_producer_ready;
    assign producer_rs1_fwd_o.producer_id = rs1_producer_id;
    assign producer_rs1_fwd_o.producer_tracked = rs1_has_producer;
    assign producer_rs1_fwd_o.addr = id_ctrl_i.rs1_addr;
    assign producer_rs1_fwd_o.data = producer_value_q[rs1_producer_slot];
    assign producer_rs2_fwd_o.valid = rs2_producer_ready;
    assign producer_rs2_fwd_o.producer_id = rs2_producer_id;
    assign producer_rs2_fwd_o.producer_tracked = rs2_has_producer;
    assign producer_rs2_fwd_o.addr = id_ctrl_i.rs2_addr;
    assign producer_rs2_fwd_o.data = producer_value_q[rs2_producer_slot];
    assign gpr_pending_o = latest_valid_q;

    wire [REGS_NUM-1:0] gpr_pending_clear_mask =
        (rf_wen_rd_i && rf_write_commit_o) ?
        (REGS_NUM'(1) << rf_waddr_rd_i) : '0;
    wire [REGS_NUM-1:0] gpr_pending_issue_mask = id_ex_rd_issue ?
        (REGS_NUM'(1) << ex_hzd_i.rd_addr) : '0;
    wire [REGS_NUM-1:0] gpr_pending_for_hazard = latest_valid_q;

    assign hzd_status_o.scoreboard_stall = scoreboard_stall;
    assign hzd_status_o.lsu_struct_stall = lsu_struct_stall;
    assign hzd_status_o.issue_store_data_ready = !id_ctrl_i.store_req | !store_data_wait;
    assign hzd_status_o.store_data_producer_id = store_data_producer_id;
    assign hzd_status_o.store_data_producer_tracked = store_data_producer_tracked;
    assign hzd_status_o.prev_alu_bypass_rs1 = prev_alu_bypass_rs1;
    assign hzd_status_o.prev_alu_bypass_rs2 = prev_alu_bypass_rs2;
    assign hzd_status_o.issue_rs1_wait = rs1_issue_hzd | rs1_pending_stall;
    assign hzd_status_o.issue_rs1_producer_id = rs1_ex_match ?
        ex_hzd_i.producer_id : rs1_producer_id;
    assign hzd_status_o.issue_rs1_producer_tracked =
        rs1_ex_match | rs1_has_producer;
    assign hzd_status_o.issue_rs2_wait = rs2_issue_hzd | rs2_pending_stall;
    assign hzd_status_o.issue_rs2_producer_id = rs2_ex_match ?
        ex_hzd_i.producer_id : rs2_producer_id;
    assign hzd_status_o.issue_rs2_producer_tracked =
        rs2_ex_match | rs2_has_producer;
    assign hzd_status_o.rs1_pending_stall = rs1_pending_stall;
    assign hzd_status_o.rs2_pending_stall = rs2_pending_stall;
    assign hzd_status_o.rd_waw_stall = rd_waw_stall;
    assign hzd_status_o.rs1_issue_hzd = rs1_issue_hzd;
    assign hzd_status_o.rs2_issue_hzd = rs2_issue_hzd;
    assign hzd_status_o.rd_issue_hzd = rd_issue_hzd;
    assign hzd_status_o.issue_load_producer = id_ex_rd_issue && ex_is_load;
    assign hzd_status_o.issue_alu_producer = id_ex_rd_issue &&
        ex_hzd_i.alu_rf_wen && ex_is_alu;
    assign hzd_status_o.issue_mul_div_producer = id_ex_rd_issue &&
        ex_hzd_i.operator_type[OPERATOR_TYPE_MUL];
    assign hzd_status_o.issue_src_hzd = rs1_issue_hzd | rs2_issue_hzd;
    assign hzd_status_o.store_data_wait = store_data_wait;
    assign hzd_status_o.id_ex_rd_issue = id_ex_rd_issue;
    assign hzd_status_o.gpr_pending_clear_mask = gpr_pending_clear_mask;
    assign hzd_status_o.gpr_pending_issue_mask = gpr_pending_issue_mask;
    assign hzd_status_o.gpr_pending_for_hazard = gpr_pending_for_hazard;
    assign wb_fwd_o = wb_fwd_q;

    integer slot_idx;
    integer reg_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            latest_valid_q <= '0;
            latest_valid_rs1_q <= '0;
            latest_valid_rs2_q <= '0;
            wb_fwd_q <= '0;
            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                producer_rd_q[slot_idx] <= '0;
                producer_value_q[slot_idx] <= '0;
                producer_tag_q[slot_idx] <= '0;
`ifndef SYNTHESIS
                dbg_producer_kind_q[slot_idx] <= '0;
`endif
            end
            for (reg_idx = 0; reg_idx < REGS_NUM; reg_idx++) begin
                latest_id_q[reg_idx] <= '0;
                latest_id_rs1_q[reg_idx] <= '0;
                latest_id_rs2_q[reg_idx] <= '0;
            end
        end else if (ex_hzd_i.interrupt) begin
            producer_valid_q <= '0;
            producer_ready_q <= '0;
            latest_valid_q <= '0;
            latest_valid_rs1_q <= '0;
            latest_valid_rs2_q <= '0;
            wb_fwd_q <= '0;
        end else begin
            wb_fwd_q.valid <= rf_wen_rd_i && rf_write_commit_o;
            wb_fwd_q.producer_id <= rf_producer_id_i;
            wb_fwd_q.producer_tracked <= rf_producer_tracked_i;
            wb_fwd_q.addr <= rf_waddr_rd_i;
            wb_fwd_q.data <= rf_wdata_rd_i;

            for (slot_idx = 0; slot_idx < PRODUCER_NUM; slot_idx++) begin
                if (producer_wb_retire_mask[slot_idx]) begin
                    producer_valid_q[slot_idx] <= 1'b0;
                    producer_ready_q[slot_idx] <= 1'b0;
                end
                if (producer_valid_q[slot_idx] && producer_complete_mask[slot_idx]) begin
                    producer_ready_q[slot_idx] <= 1'b1;
                    if (completion_bus_i[0].valid &&
                        completion_bus_i[0].producer_tracked &&
                        (completion_bus_i[0].producer_id == producer_tag_q[slot_idx]))
                        producer_value_q[slot_idx] <= completion_bus_i[0].data;
                    else if (completion_bus_i[1].valid &&
                             completion_bus_i[1].producer_tracked &&
                             (completion_bus_i[1].producer_id == producer_tag_q[slot_idx]))
                        producer_value_q[slot_idx] <= completion_bus_i[1].data;
                    else if (completion_bus_i[2].valid &&
                             completion_bus_i[2].producer_tracked &&
                             (completion_bus_i[2].producer_id == producer_tag_q[slot_idx]))
                        producer_value_q[slot_idx] <= completion_bus_i[2].data;
                end
            end

            if (rf_wen_rd_i && rf_producer_tracked_i && rf_write_commit_o) begin
                latest_valid_q[rf_waddr_rd_i] <= 1'b0;
                latest_valid_rs1_q[rf_waddr_rd_i] <= 1'b0;
                latest_valid_rs2_q[rf_waddr_rd_i] <= 1'b0;
            end

            if (producer_alloc_ex) begin
                producer_valid_q[ex_producer_slot] <= 1'b1;
                producer_ready_q[ex_producer_slot] <= 1'b0;
                producer_rd_q[ex_producer_slot] <= ex_hzd_i.rd_addr;
                producer_tag_q[ex_producer_slot] <= ex_hzd_i.producer_id;
`ifndef SYNTHESIS
                if (ex_is_load)
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_LOAD;
                else if (ex_hzd_i.operator_type[OPERATOR_TYPE_MUL])
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_MUL;
                else if (ex_is_alu)
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_ALU;
                else
                    dbg_producer_kind_q[ex_producer_slot] <= DBG_PRODUCER_OTHER;
`endif
                latest_valid_q[ex_hzd_i.rd_addr] <= 1'b1;
                latest_valid_rs1_q[ex_hzd_i.rd_addr] <= 1'b1;
                latest_valid_rs2_q[ex_hzd_i.rd_addr] <= 1'b1;
                latest_id_q[ex_hzd_i.rd_addr] <= ex_hzd_i.producer_id;
                latest_id_rs1_q[ex_hzd_i.rd_addr] <= ex_hzd_i.producer_id;
                latest_id_rs2_q[ex_hzd_i.rd_addr] <= ex_hzd_i.producer_id;
            end
        end
    end
endmodule
