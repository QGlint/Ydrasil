module ydrasil_cdc_sync #(
    parameter int WIDTH = 1,
    parameter logic [WIDTH-1:0] RESET_VALUE = '0
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire [WIDTH-1:0]     async_i,
    output wire [WIDTH-1:0]     sync_o
);
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_meta_q;
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sync_meta_q <= RESET_VALUE;
            sync_q <= RESET_VALUE;
        end else begin
            sync_meta_q <= async_i;
            sync_q <= sync_meta_q;
        end
    end

    assign sync_o = sync_q;
endmodule
