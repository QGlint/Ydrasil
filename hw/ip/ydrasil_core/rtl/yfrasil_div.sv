
`include "config.svh"

module ydrasil_div (
   input wire                  clk,
   input wire                  rst_n,
   input wire                  div_start_i,
   input wire [1:0]            opcode_i,  // 2'b00: DIV, 2'b01: DIVU, 2'b10: REM, 2'b11: REMU
   input wire [ydrasil_core_pkg::REGS_DATA_WIDTH-1:0]   dividend_i,
   input wire [ydrasil_core_pkg::REGS_DATA_WIDTH-1:0]   divisor_i,
   output wire [ydrasil_core_pkg::REGS_DATA_WIDTH-1:0]   quotient_o,
   output wire [ydrasil_core_pkg::REGS_DATA_WIDTH-1:0]   remainder_o,
   output wire                  div_ready_o
);

    localparam int N_STATE = 5;

    typedef enum logic [N_STATE-1:0] {
        STATE_IDLE  = 1 << 0,
        STATE_START = 1 << 1,
        STATE_CALC  = 1 << 2,
        STATE_END   = 1 << 3
    } state_t;

   localparam int DATA_WIDTH = ydrasil_core_pkg::REGS_DATA_WIDTH;
   localparam [1:0] OP_DIV  = 2'b00;
   localparam [1:0] OP_DIVU = 2'b01;
   localparam [1:0] OP_REM  = 2'b10;
   localparam [1:0] OP_REMU = 2'b11;

   reg [DATA_WIDTH-1:0] dividend_reg;
   reg [DATA_WIDTH-1:0] divisor_reg;
   reg [DATA_WIDTH-1:0] quotient_reg;
   reg signed [DATA_WIDTH:0]   remainder_reg;
   reg [5:0] count; // 计数器，最多需要32次
   reg busy; // 是否正在计算

   reg div_signed;
   reg dividend_neg;
   reg divisor_neg;

   assign quotient_o = quotient_reg;
   assign remainder_o = remainder_reg[DATA_WIDTH-1:0];
   assign div_ready_o = ~busy;

   wire opcode_is_div = (opcode_i == OP_DIV) || (opcode_i == OP_DIVU);
   wire opcode_is_rem = (opcode_i == OP_REM) || (opcode_i == OP_REMU);
   wire opcode_is_signed = (opcode_i == OP_DIV) || (opcode_i == OP_REM);

   wire [DATA_WIDTH-1:0] dividend_abs = dividend_neg ? (~dividend_i + 1'b1) : dividend_i;
   wire [DATA_WIDTH-1:0] divisor_abs  = divisor_neg ? (~divisor_i + 1'b1) : divisor_i;

   wire signed [DATA_WIDTH:0] remainder_shifted = {remainder_reg[DATA_WIDTH-1:0], dividend_reg[DATA_WIDTH-1]};
   wire signed [DATA_WIDTH:0] divisor_ext = {1'b0, divisor_reg};
   wire signed [DATA_WIDTH:0] remainder_calc = remainder_reg[DATA_WIDTH] ?
      (remainder_shifted + divisor_ext) :
      (remainder_shifted - divisor_ext);
   wire remainder_nonneg = ~remainder_calc[DATA_WIDTH];
   wire signed [DATA_WIDTH:0] remainder_next = remainder_calc;
   wire [DATA_WIDTH-1:0] quotient_next = {quotient_reg[DATA_WIDTH-2:0], remainder_nonneg};
   wire signed [DATA_WIDTH:0] remainder_final = remainder_calc[DATA_WIDTH] ? (remainder_calc + divisor_ext) : remainder_calc;



   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         dividend_reg  <= '0;
         divisor_reg   <= '0;
         quotient_reg  <= '0;
         remainder_reg <= '0;
         count         <= 6'd0;
         busy          <= 1'b0;
         div_signed    <= 1'b0;
         dividend_neg  <= 1'b0;
         divisor_neg   <= 1'b0;
      end else if (div_start_i && !busy) begin
         div_signed   <= opcode_is_signed;
         dividend_neg <= opcode_is_signed && dividend_i[DATA_WIDTH-1];
         divisor_neg  <= opcode_is_signed && divisor_i[DATA_WIDTH-1];

         if (divisor_i == '0) begin
            quotient_reg  <= {DATA_WIDTH{1'b1}};
            remainder_reg <= {1'b0, dividend_i};
            busy          <= 1'b0;
            count         <= 6'd0;
         end else begin
            dividend_reg  <= dividend_abs;
            divisor_reg   <= divisor_abs;
            quotient_reg  <= '0;
            remainder_reg <= '0;
            count         <= DATA_WIDTH[5:0];
            busy          <= 1'b1;
         end
      end else if (busy) begin
         dividend_reg  <= {dividend_reg[DATA_WIDTH-2:0], 1'b0};
         remainder_reg <= remainder_next;
         quotient_reg  <= quotient_next;

         if (count == 6'd1) begin
            busy  <= 1'b0;
            count <= 6'd0;

            if (opcode_is_div) begin
               if (div_signed && (dividend_neg ^ divisor_neg)) begin
                  quotient_reg <= ~quotient_next + 1'b1;
               end else begin
                  quotient_reg <= quotient_next;
               end
            end else begin
               if (div_signed && dividend_neg) begin
                  remainder_reg <= ~remainder_final + 1'b1;
               end else begin
                  remainder_reg <= remainder_final;
               end
            end
         end else begin
            count <= count - 6'd1;
         end
      end
   end

endmodule
