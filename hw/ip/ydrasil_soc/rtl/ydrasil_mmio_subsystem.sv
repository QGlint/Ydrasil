module ydrasil_mmio_subsystem
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
import ydrasil_apb_pkg::*;
import ydrasil_soc_pkg::*;
#(
    parameter int UART0_BIT_PERIOD_OVERRIDE = 0
)
(
    input  wire                       axi_clk_i,
    input  wire                       axi_rst_n_i,
    input  wire                       apb_clk_i,
    input  wire                       apb_rst_n_i,
    input  ydrasil_axi_lite_m2s_pkt_t axi_m2s_i,
    output ydrasil_axi_lite_s2m_pkt_t axi_s2m_o,
    output ydrasil_irq_pkt_t          irq_o,
    input  wire                       coremark_active_async_i,
    input  wire [63:0]                coremark_cycles_async_i,
    output wire                       coremark_start_toggle_o,
    output wire                       coremark_stop_toggle_o,
    output wire                       coremark_auto_enable_o,
    output wire [31:0]                coremark_pc_base_o,
    output wire [31:0]                coremark_pc_limit_o,
    output wire [31:0]                coremark_timeout_o,
    input  wire [31:0]                gpio_i,
    output wire [31:0]                gpio_o,
    output wire [31:0]                gpio_oe_o,
    input  wire                       uart0_rx_i,
    output wire                       uart0_tx_o,
    input  wire                       uart1_rx_i,
    output wire                       uart1_tx_o,
    input  wire                       spi_sdio_i,
    output wire                       spi_sclk_o,
    output wire                       spi_sdio_o,
    output wire                       spi_sdio_oe_o,
    output wire [3:0]                 spi_cs_n_o,
    input  wire                       i2c_scl_i,
    input  wire                       i2c_sda_i,
    output wire                       i2c_scl_drive_low_o,
    output wire                       i2c_sda_drive_low_o
);
    ydrasil_apb_req_pkt_t apb_req;
    ydrasil_apb_rsp_pkt_t apb_rsp;
    ydrasil_apb_req_pkt_t clint_req;
    ydrasil_apb_rsp_pkt_t clint_rsp;
    ydrasil_apb_req_pkt_t plic_req;
    ydrasil_apb_rsp_pkt_t plic_rsp;
    ydrasil_apb_req_pkt_t sysctrl_req;
    ydrasil_apb_rsp_pkt_t sysctrl_rsp;
    ydrasil_apb_req_pkt_t gpio_req;
    ydrasil_apb_rsp_pkt_t gpio_rsp;
    ydrasil_apb_req_pkt_t uart0_req;
    ydrasil_apb_rsp_pkt_t uart0_rsp;
    ydrasil_apb_req_pkt_t uart1_req;
    ydrasil_apb_rsp_pkt_t uart1_rsp;
    ydrasil_apb_req_pkt_t spi_req;
    ydrasil_apb_rsp_pkt_t spi_rsp;
    ydrasil_apb_req_pkt_t i2c_req;
    ydrasil_apb_rsp_pkt_t i2c_rsp;

    wire software_irq;
    wire timer_irq;
    wire external_irq;
    wire gpio_irq;
    wire uart0_irq;
    wire uart1_irq;
    wire spi_irq;
    wire i2c_irq;
    wire [IRQ_COUNT-1:0] plic_sources = {
        3'b000, gpio_irq, i2c_irq, spi_irq, uart1_irq, uart0_irq};
    wire [2:0] irq_apb = {external_irq, timer_irq, software_irq};
    wire [2:0] irq_axi;
    wire [64:0] coremark_status_apb;

    ydrasil_axi_to_apb u_axi_to_apb (
        .axi_clk_i(axi_clk_i),
        .axi_rst_n_i(axi_rst_n_i),
        .axi_m2s_i(axi_m2s_i),
        .axi_s2m_o(axi_s2m_o),
        .apb_clk_i(apb_clk_i),
        .apb_rst_n_i(apb_rst_n_i),
        .apb_req_o(apb_req),
        .apb_rsp_i(apb_rsp)
    );

    ydrasil_apb_fabric u_apb_fabric (
        .apb_req_i(apb_req),
        .apb_rsp_o(apb_rsp),
        .clint_req_o(clint_req), .clint_rsp_i(clint_rsp),
        .plic_req_o(plic_req), .plic_rsp_i(plic_rsp),
        .sysctrl_req_o(sysctrl_req), .sysctrl_rsp_i(sysctrl_rsp),
        .gpio_req_o(gpio_req), .gpio_rsp_i(gpio_rsp),
        .uart0_req_o(uart0_req), .uart0_rsp_i(uart0_rsp),
        .uart1_req_o(uart1_req), .uart1_rsp_i(uart1_rsp),
        .spi_req_o(spi_req), .spi_rsp_i(spi_rsp),
        .i2c_req_o(i2c_req), .i2c_rsp_i(i2c_rsp)
    );

    ydrasil_clint u_clint (
        .clk(apb_clk_i),
        .rst_n(apb_rst_n_i),
        .apb_req_i(clint_req),
        .apb_rsp_o(clint_rsp),
        .software_irq_o(software_irq),
        .timer_irq_o(timer_irq)
    );

    ydrasil_plic #(.NUM_SOURCES(IRQ_COUNT)) u_plic (
        .clk(apb_clk_i),
        .rst_n(apb_rst_n_i),
        .apb_req_i(plic_req),
        .apb_rsp_o(plic_rsp),
        .source_i(plic_sources),
        .irq_o(external_irq)
    );

    ydrasil_cdc_sync #(.WIDTH(65)) u_coremark_status_sync (
        .clk_i(apb_clk_i),
        .rst_n_i(apb_rst_n_i),
        .async_i({coremark_active_async_i, coremark_cycles_async_i}),
        .sync_o(coremark_status_apb)
    );

    ydrasil_apb_sysctrl u_sysctrl (
        .clk(apb_clk_i),
        .rst_n(apb_rst_n_i),
        .apb_req_i(sysctrl_req),
        .apb_rsp_o(sysctrl_rsp),
        .coremark_active_i(coremark_status_apb[64]),
        .coremark_cycles_i(coremark_status_apb[63:0]),
        .coremark_start_toggle_o(coremark_start_toggle_o),
        .coremark_stop_toggle_o(coremark_stop_toggle_o),
        .coremark_auto_enable_o(coremark_auto_enable_o),
        .coremark_pc_base_o(coremark_pc_base_o),
        .coremark_pc_limit_o(coremark_pc_limit_o),
        .coremark_timeout_o(coremark_timeout_o)
    );

    ydrasil_apb_gpio u_gpio (
        .clk(apb_clk_i),
        .rst_n(apb_rst_n_i),
        .apb_req_i(gpio_req),
        .apb_rsp_o(gpio_rsp),
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),
        .irq_o(gpio_irq)
    );

    ydrasil_apb_uart #(
        .BIT_PERIOD_OVERRIDE(UART0_BIT_PERIOD_OVERRIDE)
    ) u_uart0 (
        .clk(apb_clk_i), .rst_n(apb_rst_n_i),
        .apb_req_i(uart0_req), .apb_rsp_o(uart0_rsp),
        .rx_i(uart0_rx_i), .tx_o(uart0_tx_o), .irq_o(uart0_irq)
    );

    ydrasil_apb_uart u_uart1 (
        .clk(apb_clk_i), .rst_n(apb_rst_n_i),
        .apb_req_i(uart1_req), .apb_rsp_o(uart1_rsp),
        .rx_i(uart1_rx_i), .tx_o(uart1_tx_o), .irq_o(uart1_irq)
    );

    ydrasil_apb_spi #(.NUM_CS(4)) u_spi0 (
        .clk(apb_clk_i), .rst_n(apb_rst_n_i),
        .apb_req_i(spi_req), .apb_rsp_o(spi_rsp),
        .sdio_i(spi_sdio_i), .sclk_o(spi_sclk_o),
        .sdio_o(spi_sdio_o), .sdio_oe_o(spi_sdio_oe_o),
        .cs_n_o(spi_cs_n_o), .irq_o(spi_irq)
    );

    ydrasil_apb_i2c u_i2c0 (
        .clk(apb_clk_i), .rst_n(apb_rst_n_i),
        .apb_req_i(i2c_req), .apb_rsp_o(i2c_rsp),
        .scl_i(i2c_scl_i), .sda_i(i2c_sda_i),
        .scl_drive_low_o(i2c_scl_drive_low_o),
        .sda_drive_low_o(i2c_sda_drive_low_o), .irq_o(i2c_irq)
    );

    ydrasil_cdc_sync #(.WIDTH(3)) u_irq_sync (
        .clk_i(axi_clk_i),
        .rst_n_i(axi_rst_n_i),
        .async_i(irq_apb),
        .sync_o(irq_axi)
    );

    assign irq_o.software = irq_axi[0];
    assign irq_o.timer = irq_axi[1];
    assign irq_o.external = irq_axi[2];
endmodule
