module ydrasil_dtcm #(
    parameter int DTCM_ADDR_WIDTH = 14,
    parameter int BUS_DATA_WIDTH = 32,
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
    input  wire                       dtcm_ren,
    input  wire                       dtcm_wen,
    input  wire [3:0]                 dtcm_mask,
    input  wire [DTCM_ADDR_WIDTH-1:0] dtcm_raddr,
    input  wire [DTCM_ADDR_WIDTH-1:0] dtcm_waddr,
    input  wire [BUS_DATA_WIDTH-1:0]  dtcm_data_i,
    output wire [BUS_DATA_WIDTH-1:0]  dtcm_data_o
);
`ifdef TARGET_XILINX
    xpm_sdpram_wrapper #(
        .DEPTH(1 << DTCM_ADDR_WIDTH),
        .DATA_WIDTH(BUS_DATA_WIDTH),
        .ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_INIT_FILE(INIT_FILE),
        .USE_MEM_INIT(INIT_ENABLE),
        .USE_MEM_INIT_MMI(ENABLE_XPM_MMI),
        .MEMORY_OPTIMIZATION("false")
    ) u_impl (
`else
    ydrasil_sim_sdpram #(
        .DEPTH(1 << DTCM_ADDR_WIDTH),
        .DATA_WIDTH(BUS_DATA_WIDTH),
        .ADDR_WIDTH(DTCM_ADDR_WIDTH),
        .INIT_FILE(INIT_FILE),
        .INIT_ENABLE(INIT_ENABLE)
    ) u_impl (
`endif
        .clk(clk),
        .ren_i(dtcm_ren),
        .raddr_i(dtcm_raddr),
        .rdata_o(dtcm_data_o),
        .wen_i(dtcm_wen),
        .waddr_i(dtcm_waddr),
        .wdata_i(dtcm_data_i),
        .wstrb_i(dtcm_mask)
    );
endmodule
