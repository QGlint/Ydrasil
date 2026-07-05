`timescale 1ns / 1ps

module ydrasil_clocking (
    input  wire clk_in1_p,
    input  wire clk_in1_n,
    output wire clk_50mhz,
    output wire cpu_clk,
    output wire locked
);

`ifdef SYN_PLL_FREQ_300
    localparam real MMCM_CLKFBOUT_MULT_F  = 6.000;
    localparam real MMCM_CLKOUT0_DIVIDE_F = 24.000;
    localparam int  MMCM_CLKOUT1_DIVIDE   = 4;
`elsif SYN_PLL_FREQ_280
    localparam real MMCM_CLKFBOUT_MULT_F  = 7.000;
    localparam real MMCM_CLKOUT0_DIVIDE_F = 28.000;
    localparam int  MMCM_CLKOUT1_DIVIDE   = 5;
`elsif SYN_PLL_FREQ_250
    localparam real MMCM_CLKFBOUT_MULT_F  = 5.000;
    localparam real MMCM_CLKOUT0_DIVIDE_F = 20.000;
    localparam int  MMCM_CLKOUT1_DIVIDE   = 4;
`elsif SYN_PLL_FREQ_200
    localparam real MMCM_CLKFBOUT_MULT_F  = 5.000;
    localparam real MMCM_CLKOUT0_DIVIDE_F = 20.000;
    localparam int  MMCM_CLKOUT1_DIVIDE   = 5;
`else
    localparam real MMCM_CLKFBOUT_MULT_F  = 5.250;
    localparam real MMCM_CLKOUT0_DIVIDE_F = 21.000;
    localparam int  MMCM_CLKOUT1_DIVIDE   = 7;
`endif

    wire clk_in1_mmcm;
    wire clkfbout_mmcm;
    wire clkfbout_buf;
    wire clk_50mhz_mmcm;
    wire cpu_clk_mmcm;
    wire clkout_unused;
    wire clkoutb_unused;
    wire clkout2_unused;
    wire clkout2b_unused;
    wire clkout3_unused;
    wire clkout3b_unused;
    wire clkout4_unused;
    wire clkout5_unused;
    wire clkout6_unused;
    wire clkfbin_unused;
    wire clkin1_mmcm;
    wire locked_int;

    IBUFGDS #(
        .DIFF_TERM    ("TRUE"),
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("DIFF_HSTL_II_18")
    ) u_ibufgds (
        .I  (clk_in1_p),
        .IB (clk_in1_n),
        .O  (clk_in1_mmcm)
    );

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (1),
        .CLKFBOUT_MULT_F      (MMCM_CLKFBOUT_MULT_F),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKOUT0_DIVIDE_F     (MMCM_CLKOUT0_DIVIDE_F),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKOUT1_DIVIDE       (MMCM_CLKOUT1_DIVIDE),
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .CLKIN1_PERIOD        (5.000),
        .REF_JITTER1          (0.010)
    ) u_mmcm (
        .CLKFBOUT     (clkfbout_mmcm),
        .CLKFBOUTB    (clkfboutb_unused),
        .CLKOUT0      (clk_50mhz_mmcm),
        .CLKOUT0B     (clkout_unused),
        .CLKOUT1      (cpu_clk_mmcm),
        .CLKOUT1B     (clkoutb_unused),
        .CLKOUT2      (clkout2_unused),
        .CLKOUT2B     (clkout2b_unused),
        .CLKOUT3      (clkout3_unused),
        .CLKOUT3B     (clkout3b_unused),
        .CLKOUT4      (clkout4_unused),
        .CLKOUT5      (clkout5_unused),
        .CLKOUT6      (clkout6_unused),
        .CLKFBIN      (clkfbout_buf),
        .CLKIN1       (clk_in1_mmcm),
        .CLKIN2       (1'b0),
        .CLKINSEL     (1'b1),
        .DADDR        (7'h00),
        .DCLK         (1'b0),
        .DEN          (1'b0),
        .DI           (16'h0000),
        .DO           (),
        .DRDY         (),
        .DWE          (1'b0),
        .PSCLK        (1'b0),
        .PSEN         (1'b0),
        .PSINCDEC     (1'b0),
        .PSDONE       (),
        .LOCKED       (locked_int),
        .PWRDWN       (1'b0),
        .RST          (1'b0)
    );

    BUFG u_bufg_clkfb (
        .I (clkfbout_mmcm),
        .O (clkfbout_buf)
    );

    BUFG u_bufg_cpu_clk (
        .I (cpu_clk_mmcm),
        .O (cpu_clk)
    );

    BUFG u_bufg_50mhz (
        .I (clk_50mhz_mmcm),
        .O (clk_50mhz)
    );

    assign locked = locked_int;

endmodule
