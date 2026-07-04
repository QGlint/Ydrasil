`timescale 1ns/1ns

module ydrasil_commit_trace
import ydrasil_pkg::*;
#(
    parameter int FIFO_DEPTH = 256,
    parameter int FIFO_PTR_WIDTH = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire flush_i,

    input  wire alloc_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] alloc_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] alloc_instr_i,

    input  wire alu_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] alu_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] alu_instr_i,
    input  wire [REGS_ADDR_WIDTH-1:0] alu_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] alu_wdata_i,

    input  wire lsu_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] lsu_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] lsu_issue_instr_i,
    input  wire lsu_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] lsu_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] lsu_wdata_i,

    input  wire mul_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] mul_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] mul_issue_instr_i,
    input  wire mul_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] mul_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] mul_wdata_i,

    input  wire pipe1_issue_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0] pipe1_issue_pc_i,
    input  wire [INST_DATA_WIDTH-1:0] pipe1_issue_instr_i,
    input  wire pipe1_valid_i,
    input  wire [REGS_ADDR_WIDTH-1:0] pipe1_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0] pipe1_wdata_i
);

    reg [INST_ADDR_WIDTH-1:0] commit_pc_q    [0:FIFO_DEPTH-1];
    reg [INST_DATA_WIDTH-1:0] commit_instr_q [0:FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] commit_waddr_q [0:FIFO_DEPTH-1];
    reg [REGS_DATA_WIDTH-1:0] commit_wdata_q [0:FIFO_DEPTH-1];
    reg                       commit_ready_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0]  commit_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0]  commit_wptr_q;

    reg [INST_ADDR_WIDTH-1:0] lsu_pc_q    [0:FIFO_DEPTH-1];
    reg [INST_DATA_WIDTH-1:0] lsu_instr_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0]  lsu_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0]  lsu_wptr_q;

    reg [INST_ADDR_WIDTH-1:0] mul_pc_q    [0:FIFO_DEPTH-1];
    reg [INST_DATA_WIDTH-1:0] mul_instr_q [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0]  mul_rptr_q;
    reg [FIFO_PTR_WIDTH-1:0]  mul_wptr_q;

    task automatic print_gpr_commit;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        begin
            if (waddr != '0) begin
                $display("core   0: 0x%08h (0x%08h) unknown", pc, instr);
                $display("3 0x%08h (0x%08h) x%0d 0x%08h", pc, instr, waddr, wdata);
            end
        end
    endtask

    task automatic alloc_commit_entry;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        begin
            commit_pc_q[commit_wptr_q] = pc;
            commit_instr_q[commit_wptr_q] = instr;
            commit_waddr_q[commit_wptr_q] = '0;
            commit_wdata_q[commit_wptr_q] = '0;
            commit_ready_q[commit_wptr_q] = 1'b0;
            commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
        end
    endtask

    task automatic alloc_ready_entry;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        begin
            commit_pc_q[commit_wptr_q] = pc;
            commit_instr_q[commit_wptr_q] = instr;
            commit_waddr_q[commit_wptr_q] = waddr;
            commit_wdata_q[commit_wptr_q] = wdata;
            commit_ready_q[commit_wptr_q] = 1'b1;
            commit_wptr_q = commit_wptr_q + FIFO_PTR_WIDTH'(1);
        end
    endtask

    task automatic mark_matching_ready;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        output reg found;
        integer j;
        reg [FIFO_PTR_WIDTH-1:0] idx;
        begin
            found = 1'b0;
            for (j = 0; j < FIFO_DEPTH; j = j + 1) begin
                idx = commit_rptr_q + FIFO_PTR_WIDTH'(j);
                if (!found && (idx != commit_wptr_q) &&
                    !commit_ready_q[idx] &&
                    (commit_pc_q[idx] == pc) &&
                    (commit_instr_q[idx] == instr)) begin
                    commit_waddr_q[idx] = waddr;
                    commit_wdata_q[idx] = wdata;
                    commit_ready_q[idx] = 1'b1;
                    found = 1'b1;
                end
            end
        end
    endtask

    task automatic mark_or_alloc_ready;
        input [INST_ADDR_WIDTH-1:0] pc;
        input [INST_DATA_WIDTH-1:0] instr;
        input [REGS_ADDR_WIDTH-1:0] waddr;
        input [REGS_DATA_WIDTH-1:0] wdata;
        reg found;
        begin
            if (waddr != '0) begin
                mark_matching_ready(pc, instr, waddr, wdata, found);
                if (!found) begin
                    alloc_ready_entry(pc, instr, waddr, wdata);
                end
            end
        end
    endtask

    task automatic squash_not_ready;
        integer j;
        reg [FIFO_PTR_WIDTH-1:0] src;
        reg [FIFO_PTR_WIDTH-1:0] dst;
        begin
            dst = commit_rptr_q;
            for (j = 0; j < FIFO_DEPTH; j = j + 1) begin
                src = commit_rptr_q + FIFO_PTR_WIDTH'(j);
                if (src != commit_wptr_q) begin
                    if (commit_ready_q[src]) begin
                        if (dst != src) begin
                            commit_pc_q[dst] = commit_pc_q[src];
                            commit_instr_q[dst] = commit_instr_q[src];
                            commit_waddr_q[dst] = commit_waddr_q[src];
                            commit_wdata_q[dst] = commit_wdata_q[src];
                            commit_ready_q[dst] = commit_ready_q[src];
                            commit_ready_q[src] = 1'b0;
                        end
                        dst = dst + FIFO_PTR_WIDTH'(1);
                    end else begin
                        commit_ready_q[src] = 1'b0;
                    end
                end
            end
            commit_wptr_q = dst;
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
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                commit_pc_q[i] = '0;
                commit_instr_q[i] = '0;
                commit_waddr_q[i] = '0;
                commit_wdata_q[i] = '0;
                commit_ready_q[i] = 1'b0;
                lsu_pc_q[i] = '0;
                lsu_instr_q[i] = '0;
                mul_pc_q[i] = '0;
                mul_instr_q[i] = '0;
            end
        end else begin
            if (alloc_valid_i) begin
                alloc_commit_entry(alloc_pc_i, alloc_instr_i);
            end

            if (lsu_issue_valid_i) begin
                lsu_pc_q[lsu_wptr_q] = lsu_issue_pc_i;
                lsu_instr_q[lsu_wptr_q] = lsu_issue_instr_i;
                lsu_wptr_q = lsu_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (mul_issue_valid_i) begin
                mul_pc_q[mul_wptr_q] = mul_issue_pc_i;
                mul_instr_q[mul_wptr_q] = mul_issue_instr_i;
                mul_wptr_q = mul_wptr_q + FIFO_PTR_WIDTH'(1);
            end

            if (alu_valid_i) begin
                mark_or_alloc_ready(alu_pc_i, alu_instr_i, alu_waddr_i, alu_wdata_i);
            end

            if (mul_valid_i) begin
                if (mul_rptr_q != mul_wptr_q) begin
                    mark_or_alloc_ready(mul_pc_q[mul_rptr_q], mul_instr_q[mul_rptr_q],
                                        mul_waddr_i, mul_wdata_i);
                    mul_rptr_q = mul_rptr_q + FIFO_PTR_WIDTH'(1);
                end else begin
                    mark_or_alloc_ready('0, '0, mul_waddr_i, mul_wdata_i);
                end
            end

            if (lsu_valid_i) begin
                if (lsu_rptr_q != lsu_wptr_q) begin
                    mark_or_alloc_ready(lsu_pc_q[lsu_rptr_q], lsu_instr_q[lsu_rptr_q],
                                        lsu_waddr_i, lsu_wdata_i);
                    lsu_rptr_q = lsu_rptr_q + FIFO_PTR_WIDTH'(1);
                end else begin
                    mark_or_alloc_ready('0, '0, lsu_waddr_i, lsu_wdata_i);
                end
            end

            if (pipe1_valid_i) begin
                mark_or_alloc_ready(pipe1_issue_pc_i, pipe1_issue_instr_i,
                                    pipe1_waddr_i, pipe1_wdata_i);
            end

            if (flush_i) begin
                squash_not_ready();
            end

            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                if ((commit_rptr_q != commit_wptr_q) && commit_ready_q[commit_rptr_q]) begin
                    print_gpr_commit(commit_pc_q[commit_rptr_q], commit_instr_q[commit_rptr_q],
                                     commit_waddr_q[commit_rptr_q], commit_wdata_q[commit_rptr_q]);
                    commit_ready_q[commit_rptr_q] = 1'b0;
                    commit_rptr_q = commit_rptr_q + FIFO_PTR_WIDTH'(1);
                end
            end
        end
    end

endmodule
