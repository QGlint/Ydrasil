module ydrmem_1r1w_ram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  wire                  clk,

    input  wire                  ren_i,
    input  wire [ADDR_WIDTH-1:0] raddr_i,
    output logic [DATA_WIDTH-1:0] rdata_o,

    input  wire                  wen_i,
    input  wire [ADDR_WIDTH-1:0] waddr_i,
    input  wire [DATA_WIDTH-1:0] wdata_i
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (ren_i) begin
            rdata_o <= mem[raddr_i];
        end
        if (wen_i) begin
            mem[waddr_i] <= wdata_i;
        end
    end

endmodule
