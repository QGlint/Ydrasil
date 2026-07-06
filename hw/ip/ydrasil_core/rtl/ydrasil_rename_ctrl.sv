module ydrasil_rename_ctrl
import ydrasil_pkg::*;
#(
    parameter int PHYS_REGS = 64,
    parameter int ROB_DEPTH = 64,
    parameter int PREG_BITS = 6,
    parameter int ROB_PTR_BITS = 6
)(
    input  wire clk,
    input  wire rst_n,
    input  wire flush_id_i,
    input  wire flush_ex_i,
    input  wire interrupt_i,

    input  wire [INST_DATA_WIDTH-1:0] if_id_instr_i,

    input  wire id_ctrl_rs1_ren_i,
    input  wire id_ctrl_rs2_ren_i,
    input  wire id_ctrl_rd_wen_i,
    input  wire [REGS_ADDR_WIDTH-1:0] id_ctrl_rd_addr_i,
    input  wire [PREG_BITS-1:0] id_ctrl_rs1_psrc_i,
    input  wire [PREG_BITS-1:0] id_ctrl_rs2_psrc_i,
    input  wire [PREG_BITS-1:0] id_ctrl_pdst_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type_i,
    input  wire ctrl_rs1_ready_next_bypass_i,
    input  wire ctrl_rs2_ready_next_bypass_i,

    input  wire pipe1_ctrl_rs1_ren_i,
    input  wire pipe1_ctrl_rs2_ren_i,
    input  wire [PREG_BITS-1:0] pipe1_ctrl_rs1_psrc_i,
    input  wire [PREG_BITS-1:0] pipe1_ctrl_rs2_psrc_i,

    input  wire rn_alloc_valid_i,
    input  wire rn_if_rd_valid_i,
    input  wire rn_if_ctrl_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] rn_alloc_rd_addr_i,

    input  wire alu_wb_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] alu_wb_arch_rd_i,
    input  wire [PREG_BITS-1:0] alu_wb_pdst_i,

    input  wire lsu_wb_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] lsu_wb_arch_rd_i,
    input  wire [PREG_BITS-1:0] lsu_wb_pdst_i,

    input  wire mul_wb_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] mul_wb_arch_rd_i,
    input  wire [PREG_BITS-1:0] mul_wb_pdst_i,

    input  wire pipe1_wb_valid_i,
    input  wire [PREG_BITS-1:0] pipe1_wb_pdst_i,
    input  wire [REGS_DATA_WIDTH-1:0] pipe1_wb_data_i,
    input  wire pipe1_issue_valid_i,
    input  wire [PREG_BITS-1:0] pipe1_issue_pdst_i,

    input  wire wb_rf_wen_i,

    output wire [PREG_BITS-1:0] live_rs1_psrc_o,
    output wire [PREG_BITS-1:0] live_rs2_psrc_o,
    output wire [PREG_BITS-1:0] alloc_pdst_o,
    output logic [PHYS_REGS-1:0] preg_ready_o,

    output wire rs1_ready_o,
    output wire rs2_ready_o,
    output wire rs1_uncommitted_o,
    output wire rs2_uncommitted_o,
    output wire pipe1_rs1_ready_o,
    output wire pipe1_rs2_ready_o,
    output wire pipe1_rs1_uncommitted_o,
    output wire pipe1_rs2_uncommitted_o,
    output wire live_rs1_ready_o,
    output wire live_rs2_ready_o,
    output wire pipe1_rename_ready_o,
    output wire alloc_stall_o,
    output wire ctrl_block_o,

    output wire wb_pdst_found_o,
    output wire lsu_pdst_found_o,
    output wire mul_pdst_found_o,
    output wire pipe1_pdst_found_o,
    output wire [PREG_BITS-1:0] wb_pdst_o,
    output wire [PREG_BITS-1:0] lsu_pdst_o,
    output wire [PREG_BITS-1:0] mul_pdst_o,
    output wire [PREG_BITS-1:0] pipe1_pdst_o,

    output wire commit0_valid_o,
    output wire commit0_ready_o,
    output wire pipe1_commit_rf_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0] pipe1_commit_arch_rd_o,
    output wire [REGS_DATA_WIDTH-1:0] pipe1_commit_data_o,

