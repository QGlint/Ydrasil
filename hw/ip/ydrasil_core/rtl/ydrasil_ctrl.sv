
module ydrasil_ctrl 
import ydrasil_pkg::*;
(

    input wire rst_n,

    // from ex
    input wire                          ex_branch_jump_i,
    input wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    
    input wire                          scoreboard_stall_i,
    input wire                          lsu_struct_stall_i,
    input wire                          id_frontend_stall_i,
    input wire                          clint_stall_i,
    input wire                          ex_mul_stall_i,
    input wire                          wb_backpressure_i,

    output wire                         stall_if_o,
    output wire                         stall_id_o,
    output wire                         stall_pc_o,
    // output wire                         stall_ex_o,
    // flush
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    // output wire                         flush_mems_o, --- IGNORE ---
    //跳转
    output wire                         branch_jump_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0]  branch_target_o

);

    wire decode_bubble_stall;
    assign decode_bubble_stall =
        scoreboard_stall_i | lsu_struct_stall_i | id_frontend_stall_i |
        clint_stall_i | wb_backpressure_i;

    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;

    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o ;
    assign flush_ex_o = branch_jump_o;
    // assign flush_mems_o = 1'b0;
    // assign stall_ex_o = clint_stall_i;
    assign stall_id_o = ex_mul_stall_i;
    assign stall_if_o = decode_bubble_stall | ex_mul_stall_i;
    assign stall_pc_o = decode_bubble_stall | ex_mul_stall_i;


endmodule
