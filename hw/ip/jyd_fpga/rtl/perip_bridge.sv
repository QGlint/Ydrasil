`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/22 10:25:24
// Design Name: 
// Module Name: perip_bridge
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

module perip_bridge(
    input  wire         clk				,
    input  wire         cnt_clk			,
    input  wire         rst                ,

    input  wire [31:0]  perip_addr			,
    input  wire [31:0]  perip_wdata		,
    input  wire         perip_wen			,
	input  wire [1:0]	 perip_mask			,
    output wire [31:0]  perip_rdata		,

    input  wire [63:0]  virtual_sw_input	,
    input  wire [7:0]   virtual_key_input	,	

	output wire [39:0]  virtual_seg_output	,
    output wire [31:0]  virtual_led_output
);
    // localparam DRAM_ADDR_START = 32'h8010_0000;
    // localparam DRAM_ADDR_END   = 32'h8013_FFFF;
    localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
    localparam SEG_ADDR  = 32'h8020_0020;  // seg
    localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
    localparam CNT_ADDR  = 32'h8020_0050;  // counter

    reg [31:0] LED;
    reg [31:0] seg_wdata;
    reg [31:0] mmio_rdata;
    wire [31:0] cnt_rdata;
    // wire [31:0] dram_rdata;
    wire [39:0] seg_output;

    reg [31:0] perip_rdata_ff;
    wire [31:0] perip_rdata_comb;

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
    display_seg seg_driver (
        .clk    (clk),
        .rst    (rst),
        .s      (seg_wdata),
        .seg1   (seg_output[6:0]),
        .seg2   (seg_output[16:10]),
        .seg3   (seg_output[26:20]),
        .seg4   (seg_output[36:30]),
        .ans    ({seg_output[39:38], seg_output[29:28], seg_output[19:18], seg_output[9:8]})
    ); 
   
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
    counter counter_inst (
        .clk				(cnt_clk),
        .perip_clk            (clk),
        .rst                (rst),
        .perip_wdata		(perip_wdata),
        .cnt_wen 			(perip_wen & (perip_addr == CNT_ADDR)),
        .perip_rdata		(cnt_rdata)
    );

    assign perip_rdata_comb = {32{perip_addr == SW0_ADDR}} & mmio_rdata |
                        {32{perip_addr == SW1_ADDR}} & mmio_rdata |
                        {32{perip_addr == KEY_ADDR}} & mmio_rdata |
                        {32{perip_addr == SEG_ADDR}} & mmio_rdata |
                        // {32{perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END}} & dram_rdata |
                        {32{perip_addr == CNT_ADDR}} & cnt_rdata;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            perip_rdata_ff <= 32'h0;
        end else begin
            perip_rdata_ff <= perip_rdata_comb;
        end
    end
    assign perip_rdata = perip_rdata_ff;

    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;

endmodule