`ifndef SYNTHESIS
    output wire ctrl_rs1_block_o,
    output wire ctrl_rs2_block_o,
    output wire ctrl_at_head_o,
    output wire pipe1_branch_order_escape_o,
`endif
    output wire unused_o
);

    localparam [6:0] ROB_DEPTH_COUNT = 7'd64;

    reg [PREG_BITS-1:0] rat_q [0:REGS_NUM-1];
    reg [PREG_BITS-1:0] amt_q [0:REGS_NUM-1];
    reg [PHYS_REGS-1:0] free_q;
    reg [PHYS_REGS-1:0] busy_q;
    reg [6:0] free_count_q;
    reg [PREG_BITS-1:0] alloc_pdst_q;
    reg [PHYS_REGS-1:0] free_next_for_alloc;
    reg [PHYS_REGS-1:0] flush_free_map;
    reg [PREG_BITS-1:0] flush_rat_map [0:REGS_NUM-1];

    reg [ROB_PTR_BITS-1:0] rob_head_q;
    reg [ROB_PTR_BITS-1:0] rob_tail_q;
    reg [6:0] rob_occ_q;
    reg rob_valid_q [0:ROB_DEPTH-1];
    reg rob_ready_q [0:ROB_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] rob_arch_rd_q [0:ROB_DEPTH-1];
    reg [PREG_BITS-1:0] rob_new_pdst_q [0:ROB_DEPTH-1];
    reg [PREG_BITS-1:0] rob_old_pdst_q [0:ROB_DEPTH-1];
    reg rob_pipe1_q [0:ROB_DEPTH-1];
    reg rob_ctrl_q [0:ROB_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] rob_data_q [0:ROB_DEPTH-1];
    reg [ROB_PTR_BITS-1:0] pdst_rob_idx_q [0:PHYS_REGS-1];
    reg pdst_rob_valid_q [0:PHYS_REGS-1];

    function automatic [PREG_BITS-1:0] first_free;
        input [PHYS_REGS-1:0] free_map;
        integer k;
        begin
            first_free = '0;
            for (k = PHYS_REGS-1; k >= 1; k = k - 1) begin
                if (free_map[k]) begin
                    first_free = k[PREG_BITS-1:0];
                end
            end
        end
    endfunction

    function automatic [PHYS_REGS-1:0] free_from_amt;
        integer f;
        begin
            free_from_amt = '1;
            for (f = 0; f < REGS_NUM; f = f + 1) begin
                free_from_amt[amt_q[f]] = 1'b0;
            end
        end
    endfunction

    function automatic [PHYS_REGS-1:0] free_from_amt_with_redirect_wb;
        input preserve_valid;
        input [REGS_ADDR_WIDTH-1:0] preserve_arch_rd;
        input [PREG_BITS-1:0] preserve_pdst;
        begin
            free_from_amt_with_redirect_wb = free_from_amt();
            if (preserve_valid) begin
                if (amt_q[preserve_arch_rd] != preserve_pdst) begin
                    free_from_amt_with_redirect_wb[amt_q[preserve_arch_rd]] = 1'b1;
                end
                free_from_amt_with_redirect_wb[preserve_pdst] = 1'b0;
            end
        end
    endfunction

    function automatic [6:0] count_free;
        input [PHYS_REGS-1:0] free_map;
        integer f;
        begin
            count_free = '0;
            for (f = 0; f < PHYS_REGS; f = f + 1) begin
                count_free = count_free + (free_map[f] ? 7'd1 : 7'd0);
            end
        end
    endfunction

    function automatic rob_has_pipe1_not_head;
        integer j;
        reg found;
        reg [ROB_PTR_BITS-1:0] idx;
        begin
            found = 1'b0;
            rob_has_pipe1_not_head = 1'b0;
            for (j = 1; j < ROB_DEPTH; j = j + 1) begin
                idx = rob_head_q + ROB_PTR_BITS'(j);
                if (!found && rob_valid_q[idx] && rob_pipe1_q[idx]) begin
                    rob_has_pipe1_not_head = 1'b1;
                    found = 1'b1;
                end
            end
        end
    endfunction

    function automatic rob_has_pipe1_after_next;
        integer j;
        reg found;
        reg [ROB_PTR_BITS-1:0] idx;
        begin
            found = 1'b0;
            rob_has_pipe1_after_next = 1'b0;
            for (j = 2; j < ROB_DEPTH; j = j + 1) begin
                idx = rob_head_q + ROB_PTR_BITS'(j);
                if (!found && rob_valid_q[idx] && rob_pipe1_q[idx]) begin
                    rob_has_pipe1_after_next = 1'b1;
                    found = 1'b1;
                end
            end
        end
    endfunction

    wire alloc_needs_preg = rn_if_rd_valid_i & (rn_alloc_rd_addr_i != '0);
    wire can_alloc = (rob_occ_q < ROB_DEPTH_COUNT) &&
        (!alloc_needs_preg | (free_count_q != '0));
    wire alloc_valid = rn_alloc_valid_i & can_alloc;
    wire alloc_rd_valid = alloc_valid & alloc_needs_preg;
    wire commit0_ready =
        rob_valid_q[rob_head_q] &
        rob_ready_q[rob_head_q];
    wire redirect_wb_preserve =
        flush_ex_i &
        alu_wb_valid_i &
        (alu_wb_arch_rd_i != '0) &
        (alu_wb_pdst_i != '0);

    assign live_rs1_psrc_o = (if_id_instr_i[19:15] == '0) ? '0 : rat_q[if_id_instr_i[19:15]];
    assign live_rs2_psrc_o = (if_id_instr_i[24:20] == '0) ? '0 : rat_q[if_id_instr_i[24:20]];
    assign alloc_pdst_o = alloc_pdst_q;
    assign pipe1_rename_ready_o =
        (rob_occ_q < ROB_DEPTH_COUNT) && (free_count_q != '0);
    assign alloc_stall_o =
        (rn_if_rd_valid_i | rn_if_ctrl_valid_i) & !can_alloc;

    assign wb_pdst_o = alu_wb_pdst_i;
    assign lsu_pdst_o = lsu_wb_pdst_i;
    assign mul_pdst_o = mul_wb_pdst_i;
    assign pipe1_pdst_o = pipe1_wb_pdst_i;

    assign wb_pdst_found_o =
        alu_wb_valid_i & (alu_wb_arch_rd_i != '0) &
        (alu_wb_pdst_i != '0) & pdst_rob_valid_q[alu_wb_pdst_i];
    assign lsu_pdst_found_o =
        lsu_wb_valid_i & (lsu_wb_arch_rd_i != '0) &
        (lsu_wb_pdst_i != '0) & pdst_rob_valid_q[lsu_wb_pdst_i];
    assign mul_pdst_found_o =
        mul_wb_valid_i & (mul_wb_arch_rd_i != '0) &
        (mul_wb_pdst_i != '0) & pdst_rob_valid_q[mul_wb_pdst_i];
    assign pipe1_pdst_found_o =
        pipe1_wb_valid_i & (pipe1_wb_pdst_i != '0) &
        pdst_rob_valid_q[pipe1_wb_pdst_i];

    wire [ROB_PTR_BITS-1:0] wb_rob_idx = pdst_rob_idx_q[alu_wb_pdst_i];
    wire [ROB_PTR_BITS-1:0] lsu_rob_idx = pdst_rob_idx_q[lsu_wb_pdst_i];
    wire [ROB_PTR_BITS-1:0] mul_rob_idx = pdst_rob_idx_q[mul_wb_pdst_i];
    wire [ROB_PTR_BITS-1:0] pipe1_rob_idx = pdst_rob_idx_q[pipe1_wb_pdst_i];

    always_comb begin
        integer p;
        for (p = 0; p < PHYS_REGS; p = p + 1) begin
            preg_ready_o[p] =
                !busy_q[p] |
                (wb_pdst_found_o & (alu_wb_pdst_i == p[PREG_BITS-1:0])) |
                (lsu_pdst_found_o & (lsu_wb_pdst_i == p[PREG_BITS-1:0])) |
                (mul_pdst_found_o & (mul_wb_pdst_i == p[PREG_BITS-1:0])) |
                (pipe1_pdst_found_o & (pipe1_wb_pdst_i == p[PREG_BITS-1:0]));
        end
    end

    always_comb begin
        integer a;
        integer r;
        reg stop_at_redirect;
        reg [ROB_PTR_BITS-1:0] idx;

        flush_free_map = '1;
        for (a = 0; a < REGS_NUM; a = a + 1) begin
            flush_rat_map[a] = amt_q[a];
            flush_free_map[amt_q[a]] = 1'b0;
        end

        stop_at_redirect = 1'b0;
        for (r = 0; r < ROB_DEPTH; r = r + 1) begin
            idx = rob_head_q + ROB_PTR_BITS'(r);
            if (!stop_at_redirect && rob_valid_q[idx]) begin
                if (rob_ready_q[idx] &&
                    (rob_arch_rd_q[idx] != '0) &&
                    (rob_new_pdst_q[idx] != '0)) begin
                    if (flush_rat_map[rob_arch_rd_q[idx]] != rob_new_pdst_q[idx]) begin
                        flush_free_map[flush_rat_map[rob_arch_rd_q[idx]]] = 1'b1;
                    end
                    flush_rat_map[rob_arch_rd_q[idx]] = rob_new_pdst_q[idx];
                    flush_free_map[rob_new_pdst_q[idx]] = 1'b0;
                end

                if (rob_ctrl_q[idx]) begin
                    stop_at_redirect = 1'b1;
                end
            end
        end

        if (redirect_wb_preserve) begin
            if (flush_rat_map[alu_wb_arch_rd_i] != alu_wb_pdst_i) begin
                flush_free_map[flush_rat_map[alu_wb_arch_rd_i]] = 1'b1;
            end
            flush_rat_map[alu_wb_arch_rd_i] = alu_wb_pdst_i;
            flush_free_map[alu_wb_pdst_i] = 1'b0;
        end
    end

    assign rs1_ready_o =
        !id_ctrl_rs1_ren_i | (id_ctrl_rs1_psrc_i == '0) |
        preg_ready_o[id_ctrl_rs1_psrc_i];
    assign rs2_ready_o =
        !id_ctrl_rs2_ren_i | (id_ctrl_rs2_psrc_i == '0) |
        preg_ready_o[id_ctrl_rs2_psrc_i];
    assign live_rs1_ready_o =
        (live_rs1_psrc_o == '0) | preg_ready_o[live_rs1_psrc_o];
    assign live_rs2_ready_o =
        (live_rs2_psrc_o == '0) | preg_ready_o[live_rs2_psrc_o];
    assign pipe1_rs1_ready_o =
        !pipe1_ctrl_rs1_ren_i | (pipe1_ctrl_rs1_psrc_i == '0) |
        preg_ready_o[pipe1_ctrl_rs1_psrc_i];
    assign pipe1_rs2_ready_o =
        !pipe1_ctrl_rs2_ren_i | (pipe1_ctrl_rs2_psrc_i == '0) |
        preg_ready_o[pipe1_ctrl_rs2_psrc_i];

    assign rs1_uncommitted_o =
        id_ctrl_rs1_ren_i && (id_ctrl_rs1_psrc_i != '0) &&
        pdst_rob_valid_q[id_ctrl_rs1_psrc_i];
    assign rs2_uncommitted_o =
        id_ctrl_rs2_ren_i && (id_ctrl_rs2_psrc_i != '0) &&
        pdst_rob_valid_q[id_ctrl_rs2_psrc_i];
    assign pipe1_rs1_uncommitted_o =
        pipe1_ctrl_rs1_ren_i && (pipe1_ctrl_rs1_psrc_i != '0) &&
        pdst_rob_valid_q[pipe1_ctrl_rs1_psrc_i];
    assign pipe1_rs2_uncommitted_o =
        pipe1_ctrl_rs2_ren_i && (pipe1_ctrl_rs2_psrc_i != '0) &&
        pdst_rob_valid_q[pipe1_ctrl_rs2_psrc_i];

    assign pipe1_commit_rf_wen_o =
        commit0_ready &
        rob_pipe1_q[rob_head_q] &
        (rob_arch_rd_q[rob_head_q] != '0) &
        !wb_rf_wen_i;
    assign commit0_valid_o =
        commit0_ready &
        (!rob_pipe1_q[rob_head_q] | pipe1_commit_rf_wen_o);
    assign commit0_ready_o = commit0_ready;
    assign pipe1_commit_arch_rd_o = rob_arch_rd_q[rob_head_q];
    assign pipe1_commit_data_o = rob_data_q[rob_head_q];
    wire commit_frees_preg =
        commit0_valid_o & (rob_old_pdst_q[rob_head_q] != '0);

    wire ctrl_at_head =
        rob_valid_q[rob_head_q] &
        id_ctrl_rd_wen_i & (id_ctrl_pdst_i != '0) &
        (rob_new_pdst_q[rob_head_q] == id_ctrl_pdst_i);
    wire pipe1_head_committing =
        rob_pipe1_q[rob_head_q] & pipe1_commit_rf_wen_o;
    wire pipe1_head_rf_block =
        rob_valid_q[rob_head_q] &
        rob_pipe1_q[rob_head_q] &
        rob_ready_q[rob_head_q] &
        !pipe1_commit_rf_wen_o &
        wb_rf_wen_i;
    wire pipe1_only_head_rf_block =
        pipe1_head_rf_block &
        !rob_has_pipe1_not_head() &
        !(pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) &
        !(pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire [ROB_PTR_BITS-1:0] rob_next_head = rob_head_q + ROB_PTR_BITS'(1);
    wire pipe1_only_next_head_after_commit =
        commit0_valid_o &
        !rob_pipe1_q[rob_head_q] &
        rob_valid_q[rob_next_head] &
        rob_pipe1_q[rob_next_head] &
        rob_ready_q[rob_next_head] &
        !rob_has_pipe1_after_next() &
        !(pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) &
        !(pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire pipe1_branch_order_escape =
        pipe1_only_head_rf_block | pipe1_only_next_head_after_commit;
    wire pipe1_older_uncommitted =
        (rob_pipe1_q[rob_head_q] & !pipe1_head_committing) |
        rob_has_pipe1_not_head() |
        (pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) |
        (pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire ctrl_older_rob_block =
        id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
        (pipe1_older_uncommitted & !pipe1_branch_order_escape) &
        !ctrl_at_head;
    wire ctrl_rs1_ready_for_branch =
        rs1_ready_o |
        (id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
         ctrl_rs1_ready_next_bypass_i);
    wire ctrl_rs2_ready_for_branch =
        rs2_ready_o |
        (id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
         ctrl_rs2_ready_next_bypass_i);
    wire ctrl_rs1_block =
        id_ctrl_rs1_ren_i & !ctrl_rs1_ready_for_branch;
    wire ctrl_rs2_block =
        id_ctrl_rs2_ren_i & !ctrl_rs2_ready_for_branch;
    assign ctrl_block_o =
        (id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
         (ctrl_rs1_block | ctrl_rs2_block)) |
        ctrl_older_rob_block;

`ifndef SYNTHESIS
    assign ctrl_rs1_block_o = ctrl_rs1_block;
    assign ctrl_rs2_block_o = ctrl_rs2_block;
    assign ctrl_at_head_o = ctrl_at_head;
    assign pipe1_branch_order_escape_o = pipe1_branch_order_escape;
`endif
    assign unused_o = 1'b0;

    always_comb begin
        free_next_for_alloc = free_q;
        if (commit_frees_preg) begin
            free_next_for_alloc[rob_old_pdst_q[rob_head_q]] = 1'b1;
        end
        if (alloc_rd_valid && (alloc_pdst_q != '0)) begin
            free_next_for_alloc[alloc_pdst_q] = 1'b0;
        end
    end

    wire [PREG_BITS-1:0] alloc_pdst_next = first_free(free_next_for_alloc);

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            free_q <= 64'hffff_ffff_0000_0000;
            busy_q <= '0;
            free_count_q <= 7'd32;
            alloc_pdst_q <= 6'd32;
            rob_head_q <= '0;
            rob_tail_q <= '0;
            rob_occ_q <= '0;
            for (i = 0; i < REGS_NUM; i = i + 1) begin
                rat_q[i] <= i[PREG_BITS-1:0];
                amt_q[i] <= i[PREG_BITS-1:0];
            end
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                rob_valid_q[i] <= 1'b0;
                rob_ready_q[i] <= 1'b0;
                rob_arch_rd_q[i] <= '0;
                rob_new_pdst_q[i] <= '0;
                rob_old_pdst_q[i] <= '0;
                rob_pipe1_q[i] <= 1'b0;
                rob_ctrl_q[i] <= 1'b0;
                rob_data_q[i] <= '0;
                pdst_rob_idx_q[i] <= '0;
                pdst_rob_valid_q[i] <= 1'b0;
            end
        end else if (flush_id_i | flush_ex_i | interrupt_i) begin
            free_q <= flush_free_map;
            busy_q <= '0;
            free_count_q <= count_free(flush_free_map);
            alloc_pdst_q <= first_free(flush_free_map);
            rob_head_q <= '0;
            rob_tail_q <= '0;
            rob_occ_q <= '0;
            for (i = 0; i < REGS_NUM; i = i + 1) begin
                rat_q[i] <= flush_rat_map[i];
                amt_q[i] <= flush_rat_map[i];
            end
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                rob_valid_q[i] <= 1'b0;
                rob_ready_q[i] <= 1'b0;
                rob_arch_rd_q[i] <= '0;
                rob_new_pdst_q[i] <= '0;
                rob_old_pdst_q[i] <= '0;
                rob_pipe1_q[i] <= 1'b0;
                rob_ctrl_q[i] <= 1'b0;
                rob_data_q[i] <= '0;
                pdst_rob_idx_q[i] <= '0;
                pdst_rob_valid_q[i] <= 1'b0;
            end
        end else begin
            if (wb_pdst_found_o) begin
                busy_q[alu_wb_pdst_i] <= 1'b0;
                if (rob_valid_q[wb_rob_idx] && !rob_ready_q[wb_rob_idx]) begin
                    rob_ready_q[wb_rob_idx] <= 1'b1;
                end
            end
            if (lsu_pdst_found_o) begin
                busy_q[lsu_wb_pdst_i] <= 1'b0;
                if (rob_valid_q[lsu_rob_idx] && !rob_ready_q[lsu_rob_idx]) begin
                    rob_ready_q[lsu_rob_idx] <= 1'b1;
                end
            end
            if (mul_pdst_found_o) begin
                busy_q[mul_wb_pdst_i] <= 1'b0;
                if (rob_valid_q[mul_rob_idx] && !rob_ready_q[mul_rob_idx]) begin
                    rob_ready_q[mul_rob_idx] <= 1'b1;
                end
            end
            if (pipe1_pdst_found_o) begin
                busy_q[pipe1_wb_pdst_i] <= 1'b0;
                if (rob_valid_q[pipe1_rob_idx] && !rob_ready_q[pipe1_rob_idx]) begin
                    rob_ready_q[pipe1_rob_idx] <= 1'b1;
                    rob_pipe1_q[pipe1_rob_idx] <= 1'b1;
                    rob_data_q[pipe1_rob_idx] <= pipe1_wb_data_i;
                end
            end

            if (commit0_valid_o) begin
                if (rob_arch_rd_q[rob_head_q] != '0) begin
                    amt_q[rob_arch_rd_q[rob_head_q]] <= rob_new_pdst_q[rob_head_q];
                    pdst_rob_valid_q[rob_new_pdst_q[rob_head_q]] <= 1'b0;
                end
                if (commit_frees_preg) begin
                    free_q[rob_old_pdst_q[rob_head_q]] <= 1'b1;
                    pdst_rob_valid_q[rob_old_pdst_q[rob_head_q]] <= 1'b0;
                end
                rob_valid_q[rob_head_q] <= 1'b0;
                rob_ready_q[rob_head_q] <= 1'b0;
                rob_pipe1_q[rob_head_q] <= 1'b0;
                rob_ctrl_q[rob_head_q] <= 1'b0;
                rob_data_q[rob_head_q] <= '0;
                rob_head_q <= rob_head_q + ROB_PTR_BITS'(1);
            end

            if (alloc_valid) begin
                if (alloc_rd_valid) begin
                    free_q[alloc_pdst_q] <= 1'b0;
                    busy_q[alloc_pdst_q] <= 1'b1;
                    rat_q[rn_alloc_rd_addr_i] <= alloc_pdst_q;
                    pdst_rob_idx_q[alloc_pdst_q] <= rob_tail_q;
                    pdst_rob_valid_q[alloc_pdst_q] <= 1'b1;
                end
                rob_valid_q[rob_tail_q] <= 1'b1;
                rob_ready_q[rob_tail_q] <= !alloc_rd_valid;
                rob_arch_rd_q[rob_tail_q] <= alloc_rd_valid ? rn_alloc_rd_addr_i : '0;
                rob_new_pdst_q[rob_tail_q] <= alloc_rd_valid ? alloc_pdst_q : '0;
                rob_old_pdst_q[rob_tail_q] <= alloc_rd_valid ? rat_q[rn_alloc_rd_addr_i] : '0;
                rob_pipe1_q[rob_tail_q] <= 1'b0;
                rob_ctrl_q[rob_tail_q] <= rn_if_ctrl_valid_i;
                rob_data_q[rob_tail_q] <= '0;
                rob_tail_q <= rob_tail_q + ROB_PTR_BITS'(1);
            end

            rob_occ_q <=
                rob_occ_q +
                (alloc_valid ? 7'd1 : 7'd0) -
                (commit0_valid_o ? 7'd1 : 7'd0);
            free_count_q <=
                free_count_q -
                (alloc_rd_valid ? 7'd1 : 7'd0) +
                (commit_frees_preg ? 7'd1 : 7'd0);
            alloc_pdst_q <= alloc_pdst_next;
        end
    end

endmodule
