
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

    ydrmem_ram2 #(
        .ADDR_WIDTH(ITCM_ADDR_WIDTH),
        .DATA_WIDTH(INST_DATA_WIDTH),
        .READ_MODE("READ_FIRST")
    ) u_irom (
        .clk(clk),
        .rst_n(itcm_en | itcm_en1),
        .addr_a(itcm_addr),
        .wdata_a('0),
        .we_a(1'b0),
        .rdata_a(itcm_data_o),
        .addr_b(itcm_addr1),
        .wdata_b('0),
        .we_b(1'b0),
        .rdata_b(itcm_data1_o)
    );

endmodule
