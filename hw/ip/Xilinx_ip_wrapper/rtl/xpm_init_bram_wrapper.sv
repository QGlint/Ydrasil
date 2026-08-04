module xpm_init_bram_wrapper #(
    parameter int DEPTH = 32768,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter MEMORY_INIT_FILE = "none",
    parameter bit USE_MEM_INIT = 1'b1,
    parameter bit USE_MEM_INIT_MMI = 1'b0
) (
    input  wire                  clk,
    input  wire                  ena_i,
    input  wire [ADDR_WIDTH-1:0] addra_i,
    output wire [DATA_WIDTH-1:0] douta_o,
    input  wire                  enb_i,
    input  wire [ADDR_WIDTH-1:0] addrb_i,
    output wire [DATA_WIDTH-1:0] doutb_o
);
    xpm_tpdram_wrapper #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .ADDR_WIDTH_B(ADDR_WIDTH),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .MEMORY_PRIMITIVE("block"),
        .WRITE_MODE_A("read_first"),
        .WRITE_MODE_B("read_first"),
        .MEMORY_INIT_FILE(MEMORY_INIT_FILE),
        .USE_MEM_INIT(USE_MEM_INIT),
        .USE_MEM_INIT_MMI(USE_MEM_INIT_MMI)
    ) u_bram (
        .clk(clk),
        .ena_i(ena_i),
        .addra_i(addra_i),
        .dina_i('0),
        .wea_i('0),
        .douta_o(douta_o),
        .enb_i(enb_i),
        .addrb_i(addrb_i),
        .dinb_i('0),
        .web_i('0),
        .doutb_o(doutb_o)
    );
endmodule
