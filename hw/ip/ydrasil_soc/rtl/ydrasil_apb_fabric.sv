module ydrasil_apb_fabric
import ydrasil_apb_pkg::*;
import ydrasil_soc_pkg::*;
(
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    output ydrasil_apb_req_pkt_t clint_req_o,
    input  ydrasil_apb_rsp_pkt_t clint_rsp_i,
    output ydrasil_apb_req_pkt_t plic_req_o,
    input  ydrasil_apb_rsp_pkt_t plic_rsp_i,
    output ydrasil_apb_req_pkt_t sysctrl_req_o,
    input  ydrasil_apb_rsp_pkt_t sysctrl_rsp_i,
    output ydrasil_apb_req_pkt_t gpio_req_o,
    input  ydrasil_apb_rsp_pkt_t gpio_rsp_i,
    output ydrasil_apb_req_pkt_t uart0_req_o,
    input  ydrasil_apb_rsp_pkt_t uart0_rsp_i,
    output ydrasil_apb_req_pkt_t uart1_req_o,
    input  ydrasil_apb_rsp_pkt_t uart1_rsp_i,
    output ydrasil_apb_req_pkt_t spi_req_o,
    input  ydrasil_apb_rsp_pkt_t spi_rsp_i,
    output ydrasil_apb_req_pkt_t i2c_req_o,
    input  ydrasil_apb_rsp_pkt_t i2c_rsp_i
);
    wire clint_sel = (apb_req_i.paddr[31:16] == CLINT_BASE[31:16]);
    wire plic_sel = (apb_req_i.paddr[31:16] == PLIC_BASE[31:16]);
    wire sysctrl_sel = (apb_req_i.paddr[31:12] == SYSCTRL_BASE[31:12]);
    wire gpio_sel = (apb_req_i.paddr[31:12] == GPIO_BASE[31:12]);
    wire uart0_sel = (apb_req_i.paddr[31:12] == UART0_BASE[31:12]);
    wire uart1_sel = (apb_req_i.paddr[31:12] == UART1_BASE[31:12]);
    wire spi_sel = (apb_req_i.paddr[31:12] == SPI0_BASE[31:12]);
    wire i2c_sel = (apb_req_i.paddr[31:12] == I2C0_BASE[31:12]);
    wire any_sel = clint_sel || plic_sel || sysctrl_sel || gpio_sel ||
        uart0_sel || uart1_sel || spi_sel || i2c_sel;

    always_comb begin
        clint_req_o = apb_req_i;
        plic_req_o = apb_req_i;
        sysctrl_req_o = apb_req_i;
        gpio_req_o = apb_req_i;
        uart0_req_o = apb_req_i;
        uart1_req_o = apb_req_i;
        spi_req_o = apb_req_i;
        i2c_req_o = apb_req_i;
        clint_req_o.psel = apb_req_i.psel && clint_sel;
        plic_req_o.psel = apb_req_i.psel && plic_sel;
        sysctrl_req_o.psel = apb_req_i.psel && sysctrl_sel;
        gpio_req_o.psel = apb_req_i.psel && gpio_sel;
        uart0_req_o.psel = apb_req_i.psel && uart0_sel;
        uart1_req_o.psel = apb_req_i.psel && uart1_sel;
        spi_req_o.psel = apb_req_i.psel && spi_sel;
        i2c_req_o.psel = apb_req_i.psel && i2c_sel;

        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        apb_rsp_o.pslverr = apb_req_i.psel && apb_req_i.penable && !any_sel;
        if (clint_sel)
            apb_rsp_o = clint_rsp_i;
        else if (plic_sel)
            apb_rsp_o = plic_rsp_i;
        else if (sysctrl_sel)
            apb_rsp_o = sysctrl_rsp_i;
        else if (gpio_sel)
            apb_rsp_o = gpio_rsp_i;
        else if (uart0_sel)
            apb_rsp_o = uart0_rsp_i;
        else if (uart1_sel)
            apb_rsp_o = uart1_rsp_i;
        else if (spi_sel)
            apb_rsp_o = spi_rsp_i;
        else if (i2c_sel)
            apb_rsp_o = i2c_rsp_i;
    end
endmodule
