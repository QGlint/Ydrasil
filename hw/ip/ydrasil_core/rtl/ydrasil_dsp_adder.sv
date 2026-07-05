module ydrasil_dsp_adder
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                       sub_i,
    input  wire [DATA_WIDTH-1:0]      operand_a_i,
    input  wire [DATA_WIDTH-1:0]      operand_b_i,
    output wire [DATA_WIDTH:0]        result_o
);

`ifdef SYNTHESIS
    // Vivado synthesis: use DSP48E1 for ~3ns fixed-latency add/sub
    wire [29:0] dsp_a;
    wire [17:0] dsp_b;
    wire [47:0] dsp_c;
    wire [47:0] dsp_p;

    assign dsp_a = sub_i ? {14'b0, operand_b_i[31:18]} : {14'b0, operand_a_i[31:18]};
    assign dsp_b = sub_i ? operand_b_i[17:0]            : operand_a_i[17:0];
    assign dsp_c = sub_i ? {16'b0, operand_a_i}         : {16'b0, operand_b_i};

    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
        .USE_DPORT("FALSE"), .USE_MULT("NONE"), .USE_SIMD("ONE48"),
        .AUTORESET_PATDET("NO_RESET"),
        .MASK(48'h3fffffffffff), .PATTERN(48'h000000000000),
        .SEL_MASK("MASK"), .SEL_PATTERN("PATTERN"),
        .USE_PATTERN_DETECT("NO_PATDET"),
        .ACASCREG(0), .ADREG(0), .ALUMODEREG(0),
        .AREG(0), .BCASCREG(0), .BREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0),
        .CREG(0), .DREG(0), .INMODEREG(0),
        .MREG(0), .OPMODEREG(0), .PREG(0)
    ) u_dsp (
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .MULTSIGNOUT(), .PCOUT(),
        .ALUMODE(sub_i ? 4'b0011 : 4'b0000),
        .CARRYINSEL(3'b000), .CARRYIN(1'b0), .CLK(1'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0),
        .CEM(1'b0), .CEP(1'b0),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0),
        .RSTD(1'b0), .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(1'b0),
        .A(dsp_a), .ACIN(30'b0),
        .B(dsp_b), .BCIN(18'b0),
        .C(dsp_c), .CARRYCASCIN(1'b0),
        .D(25'b0), .INMODE(5'b0), .MULTSIGNIN(1'b0),
        .OPMODE(7'b0110011),
        .PCIN(48'b0),
        .P(dsp_p)
    );
    assign result_o = dsp_p[32:0];

`else
    // Simulation/Verilator: behavioral fallback
    assign result_o = sub_i
        ? ({1'b0, operand_a_i} - {1'b0, operand_b_i})
        : ({1'b0, operand_a_i} + {1'b0, operand_b_i});
`endif

endmodule
