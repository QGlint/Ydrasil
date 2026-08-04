module ydrasil_coremark_monitor (
    input  wire        cpu_clk_i,
    input  wire        cpu_rst_n_i,
    input  wire        start_toggle_async_i,
    input  wire        stop_toggle_async_i,
    input  wire        auto_enable_async_i,
    input  wire [31:0] pc_base_async_i,
    input  wire [31:0] pc_limit_async_i,
    input  wire [31:0] timeout_async_i,
    input  wire        retire0_valid_i,
    input  wire [31:0] retire0_pc_i,
    input  wire        retire1_valid_i,
    input  wire [31:0] retire1_pc_i,
    output wire        active_o,
    output wire [63:0] cycles_o
);
    wire [97:0] config_sync;
    wire start_toggle_sync;
    wire stop_toggle_sync;
    logic start_seen_q;
    logic stop_seen_q;
    logic active_q;
    logic [63:0] cycles_q;
    logic [31:0] outside_count_q;

    wire auto_enable = config_sync[97];
    wire [31:0] pc_base = config_sync[96:65];
    wire [31:0] pc_limit = config_sync[64:33];
    wire [31:0] timeout_cycles = config_sync[32:1];
    wire range_valid = pc_limit > pc_base;
    wire retire_in_range = range_valid &&
        ((retire0_valid_i && (retire0_pc_i >= pc_base) &&
          (retire0_pc_i < pc_limit)) ||
         (retire1_valid_i && (retire1_pc_i >= pc_base) &&
          (retire1_pc_i < pc_limit)));
    wire retire_outside = (retire0_valid_i || retire1_valid_i) &&
        !retire_in_range;
    wire start_event = start_toggle_sync != start_seen_q;
    wire stop_event = stop_toggle_sync != stop_seen_q;

    ydrasil_cdc_sync #(.WIDTH(98)) u_config_sync (
        .clk_i(cpu_clk_i),
        .rst_n_i(cpu_rst_n_i),
        .async_i({auto_enable_async_i, pc_base_async_i, pc_limit_async_i,
            timeout_async_i, 1'b0}),
        .sync_o(config_sync)
    );

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
            outside_count_q <= '0;
        end else begin
            start_seen_q <= start_toggle_sync;
            stop_seen_q <= stop_toggle_sync;

            if (stop_event) begin
                active_q <= 1'b0;
                outside_count_q <= '0;
            end else if (start_event ||
                (auto_enable && !active_q && retire_in_range)) begin
                active_q <= 1'b1;
                cycles_q <= '0;
                outside_count_q <= '0;
            end else if (active_q) begin
                cycles_q <= cycles_q + 1'b1;
                if (retire_in_range) begin
                    outside_count_q <= '0;
                end else if (retire_outside && (timeout_cycles != 0)) begin
                    if (outside_count_q >= (timeout_cycles - 1'b1)) begin
                        active_q <= 1'b0;
                        outside_count_q <= '0;
                    end else begin
                        outside_count_q <= outside_count_q + 1'b1;
                    end
                end
            end
        end
    end

    assign active_o = active_q;
    assign cycles_o = cycles_q;
endmodule
