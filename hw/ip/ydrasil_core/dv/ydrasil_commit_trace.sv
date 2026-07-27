`timescale 1ns/1ns

module ydrasil_commit_trace
import ydrasil_pkg::*;
#(
    parameter int FIFO_DEPTH = 256,
    parameter int FIFO_PTR_WIDTH = 8
) (
    input  wire clk,
    input  wire rst_n,

    input  wire alu_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] alu_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] alu_instr_i,
    input  wire [REGS_ADDR_WIDTH-1:0] alu_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] alu_wdata_i,

    input  wire dual_alu_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] dual_alu_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] dual_alu_instr_i,
    input  wire [REGS_ADDR_WIDTH-1:0] dual_alu_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] dual_alu_wdata_i,

    input  wire dual_lsu_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] dual_lsu_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] dual_lsu_issue_instr_i,

    input  wire lsu_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] lsu_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] lsu_issue_instr_i,
    input  wire lsu_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] lsu_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] lsu_wdata_i,
    input  wire lsu_fp_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] lsu_fp_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] lsu_fp_wdata_i,

    input  wire mul_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] mul_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] mul_issue_instr_i,
    input  wire mul_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] mul_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] mul_wdata_i
    ,input wire fpu_issue_valid_i
    ,input wire [INST_ADDR_WIDTH-1:0] fpu_issue_pc_i
    ,input wire [INST_DATA_WIDTH-1:0] fpu_issue_instr_i
    ,input wire fpu_valid_i
    ,input wire fpu_result_fpr_i
    ,input wire [REGS_ADDR_WIDTH-1:0] fpu_waddr_i
    ,input wire [REGS_DATA_WIDTH-1:0] fpu_wdata_i
    ,input ydrasil_commit_pkt_t retire_i
    ,input wire [INST_DATA_WIDTH-1:0] retire_instr_i
    ,input ydrasil_commit_pkt_t retire1_i
    ,input wire [INST_DATA_WIDTH-1:0] retire1_instr_i
);

    localparam [1:0] COMMIT_ALU = 2'd0;
    localparam [1:0] COMMIT_LSU = 2'd1;
    localparam [1:0] COMMIT_MUL = 2'd2;
    localparam [1:0] COMMIT_DIV = 2'd3;

    reg [1:0]                 commit_kind_q  [0:FIFO_DEPTH-1];
    reg [INST_ADDR_WIDTH-1:0] commit_pc_q    [0:FIFO_DEPTH-1];
    reg [INST_DATA_WIDTH-1:0] commit_instr_q [0:FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] commit_waddr_q [0:FIFO_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] commit_wdata_q [0:FIFO_DEPTH-1];
    reg                       commit_ready_q [0:FIFO_DEPTH-1];
    reg                       commit_is_fpr_q[0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0]  commit_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0]  commit_wptr_q;

    reg [FIFO_PTR_WIDTH-1:0] lsu_commit_idx_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0] lsu_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0] lsu_wptr_q;

    reg [FIFO_PTR_WIDTH-1:0] mul_commit_idx_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0] mul_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0] mul_wptr_q;
    reg [FIFO_PTR_WIDTH-1:0] fpu_commit_idx_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0] fpu_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0] fpu_wptr_q;
    reg [FIFO_PTR_WIDTH-1:0] div_commit_idx_q;
    reg                      div_pending_q;
    reg                      div_active_seen_q;
    bit trace_en;

    // DIV is completed through the ALU writeback path and has no public trace
    // issue port. Observe it here so the verification-only commit FIFO still
    // represents architectural order.
    wire div_active = $root.ydrasil_core_tb.u_dut.u_ydrasil_ex_block.div_active_q;
    wire div_result_valid =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_ex_block.alu_rf_wen_rd_ff;
    wire [REGS_ADDR_WIDTH-1:0] div_waddr =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_ex_block.alu_rf_waddr_rd_ff;
    wire [REGS_DATA_WIDTH-1:0] div_wdata =
        $root.ydrasil_core_tb.u_dut.u_ydrasil_ex_block.alu_result_ff;
    wire [INST_ADDR_WIDTH-1:0] div_issue_pc =
        $root.ydrasil_core_tb.u_dut.id_instr_addr;
    wire [INST_DATA_WIDTH-1:0] div_issue_instr =
        $root.ydrasil_core_tb.u_dut.commit_mul_instr;

    initial begin
        trace_en = $test$plusargs("commit_trace");
    end

    task automatic print_register_commit;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        input is_fpr;
        begin
            if (trace_en && (is_fpr || (waddr != '0))) begin
                $display("core   0: 0x%08h (0x%08h) unknown", pc, instr);
                if (is_fpr)
                    $display("3 0x%08h (0x%08h) f%0d 0x%08h", pc, instr, waddr, wdata);
                else
                    $display("3 0x%08h (0x%08h) x%0d 0x%08h", pc, instr, waddr, wdata);
            end
        end
    endtask

    always @(negedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            commit_rptr_q = '0;
            commit_wptr_q = '0;
            lsu_rptr_q = '0;
            lsu_wptr_q = '0;
            mul_rptr_q = '0;
            mul_wptr_q = '0;
            fpu_rptr_q = '0;
            fpu_wptr_q = '0;
            div_commit_idx_q = '0;
            div_pending_q = 1'b0;
            div_active_seen_q = 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                commit_kind_q[i] = '0;
                commit_pc_q[i] = '0;
                commit_instr_q[i] = '0;
                commit_waddr_q[i] = '0;
                commit_wdata_q[i] = '0;
                commit_ready_q[i] = 1'b0;
                commit_is_fpr_q[i] = 1'b0;
                lsu_commit_idx_q[i] = '0;
                mul_commit_idx_q[i] = '0;
                fpu_commit_idx_q[i] = '0;
            end
        end else if (1'b0) begin
            if (alu_valid_i &&
                !(div_pending_q && div_active_seen_q && !div_active && div_result_valid)) begin
                commit_kind_q[commit_wptr_q] = COMMIT_ALU;
                commit_pc_q[commit_wptr_q] = alu_pc_i;
                commit_instr_q[commit_wptr_q] = alu_instr_i;
                commit_waddr_q[commit_wptr_q] = alu_waddr_i;
                commit_wdata_q[commit_wptr_q] = alu_wdata_i;
                commit_ready_q[commit_wptr_q] = 1'b1;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (dual_alu_valid_i) begin
                commit_kind_q[commit_wptr_q] = COMMIT_ALU;
                commit_pc_q[commit_wptr_q] = dual_alu_pc_i;
                commit_instr_q[commit_wptr_q] = dual_alu_instr_i;
                commit_waddr_q[commit_wptr_q] = dual_alu_waddr_i;
                commit_wdata_q[commit_wptr_q] = dual_alu_wdata_i;
                commit_ready_q[commit_wptr_q] = 1'b1;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (dual_lsu_issue_valid_i) begin
                commit_kind_q[commit_wptr_q] = COMMIT_LSU;
                commit_pc_q[commit_wptr_q] = dual_lsu_issue_pc_i;
                commit_instr_q[commit_wptr_q] = dual_lsu_issue_instr_i;
                commit_waddr_q[commit_wptr_q] = '0;
                commit_wdata_q[commit_wptr_q] = '0;
                commit_ready_q[commit_wptr_q] = 1'b0;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                lsu_commit_idx_q[lsu_wptr_q] = commit_wptr_q;
                lsu_wptr_q = lsu_wptr_q + FIFO_PTR_WIDTH'(1);
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (lsu_issue_valid_i) begin
                commit_kind_q[commit_wptr_q] = COMMIT_LSU;
                commit_pc_q[commit_wptr_q] = lsu_issue_pc_i;
                commit_instr_q[commit_wptr_q] = lsu_issue_instr_i;
                commit_waddr_q[commit_wptr_q] = '0;
                commit_wdata_q[commit_wptr_q] = '0;
                commit_ready_q[commit_wptr_q] = 1'b0;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                lsu_commit_idx_q[lsu_wptr_q] = commit_wptr_q;
                lsu_wptr_q = lsu_wptr_q + FIFO_PTR_WIDTH'(1);
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (mul_issue_valid_i) begin
                commit_kind_q[commit_wptr_q] = COMMIT_MUL;
                commit_pc_q[commit_wptr_q] = mul_issue_pc_i;
                commit_instr_q[commit_wptr_q] = mul_issue_instr_i;
                commit_waddr_q[commit_wptr_q] = '0;
                commit_wdata_q[commit_wptr_q] = '0;
                commit_ready_q[commit_wptr_q] = 1'b0;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                mul_commit_idx_q[mul_wptr_q] = commit_wptr_q;
                mul_wptr_q = mul_wptr_q + FIFO_PTR_WIDTH'(1);
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (fpu_issue_valid_i) begin
                commit_kind_q[commit_wptr_q] = COMMIT_MUL;
                commit_pc_q[commit_wptr_q] = fpu_issue_pc_i;
                commit_instr_q[commit_wptr_q] = fpu_issue_instr_i;
                commit_waddr_q[commit_wptr_q] = '0;
                commit_wdata_q[commit_wptr_q] = '0;
                commit_ready_q[commit_wptr_q] = 1'b0;
                commit_is_fpr_q[commit_wptr_q] = 1'b0;
                fpu_commit_idx_q[fpu_wptr_q] = commit_wptr_q;
                fpu_wptr_q = fpu_wptr_q + FIFO_PTR_WIDTH'(1);
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (div_active && !div_active_seen_q) begin
                commit_kind_q[commit_wptr_q] = COMMIT_DIV;
                commit_pc_q[commit_wptr_q] = div_issue_pc;
                commit_instr_q[commit_wptr_q] = div_issue_instr;
                commit_waddr_q[commit_wptr_q] = '0;
                commit_wdata_q[commit_wptr_q] = '0;
                commit_ready_q[commit_wptr_q] = 1'b0;
                div_commit_idx_q = commit_wptr_q;
                div_pending_q = 1'b1;
                commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (mul_valid_i) begin
                commit_waddr_q[mul_commit_idx_q[mul_rptr_q]] = mul_waddr_i;
                commit_wdata_q[mul_commit_idx_q[mul_rptr_q]] = mul_wdata_i;
                commit_ready_q[mul_commit_idx_q[mul_rptr_q]] = 1'b1;
                mul_rptr_q = mul_rptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (fpu_valid_i) begin
                commit_waddr_q[fpu_commit_idx_q[fpu_rptr_q]] = fpu_waddr_i;
                commit_wdata_q[fpu_commit_idx_q[fpu_rptr_q]] = fpu_wdata_i;
                commit_is_fpr_q[fpu_commit_idx_q[fpu_rptr_q]] = fpu_result_fpr_i;
                commit_ready_q[fpu_commit_idx_q[fpu_rptr_q]] = 1'b1;
                fpu_rptr_q = fpu_rptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (lsu_valid_i || lsu_fp_valid_i) begin
                commit_waddr_q[lsu_commit_idx_q[lsu_rptr_q]] =
                    lsu_fp_valid_i ? lsu_fp_waddr_i : lsu_waddr_i;
                commit_wdata_q[lsu_commit_idx_q[lsu_rptr_q]] =
                    lsu_fp_valid_i ? lsu_fp_wdata_i : lsu_wdata_i;
                commit_is_fpr_q[lsu_commit_idx_q[lsu_rptr_q]] = lsu_fp_valid_i;
                commit_ready_q[lsu_commit_idx_q[lsu_rptr_q]] = 1'b1;
                lsu_rptr_q = lsu_rptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (div_pending_q && div_active_seen_q && !div_active) begin
                commit_waddr_q[div_commit_idx_q] = div_result_valid ? div_waddr : '0;
                commit_wdata_q[div_commit_idx_q] = div_wdata;
                commit_ready_q[div_commit_idx_q] = 1'b1;
                div_pending_q = 1'b0;
            end

            div_active_seen_q = div_active;

            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                if ((commit_rptr_q != commit_wptr_q) && commit_ready_q[commit_rptr_q]) begin
                    print_register_commit(commit_pc_q[commit_rptr_q], commit_instr_q[commit_rptr_q],
                                          commit_waddr_q[commit_rptr_q], commit_wdata_q[commit_rptr_q],
                                          commit_is_fpr_q[commit_rptr_q]);
                    commit_ready_q[commit_rptr_q] = 1'b0;
                    commit_rptr_q = commit_rptr_q + FIFO_PTR_WIDTH'(1);
                end
            end
        end
    end

    // Architectural trace follows the retirement ROB. The legacy issue FIFO
    // above cannot stay aligned when an execution result moves across a stage
    // boundary, and it also observes instructions later removed by a redirect.
    always @(posedge clk) begin
        if (rst_n) begin
            if (retire_i.valid && retire_i.writes_gpr)
                print_register_commit(retire_i.pc, retire_instr_i,
                    retire_i.rd_addr, retire_i.value, 1'b0);
            if (retire1_i.valid && retire1_i.writes_gpr)
                print_register_commit(retire1_i.pc, retire1_instr_i,
                    retire1_i.rd_addr, retire1_i.value, 1'b0);
        end
    end

endmodule
