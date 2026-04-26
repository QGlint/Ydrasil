`include "define_mem_reg.svh"
module ydrasil_ctrl (

    input wire rst_n,

    // from ex
    input wire                          ex_branch_jump_i,
    input wire [`INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    // input wire                          stall_ex_i,
    // input wire                          stall_mems_i,
    output wire                         stall_if_o,
    output wire                         stall_id_o,
    // flush
    output wire                         flush_if_o,
    output wire                         flush_id_o,
    output wire                         flush_ex_o,
    // output wire                         flush_mems_o, --- IGNORE ---
    //跳转
    output wire                         branch_jump_o,
    output wire [`INST_ADDR_WIDTH-1:0]  branch_target_o

);

    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;

    assign flush_id_o = branch_jump_o;
    assign flush_if_o = branch_jump_o;
    assign flush_ex_o = 1'b0; 
    // assign flush_mems_o = 1'b0;
    
    assign stall_id_o = 1'b0;
    assign stall_if_o = 1'b0;
    // assign stall_ex_o = 1'b0;
    // assign stall_mems_o = 1'b0;


endmodule
