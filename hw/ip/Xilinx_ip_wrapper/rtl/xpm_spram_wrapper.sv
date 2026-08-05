module xpm_spram_wrapper #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int READ_LATENCY = 1,
    parameter int BYTE_WRITE_WIDTH = 8,
    parameter int WRITE_ENABLE_WIDTH = DATA_WIDTH / BYTE_WRITE_WIDTH,
    parameter MEMORY_PRIMITIVE = "block",
    parameter WRITE_MODE = "read_first",
    parameter MEMORY_INIT_FILE = "none",
    parameter bit USE_MEM_INIT = 1'b0,
    parameter bit USE_MEM_INIT_MMI = 1'b0,
    parameter MEMORY_OPTIMIZATION = "true",
    parameter int MEMORY_SIZE = DEPTH * DATA_WIDTH
) (
    input  wire                          clk,
    input  wire                          en_i,
    input  wire [ADDR_WIDTH-1:0]         addr_i,
    output wire [DATA_WIDTH-1:0]         rdata_o,
    input  wire [DATA_WIDTH-1:0]         wdata_i,
    input  wire [WRITE_ENABLE_WIDTH-1:0] wstrb_i
);
    wire dbiterr_unused;
    wire sbiterr_unused;

    xpm_memory_spram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(BYTE_WRITE_WIDTH),
        .CASCADE_HEIGHT(0),
        .ECC_BIT_RANGE("7:0"),
        .ECC_MODE("no_ecc"),
        .ECC_TYPE("none"),
        .IGNORE_INIT_SYNTH(0),
        .MEMORY_INIT_FILE(MEMORY_INIT_FILE),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION(MEMORY_OPTIMIZATION),
        .MEMORY_PRIMITIVE(MEMORY_PRIMITIVE),
        .MEMORY_SIZE(MEMORY_SIZE),
        .MESSAGE_CONTROL(0),
        .RAM_DECOMP("auto"),
        .READ_DATA_WIDTH_A(DATA_WIDTH),
        .READ_LATENCY_A(READ_LATENCY),
        .READ_RESET_VALUE_A("0"),
        .RST_MODE_A("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_MEM_INIT(USE_MEM_INIT),
        .USE_MEM_INIT_MMI(USE_MEM_INIT_MMI),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        .WRITE_MODE_A(WRITE_MODE),
        .WRITE_PROTECT(1)
    ) u_xpm_memory_spram (
        .dbiterra(dbiterr_unused),
        .douta(rdata_o),
        .sbiterra(sbiterr_unused),
        .addra(addr_i),
        .clka(clk),
        .dina(wdata_i),
        .ena(en_i),
        .injectdbiterra(1'b0),
        .injectsbiterra(1'b0),
        .regcea(1'b1),
        .rsta(1'b0),
        .sleep(1'b0),
        .wea(wstrb_i)
    );
endmodule
