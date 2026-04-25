`include "config.svh"
module ctrl (

    input wire rst_n,

    // from ex
    input wire                        jump_flag_i,
    input wire [`INST_ADDR_WIDTH-1:0] jump_addr_i,
    input wire                        hold_flag_ex_i,

    // from mems arbiter
    input wire hold_flag_mems_i,

    // from clint
    input wire hold_flag_clint_i,

    output wire [`HOLD_BUS_WIDTH-1:0] hold_flag_o,

    // to pc_reg
    output wire                        jump_flag_o,
    output wire [`INST_ADDR_WIDTH-1:0] jump_addr_o

);

    assign jump_addr_o = jump_addr_i;
    assign jump_flag_o = jump_flag_i;

    assign hold_flag_o = (jump_flag_i || hold_flag_ex_i  || hold_flag_clint_i ) ? `Hold_Id :
                         (hold_flag_mems_i ) ? `Hold_Pc :
                         `Hold_None;

endmodule