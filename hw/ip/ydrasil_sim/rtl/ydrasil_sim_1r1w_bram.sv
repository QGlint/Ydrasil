module ydrasil_sim_1r1w_bram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
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

    always_ff @(posedge clk) begin
        if (ren_i)
            rdata_o <= mem_r[raddr_i];
        if (wen_i)
            mem_r[waddr_i] <= wdata_i;
    end
endmodule
