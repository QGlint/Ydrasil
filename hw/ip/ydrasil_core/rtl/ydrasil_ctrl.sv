module ydrasil_ctrl
import ydrasil_pkg::*;
(

    input wire rst_n,

    // from ex
    input wire                          ex_branch_jump_i,
    input wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]   ex_branch_target_i,

    input wire                          scoreboard_stall_i,
    input wire                          lsu_struct_stall_i,
    input wire                          clint_stall_i,
    input wire                          ex_mul_stall_i,
    input wire                          wb_backpressure_i,

    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         stall_rf_o,
    output wire                         stall_pc_o,

    // flush
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_rf_o,
    output wire                         flush_ex_o,

    output wire                         branch_jump_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]  branch_target_o

);

    wire decode_bubble_stall;
    assign decode_bubble_stall =
        scoreboard_stall_i | lsu_struct_stall_i | clint_stall_i | wb_backpressure_i;

    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;

    // 6-stage: flush IF, ID, and RF on branch redirect
    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_rf_o = branch_jump_o;
    assign flush_ex_o = branch_jump_o;

    // 6-stage stall chain: backpressure propagates EX -> RF -> ID -> IF
    assign stall_rf_o = decode_bubble_stall;
    assign stall_id_o = decode_bubble_stall;
    assign stall_if_o = decode_bubble_stall;
    assign stall_pc_o = decode_bubble_stall;

endmodule
