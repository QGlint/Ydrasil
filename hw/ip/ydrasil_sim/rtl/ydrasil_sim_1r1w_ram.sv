module ydrasil_sim_1r1w_ram #(
    parameter int DEPTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int READ_LATENCY = 1,
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
    logic [DATA_WIDTH-1:0] mem_r [0:DEPTH-1];
    integer idx;

    initial begin
        for (idx = 0; idx < DEPTH; idx = idx + 1)
            mem_r[idx] = INIT_VALUE;
    end

    generate
        if (READ_LATENCY == 0) begin : g_comb_read
            always_comb rdata_o = ren_i ? mem_r[raddr_i] : '0;
        end else begin : g_sync_read
            always_ff @(posedge clk)
                if (ren_i)
                    rdata_o <= mem_r[raddr_i];
        end
    endgenerate

    always_ff @(posedge clk)
        if (wen_i)
            mem_r[waddr_i] <= wdata_i;
endmodule

module ydrasil_sim_1r1w_masked_ram #(
    parameter int DEPTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int WRITE_LANES = DATA_WIDTH / 8,
    parameter logic [DATA_WIDTH-1:0] INIT_VALUE = '0
) (
    input  wire                         clk,
    input  wire                         ren_i,
    input  wire [ADDR_WIDTH-1:0]        raddr_i,
    output logic [DATA_WIDTH-1:0]       rdata_o,
    input  wire [WRITE_LANES-1:0]       wstrb_i,
    input  wire [ADDR_WIDTH-1:0]        waddr_i,
    input  wire [DATA_WIDTH-1:0]        wdata_i
);
    logic [DATA_WIDTH-1:0] mem_r [0:DEPTH-1];
    integer init_idx;
    integer byte_idx;

    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
            mem_r[init_idx] = INIT_VALUE;
    end

    always_comb rdata_o = ren_i ? mem_r[raddr_i] : '0;

    always_ff @(posedge clk) begin
        for (byte_idx = 0; byte_idx < WRITE_LANES; byte_idx = byte_idx + 1) begin
            if (wstrb_i[byte_idx])
                mem_r[waddr_i][byte_idx*8 +: 8] <= wdata_i[byte_idx*8 +: 8];
        end
    end
endmodule
