
module itcm(
    input wire                  clk,
    input wire                  itcm_en,
    input wire [15:0]           itcm_addr,
    output wire [31:0]          itcm_data_o
);


IROM u_IROM (
  .clka(clk),    // input wire clka
  .ena(itcm_en),      // input wire ena
  .addra(itcm_addr),  // input wire [12 : 0] addra
  .douta(itcm_data_o)  // output wire [31 : 0] douta
);

endmodule