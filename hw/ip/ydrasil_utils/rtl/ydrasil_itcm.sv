module ydrasil_itcm #(
    parameter int ITCM_ADDR_WIDTH = 15,
    parameter int INST_DATA_WIDTH = 32,
    parameter string INIT_FILE = "none",
    parameter bit INIT_ENABLE = 1'b0
) (
    input  wire                              clk,
    input  wire                              itcm_en,
    input  wire [ITCM_ADDR_WIDTH-2:0]        itcm_addr,
    output wire [(2*INST_DATA_WIDTH)-1:0]    itcm_data_o
);
`ifdef TARGET_XILINX
    xpm_sdpram_wrapper #(
        .DEPTH(1 << (ITCM_ADDR_WIDTH - 1)),
        .DATA_WIDTH(2 * INST_DATA_WIDTH),
        .ADDR_WIDTH(ITCM_ADDR_WIDTH - 1),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_INIT_FILE(INIT_FILE),
        .USE_MEM_INIT(INIT_ENABLE),
        .USE_MEM_INIT_MMI(1'b1),
        .MEMORY_OPTIMIZATION("false")
    ) u_impl (
`else
    ydrasil_sim_sdpram #(
        .DEPTH(1 << (ITCM_ADDR_WIDTH - 1)),
        .DATA_WIDTH(2 * INST_DATA_WIDTH),
        .ADDR_WIDTH(ITCM_ADDR_WIDTH - 1),
        .INIT_FILE(INIT_FILE),
        .INIT_ENABLE(INIT_ENABLE)
    ) u_impl (
`endif
        .clk(clk),
        .ren_i(itcm_en),
        .raddr_i(itcm_addr),
        .rdata_o(itcm_data_o),
        .wen_i(1'b0),
        .waddr_i('0),
        .wdata_i('0),
        .wstrb_i('0)
    );
endmodule
