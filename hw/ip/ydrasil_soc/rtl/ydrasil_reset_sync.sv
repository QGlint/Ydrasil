module ydrasil_reset_sync (
    input  wire clk_i,
    input  wire arst_n_i,
    output wire rst_n_o
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] sync_q;

    always_ff @(posedge clk_i or negedge arst_n_i) begin
        if (!arst_n_i)
            sync_q <= '0;
        else
            sync_q <= {sync_q[0], 1'b1};
    end

    assign rst_n_o = sync_q[1];
endmodule
