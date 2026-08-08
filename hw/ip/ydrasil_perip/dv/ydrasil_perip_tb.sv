module ydrasil_perip_tb;
    import ydrasil_apb_pkg::*;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    ydrasil_apb_req_pkt_t apb_req;
    ydrasil_apb_rsp_pkt_t sysctrl_rsp;
    ydrasil_apb_rsp_pkt_t gpio_rsp;
    ydrasil_apb_rsp_pkt_t uart_rsp;
    ydrasil_apb_rsp_pkt_t spi_rsp;
    ydrasil_apb_rsp_pkt_t i2c_rsp;
    ydrasil_apb_rsp_pkt_t plic_rsp;

    logic [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;
    wire gpio_irq;
    wire uart_tx;
    wire uart_irq;
    wire spi_sclk;
    wire spi_sdio_out;
    wire spi_sdio_oe;
    wire [3:0] spi_cs_n;
    logic spi_sdio_in;
    wire i2c_scl_low;
    wire i2c_sda_low;
    wire i2c_irq;
    wire i2c_scl = i2c_scl_low ? 1'b0 : 1'b1;
    wire i2c_sda = i2c_sda_low ? 1'b0 : 1'b1;
    logic [7:0] plic_sources;
    wire plic_irq;
    wire coremark_start_toggle;
    wire coremark_stop_toggle;
    wire coremark_auto_enable;
    wire [31:0] coremark_pc_base;
    wire [31:0] coremark_pc_limit;
    wire [31:0] coremark_timeout;

    always #5 clk = ~clk;

    ydrasil_apb_sysctrl u_sysctrl (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(sysctrl_rsp), .coremark_active_i(1'b0),
        .coremark_cycles_i(64'h1234_5678_9abc_def0),
        .coremark_start_toggle_o(coremark_start_toggle),
        .coremark_stop_toggle_o(coremark_stop_toggle),
        .coremark_auto_enable_o(coremark_auto_enable),
        .coremark_pc_base_o(coremark_pc_base),
        .coremark_pc_limit_o(coremark_pc_limit),
        .coremark_timeout_o(coremark_timeout)
    );

    ydrasil_apb_gpio u_gpio (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(gpio_rsp), .gpio_i(gpio_i), .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe), .irq_o(gpio_irq)
    );

    ydrasil_apb_uart #(
        .CLOCK_FREQ_HZ(1000000), .RESET_BAUD(250000)
    ) u_uart (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(uart_rsp), .rx_i(uart_tx), .tx_o(uart_tx),
        .irq_o(uart_irq)
    );

    ydrasil_apb_spi u_spi (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(spi_rsp), .sdio_i(spi_sdio_in), .sclk_o(spi_sclk),
        .sdio_o(spi_sdio_out), .sdio_oe_o(spi_sdio_oe),
        .cs_n_o(spi_cs_n), .irq_o()
    );

    ydrasil_apb_i2c u_i2c (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(i2c_rsp), .scl_i(i2c_scl), .sda_i(i2c_sda),
        .scl_drive_low_o(i2c_scl_low),
        .sda_drive_low_o(i2c_sda_low), .irq_o(i2c_irq)
    );

    ydrasil_plic u_plic (
        .clk(clk), .rst_n(rst_n), .apb_req_i(apb_req),
        .apb_rsp_o(plic_rsp), .source_i(plic_sources), .irq_o(plic_irq)
    );

    task automatic reset_dut;
        begin
            apb_req = '0;
            gpio_i = '0;
            spi_sdio_in = 1'b1;
            plic_sources = '0;
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic apb_write(input logic [31:0] address,
                             input logic [31:0] data);
        begin
            @(negedge clk);
            apb_req.psel = 1'b1;
            apb_req.penable = 1'b0;
            apb_req.pwrite = 1'b1;
            apb_req.paddr = address;
            apb_req.pwdata = data;
            apb_req.pstrb = 4'hf;
            @(negedge clk);
            apb_req.penable = 1'b1;
            @(negedge clk);
            apb_req = '0;
        end
    endtask

    task automatic apb_read(input logic [31:0] address,
                            input int response_select,
                            output logic [31:0] data);
        begin
            @(negedge clk);
            apb_req.psel = 1'b1;
            apb_req.penable = 1'b0;
            apb_req.pwrite = 1'b0;
            apb_req.paddr = address;
            @(negedge clk);
            apb_req.penable = 1'b1;
            #4;
            unique case (response_select)
                0: data = sysctrl_rsp.prdata;
                1: data = gpio_rsp.prdata;
                2: data = uart_rsp.prdata;
                3: data = spi_rsp.prdata;
                4: data = i2c_rsp.prdata;
                5: data = plic_rsp.prdata;
                default: data = 'x;
            endcase
            @(posedge clk);
            @(negedge clk);
            apb_req = '0;
        end
    endtask

    task automatic expect_equal(input logic [31:0] actual,
                                input logic [31:0] expected,
                                input string label_text);
        begin
            if (actual !== expected)
                $fatal(1, "%s: expected %08x, got %08x",
                    label_text, expected, actual);
        end
    endtask

    initial begin : test_sequence
        logic [31:0] value;
        int timeout_count;

        reset_dut();
        apb_write(32'h0000_0000, 32'h0000_00a5);
        apb_write(32'h0000_0008, 32'h0000_005a);
        expect_equal(gpio_oe, 32'h0000_00a5, "GPIO direction");
        expect_equal(gpio_o, 32'h0000_005a, "GPIO output");
        gpio_i = 32'h1357_2468;
        repeat (3) @(posedge clk);
        apb_read(32'h0000_0004, 1, value);
        expect_equal(value, 32'h1357_2468, "GPIO synchronized input");
        gpio_i = '0;
        repeat (3) @(posedge clk);
        apb_write(32'h0000_000c, 32'h0000_0001);
        apb_write(32'h0000_0010, 32'h0000_0000);
        apb_write(32'h0000_0014, 32'h0000_0001);
        gpio_i[0] = 1'b1;
        repeat (4) @(posedge clk);
        if (!gpio_irq)
            $fatal(1, "GPIO rising-edge interrupt did not assert");
        apb_write(32'h0000_0018, 32'h0000_0001);

        reset_dut();
        apb_write(32'h0000_000c, 32'h0000_0080);
        apb_write(32'h0000_0000, 32'h0000_0004);
        apb_write(32'h0000_0004, 32'h0000_0000);
        apb_write(32'h0000_000c, 32'h0000_0003);
        apb_write(32'h0000_0008, 32'h0000_0006);
        apb_write(32'h0000_0004, 32'h0000_0001);
        apb_write(32'h0000_0000, 32'h0000_00a5);
        timeout_count = 0;
        value = '0;
        while (!value[0] && (timeout_count < 200)) begin
            apb_read(32'h0000_0014, 2, value);
            timeout_count++;
        end
        if (!value[0] || !uart_irq)
            $fatal(1, "UART loopback receive timed out");
        apb_read(32'h0000_0000, 2, value);
        expect_equal({24'h0, value[7:0]}, 32'h0000_00a5,
            "UART loopback byte");

        reset_dut();
        apb_write(32'h0000_0004, 32'h0000_0000);
        apb_write(32'h0000_0010, 32'h0008_0000);
        apb_write(32'h0000_0000, 32'h0000_0101);
        repeat (2) @(posedge clk);
        if (spi_sdio_oe)
            $fatal(1, "SPI SDIO must be released during read data");
        timeout_count = 0;
        value = '0;
        while ((value[23:16] == 0) && (timeout_count < 100)) begin
            apb_read(32'h0000_0000, 3, value);
            timeout_count++;
        end
        if (value[23:16] != 1)
            $fatal(1, "SPI 8-bit receive did not fill RX FIFO");
        apb_read(32'h0000_0020, 3, value);
        expect_equal(value, 32'h0000_00ff, "SPI short-word alignment");

        reset_dut();
        apb_write(32'h0000_0004, 32'h0000_0000);
        apb_write(32'h0000_0010, 32'h0008_0000);
        apb_write(32'h0000_0018, 32'ha500_0000);
        apb_write(32'h0000_0000, 32'h0000_0002);
        repeat (2) @(posedge clk);
        if (!spi_sdio_oe)
            $fatal(1, "SPI SDIO must be driven during write data");
        timeout_count = 0;
        value = '0;
        while (!value[0] && (timeout_count < 100)) begin
            apb_read(32'h0000_0000, 3, value);
            timeout_count++;
        end
        if (!value[0] || spi_sdio_oe)
            $fatal(1, "SPI write did not finish with SDIO released");

        reset_dut();
        apb_write(32'h0000_0000, 32'h0000_0001);
        apb_write(32'h0000_0004, 32'h0000_00c0);
        apb_write(32'h0000_0010, 32'h0000_00a0);
        apb_write(32'h0000_0014, 32'h0000_00d0);
        timeout_count = 0;
        value = 32'h0000_0002;
        while (value[1] && (timeout_count < 300)) begin
            apb_read(32'h0000_000c, 4, value);
            timeout_count++;
        end
        if (value[1] || !value[7] || !i2c_irq)
            $fatal(1, "I2C no-ACK transaction status is invalid: %02x", value[7:0]);
        apb_write(32'h0000_0014, 32'h0000_0001);

        reset_dut();
        apb_write(32'h0000_0004, 32'h0000_0001);
        plic_sources[0] = 1'b1;
        repeat (2) @(posedge clk);
        if (!plic_irq)
            $fatal(1, "PLIC interrupt did not assert");
        plic_sources[0] = 1'b0;
        apb_read(32'h0000_0008, 5, value);
        expect_equal(value, 32'h0000_0001, "PLIC claim ID");
        repeat (2) @(posedge clk);
        if (plic_irq)
            $fatal(1, "PLIC interrupt did not clear after claim");

        reset_dut();
        apb_write(32'h0000_0018, 32'h8000_1000);
        apb_write(32'h0000_001c, 32'h8000_2000);
        apb_write(32'h0000_0020, 32'h0000_0400);
        apb_write(32'h0000_0010, 32'h0000_0005);
        if (!coremark_start_toggle || !coremark_auto_enable)
            $fatal(1, "SYSCTRL CoreMark start controls did not update");
        expect_equal(coremark_pc_base, 32'h8000_1000, "CoreMark PC base");
        expect_equal(coremark_pc_limit, 32'h8000_2000, "CoreMark PC limit");
        expect_equal(coremark_timeout, 32'h0000_0400, "CoreMark timeout");
        apb_write(32'h0000_0010, 32'h0000_0002);
        if (!coremark_stop_toggle || coremark_auto_enable)
            $fatal(1, "SYSCTRL CoreMark stop controls did not update");

        $display("YDRASIL_PERIP_TB PASS");
        $finish;
    end
endmodule
