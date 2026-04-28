`include "define_mem_reg.svh"
module ydrasil_ctrl (

    input wire rst_n,

    // from ex
    input wire                          ex_branch_jump_i,
    input wire [`INST_ADDR_WIDTH-1:0]   ex_branch_target_i,
    
    input wire                           lsu_ctrl_stall_i, // LSU 可能会因为等待内存响应而请求stall
    input wire                           lsu_ctrl_stall_wb_i, // LSU 可能会因为异常等原因
    input wire [`REGS_ADDR_WIDTH-1:0]    lsu_ctrl_waddr_rd_i,
    input wire [`REGS_ADDR_WIDTH-1:0]    lsu_ctrl_waddr_rd_wb_i,

    input wire [`REGS_ADDR_WIDTH-1:0]    id_ctrl_rs1_addr_i,
    input wire [`REGS_ADDR_WIDTH-1:0]    id_ctrl_rs2_addr_i,

    input wire                          clint_stall_i,

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
    output wire [`INST_ADDR_WIDTH-1:0]  branch_target_o

);

    wire lsu_stall_rs_rd;
    wire lsu_stall_rs_rd_wb;

    wire lsu_stall ;
    assign lsu_stall = lsu_ctrl_stall_i | lsu_ctrl_stall_wb_i;

    assign branch_target_o = ex_branch_target_i;
    assign branch_jump_o = ex_branch_jump_i;

    assign flush_id_o = branch_jump_o | lsu_stall | clint_stall_i;
    assign flush_if_o = branch_jump_o ;
    assign flush_ex_o = 1'b0; 
    // assign flush_mems_o = 1'b0;
    assign lsu_stall_rs_rd = ((id_ctrl_rs1_addr_i == lsu_ctrl_waddr_rd_i) || (id_ctrl_rs2_addr_i == lsu_ctrl_waddr_rd_i)) && lsu_ctrl_stall_i;
    assign lsu_stall_rs_rd_wb = ((id_ctrl_rs1_addr_i == lsu_ctrl_waddr_rd_wb_i) || (id_ctrl_rs2_addr_i == lsu_ctrl_waddr_rd_wb_i)) && lsu_ctrl_stall_wb_i;

    // assign stall_ex_o = clint_stall_i;
    assign stall_id_o = 1'b0; 
    assign stall_if_o = lsu_stall | clint_stall_i;
    assign stall_pc_o = lsu_stall | clint_stall_i;


endmodule
