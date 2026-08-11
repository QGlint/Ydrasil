module ydrasil_soc_core
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
#(
    parameter int UART0_BIT_PERIOD_OVERRIDE = 0
)
(
    input  wire        cpu_clk_i,
    input  wire        cpu_rst_n_i,
    input  wire        apb_clk_i,
    input  wire        apb_rst_n_i,
    input  wire [31:0] gpio_i,
    output wire [31:0] gpio_o,
    output wire [31:0] gpio_oe_o,
    input  wire        uart0_rx_i,
    output wire        uart0_tx_o,
    input  wire        uart1_rx_i,
    output wire        uart1_tx_o,
    input  wire        spi_sdio_i,
    output wire        spi_sclk_o,
    output wire        spi_sdio_o,
    output wire        spi_sdio_oe_o,
    output wire [3:0]  spi_cs_n_o,
    input  wire        i2c_scl_i,
    input  wire        i2c_sda_i,
    output wire        i2c_scl_drive_low_o,
    output wire        i2c_sda_drive_low_o,
    output wire        coremark_active_o
);
    ydrasil_axi_lite_m2s_pkt_t axi_m2s;
    ydrasil_axi_lite_s2m_pkt_t axi_s2m;
    ydrasil_irq_pkt_t irq;
    wire coremark_start_toggle;
    wire coremark_stop_toggle;
    wire [63:0] coremark_cycles;
`ifdef YDRASIL_RETIRE_TRACE
    wire retire0_valid;
    wire [31:0] retire0_pc;
    wire retire1_valid;
    wire [31:0] retire1_pc;
`endif

    ydrasil_core u_core (
        .clk(cpu_clk_i),
        .rst_n(cpu_rst_n_i),
        .axi_m2s_o(axi_m2s),
        .axi_s2m_i(axi_s2m),
        .irq_i(irq)
`ifdef YDRASIL_RETIRE_TRACE
        ,
        .retire0_valid_o(retire0_valid),
        .retire0_pc_o(retire0_pc),
        .retire1_valid_o(retire1_valid),
        .retire1_pc_o(retire1_pc)
`endif
    );

    ydrasil_mmio_subsystem #(
        .UART0_BIT_PERIOD_OVERRIDE(UART0_BIT_PERIOD_OVERRIDE)
    ) u_mmio (
        .axi_clk_i(cpu_clk_i), .axi_rst_n_i(cpu_rst_n_i),
        .apb_clk_i(apb_clk_i), .apb_rst_n_i(apb_rst_n_i),
        .axi_m2s_i(axi_m2s), .axi_s2m_o(axi_s2m), .irq_o(irq),
        .coremark_active_async_i(coremark_active_o),
        .coremark_cycles_async_i(coremark_cycles),
        .coremark_start_toggle_o(coremark_start_toggle),
        .coremark_stop_toggle_o(coremark_stop_toggle),
        .coremark_auto_enable_o(),
        .coremark_pc_base_o(),
        .coremark_pc_limit_o(),
        .coremark_timeout_o(),
        .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe_o(gpio_oe_o),
        .uart0_rx_i(uart0_rx_i), .uart0_tx_o(uart0_tx_o),
        .uart1_rx_i(uart1_rx_i), .uart1_tx_o(uart1_tx_o),
        .spi_sdio_i(spi_sdio_i), .spi_sclk_o(spi_sclk_o),
        .spi_sdio_o(spi_sdio_o), .spi_sdio_oe_o(spi_sdio_oe_o),
        .spi_cs_n_o(spi_cs_n_o),
        .i2c_scl_i(i2c_scl_i), .i2c_sda_i(i2c_sda_i),
        .i2c_scl_drive_low_o(i2c_scl_drive_low_o),
        .i2c_sda_drive_low_o(i2c_sda_drive_low_o)
    );

    ydrasil_coremark_monitor u_coremark_monitor (
        .cpu_clk_i(cpu_clk_i), .cpu_rst_n_i(cpu_rst_n_i),
        .start_toggle_async_i(coremark_start_toggle),
        .stop_toggle_async_i(coremark_stop_toggle),
        .active_o(coremark_active_o), .cycles_o(coremark_cycles)
    );
endmodule
