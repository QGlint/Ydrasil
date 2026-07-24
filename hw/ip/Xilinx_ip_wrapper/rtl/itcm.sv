
module itcm #(
    parameter int ITCM_ADDR_WIDTH  = 12,
    parameter int INST_DATA_WIDTH  = 32
) (
    input wire                  clk,
    input wire                  itcm_en,
    input wire [ITCM_ADDR_WIDTH-1:0]           itcm_addr,
    output wire [INST_DATA_WIDTH-1:0]          itcm_data_o,
    input wire                  itcm_en1,
    input wire [ITCM_ADDR_WIDTH-1:0]           itcm_addr1,
    output wire [INST_DATA_WIDTH-1:0]          itcm_data1_o
);

IROM u_IROM1 (
  .clka(clk),
  .ena(itcm_en1),
  .addra(itcm_addr1),
  .douta(itcm_data1_o)
);


IROM u_IROM (
  .clka(clk),    // input wire clka
  .ena(itcm_en),      // input wire ena
  .addra(itcm_addr),  // input wire [12 : 0] addra
  .douta(itcm_data_o)  // output wire [31 : 0] douta
);

endmodule
