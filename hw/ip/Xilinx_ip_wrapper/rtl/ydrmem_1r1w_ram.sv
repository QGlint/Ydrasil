module ydrmem_1r1w_ram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    // Kept in the wrapper interface so the BRAM-backed synthesis model has
    // the same contract as the simulation RAM.  XPM memory contents are
    // supplied by the surrounding memory configuration in this path.
    parameter logic [DATA_WIDTH-1:0] INIT_VALUE = '0
) (
    input  wire                   clk,

    input  wire                   ren_i,
    input  wire [ADDR_WIDTH-1:0]  raddr_i,
    output logic [DATA_WIDTH-1:0] rdata_o,

    input  wire                   wen_i,
    input  wire [ADDR_WIDTH-1:0]  waddr_i,
    input  wire [DATA_WIDTH-1:0]  wdata_i
);

    wire [DATA_WIDTH-1:0] rdata;
    wire [DATA_WIDTH-1:0] wport_rdata_unused;

    assign rdata_o = rdata;

    tpdram_wrapper #(
        .DEPTH           (DEPTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH_A    (ADDR_WIDTH),
        .ADDR_WIDTH_B    (ADDR_WIDTH),
        .READ_LATENCY_A  (1),
        .READ_LATENCY_B  (1),
        // Predictor tables are synchronous and must map to BRAM on the
        // Vivado path.  "auto" may select distributed RAM for the small BHT
        // instances, putting a wide/fanout lookup back on the timing path.
        .MEMORY_PRIMITIVE("block"),
        .WRITE_MODE_A    ("no_change"),
        .WRITE_MODE_B    ("no_change")
    ) u_ram (
        .clk     (clk),

        .ena_i   (ren_i),
        .addra_i (raddr_i),
        .dina_i  ({DATA_WIDTH{1'b0}}),
        .wea_i   ('0),
        .douta_o (rdata),

        .enb_i   (wen_i),
        .addrb_i (waddr_i),
        .dinb_i  (wdata_i),
        .web_i   ({(DATA_WIDTH/8){wen_i}}),
        .doutb_o (wport_rdata_unused)
    );

endmodule
