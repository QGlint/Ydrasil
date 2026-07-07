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
    input  wire [INST_DATA_WIDTH-1:0] if_id1_instr_i,

    input  wire id_ctrl_rs1_ren_i,
    input  wire id_ctrl_rs2_ren_i,
    input  wire id_ctrl_rd_wen_i,
    input  wire [REGS_ADDR_WIDTH-1:0] id_ctrl_rd_addr_i,
    input  wire [PREG_BITS-1:0] id_ctrl_rs1_psrc_i,
    input  wire [PREG_BITS-1:0] id_ctrl_rs2_psrc_i,
    input  wire [PREG_BITS-1:0] id_ctrl_pdst_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] id_ctrl_operator_type_i,

    input  wire pipe1_ctrl_rs1_ren_i,
    input  wire pipe1_ctrl_rs2_ren_i,
    input  wire [PREG_BITS-1:0] pipe1_ctrl_rs1_psrc_i,
    input  wire [PREG_BITS-1:0] pipe1_ctrl_rs2_psrc_i,

    input  wire rn_alloc_valid_i,
    input  wire rn_if_rd_valid_i,
    input  wire rn_if_ctrl_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] rn_alloc_rd_addr_i,
    input  wire rn_alloc1_valid_i,
    input  wire rn_if1_rd_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] rn_alloc1_rd_addr_i,

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
	    input  wire pipe1_wb_rob_valid_i,
	    input  wire [ROB_PTR_BITS-1:0] pipe1_wb_rob_idx_i,
	    input  wire pipe1_issue_valid_i,
	    input  wire [PREG_BITS-1:0] pipe1_issue_pdst_i,
	    input  wire ctrl_complete_valid_i,
	    input  wire [ROB_PTR_BITS-1:0] ctrl_complete_rob_idx_i,

    input  wire wb_rf_wen_i,

    output wire [PREG_BITS-1:0] live_rs1_psrc_o,
    output wire [PREG_BITS-1:0] live_rs2_psrc_o,
    output wire [PREG_BITS-1:0] live1_rs1_psrc_o,
	    output wire [PREG_BITS-1:0] live1_rs2_psrc_o,
	    output wire [PREG_BITS-1:0] alloc_pdst_o,
	    output wire [PREG_BITS-1:0] alloc1_pdst_o,
	    output wire [ROB_PTR_BITS-1:0] alloc0_rob_idx_o,
	    output wire [ROB_PTR_BITS-1:0] alloc1_rob_idx_o,
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
    output wire live1_rs1_ready_o,
    output wire live1_rs2_ready_o,
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
    output wire pipe1_commit1_rf_wen_o,
    output wire [REGS_ADDR_WIDTH-1:0] pipe1_commit1_arch_rd_o,
    output wire [REGS_DATA_WIDTH-1:0] pipe1_commit1_data_o,

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
    reg [PHYS_REGS-1:0] amt_free_q;
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

    reg [PREG_BITS-1:0] first_free_next_for_alloc;
    reg [PREG_BITS-1:0] first_free_flush_map;
    reg [PREG_BITS-1:0] first_free_without_alloc0;
    reg rob_has_pipe1_not_head_comb;
    reg rob_has_pipe1_after_next_comb;

    always_comb begin
        integer k;
        first_free_next_for_alloc = '0;
        first_free_flush_map = '0;
        first_free_without_alloc0 = '0;
        for (k = PHYS_REGS-1; k >= 1; k = k - 1) begin
            if (free_next_for_alloc[k]) begin
                first_free_next_for_alloc = k[PREG_BITS-1:0];
            end
            if (flush_free_map[k]) begin
                first_free_flush_map = k[PREG_BITS-1:0];
            end
            if (free_q[k] && (k[PREG_BITS-1:0] != alloc_pdst_q)) begin
                first_free_without_alloc0 = k[PREG_BITS-1:0];
            end
        end
    end

    always_comb begin
        integer j;
        reg found_not_head;
        reg found_after_next;
        reg [ROB_PTR_BITS-1:0] idx;
        found_not_head = 1'b0;
        found_after_next = 1'b0;
        rob_has_pipe1_not_head_comb = 1'b0;
        rob_has_pipe1_after_next_comb = 1'b0;
        for (j = 1; j < ROB_DEPTH; j = j + 1) begin
            idx = rob_head_q + ROB_PTR_BITS'(j);
            if (!found_not_head && rob_valid_q[idx] && rob_pipe1_q[idx]) begin
                rob_has_pipe1_not_head_comb = 1'b1;
                found_not_head = 1'b1;
            end
            if ((j >= 2) && !found_after_next &&
                rob_valid_q[idx] && rob_pipe1_q[idx]) begin
                rob_has_pipe1_after_next_comb = 1'b1;
                found_after_next = 1'b1;
            end
        end
    end

    wire alloc_needs_preg = rn_if_rd_valid_i & (rn_alloc_rd_addr_i != '0);
    wire alloc1_needs_preg = rn_if1_rd_valid_i & (rn_alloc1_rd_addr_i != '0);
    wire [1:0] alloc_req_count =
        {1'b0, rn_alloc_valid_i} + {1'b0, rn_alloc1_valid_i};
    wire [1:0] alloc_preg_req_count =
        {1'b0, (rn_alloc_valid_i & alloc_needs_preg)} +
        {1'b0, (rn_alloc1_valid_i & alloc1_needs_preg)};
    wire can_alloc =
        ({1'b0, rob_occ_q} + {6'd0, alloc_req_count} <= {1'b0, ROB_DEPTH_COUNT}) &&
        ({1'b0, free_count_q} >= {6'd0, alloc_preg_req_count});
    wire alloc_valid = rn_alloc_valid_i & can_alloc;
    wire alloc1_valid = rn_alloc1_valid_i & can_alloc;
    wire alloc_rd_valid = alloc_valid & alloc_needs_preg;
    wire alloc1_rd_valid = alloc1_valid & alloc1_needs_preg;
    wire [ROB_PTR_BITS-1:0] alloc0_tail = rob_tail_q;
    wire [ROB_PTR_BITS-1:0] alloc1_tail = rob_tail_q + ROB_PTR_BITS'(alloc_valid ? 1 : 0);
    wire [REGS_ADDR_WIDTH-1:0] live1_rs1_addr = if_id1_instr_i[19:15];
    wire [REGS_ADDR_WIDTH-1:0] live1_rs2_addr = if_id1_instr_i[24:20];
    wire live1_rs1_dep_alloc0 =
        alloc_needs_preg &&
        (live1_rs1_addr == rn_alloc_rd_addr_i);
    wire live1_rs2_dep_alloc0 =
        alloc_needs_preg &&
        (live1_rs2_addr == rn_alloc_rd_addr_i);
    wire [PREG_BITS-1:0] alloc1_pdst =
        alloc_needs_preg ? first_free_without_alloc0 : alloc_pdst_q;
    wire [PREG_BITS-1:0] alloc1_old_pdst =
        (alloc_needs_preg && (rn_alloc1_rd_addr_i == rn_alloc_rd_addr_i)) ?
        alloc_pdst_q : rat_q[rn_alloc1_rd_addr_i];
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
    assign live1_rs1_psrc_o =
        (live1_rs1_addr == '0) ? '0 :
        live1_rs1_dep_alloc0 ? alloc_pdst_q : rat_q[live1_rs1_addr];
    assign live1_rs2_psrc_o =
        (live1_rs2_addr == '0) ? '0 :
        live1_rs2_dep_alloc0 ? alloc_pdst_q : rat_q[live1_rs2_addr];
	    assign alloc_pdst_o = alloc_pdst_q;
	    assign alloc1_pdst_o = alloc1_pdst;
	    assign alloc0_rob_idx_o = alloc0_tail;
	    assign alloc1_rob_idx_o = alloc1_tail;
	    assign pipe1_rename_ready_o =
        (rob_occ_q < ROB_DEPTH_COUNT) && (free_count_q != '0);
    assign alloc_stall_o =
        (rn_alloc_valid_i | rn_alloc1_valid_i) & !can_alloc;

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

        flush_free_map = amt_free_q;
        for (a = 0; a < REGS_NUM; a = a + 1) begin
            flush_rat_map[a] = amt_q[a];
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
    assign live1_rs1_ready_o =
        (live1_rs1_psrc_o == '0) |
        (!live1_rs1_dep_alloc0 && preg_ready_o[live1_rs1_psrc_o]);
    assign live1_rs2_ready_o =
        (live1_rs2_psrc_o == '0) |
        (!live1_rs2_dep_alloc0 && preg_ready_o[live1_rs2_psrc_o]);
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
        (rob_arch_rd_q[rob_head_q] != '0);
    wire pipe1_head_wait_rf_port =
        1'b0;
    assign commit0_valid_o = commit0_ready;
    assign commit0_ready_o = commit0_ready;
    assign pipe1_commit_arch_rd_o = rob_arch_rd_q[rob_head_q];
    assign pipe1_commit_data_o = rob_data_q[rob_head_q];
    wire [ROB_PTR_BITS-1:0] rob_next_head = rob_head_q + ROB_PTR_BITS'(1);
    wire commit1_valid =
        commit0_valid_o &&
        !rob_ctrl_q[rob_head_q] &&
        !rob_ctrl_q[rob_next_head] &&
        rob_valid_q[rob_next_head] &&
        rob_ready_q[rob_next_head];
    assign pipe1_commit1_rf_wen_o =
        commit1_valid &
        rob_pipe1_q[rob_next_head] &
        (rob_arch_rd_q[rob_next_head] != '0);
    assign pipe1_commit1_arch_rd_o = rob_arch_rd_q[rob_next_head];
    assign pipe1_commit1_data_o = rob_data_q[rob_next_head];
    wire commit0_frees_preg =
        commit0_valid_o & (rob_old_pdst_q[rob_head_q] != '0);
    wire commit1_frees_preg =
        commit1_valid & (rob_old_pdst_q[rob_next_head] != '0);

    wire ctrl_at_head =
        rob_valid_q[rob_head_q] &
        rob_ctrl_q[rob_head_q];
    wire pipe1_head_committing =
        rob_pipe1_q[rob_head_q] & pipe1_commit_rf_wen_o;
    wire pipe1_head_rf_block =
        rob_valid_q[rob_head_q] &
        rob_pipe1_q[rob_head_q] &
        rob_ready_q[rob_head_q] &
        pipe1_head_wait_rf_port;
    wire pipe1_only_head_rf_block =
        pipe1_head_rf_block &
        !rob_has_pipe1_not_head_comb &
        !(pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) &
        !(pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire pipe1_only_next_head_after_commit =
        commit0_valid_o &
        !rob_pipe1_q[rob_head_q] &
        rob_valid_q[rob_next_head] &
        rob_pipe1_q[rob_next_head] &
        rob_ready_q[rob_next_head] &
        !rob_has_pipe1_after_next_comb &
        !(pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) &
        !(pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire pipe1_branch_order_escape =
        pipe1_only_head_rf_block | pipe1_only_next_head_after_commit;
    wire pipe1_older_uncommitted =
        (rob_pipe1_q[rob_head_q] & !pipe1_head_committing) |
        rob_has_pipe1_not_head_comb |
        (pipe1_pdst_found_o & (pipe1_wb_pdst_i != '0)) |
        (pipe1_issue_valid_i & (pipe1_issue_pdst_i != '0));
    wire ctrl_older_rob_block =
        id_ctrl_operator_type_i[OPERATOR_TYPE_BJP] &
        (rob_occ_q != '0) &
        !ctrl_at_head;
    wire ctrl_rs1_ready_for_branch =
        rs1_ready_o;
    wire ctrl_rs2_ready_for_branch =
        rs2_ready_o;
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
        if (commit0_frees_preg) begin
            free_next_for_alloc[rob_old_pdst_q[rob_head_q]] = 1'b1;
        end
        if (commit1_frees_preg) begin
            free_next_for_alloc[rob_old_pdst_q[rob_next_head]] = 1'b1;
        end
        if (alloc_rd_valid && (alloc_pdst_q != '0)) begin
            free_next_for_alloc[alloc_pdst_q] = 1'b0;
        end
        if (alloc1_rd_valid && (alloc1_pdst != '0)) begin
            free_next_for_alloc[alloc1_pdst] = 1'b0;
        end
    end

    wire [PREG_BITS-1:0] alloc_pdst_next = first_free_next_for_alloc;

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            free_q <= 64'hffff_ffff_0000_0000;
            amt_free_q <= 64'hffff_ffff_0000_0000;
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
            amt_free_q <= flush_free_map;
            busy_q <= '0;
            free_count_q <= 7'd32;
            alloc_pdst_q <= first_free_flush_map;
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
	            if (pipe1_wb_valid_i && pipe1_wb_rob_valid_i &&
	                rob_valid_q[pipe1_wb_rob_idx_i]) begin
	                if (pipe1_wb_pdst_i != '0) begin
	                    busy_q[pipe1_wb_pdst_i] <= 1'b0;
	                end
	                if (!rob_ready_q[pipe1_wb_rob_idx_i]) begin
	                    rob_ready_q[pipe1_wb_rob_idx_i] <= 1'b1;
	                    rob_pipe1_q[pipe1_wb_rob_idx_i] <= 1'b1;
	                    rob_data_q[pipe1_wb_rob_idx_i] <= pipe1_wb_data_i;
	                end
	            end else if (pipe1_pdst_found_o) begin
	                busy_q[pipe1_wb_pdst_i] <= 1'b0;
	                if (rob_valid_q[pipe1_rob_idx] && !rob_ready_q[pipe1_rob_idx]) begin
                    rob_ready_q[pipe1_rob_idx] <= 1'b1;
                    rob_pipe1_q[pipe1_rob_idx] <= 1'b1;
                    rob_data_q[pipe1_rob_idx] <= pipe1_wb_data_i;
                end
            end
	            if (ctrl_complete_valid_i &&
	                rob_valid_q[ctrl_complete_rob_idx_i] &&
	                rob_ctrl_q[ctrl_complete_rob_idx_i]) begin
	                rob_ready_q[ctrl_complete_rob_idx_i] <= 1'b1;
	            end

            if (commit0_valid_o) begin
                if (rob_arch_rd_q[rob_head_q] != '0) begin
                    amt_q[rob_arch_rd_q[rob_head_q]] <= rob_new_pdst_q[rob_head_q];
                    if (rob_new_pdst_q[rob_head_q] != '0) begin
                        amt_free_q[rob_new_pdst_q[rob_head_q]] <= 1'b0;
                    end
                    pdst_rob_valid_q[rob_new_pdst_q[rob_head_q]] <= 1'b0;
                end
                if (commit0_frees_preg) begin
                    free_q[rob_old_pdst_q[rob_head_q]] <= 1'b1;
                    amt_free_q[rob_old_pdst_q[rob_head_q]] <= 1'b1;
                    pdst_rob_valid_q[rob_old_pdst_q[rob_head_q]] <= 1'b0;
                end
                rob_valid_q[rob_head_q] <= 1'b0;
                rob_ready_q[rob_head_q] <= 1'b0;
                rob_pipe1_q[rob_head_q] <= 1'b0;
                rob_ctrl_q[rob_head_q] <= 1'b0;
                rob_data_q[rob_head_q] <= '0;
                rob_head_q <= rob_head_q + ROB_PTR_BITS'(commit1_valid ? 2 : 1);
            end

            if (commit1_valid) begin
                if (rob_arch_rd_q[rob_next_head] != '0) begin
                    amt_q[rob_arch_rd_q[rob_next_head]] <= rob_new_pdst_q[rob_next_head];
                    if (rob_new_pdst_q[rob_next_head] != '0) begin
                        amt_free_q[rob_new_pdst_q[rob_next_head]] <= 1'b0;
                    end
                    pdst_rob_valid_q[rob_new_pdst_q[rob_next_head]] <= 1'b0;
                end
                if (commit1_frees_preg) begin
                    free_q[rob_old_pdst_q[rob_next_head]] <= 1'b1;
                    amt_free_q[rob_old_pdst_q[rob_next_head]] <= 1'b1;
                    pdst_rob_valid_q[rob_old_pdst_q[rob_next_head]] <= 1'b0;
                end
                rob_valid_q[rob_next_head] <= 1'b0;
                rob_ready_q[rob_next_head] <= 1'b0;
                rob_pipe1_q[rob_next_head] <= 1'b0;
                rob_ctrl_q[rob_next_head] <= 1'b0;
                rob_data_q[rob_next_head] <= '0;
            end

            if (alloc_valid) begin
                if (alloc_rd_valid) begin
                    free_q[alloc_pdst_q] <= 1'b0;
                    busy_q[alloc_pdst_q] <= 1'b1;
                    rat_q[rn_alloc_rd_addr_i] <= alloc_pdst_q;
                    pdst_rob_idx_q[alloc_pdst_q] <= alloc0_tail;
                    pdst_rob_valid_q[alloc_pdst_q] <= 1'b1;
                end
                rob_valid_q[alloc0_tail] <= 1'b1;
                rob_ready_q[alloc0_tail] <= !alloc_rd_valid && !rn_if_ctrl_valid_i;
                rob_arch_rd_q[alloc0_tail] <= alloc_rd_valid ? rn_alloc_rd_addr_i : '0;
                rob_new_pdst_q[alloc0_tail] <= alloc_rd_valid ? alloc_pdst_q : '0;
                rob_old_pdst_q[alloc0_tail] <= alloc_rd_valid ? rat_q[rn_alloc_rd_addr_i] : '0;
                rob_pipe1_q[alloc0_tail] <= 1'b0;
                rob_ctrl_q[alloc0_tail] <= rn_if_ctrl_valid_i;
                rob_data_q[alloc0_tail] <= '0;
            end

            if (alloc1_valid) begin
                if (alloc1_rd_valid) begin
                    free_q[alloc1_pdst] <= 1'b0;
                    busy_q[alloc1_pdst] <= 1'b1;
                    rat_q[rn_alloc1_rd_addr_i] <= alloc1_pdst;
                    pdst_rob_idx_q[alloc1_pdst] <= alloc1_tail;
                    pdst_rob_valid_q[alloc1_pdst] <= 1'b1;
                end
                rob_valid_q[alloc1_tail] <= 1'b1;
                rob_ready_q[alloc1_tail] <= !alloc1_rd_valid;
                rob_arch_rd_q[alloc1_tail] <= alloc1_rd_valid ? rn_alloc1_rd_addr_i : '0;
                rob_new_pdst_q[alloc1_tail] <= alloc1_rd_valid ? alloc1_pdst : '0;
                rob_old_pdst_q[alloc1_tail] <= alloc1_rd_valid ? alloc1_old_pdst : '0;
                rob_pipe1_q[alloc1_tail] <= 1'b0;
                rob_ctrl_q[alloc1_tail] <= 1'b0;
                rob_data_q[alloc1_tail] <= '0;
            end

            if (alloc_valid | alloc1_valid) begin
                rob_tail_q <= rob_tail_q +
                    ROB_PTR_BITS'(alloc_valid ? 1 : 0) +
                    ROB_PTR_BITS'(alloc1_valid ? 1 : 0);
            end

            rob_occ_q <=
                rob_occ_q +
                (alloc_valid ? 7'd1 : 7'd0) +
                (alloc1_valid ? 7'd1 : 7'd0) -
                (commit0_valid_o ? 7'd1 : 7'd0) -
                (commit1_valid ? 7'd1 : 7'd0);
            free_count_q <=
                free_count_q -
                (alloc_rd_valid ? 7'd1 : 7'd0) -
                (alloc1_rd_valid ? 7'd1 : 7'd0) +
                (commit0_frees_preg ? 7'd1 : 7'd0) +
                (commit1_frees_preg ? 7'd1 : 7'd0);
            alloc_pdst_q <= alloc_pdst_next;
        end
    end

endmodule
