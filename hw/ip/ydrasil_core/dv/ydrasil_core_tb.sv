`timescale 1ns/1ns
`include "define_mem_reg.svh"

parameter longint time_end = 100000; 

module ydrasil_core_tb(
`ifdef VERILATOR_CC
    input clk,
    input rst_n
`endif

);
string itcmfile;
string dtcmfile;
// ToHost程序地址,用于监控测试是否结束
`define PC_WRITE_TOHOST 32'h80000040
// ITCM 访问路径
`define ITCM u_dut.u_ydrasil_mems.u_itcm.u_irom
`define DTCM u_dut.u_ydrasil_mems.u_dtcm.u_dram

longint time_out;
longint sv_timeout;
initial begin
    if ($value$plusargs("itcmfile=%s", itcmfile)) begin
      $display("Loading memory from %s", itcmfile);
      $readmemh(itcmfile, `ITCM.mem_r);
    end else begin
      $display("No itcmfile provided");
    end

    if ($value$plusargs("dtcmfile=%s", dtcmfile)) begin
      $display("Loading memory from %s", dtcmfile);
      $readmemh(dtcmfile, `DTCM.mem_r);
    end else begin
      $display("No dtcmfile provided");
    end

    if ($value$plusargs("sv_timeout=%d", time_out))begin
        sv_timeout = time_out;
    end else begin
        sv_timeout = time_end;
    end
end



`ifndef VERILATOR_CC
	logic        clk;
	logic        rst_n;
`endif

	logic [31:0] perip_addr;
	logic        perip_wen;
	logic [3:0]  perip_mask;
	logic [31:0] perip_wdata;
	logic [31:0] perip_rdata;

    // 通用寄存器访问 - 仅用于错误信息显示
    wire [31:0] x3 = u_dut.u_ydrasil_registers.registers[3];
    // PC 监控
    wire [31:0] pc = u_dut.u_ydrasil_if_stage.pc_ff;
    // wire [31:0] csr_instret = u_dut.u_ydrasil_csr.minstret[31:0];
    wire [31:0] csr_cyclel = u_dut.u_ydrasil_registers_csr.cycle[31:0]; 

    integer           r;
    reg     [8*300:1] testcase;

    // 计算ITCM的深度和字节大小
    localparam ITCM_DEPTH = (1 << (`ITCM_ADDR_WIDTH));  // ITCM中的字数
    localparam ITCM_BYTE_SIZE = ITCM_DEPTH * 4;  // 总字节数

    // 创建与ITCM容量相同的临时字节数组
    reg [7:0] prog_mem[0:ITCM_BYTE_SIZE-1];
    integer i;

    // 添加PC监控变量
    reg [31:0] pc_write_to_host_cnt;
    reg [31:0] pc_write_to_host_cycle;
    wire  [31:0] cycle_count = csr_cyclel;
    reg pc_write_to_host_flag;
    reg [31:0] last_pc;

    // 添加指令计数和IPC计算相关变量
    reg [31:0] instruction_count ;//= csr_instret; // 直接使用CSR中的instret寄存器
    wire valid_instruction = (pc != last_pc);
    real ipc;

	ydrasil_core u_dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.perip_addr (perip_addr),
		.perip_wen  (perip_wen),
		.perip_mask (perip_mask),
		.perip_wdata(perip_wdata),
		.perip_rdata(perip_rdata)
	);
