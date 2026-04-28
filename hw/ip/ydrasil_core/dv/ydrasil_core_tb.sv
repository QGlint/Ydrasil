`timescale 1ns/1ns
parameter CNT_s = 40;
parameter CNT_us = 50;
parameter time_end = CNT_us*1000; // 1ms
parameter time_end = 50*CNT_us; // 40s

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
		forever #10 clk = ~clk;
	end

	initial begin
		rst_n = 1'b0;
		repeat (10) @(posedge clk);
		rst_n = 1'b1;
	end

	wire rst;
	assign rst = ~rst_n;

	initial begin
		repeat (time_end) @(posedge clk);
		$display("[TB] timeout reached, finish simulation");
		$finish;
	end

	initial begin
		$monitor("[TB] time=%0t, rst_n=%b, LED=0x%08h, seg_wdata=0x%08h",
			$time, rst_n, LED, seg_wdata);
	end


	localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
    localparam SEG_ADDR  = 32'h8020_0020;  // seg
    localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
    localparam CNT_ADDR  = 32'h8020_0050;  // counter

    logic [31:0] LED;
    logic [31:0] seg_wdata, cnt_rdata, mmio_rdata, dram_rdata;
    logic [39:0] seg_output;

    // we don't care perip_mask in LED, SEG, SW & KEY, only care in DRAM
    // write process
    always_ff @(posedge clk) begin
        if (perip_wen) begin
            case (perip_addr)
                LED_ADDR:   LED <= perip_wdata;
                SEG_ADDR:   seg_wdata <= perip_wdata;
            endcase
        end
    end

	wire [31:0] virtual_led_output;
	wire [39:0] virtual_seg_output;
	wire [63:0] virtual_sw_input = 0;
	wire [7:0]  virtual_key_input = 0;

    // read process: in one cycle
    always_comb begin
        if (~perip_wen) begin
            case (perip_addr)
                SW0_ADDR:  mmio_rdata = virtual_sw_input[31:0];
                SW1_ADDR:  mmio_rdata = virtual_sw_input[63:32];
                KEY_ADDR:  mmio_rdata = {24'd0, virtual_key_input};
                SEG_ADDR:  mmio_rdata = seg_wdata;
                default:   mmio_rdata = 32'hDEAD_BEEF;
            endcase
        end else begin
            mmio_rdata = 32'h0;
        end
    end

    // seg driver
  
    assign seg_output[7]  = 0;
    assign seg_output[17] = 0;
    assign seg_output[27] = 0;
    assign seg_output[37] = 0;
    

    // dram rw
    // dram_driver dram_driver_inst (
    //     .clk				(clk),
    //     .perip_addr			(perip_addr[17:0]),
    //     .perip_wdata		(perip_wdata),
    //     .perip_mask			(perip_mask),
    //     .dram_wen 			(perip_wen & (perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END)),
    //     .perip_rdata		(dram_rdata)
    // );

    // counter rw
    // counter counter_inst (
    //     .clk				(cnt_clk),
    //     .rst                (rst),
    //     .perip_wdata		(perip_wdata),
    //     .cnt_wen 			(perip_wen & (perip_addr == CNT_ADDR)),
    //     .perip_rdata		(cnt_rdata)
    // );

	wire cnt_wen ;
	assign cnt_wen = perip_wen & (perip_addr == CNT_ADDR);

    assign perip_rdata = {32{perip_addr == SW0_ADDR}} & mmio_rdata |
                        {32{perip_addr == SW1_ADDR}} & mmio_rdata |
                        {32{perip_addr == KEY_ADDR}} & mmio_rdata |
                        {32{perip_addr == SEG_ADDR}} & mmio_rdata |
                        // {32{perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END}} & dram_rdata |
                        {32{perip_addr == CNT_ADDR}} & cnt_rdata;
    


    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;
    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic start;

    always_ff @(posedge clk) begin
        if (rst) begin
            start <= 0;
        end else if (cnt_wen & cnt_rdata == 32'h8000_0000) begin
            start <= 1;
        end else if (cnt_wen & perip_wdata == 32'hFFFF_FFFF) begin
            start <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt_1ms <= 0;
        end else if (start) begin
            if (cnt_1ms == 49999) begin
                cnt_1ms <= 0;
            end else begin
                cnt_1ms <= cnt_1ms + 1;
            end
        end else begin
            cnt_1ms <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt_ms <= 0;
        end else if (start && cnt_1ms == 49999) begin
            cnt_ms <= cnt_ms + 1;
        end
    end

    assign perip_rdata = cnt_ms;



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
