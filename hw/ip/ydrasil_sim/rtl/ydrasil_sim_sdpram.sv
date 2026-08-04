module ydrasil_sim_sdpram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter string INIT_FILE = "none",
    parameter bit INIT_ENABLE = 1'b0
) (
    input  wire                      clk,
    input  wire                      ren_i,
    input  wire [ADDR_WIDTH-1:0]     raddr_i,
    output logic [DATA_WIDTH-1:0]    rdata_o,
    input  wire                      wen_i,
    input  wire [ADDR_WIDTH-1:0]     waddr_i,
    input  wire [DATA_WIDTH-1:0]     wdata_i,
    input  wire [(DATA_WIDTH/8)-1:0] wstrb_i
);
    logic [DATA_WIDTH-1:0] mem_r [0:DEPTH-1];
    integer byte_idx;

    initial begin
        if (INIT_ENABLE && (INIT_FILE != "none") && (INIT_FILE != ""))
            $readmemh(INIT_FILE, mem_r);
    end

    always_ff @(posedge clk) begin
        if (ren_i)
            rdata_o <= mem_r[raddr_i];
        if (wen_i)
            for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1)
                if (wstrb_i[byte_idx])
                    mem_r[waddr_i][byte_idx*8 +: 8] <= wdata_i[byte_idx*8 +: 8];
    end
endmodule
