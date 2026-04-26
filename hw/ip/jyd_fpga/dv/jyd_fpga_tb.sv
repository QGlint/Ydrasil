`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:28:41 PM
// Design Name: 
// Module Name: tb_top
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

module jyd_fpga_tb;
    reg clk;

    reg serial_rx;          
    wire serial_tx;         
    
    reg got_tx;
    
    jyd_fpga uut (
        .i_sys_clk_p(clk),
        .i_sys_clk_n(~clk),
        .i_uart_rx(serial_rx),
        .o_uart_tx(serial_tx),
        .virtual_led(),  
        .virtual_seg()
    );
    

    //  clock 50MHz=2.5 20ns
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    initial begin
        serial_rx = 1;
        #200;
    end

    initial begin
        integer i;
        reg [7:0] tx_byte;

        #1000;

        $display("==== send 0x00 to uart_rx ====");
        tx_byte = 8'h00;

        // start bit
        serial_rx = 1'b0;
        #(104166);

        // data bits LSB first
        for (i = 0; i < 8; i = i + 1) begin
            serial_rx = tx_byte[i];
            #(104166);
        end

        // stop bit
        serial_rx = 1'b1;
        #(104166);

        got_tx = 1'b0;
        
        fork
            begin
                @(negedge serial_tx);
                got_tx = 1'b1;
            end
            begin
                #100000;
            end
        join

        if (got_tx) begin
            $display("ERROR: 0x00 should not have tx data?");
            $finish;
        end else begin
            $display("PASS: 0x00 instruction");
        end
           
        $finish;
    end

    initial begin
        #1000000000 $finish;
    end

    initial begin
        integer i_time;
        for(i_time = 0; i_time < 1000; i_time = i_time + 1) begin
            $display("time: %0t ns", $time);
            #1000000;
        end
    end


    initial begin
        `ifdef VERILATOR_SV
            $dumpfile("wave.vcd");
            $dumpvars(0, jyd_fpga_tb);
        `elsif VCS_FSDB
            $fsdbDumpfile("jyd_fpga_tb.fsdb");
            $fsdbDumpvars(0, jyd_fpga_tb, "+all");
        `elsif IVERILOG_VCD
            $dumpfile("wave.vcd");
            $dumpvars(0, jyd_fpga_tb);
        `endif
    end

endmodule

