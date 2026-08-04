package ydrasil_soc_pkg;
    localparam logic [31:0] CLINT_BASE   = 32'h0200_0000;
    localparam logic [31:0] PLIC_BASE    = 32'h0c00_0000;
    localparam logic [31:0] SYSCTRL_BASE = 32'h4000_0000;
    localparam logic [31:0] GPIO_BASE    = 32'h4000_1000;
    localparam logic [31:0] UART0_BASE   = 32'h4000_2000;
    localparam logic [31:0] UART1_BASE   = 32'h4000_3000;
    localparam logic [31:0] SPI0_BASE    = 32'h4000_4000;
    localparam logic [31:0] I2C0_BASE    = 32'h4000_5000;

    localparam int IRQ_UART0 = 0;
    localparam int IRQ_UART1 = 1;
    localparam int IRQ_SPI0  = 2;
    localparam int IRQ_I2C0  = 3;
    localparam int IRQ_GPIO  = 4;
    localparam int IRQ_COUNT = 8;
endpackage
