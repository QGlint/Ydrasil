
module dtcm
import ydrasil_pkg::*;
(
    input wire                  clk,
    input wire                  dtcm_en,
    input wire                  dtcm_wen,
    input wire [3:0]            dtcm_mask,
    input wire [ydrasil_pkg::DTCM_ADDR_WIDTH-1:0]           dtcm_addr,
    input wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]           dtcm_data_i,
    output wire [ydrasil_pkg::BUS_DATA_WIDTH-1:0]          dtcm_data_o
);

    ydrmem_ram #(
        .ADDR_WIDTH(ydrasil_pkg::DTCM_ADDR_WIDTH),
        .DATA_WIDTH(ydrasil_pkg::BUS_DATA_WIDTH)
    ) u_dram (
        .clk(clk),
        .en_i(dtcm_en),
        .we_i(dtcm_wen),
        .we_mask_i(dtcm_mask),
        .addr_i(dtcm_addr),
        .data_i(dtcm_data_i),
        .data_o(dtcm_data_o)
    );

endmodule