module ydrasil_itcm #(
    parameter int ITCM_ADDR_WIDTH = 15,
    parameter int INST_DATA_WIDTH = 32,
    parameter string INIT_FILE = "none",
    parameter bit INIT_ENABLE = 1'b0,
    parameter bit ENABLE_XPM_MMI =
`ifdef YDRASIL_XPM_MMI
        1'b1
`else
        1'b0
`endif
) (
    input  wire                       clk,
    input  wire                       itcm_en,
    input  wire [ITCM_ADDR_WIDTH-1:0] itcm_addr,
    output wire [INST_DATA_WIDTH-1:0] itcm_data_o,
    input  wire                       itcm_en1,
    input  wire [ITCM_ADDR_WIDTH-1:0] itcm_addr1,
    output wire [INST_DATA_WIDTH-1:0] itcm_data1_o
);
`ifdef TARGET_XILINX
    xpm_tpdram_wrapper #(
        .DEPTH(1 << ITCM_ADDR_WIDTH),
        .DATA_WIDTH(INST_DATA_WIDTH),
        .ADDR_WIDTH_A(ITCM_ADDR_WIDTH),
        .ADDR_WIDTH_B(ITCM_ADDR_WIDTH),
        .MEMORY_INIT_FILE(INIT_FILE),
        .USE_MEM_INIT(INIT_ENABLE),
        .USE_MEM_INIT_MMI(ENABLE_XPM_MMI),
        .MEMORY_OPTIMIZATION("false")
    ) u_impl (
`else
    ydrasil_sim_tpdram #(
        .DEPTH(1 << ITCM_ADDR_WIDTH),
        .DATA_WIDTH(INST_DATA_WIDTH),
        .ADDR_WIDTH(ITCM_ADDR_WIDTH),
        .INIT_FILE(INIT_FILE),
        .INIT_ENABLE(INIT_ENABLE)
    ) u_impl (
`endif
        .clk(clk),
        .ena_i(itcm_en),
        .addra_i(itcm_addr),
        .dina_i('0),
        .wea_i('0),
        .douta_o(itcm_data_o),
        .enb_i(itcm_en1),
        .addrb_i(itcm_addr1),
        .dinb_i('0),
        .web_i('0),
        .doutb_o(itcm_data1_o)
    );
endmodule
