`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:44 PM
// Design Name: 
// Module Name: top
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
// `define FPGA

module jyd_fpga(
    input  wire i_sys_clk_p         ,
    input  wire i_sys_clk_n         ,
    input  wire i_uart_rx           ,
    output wire o_uart_tx           ,

    output wire [31:0] virtual_led  ,
    output wire [39:0] virtual_seg
);

    wire w_clk_50Mhz, cpu_clk;
    wire w_clk_rst;

    wire [7:0] virtual_key;
    wire [63:0] virtual_sw;

    wire [7:0] rx_data;
    wire rx_ready;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_busy;

`ifdef SYNTHESIS
    pll pll_inst(
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n),
        .clk_out1(w_clk_50Mhz),
        .clk_out2(cpu_clk),
        .locked(w_clk_rst)
    );
`elsif __XILINX_SIMULATOR__
        pll pll_inst(
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n),
        .clk_out1(w_clk_50Mhz),
        .clk_out2(cpu_clk),
        .locked(w_clk_rst)
    );
`else
//else
    logic [2:0]cnt = 0;

    always_ff @(posedge i_sys_clk_p) begin
        cnt <= cnt + 1;
    end

    logic rst_n = 0;

    logic [16:0] rst_cnt = 0;

    always_ff @(posedge i_sys_clk_p) begin
        if (rst_cnt < 30) begin
            rst_cnt <= rst_cnt + 1;
        end
    end

    always_ff @(posedge i_sys_clk_p) begin
        if (rst_cnt < 30) begin
            rst_n <= 0;
        end else begin
            rst_n <= 1;
        end
    end

    assign w_clk_50Mhz = cnt[2];  // 直接使用输入时钟，假设它是50MHz
    assign cpu_clk = i_sys_clk_p;      // 直接使用输入时钟，
    assign w_clk_rst = rst_n;          // 永远不复位，假设系统上电后一直正常工作

`endif





    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(o_uart_tx),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

    twin_controller twin_controller_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .sw(virtual_sw),
        .key(virtual_key),
        .seg(virtual_seg),
        .led(virtual_led)
    );

    student_top student_top_inst(
        .w_cpu_clk(cpu_clk),
        .w_clk_50Mhz(w_clk_50Mhz),
        .w_clk_rst(~w_clk_rst),
        .virtual_key(virtual_key),
        .virtual_sw(virtual_sw),
        .virtual_led(virtual_led),
        .virtual_seg(virtual_seg)
    );

endmodule

