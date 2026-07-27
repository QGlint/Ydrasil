
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

wire [BUS_DATA_WIDTH-1:0] store_rdata_unused;
tpdram_wrapper #(
  .DEPTH(1 << DTCM_ADDR_WIDTH),
  .DATA_WIDTH(BUS_DATA_WIDTH),
  .ADDR_WIDTH_A(DTCM_ADDR_WIDTH),
  .ADDR_WIDTH_B(DTCM_ADDR_WIDTH),
  .READ_LATENCY_A(1),
  .READ_LATENCY_B(1),
  .MEMORY_PRIMITIVE("block"),
  .WRITE_MODE_A("no_change"),
  .WRITE_MODE_B("no_change")
) u_dram (
  .clk(clk),
  .ena_i(dtcm_ren), .addra_i(dtcm_raddr), .dina_i('0), .wea_i('0),
  .douta_o(dtcm_data_o),
  .enb_i(dtcm_wen), .addrb_i(dtcm_waddr), .dinb_i(dtcm_data_i),
  .web_i(dtcm_mask), .doutb_o(store_rdata_unused)
);

endmodule
