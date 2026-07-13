`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 03:04:25 PM
// Design Name: 
// Module Name: counter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module counter(
    input  logic         clk,
    input  wire          perip_clk,
    input  logic         rst,

    input  logic         perip_cmd_valid,
    input  logic         perip_cmd_start,
    input  logic         perip_cmd_stop,
    output logic [31:0]  perip_rdata
);

    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic        run_perip;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  run_sync;
    logic        start;
    logic [31:0] cnt_ms_gray;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cnt_ms_gray_perip_meta;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cnt_ms_gray_perip_sync;
    logic [31:0] cnt_ms_perip;

    assign cnt_ms_gray = cnt_ms ^ (cnt_ms >> 1);
    genvar gray_bit_idx;
    generate
        for (gray_bit_idx = 0; gray_bit_idx < 32;
             gray_bit_idx = gray_bit_idx + 1) begin : g_gray_to_binary
            assign cnt_ms_perip[gray_bit_idx] =
                ^cnt_ms_gray_perip_sync[31:gray_bit_idx];
        end
    endgenerate

    always_ff @(posedge perip_clk or posedge rst) begin
        if (rst) begin
            run_perip <= 1'b0;
            cnt_ms_gray_perip_meta <= 32'h0;
            cnt_ms_gray_perip_sync <= 32'h0;
        end else begin
            if (perip_cmd_valid && perip_cmd_start) begin
                run_perip <= 1'b1;
            end
            if (perip_cmd_valid && perip_cmd_stop) begin
                run_perip <= 1'b0;
            end
            cnt_ms_gray_perip_meta <= cnt_ms_gray;
            cnt_ms_gray_perip_sync <= cnt_ms_gray_perip_meta;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            run_sync <= 2'b00;
            start <= 1'b0;
        end else begin
            run_sync <= {run_sync[0], run_perip};
            start <= run_sync[1];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_1ms <= 16'h0;
        end else if (start) begin
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
        end else if (start && cnt_1ms == 49999) begin
            cnt_ms <= cnt_ms + 1;
        end
    end

    assign perip_rdata = cnt_ms_perip;

endmodule
