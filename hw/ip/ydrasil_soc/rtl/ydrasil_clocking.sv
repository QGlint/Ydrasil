`timescale 1ns / 1ps

module ydrasil_clocking (
    input  wire clk_in1_p,
    input  wire clk_in1_n,
    output wire apb_clk,
    output wire cpu_clk,
    output wire locked
);
`ifdef VERILATOR_SV
    assign apb_clk = clk_in1_p;
    assign cpu_clk = clk_in1_p;
    assign locked = 1'b1;
`else
`ifdef SYN_PLL_FREQ_200
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 5.000;
    localparam real APB_DIVIDE_F = 20.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_225
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 5.625;
    localparam real APB_DIVIDE_F = 22.500;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_240
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.000;
    localparam real APB_DIVIDE_F = 24.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_250
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.250;
    localparam real APB_DIVIDE_F = 25.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_260
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.500;
    localparam real APB_DIVIDE_F = 26.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_270
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.750;
    localparam real APB_DIVIDE_F = 27.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_275
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.875;
    localparam real APB_DIVIDE_F = 27.500;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_280
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 7.000;
    localparam real APB_DIVIDE_F = 28.000;
    localparam int CPU_DIVIDE = 5;
`elsif SYN_PLL_FREQ_290P625
    localparam int DIVCLK_DIVIDE = 2;
    localparam real CLKFBOUT_MULT_F = 11.625;
    localparam real APB_DIVIDE_F = 23.250;
    localparam int CPU_DIVIDE = 4;
`elsif SYN_PLL_FREQ_300
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 6.000;
    localparam real APB_DIVIDE_F = 24.000;
    localparam int CPU_DIVIDE = 4;
`else
    localparam int DIVCLK_DIVIDE = 1;
    localparam real CLKFBOUT_MULT_F = 5.250;
    localparam real APB_DIVIDE_F = 21.000;
    localparam int CPU_DIVIDE = 7;
`endif

    wire clk_in_mmcm;
    wire clkfb_mmcm;
    wire clkfb_buf;
    wire apb_clk_mmcm;
    wire cpu_clk_mmcm;
    wire clkout0b_unused;
    wire clkout1b_unused;
    wire clkout2_unused;
    wire clkout2b_unused;
    wire clkout3_unused;
    wire clkout3b_unused;
    wire clkout4_unused;
    wire clkout5_unused;
    wire clkout6_unused;
    wire clkfboutb_unused;
    wire clkfbstopped_unused;
    wire clkinstopped_unused;
    wire [15:0] do_unused;
    wire drdy_unused;
    wire psdone_unused;

    IBUFDS u_clk_ibufds (
        .O(clk_in_mmcm), .I(clk_in1_p), .IB(clk_in1_n)
    );

    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKOUT4_CASCADE("FALSE"),
        .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(DIVCLK_DIVIDE),
        .CLKFBOUT_MULT_F(CLKFBOUT_MULT_F),
        .CLKFBOUT_PHASE(0.000),
        .CLKFBOUT_USE_FINE_PS("FALSE"),
        .CLKOUT0_DIVIDE_F(APB_DIVIDE_F),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_USE_FINE_PS("FALSE"),
        .CLKOUT1_DIVIDE(CPU_DIVIDE),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKOUT1_USE_FINE_PS("FALSE"),
        .CLKIN1_PERIOD(5.000),
        .REF_JITTER1(0.010)
    ) u_mmcm (
        .CLKFBOUT(clkfb_mmcm), .CLKFBOUTB(clkfboutb_unused),
        .CLKOUT0(apb_clk_mmcm), .CLKOUT0B(clkout0b_unused),
        .CLKOUT1(cpu_clk_mmcm), .CLKOUT1B(clkout1b_unused),
        .CLKOUT2(clkout2_unused), .CLKOUT2B(clkout2b_unused),
        .CLKOUT3(clkout3_unused), .CLKOUT3B(clkout3b_unused),
        .CLKOUT4(clkout4_unused), .CLKOUT5(clkout5_unused),
        .CLKOUT6(clkout6_unused), .CLKFBIN(clkfb_buf),
        .CLKIN1(clk_in_mmcm), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .DADDR(7'h00), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0000),
        .DO(do_unused), .DRDY(drdy_unused), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0),
        .PSDONE(psdone_unused), .LOCKED(locked),
        .CLKINSTOPPED(clkinstopped_unused),
        .CLKFBSTOPPED(clkfbstopped_unused), .PWRDWN(1'b0), .RST(1'b0)
    );

    BUFG u_clkfb_buf (.O(clkfb_buf), .I(clkfb_mmcm));
    BUFG u_apb_clk_buf (.O(apb_clk), .I(apb_clk_mmcm));
    BUFG u_cpu_clk_buf (.O(cpu_clk), .I(cpu_clk_mmcm));
`endif
endmodule
