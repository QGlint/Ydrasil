module ydrasil_1r1w_bram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter logic [DATA_WIDTH-1:0] INIT_VALUE = '0
) (
    input  wire                  clk,
    input  wire                  ren_i,
    input  wire [ADDR_WIDTH-1:0] raddr_i,
    output wire [DATA_WIDTH-1:0] rdata_o,
    input  wire                  wen_i,
    input  wire [ADDR_WIDTH-1:0] waddr_i,
    input  wire [DATA_WIDTH-1:0] wdata_i
);
`ifdef TARGET_XILINX
    wire [DATA_WIDTH-1:0] wport_rdata_unused;

    xpm_tpdram_wrapper #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .ADDR_WIDTH_B(ADDR_WIDTH),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .MEMORY_PRIMITIVE("block"),
        .WRITE_MODE_A("no_change"),
        .WRITE_MODE_B("no_change"),
        .USE_MEM_INIT(1'b1),
        .USE_MEM_INIT_MMI(1'b0)
    ) u_ram (
        .clk(clk),
        .ena_i(ren_i),
        .addra_i(raddr_i),
        .dina_i('0),
        .wea_i('0),
        .douta_o(rdata_o),
        .enb_i(wen_i),
        .addrb_i(waddr_i),
        .dinb_i(wdata_i),
        .web_i({(DATA_WIDTH / 8){wen_i}}),
        .doutb_o(wport_rdata_unused)
    );
`else
    ydrasil_sim_1r1w_bram #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_VALUE(INIT_VALUE)
    ) u_ram (
        .clk(clk),
        .ren_i(ren_i),
        .raddr_i(raddr_i),
        .rdata_o(rdata_o),
        .wen_i(wen_i),
        .waddr_i(waddr_i),
        .wdata_i(wdata_i)
    );
`endif
endmodule
