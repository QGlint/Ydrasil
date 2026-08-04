module ydrasil_soc (
    input  wire       clk_in1_p,
    input  wire       clk_in1_n,
    input  wire       rs232_rx,
    output wire       rs232_tx,
    output wire       uart_rst,
    input  wire       uart1_rx,
    output wire       uart1_tx,
    input  wire       spi_miso,
    output wire       spi_sclk,
    output wire       spi_mosi,
    output wire [3:0] spi_cs_n,
    inout  wire       i2c_scl,
    inout  wire       i2c_sda,
    inout  wire [8:0] gpio,
    output wire [7:0] led
);
    localparam int GPIO_COUNT = 9;

    wire cpu_clk;
    wire apb_clk;
    wire clock_locked;
    wire cpu_rst_n;
    wire apb_rst_n;
    wire [31:0] gpio_input;
    wire [31:0] gpio_output;
    wire [31:0] gpio_oe;
    wire i2c_scl_drive_low;
    wire i2c_sda_drive_low;
    wire coremark_active;

    ydrasil_clocking u_clocking (
        .clk_in1_p(clk_in1_p),
        .clk_in1_n(clk_in1_n),
        .apb_clk(apb_clk),
        .cpu_clk(cpu_clk),
        .locked(clock_locked)
    );

    ydrasil_reset_sync u_cpu_reset_sync (
        .clk_i(cpu_clk), .arst_n_i(clock_locked), .rst_n_o(cpu_rst_n)
    );

    ydrasil_reset_sync u_apb_reset_sync (
        .clk_i(apb_clk), .arst_n_i(clock_locked), .rst_n_o(apb_rst_n)
    );

    ydrasil_soc_core u_soc_core (
        .cpu_clk_i(cpu_clk), .cpu_rst_n_i(cpu_rst_n),
        .apb_clk_i(apb_clk), .apb_rst_n_i(apb_rst_n),
        .gpio_i(gpio_input), .gpio_o(gpio_output), .gpio_oe_o(gpio_oe),
        .uart0_rx_i(rs232_rx), .uart0_tx_o(rs232_tx),
        .uart1_rx_i(uart1_rx), .uart1_tx_o(uart1_tx),
        .spi_miso_i(spi_miso), .spi_sclk_o(spi_sclk),
        .spi_mosi_o(spi_mosi), .spi_cs_n_o(spi_cs_n),
        .i2c_scl_i(i2c_scl), .i2c_sda_i(i2c_sda),
        .i2c_scl_drive_low_o(i2c_scl_drive_low),
        .i2c_sda_drive_low_o(i2c_sda_drive_low),
        .coremark_active_o(coremark_active)
    );

    for (genvar gpio_index = 0; gpio_index < GPIO_COUNT;
         gpio_index = gpio_index + 1) begin : g_gpio
        assign gpio[gpio_index] = gpio_oe[gpio_index] ?
            gpio_output[gpio_index] : 1'bz;
        assign gpio_input[gpio_index] = gpio[gpio_index];
    end
    assign gpio_input[31:GPIO_COUNT] = '0;

    assign i2c_scl = i2c_scl_drive_low ? 1'b0 : 1'bz;
    assign i2c_sda = i2c_sda_drive_low ? 1'b0 : 1'bz;
    assign led = {gpio_output[7:1], gpio_output[0] | coremark_active};
    assign uart_rst = 1'b1;
endmodule
