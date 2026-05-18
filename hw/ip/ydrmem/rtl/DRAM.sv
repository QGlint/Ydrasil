`include "define_mem_reg.svh"

module DRAM(
    input wire [15:0] addr_i,
    output wire [31:0] data_o
);

    ydrmem_rom #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(32)
    ) u_rom (
        .addr_i(addr_i),
        .data_o(data_o)
    );

endmodule