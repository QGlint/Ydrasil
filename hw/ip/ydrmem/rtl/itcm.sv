`include "define_mem_reg.svh"

module itcm(
    input wire                  clk,
    input wire                  itcm_en,
    input wire [`ITCM_ADDR_WIDTH-1:0]           itcm_addr,
    output wire [`INST_DATA_WIDTH-1:0]          itcm_data_o
);

    ydrmem_ram #(
        .ADDR_WIDTH(`ITCM_ADDR_WIDTH),
        .DATA_WIDTH(`INST_DATA_WIDTH)
    ) u_irom (
        .clk(clk),
        .en_i(itcm_en),
        .we_i(1'b0),
        .we_mask_i(4'b0),
        .addr_i(itcm_addr),
        .data_i(`INST_DATA_WIDTH'b0),
        .data_o(itcm_data_o)
    );

endmodule
