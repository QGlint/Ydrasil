module ydrasil_1r1w_ram #(
    parameter int DEPTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int READ_LATENCY = 1,
    parameter logic [DATA_WIDTH-1:0] INIT_VALUE = '0
) (
    input  wire                   clk,
    input  wire                   ren_i,
    input  wire [ADDR_WIDTH-1:0]  raddr_i,
    output wire [DATA_WIDTH-1:0]  rdata_o,
    input  wire                   wen_i,
    input  wire [ADDR_WIDTH-1:0]  waddr_i,
    input  wire [DATA_WIDTH-1:0]  wdata_i
);
`ifdef TARGET_XILINX
    xpm_sdpram_wrapper #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_LATENCY(READ_LATENCY),
        .BYTE_WRITE_WIDTH(DATA_WIDTH),
        .WRITE_ENABLE_WIDTH(1),
        .MEMORY_PRIMITIVE("distributed"),
        .USE_MEM_INIT(1'b1),
        .MEMORY_SIZE(DEPTH * DATA_WIDTH)
    ) u_ram (
        .clk(clk),
        .ren_i(ren_i),
        .raddr_i(raddr_i),
        .rdata_o(rdata_o),
        .wen_i(wen_i),
        .waddr_i(waddr_i),
        .wdata_i(wdata_i),
        .wstrb_i(wen_i)
    );
`else
    ydrasil_sim_1r1w_ram #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_LATENCY(READ_LATENCY),
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
