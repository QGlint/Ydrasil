
module itcm
import ydrasil_pkg::*;
(
    input wire                  clk,
    input wire                  itcm_en,
    input wire [ydrasil_pkg::ITCM_ADDR_WIDTH-1:0]           itcm_addr,
    output wire [ydrasil_pkg::INST_DATA_WIDTH-1:0]          itcm_data_o
);

    ydrmem_ram #(
        .ADDR_WIDTH(ydrasil_pkg::ITCM_ADDR_WIDTH),
        .DATA_WIDTH(ydrasil_pkg::INST_DATA_WIDTH)
    ) u_irom (
        .clk(clk),
        .en_i(itcm_en),
        .we_i(1'b0),
        .we_mask_i(4'b0),
        .addr_i(itcm_addr),
        .data_i({ydrasil_pkg::INST_DATA_WIDTH{1'b0}}),
        .data_o(itcm_data_o)
    );

endmodule
