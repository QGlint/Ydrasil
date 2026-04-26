`timescale 1ns / 1ns

module jyd_fpga_tb;

    logic clk;
    logic serial_rx;
    logic serial_tx;
    logic got_tx;
    logic [7:0] rx_data[0:17];
    integer j;

    // 常量定义，方便维护
    localparam CLK_PERIOD = 5; 
    localparam BIT_CYCLES = 20833; // 104166ns / 5ns
    localparam HALF_BIT_CYCLES = 10416;

    jyd_fpga uut (
        .i_sys_clk_p(clk),
        .i_sys_clk_n(~clk),
        .i_uart_rx(serial_rx),
        .o_uart_tx(serial_tx),
        .virtual_led(),
        .virtual_seg()
    );

    //================================================
    // clock: Verilator 支持这种基本的时钟生成
    //================================================
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk; 
    end

    //================================================
    // UART SEND (修改为基于时钟周期)
    //================================================
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            serial_rx = 0;
            repeat(BIT_CYCLES) @(posedge clk);

            // Data bits
            for(i = 0; i < 8; i = i + 1) begin
                serial_rx = data[i];
                repeat(BIT_CYCLES) @(posedge clk);
            end

            // Stop bit
            serial_rx = 1;
            repeat(BIT_CYCLES) @(posedge clk);
        end
    endtask

    //================================================
    // UART RECEIVE (修改为基于时钟周期)
    //================================================
    task uart_receive_byte(output [7:0] data);
        integer i;
        begin
            // 等待 start bit (检测下降沿或低电平)
            while (serial_tx == 1) begin
                @(posedge clk);
            end

            // 对齐到数据位的中心
            repeat(HALF_BIT_CYCLES) @(posedge clk); 

            for(i = 0; i < 8; i = i + 1) begin
                repeat(BIT_CYCLES) @(posedge clk);
                data[i] = serial_tx;
            end

            // 等待停止位周期结束
            repeat(BIT_CYCLES) @(posedge clk);
        end
    endtask

    //================================================
    // 等待 TX 或超时 (Verilator 支持命名块和 disable)
    //================================================
    task wait_tx_or_timeout(output logic got_tx);
        integer cycle;
        begin : wait_loop
            got_tx = 0;
            for (cycle = 0; cycle < 50000; cycle = cycle + 1) begin
                @(posedge clk);
                if (serial_tx == 0) begin
                    got_tx = 1;
                    disable wait_loop;
                end
            end
        end
    endtask

    //================================================
    // MAIN TEST
    //================================================
    initial begin

        serial_rx = 1;
        
        // 等待复位或稳定
        repeat(200) @(posedge clk);

        $display("==== send 0x00 to uart_rx ====");
        uart_send_byte(8'h00);

        wait_tx_or_timeout(got_tx);

        if (got_tx) begin
            $display("ERROR: 0x00 should not have tx data?");
            $finish;
        end else begin
            $display("PASS: 0x00 instruction");
        end

        $display("==== send 0x81 SW[0]=1 ====");
        uart_send_byte(8'b10000001);
        repeat(400) @(posedge clk);

        $display("==== send 0xa0 SW[31]=1 ====");
        uart_send_byte(8'b10100000); // 修正了你的原始位运算逻辑以提高可读性
        repeat(400) @(posedge clk);

        $display("==== send 0xc1 KEY[0]=1 ====");
        uart_send_byte(8'hC1);
        repeat(400) @(posedge clk);

        $display("==== send 0x80 read 18bit data ====");
        uart_send_byte(8'h80);

        for(j = 0; j < 18; j = j + 1) begin
            uart_receive_byte(rx_data[j]);
            $display("RX[%0d] = %02x", j, rx_data[j]);
        end

        // 简化的校验逻辑
        if(rx_data[5][0] !== 1'b1 || rx_data[6][0] != 1'b1 || rx_data[9][7] != 1'b1)
            $display("ERROR: Data mismatch in SW/KEY status");
        else
            $display("PASS: SW[0] KEY[0] SW[31] data correct");

        $finish;
    end

    // Watchdog
    initial begin
        // 增加足够长的周期防止意外退出
        repeat(1000) @(posedge clk);
        $display("TIMEOUT EXIT");
        $finish;
    end

    // 波形输出
    initial begin
        if ($test$plusargs("trace") != 0) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, jyd_fpga_tb);
        end
    end

endmodule