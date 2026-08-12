# Official digital-twin board constraints for ydrasil_soc.
set_property PACKAGE_PIN AD12 [get_ports clk_in1_p]
set_property PACKAGE_PIN AD11 [get_ports clk_in1_n]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports {clk_in1_p clk_in1_n}]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]
set_input_jitter [get_clocks clk_in1_p] 0.050

set_property PACKAGE_PIN D18 [get_ports uart_rx]
set_property PACKAGE_PIN D17 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx uart_tx}]

# GPIO1-2: UART1. J
set_property PACKAGE_PIN G17 [get_ports uart1_rx]
set_property PACKAGE_PIN G18 [get_ports uart1_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart1_rx uart1_tx}]

# GPIO12-15: SSD1306 half-duplex SPI. CS is tied low on the display board.
set_property PACKAGE_PIN B19 [get_ports spi_sclk]
set_property PACKAGE_PIN B18 [get_ports spi_sdio]
set_property PACKAGE_PIN A18 [get_ports {gpio[1]}]
set_property PACKAGE_PIN A20 [get_ports {gpio[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sclk spi_sdio gpio[1] gpio[2]}]

# GPIO31 and GPIO34-39: remaining software-controlled GPIO.
set_property PACKAGE_PIN A22 [get_ports {gpio[0]}]
set_property PACKAGE_PIN D21 [get_ports {gpio[3]}]
set_property PACKAGE_PIN C22 [get_ports {gpio[4]}]
set_property PACKAGE_PIN E21 [get_ports {gpio[5]}]
set_property PACKAGE_PIN D22 [get_ports {gpio[6]}]
set_property PACKAGE_PIN F21 [get_ports {gpio[7]}]
set_property PACKAGE_PIN F22 [get_ports {gpio[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[0] gpio[3] gpio[4] gpio[5] gpio[6] gpio[7] gpio[8]}]

# The SoC uses the first eight LEDs from the original board mapping.
set_property PACKAGE_PIN G24 [get_ports {led[0]}]
set_property PACKAGE_PIN E24 [get_ports {led[1]}]
set_property PACKAGE_PIN C24 [get_ports {led[2]}]
set_property PACKAGE_PIN E25 [get_ports {led[3]}]
set_property PACKAGE_PIN C26 [get_ports {led[4]}]
set_property PACKAGE_PIN F26 [get_ports {led[5]}]
set_property PACKAGE_PIN G25 [get_ports {led[6]}]
set_property PACKAGE_PIN E29 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[0] led[1] led[2] led[3] led[4] led[5] led[6] led[7]}]
