module ydrasil_fpu_registers
import ydrasil_pkg::*;
(
	input  wire                         clk,
	input  wire                         rst_n,
	input  wire                         write_valid_i,
	input  wire [REGS_ADDR_WIDTH-1:0]   write_addr_i,
	input  wire [FPU_DATA_WIDTH-1:0]    write_data_i,
	input  wire [REGS_ADDR_WIDTH-1:0]   read_addr1_i,
	input  wire [REGS_ADDR_WIDTH-1:0]   read_addr2_i,
	input  wire [REGS_ADDR_WIDTH-1:0]   read_addr3_i,
	output wire [FPU_DATA_WIDTH-1:0]    read_data1_o,
	output wire [FPU_DATA_WIDTH-1:0]    read_data2_o,
	output wire [FPU_DATA_WIDTH-1:0]    read_data3_o
);
	reg [FPU_DATA_WIDTH-1:0] fpr_q [0:REGS_NUM-1];
	integer index;

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			for (index = 0; index < REGS_NUM; index = index + 1)
				fpr_q[index] <= '0;
		end else if (write_valid_i) begin
			fpr_q[write_addr_i] <= write_data_i;
		end
	end

	assign read_data1_o = fpr_q[read_addr1_i];
	assign read_data2_o = fpr_q[read_addr2_i];
	assign read_data3_o = fpr_q[read_addr3_i];
endmodule
