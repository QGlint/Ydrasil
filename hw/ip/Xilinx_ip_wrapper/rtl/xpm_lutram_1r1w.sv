// One-read-port, one-write-port LUTRAM.
//
// Predictor and issue-side tables must not rely on inference attributes.  The
// Xilinx implementation explicitly selects distributed RAM and the non-Xilinx
// branch below is the simulation model for the same interface.
module xpm_lutram_1r1w #(
    parameter int DEPTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    // Zero keeps a combinational lookup in the caller's pipeline stage.
    // One is the default registered read used by queued tables.
    parameter int READ_LATENCY = 1,
    parameter logic [DATA_WIDTH-1:0] INIT_VALUE = '0
) (
    input  wire                  clk,
    input  wire                  ren_i,
    input  wire [ADDR_WIDTH-1:0] raddr_i,
    output logic [DATA_WIDTH-1:0] rdata_o,
    input  wire                  wen_i,
    input  wire [ADDR_WIDTH-1:0] waddr_i,
    input  wire [DATA_WIDTH-1:0] wdata_i
);

`ifdef TARGET_XILINX
    wire dbiterr_unused;
    wire sbiterr_unused;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .ADDR_WIDTH_B(ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_BIT_RANGE("7:0"),
        .ECC_MODE("no_ecc"),
        .ECC_TYPE("none"),
        .IGNORE_INIT_SYNTH(0),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("distributed"),
        .MEMORY_SIZE(DEPTH * DATA_WIDTH),
        .MESSAGE_CONTROL(0),
        .RAM_DECOMP("auto"),
        .READ_DATA_WIDTH_B(DATA_WIDTH),
        .READ_LATENCY_B(READ_LATENCY),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(1),
        .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        // Distributed simple-dual-port RAM supports read-first on the read
        // port. Read/write address collisions are architecturally excluded
        // from predictor lookup, so this preserves the external contract.
        .WRITE_MODE_B("read_first"),
        .WRITE_PROTECT(1)
    ) u_xpm_memory_sdpram (
        .dbiterrb(dbiterr_unused),
        .doutb(rdata_o),
        .sbiterrb(sbiterr_unused),
        .addra(waddr_i),
        .addrb(raddr_i),
        .clka(clk),
        .clkb(clk),
        .dina(wdata_i),
        .ena(wen_i),
        .enb(ren_i),
        .injectdbiterra(1'b0),
        .injectsbiterra(1'b0),
        .regceb(1'b1),
        .rstb(1'b0),
        .sleep(1'b0),
        .wea(wen_i)
    );
`else
    // Simulation model.  The write uses nonblocking assignment so a same-edge
    // registered read observes the previous value, matching read-first XPM
    // collision behaviour.
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
            mem[init_idx] = INIT_VALUE;
    end

    generate
        if (READ_LATENCY == 0) begin : g_comb_read
            always_comb begin
                if (ren_i)
                    rdata_o = mem[raddr_i];
                else
                    rdata_o = '0;
            end
        end else begin : g_registered_read
            always_ff @(posedge clk) begin
                if (ren_i)
                    rdata_o <= mem[raddr_i];
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (wen_i)
            mem[waddr_i] <= wdata_i;
    end
`endif

endmodule
