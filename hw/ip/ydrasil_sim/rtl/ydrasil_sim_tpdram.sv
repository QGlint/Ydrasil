module ydrasil_sim_tpdram #(
    parameter int DEPTH = 256,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter string INIT_FILE = "none",
    parameter bit INIT_ENABLE = 1'b0
) (
    input  wire                      clk,
    input  wire                      ena_i,
    input  wire [ADDR_WIDTH-1:0]     addra_i,
    input  wire [DATA_WIDTH-1:0]     dina_i,
    input  wire [(DATA_WIDTH/8)-1:0] wea_i,
    output logic [DATA_WIDTH-1:0]    douta_o,
    input  wire                      enb_i,
    input  wire [ADDR_WIDTH-1:0]     addrb_i,
    input  wire [DATA_WIDTH-1:0]     dinb_i,
    input  wire [(DATA_WIDTH/8)-1:0] web_i,
    output logic [DATA_WIDTH-1:0]    doutb_o
);
    logic [DATA_WIDTH-1:0] mem_r [0:DEPTH-1];
    integer byte_idx;

    initial begin
        if (INIT_ENABLE && (INIT_FILE != "none") && (INIT_FILE != ""))
            $readmemh(INIT_FILE, mem_r);
    end

    always_ff @(posedge clk) begin
        if (ena_i) begin
            douta_o <= mem_r[addra_i];
            for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1)
                if (wea_i[byte_idx])
                    mem_r[addra_i][byte_idx*8 +: 8] <= dina_i[byte_idx*8 +: 8];
        end
        if (enb_i) begin
            doutb_o <= mem_r[addrb_i];
            for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1)
                if (web_i[byte_idx])
                    mem_r[addrb_i][byte_idx*8 +: 8] <= dinb_i[byte_idx*8 +: 8];
        end
    end
endmodule
