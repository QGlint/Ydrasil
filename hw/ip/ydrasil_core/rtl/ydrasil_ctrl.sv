`include "define_mem_reg.svh"
module ydrasil_ctrl (

    input logic rst_n,

    // from ex
    input logic                          ex_branch_jump_i,
    input logic [`INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    // input logic                          stall_ex_i,
    // input logic                          stall_mems_i,
    output logic                         stall_if_o,
    output logic                         stall_id_o,
    // flush
    output logic                         flush_if_o,
    output logic                         flush_id_o,
    output logic                         flush_ex_o,
    // output logic                         flush_mems_o, --- IGNORE ---
    //跳转
    output logic                         branch_jump_o,
    output logic [`INST_ADDR_WIDTH-1:0]  branch_target_o

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