`ifndef VERILATOR_CC
	initial begin
		clk = 1'b0;
		forever #10 clk = ~clk;
	end

	initial begin
		rst_n = 1'b0;
		repeat (10) @(posedge clk);
		rst_n = 1'b1;
	end
`endif

	wire rst;
	assign rst = ~rst_n;

	always_ff @(posedge clk) begin
		if($time >= sv_timeout) begin
            $display("[TB] timeout reached, finish simulation");
            $finish;
        end
        if(LED > 0)
            $finish; 
	end

    // 周期计数器 - 保持同步实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instruction_count <= 32'b0;
            last_pc           <= 32'b0;
        end else begin
            last_pc     <= pc;
            if (valid_instruction) begin
                instruction_count <= instruction_count + 1;
            end
        end
    end

    // PC监控逻辑
    always @(pc) begin
        if (pc == `PC_WRITE_TOHOST && pc != last_pc) begin
            pc_write_to_host_cnt = pc_write_to_host_cnt + 1'b1;
            if (pc_write_to_host_flag == 1'b0) begin
                pc_write_to_host_cycle = cycle_count;
                pc_write_to_host_flag  = 1'b1;
            end
        end
    end

    // 添加异步复位逻辑
    always @(negedge rst_n) begin
        if (!rst_n) begin
            pc_write_to_host_cnt   = 32'b0;
            pc_write_to_host_flag  = 1'b0;
            pc_write_to_host_cycle = 32'b0;
        end
    end

    // 测试用例解析与ITCM加载
    initial begin
        if ($value$plusargs("itcm_init=%s", testcase)) begin
            display_testcase_name();
            $display("");

            $readmemh({testcase, ".verilog"}, prog_mem);
            for (i = 0; i < ITCM_DEPTH; i = i + 1) begin
                `ITCM.mem_r[i] = {prog_mem[i*4+3], prog_mem[i*4+2], prog_mem[i*4+1], prog_mem[i*4+0]};
            end
            $display("Successfully loaded instructions to ITCM");
            $display("ITCM 0x00: %h", `ITCM.mem_r[0]);
            $display("ITCM 0x01: %h", `ITCM.mem_r[1]);
            $display("ITCM 0x02: %h", `ITCM.mem_r[2]);
            $display("ITCM 0x03: %h", `ITCM.mem_r[3]);
            $display("ITCM 0x04: %h", `ITCM.mem_r[4]);
        end else begin
            $display("No itcm_init defined, use default ITCM init.");
        end
    end

	initial begin
		$monitor("[TB] time=%0t, rst_n=%b, LED=0x%08h, seg_wdata=0x%08h",
			$time, rst_n, LED, seg_wdata);
	end

	initial begin
		if(pc == 32'h800001b4) begin
			$display("PC = 0x800001b4,time = %0t", $time);
		end
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

    reg [31:0] mmio_rdata_reg;
    reg [31:0] back_rdata;
    always_ff @(posedge clk) begin
        mmio_rdata_reg <= back_rdata;
    end
    assign perip_rdata = mmio_rdata_reg;
    assign back_rdata = {32{perip_addr == SW0_ADDR}} & mmio_rdata |
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
        end else if (cnt_wen & perip_wdata == 32'h8000_0000) begin
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

    assign cnt_rdata = cnt_ms;

    // 对pc_write_to_host_cnt的变化进行监控
    always @(pc_write_to_host_cnt) begin
        if (pc_write_to_host_cnt == 32'd8) begin
            ipc = (instruction_count > 0 && cycle_count > 0) ? (instruction_count * 1.0) / cycle_count : 0.0;

            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~ Test Result Summary ~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $write("~TESTCASE: ");
            display_testcase_name();
            $display("~");
            $display("~~~~~~~~~~~~~~Total cycle_count value: %d ~~~~~~~~~~~~~", cycle_count);
            $display("~~~~~The test ending reached at cycle: %d ~~~~~~~~~~~~~", pc_write_to_host_cycle);
            $display("~~~~~~~~~~Total instructions executed: %d ~~~~~~~~~~~~~", instruction_count);
            $display("~~~~~~~~~~~~~~~~~~ IPC value: %.4f ~~~~~~~~~~~~~~~~~~", ipc);
            $display("~~~~~~~~~~~~~~~The final x3 Reg value: %d ~~~~~~~~~~~~~", x3);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

            if (x3 == 1) begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
                $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("fail testnum = %2d", x3);
                for (r = 0; r < 32; r = r + 1) $display("x%2d = 0x%x", r, u_dut.u_ydrasil_registers.registers[r]);
            end
            $display("PERF_METRIC: CYCLES=%-d INSTS=%-d IPC=%.4f", cycle_count, instruction_count, ipc);
            $finish;
        end
    end

    // 添加一个任务来显示处理过的testcase名称
    task automatic display_testcase_name;
        integer i;
        reg [7:0] ch;
        reg printing;

        printing = 0;
        for (i = 300; i >= 1; i = i - 1) begin
            ch = testcase[i*8-:8];
            if (!printing && ch != " " && ch != 8'h00 && ch != 8'h20) begin
                printing = 1;
            end
            if (printing && (ch == 8'h00 || ch == 8'h0A)) begin
                printing = 0;
                break;
            end
            if (printing && ch >= 8'h20) begin
                $write("%c", ch);
            end
        end
    endtask



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
