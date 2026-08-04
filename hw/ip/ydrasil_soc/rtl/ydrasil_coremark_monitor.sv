module ydrasil_coremark_monitor (
    input  wire        cpu_clk_i,
    input  wire        cpu_rst_n_i,
    input  wire        start_toggle_async_i,
    input  wire        stop_toggle_async_i,
    output wire        active_o,
    output wire [63:0] cycles_o
);
    wire start_toggle_sync;
    wire stop_toggle_sync;
    logic start_seen_q;
    logic stop_seen_q;
    logic active_q;
    logic [63:0] cycles_q;
    wire start_event = start_toggle_sync != start_seen_q;
    wire stop_event = stop_toggle_sync != stop_seen_q;

    ydrasil_cdc_sync u_start_sync (
        .clk_i(cpu_clk_i),
        .rst_n_i(cpu_rst_n_i),
        .async_i(start_toggle_async_i),
        .sync_o(start_toggle_sync)
    );

    ydrasil_cdc_sync u_stop_sync (
        .clk_i(cpu_clk_i),
        .rst_n_i(cpu_rst_n_i),
        .async_i(stop_toggle_async_i),
        .sync_o(stop_toggle_sync)
    );

    always_ff @(posedge cpu_clk_i or negedge cpu_rst_n_i) begin
        if (!cpu_rst_n_i) begin
            start_seen_q <= 1'b0;
            stop_seen_q <= 1'b0;
            active_q <= 1'b0;
            cycles_q <= '0;
        end else begin
            start_seen_q <= start_toggle_sync;
            stop_seen_q <= stop_toggle_sync;

            if (stop_event) begin
                active_q <= 1'b0;
            end else if (start_event) begin
                active_q <= 1'b1;
                cycles_q <= '0;
            end else if (active_q) begin
                cycles_q <= cycles_q + 1'b1;
            end
        end
    end

    assign active_o = active_q;
    assign cycles_o = cycles_q;
endmodule
