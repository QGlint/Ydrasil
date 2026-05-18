`include "define_mem_reg.svh"

module dtcm(
    input wire                  clk,
    input wire                  dtcm_en,
    input wire                  dtcm_wen,
    input wire [3:0]            dtcm_mask,
    input wire [`DTCM_ADDR_WIDTH-1:0]           dtcm_addr,
    input wire [`BUS_DATA_WIDTH-1:0]           dtcm_data_i,
    output wire [`BUS_DATA_WIDTH-1:0]          dtcm_data_o
);

DRAM u_dram (
  .clka(clk),    // input wire clka
  .ena(dtcm_en),      // input wire ena
  .wea(dtcm_mask),      // input wire [3 : 0] wea
  .addra(dtcm_addr),  // input wire [15 : 0] addra
  .dina(dtcm_data_i),    // input wire [31 : 0] dina
  .douta(dtcm_data_o)  // output wire [31 : 0] douta
);

endmodule
