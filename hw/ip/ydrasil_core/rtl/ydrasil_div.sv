
module ydrasil_div
import ydrasil_pkg::*;
 #(
localparam int DATA_WIDTH = ydrasil_pkg::REGS_DATA_WIDTH,
localparam MODE = ydrasil_pkg::DIV_MODE
)
(
   input wire                  clk,
   input wire                  rst_n,
   input wire                  div_start_i,
   input wire [1:0]            div_type_i,  // 2'b00: DIV, 2'b01: DIVU, 2'b10: REM, 2'b11: REMU
   input wire [DATA_WIDTH-1:0]   dividend_i,
   input wire [DATA_WIDTH-1:0]   divisor_i,
   output wire [DATA_WIDTH-1:0]   quotient_o,
   output wire [DATA_WIDTH-1:0]   remainder_o,
   output wire                  div_ready_o
);

   if(!MODE) begin 

   
   end
   else begin 

    localparam int N_STATE = 4;

    typedef enum logic [N_STATE-1:0] {
        STATE_IDLE  = 1 << 0,
        STATE_START = 1 << 1,
        STATE_CALC  = 1 << 2,
        STATE_END   = 1 << 3
    } state_t;

   state_t state;
   
   reg [DATA_WIDTH-1:0] dividend_reg;
   reg [DATA_WIDTH-1:0] divisor_reg;
   reg [DATA_WIDTH-1:0] quotient_reg;
   reg signed [DATA_WIDTH:0]   remainder_reg;
   reg [5:0] count; // 计数器，最多需要32次
   reg busy; // 是否正在计算

   wire div_signed;
   wire dividend_neg;
   wire divisor_neg;

   wire opcode_is_div;
   wire opcode_is_rem;
   wire opcode_is_signed;

   assign quotient_o = quotient_reg;
   assign remainder_o = remainder_reg[DATA_WIDTH-1:0];
   assign div_ready_o = ~busy;

   assign opcode_is_div = ~div_type_i[1];
   assign opcode_is_rem = div_type_i[1];
   assign opcode_is_signed = ~div_type_i[0] ;

   wire [DATA_WIDTH-1:0] dividend_abs ;
   wire [DATA_WIDTH-1:0] divisor_abs  ;

   assign dividend_abs = dividend_neg ? (~dividend_i + 1'b1) : dividend_i;
   assign divisor_abs  = divisor_neg ? (~divisor_i + 1'b1) : divisor_i;

   assign dividend_neg= opcode_is_signed && dividend_i[DATA_WIDTH-1];
   assign divisor_neg = opcode_is_signed && divisor_i[DATA_WIDTH-1];

   wire [DATA_WIDTH-1:0] quotient_next;

   wire [DATA_WIDTH*2-1:0] div_shifter;
   wire [DATA_WIDTH*2-1:0] div_shifter_next;

   assign div_shifter_next =  {div_shifter [DATA_WIDTH*2-2:0], 1'b0};
   assign div_shifter = {remainder_reg[DATA_WIDTH-1:0], dividend_reg};

   assign remainder_next = ;
   assign dividend_reg_next = div_shifter_next[DATA_WIDTH-1:0];



   
   ydrasil_lzc #(
      .WIDTH     	(DATA_WIDTH),
      .MODE      	(1   )
   )u_ydrasil_a(
      .lzc_in_i    	(lzc_a_i     ),
      .lzc_cnt_o   	(lzc_a_result_o    ),
      .lzc_empty_o 	(lzc_a_empty_o  )
   );
   
   ydrasil_lzc #(
      .WIDTH     	(DATA_WIDTH),
      .MODE      	(1   )
   )u_ydrasil_b(
      .lzc_in_i    	(lzc_b_i     ),
      .lzc_cnt_o   	(lzc_b_result_o    ),
      .lzc_empty_o 	(lzc_b_empty_o  )
   );


   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         dividend_reg  <= '0;
         divisor_reg   <= '0;
         quotient_reg  <= '0;
         remainder_reg <= '0;
         count         <= 6'd0;
         busy          <= 1'b0;
      end else begin
         unique case (state)
            STATE_IDLE: begin
               dividend_reg  <= dividend_abs;
               divisor_reg   <= divisor_abs;
               quotient_reg  <= '0;
               remainder_reg <= '0;
               if (div_start_i) begin
                  count         <= 6'd0;
                  busy          <= 1'b1;
                  state         <= STATE_CALC;
               end
            end
            STATE_CALC: begin
               if (count < DATA_WIDTH) begin
                  remainder_reg <= remainder_next;
                  quotient_reg  <= quotient_next;
                  count         <= count + 1'b1;
               end else begin
                  // 最后一次调整余数符号
                  remainder_reg <= remainder_final;
                  busy          <= 1'b0;
                  state         <= STATE_END;
               end
            end
            STATE_END: begin
               if (!div_start_i) begin
                  state <= STATE_IDLE;
               end
            end
            default: state <= STATE_IDLE;
         endcase
      end
   end

   end

endmodule
