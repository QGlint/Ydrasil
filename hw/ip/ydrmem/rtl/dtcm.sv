
module dtcm #(
    parameter int DTCM_ADDR_WIDTH = 16,
    parameter int BUS_DATA_WIDTH  = 32
) (
    input wire                  clk,
    input wire                  dtcm_ren,
    input wire                  dtcm_wen,
    input wire [3:0]            dtcm_mask,
    input wire [DTCM_ADDR_WIDTH-1:0]           dtcm_raddr,
    input wire [DTCM_ADDR_WIDTH-1:0]           dtcm_waddr,
    input wire [BUS_DATA_WIDTH-1:0]           dtcm_data_i,
    output wire [BUS_DATA_WIDTH-1:0]          dtcm_data_o
);

    ydrmem_ram #(
        .ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .DATA_WIDTH(BUS_DATA_WIDTH)
    ) u_dram (
        .clk(clk),
        .ren_i(dtcm_ren),
        .wen_i(dtcm_wen),
        .we_mask_i(dtcm_mask),
        .raddr_i(dtcm_raddr),
        .waddr_i(dtcm_waddr),
        .data_i(dtcm_data_i),
        .data_o(dtcm_data_o)
    );

endmodule
