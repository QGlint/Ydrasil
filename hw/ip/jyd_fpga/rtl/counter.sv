`timescale 1ns / 1ns
module counter(
    input  logic         clk,
    input  logic         rst,
    input  logic         cmd_valid_i,
    input  logic         cmd_start_i,
    input  logic         cmd_stop_i,
    output logic [31:0]  count_o
);

    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic        running_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            running_q <= 1'b0;
        end else begin
            if (cmd_valid_i && cmd_start_i)
                running_q <= 1'b1;
            if (cmd_valid_i && cmd_stop_i)
                running_q <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_1ms <= 16'h0;
        end else if (running_q) begin
            if (cnt_1ms == 49999) begin
                cnt_1ms <= 16'h0;
            end else begin
                cnt_1ms <= cnt_1ms + 1;
            end
        end else begin
            cnt_1ms <= 16'h0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_ms <= 32'h0;
        end else if (running_q && cnt_1ms == 49999) begin
            cnt_ms <= cnt_ms + 1;
        end
    end

    assign count_o = cnt_ms;

endmodule
