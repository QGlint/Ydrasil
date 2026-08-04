# AG10/AH10 custom board constraints for ydrasil_soc.
set_property PACKAGE_PIN AG10 [get_ports clk_in1_p]
set_property PACKAGE_PIN AH10 [get_ports clk_in1_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {clk_in1_p clk_in1_n}]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]
set_input_jitter [get_clocks clk_in1_p] 0.050

set_property PACKAGE_PIN H12 [get_ports uart_rx]
set_property PACKAGE_PIN J12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx uart_tx}]

# GPIO1-2: UART1.
set_property PACKAGE_PIN A13 [get_ports uart1_rx]
set_property PACKAGE_PIN C14 [get_ports uart1_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart1_rx uart1_tx}]

# GPIO3-9: SPI0.
set_property PACKAGE_PIN B14 [get_ports spi_miso]
set_property PACKAGE_PIN G13 [get_ports spi_sclk]
set_property PACKAGE_PIN A15 [get_ports spi_mosi]
set_property PACKAGE_PIN B15 [get_ports {spi_cs_n[0]}]
set_property PACKAGE_PIN C15 [get_ports {spi_cs_n[1]}]
set_property PACKAGE_PIN E15 [get_ports {spi_cs_n[2]}]
set_property PACKAGE_PIN F15 [get_ports {spi_cs_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_miso spi_sclk spi_mosi spi_cs_n[0] spi_cs_n[1] spi_cs_n[2] spi_cs_n[3]}]

# GPIO10-11: I2C0.
set_property PACKAGE_PIN E16 [get_ports i2c_scl]
set_property PACKAGE_PIN F16 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS33 [get_ports {i2c_scl i2c_sda}]

# GPIO12-20: nine software-controlled GPIO signals.
set_property PACKAGE_PIN G15 [get_ports {gpio[0]}]
set_property PACKAGE_PIN H15 [get_ports {gpio[1]}]
set_property PACKAGE_PIN H16 [get_ports {gpio[2]}]
set_property PACKAGE_PIN J16 [get_ports {gpio[3]}]
set_property PACKAGE_PIN J14 [get_ports {gpio[4]}]
set_property PACKAGE_PIN K16 [get_ports {gpio[5]}]
set_property PACKAGE_PIN K15 [get_ports {gpio[6]}]
set_property PACKAGE_PIN L16 [get_ports {gpio[7]}]
set_property PACKAGE_PIN L15 [get_ports {gpio[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[0] gpio[1] gpio[2] gpio[3] gpio[4] gpio[5] gpio[6] gpio[7] gpio[8]}]

# Dedicated LEDs.
set_property PACKAGE_PIN B12 [get_ports {led[0]}]
set_property PACKAGE_PIN A12 [get_ports {led[1]}]
set_property PACKAGE_PIN D13 [get_ports {led[2]}]
set_property PACKAGE_PIN B13 [get_ports {led[3]}]
set_property PACKAGE_PIN D11 [get_ports {led[4]}]
set_property PACKAGE_PIN C11 [get_ports {led[5]}]
set_property PACKAGE_PIN A11 [get_ports {led[6]}]
set_property PACKAGE_PIN C12 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0] led[1] led[2] led[3] led[4] led[5] led[6] led[7]}]
