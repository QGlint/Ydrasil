`timescale 1ns/10ps

module ydrasil_core_tb;

	logic        clk;
	logic        rst_n;

	logic [31:0] perip_addr;
	logic        perip_wen;
	logic [1:0]  perip_mask;
	logic [31:0] perip_wdata;
	logic [31:0] perip_rdata;

	assign perip_rdata = 32'h0000_0000;

	ydrasil_core u_dut (
		.clk_i      (clk),
		.rst_n_i    (rst_n),
		.perip_addr (perip_addr),
		.perip_wen  (perip_wen),
		.perip_mask (perip_mask),
		.perip_wdata(perip_wdata),
		.perip_rdata(perip_rdata)
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	initial begin
		rst_n = 1'b0;
		repeat (10) @(posedge clk);
		rst_n = 1'b1;
	end

	initial begin
		repeat (2000) @(posedge clk);
		$display("[TB] timeout reached, finish simulation");
		$finish;
	end

	initial begin
`ifdef VERILATOR_SV
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`elsif IVERILOG_VCD
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`endif
	end

endmodule
