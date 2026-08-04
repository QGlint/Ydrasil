# Official board constraints for the common ydrasil_soc top.
set_property PACKAGE_PIN AD12 [get_ports clk_in1_p]
set_property PACKAGE_PIN AD11 [get_ports clk_in1_n]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports {clk_in1_p clk_in1_n}]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]
set_input_jitter [get_clocks clk_in1_p] 0.050

set_property PACKAGE_PIN D18 [get_ports rs232_rx]
set_property PACKAGE_PIN D17 [get_ports rs232_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {rs232_rx rs232_tx}]

# GPIO1-10 is the UART1 group. GPIO3 carries the active-high UART reset.
set_property PACKAGE_PIN G17 [get_ports uart1_rx]
set_property PACKAGE_PIN G18 [get_ports uart1_tx]
set_property PACKAGE_PIN F17 [get_ports uart_rst]
set_property IOSTANDARD LVCMOS18 [get_ports {uart1_rx uart1_tx uart_rst}]

# GPIO11-20 is the SPI0 group.
set ydrasil_spi_ports [list spi_miso spi_sclk spi_mosi \
    {spi_cs_n[0]} {spi_cs_n[1]} {spi_cs_n[2]} {spi_cs_n[3]}]
set ydrasil_spi_pins [list C19 B19 B18 A18 A20 H21 C20]
for {set pin_index 0} {$pin_index < [llength $ydrasil_spi_ports]} {incr pin_index} {
    set spi_port [get_ports [lindex $ydrasil_spi_ports $pin_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_spi_pins $pin_index] $spi_port
    set_property IOSTANDARD LVCMOS18 $spi_port
}

# GPIO21-30 is the I2C0 group.
set_property PACKAGE_PIN K20 [get_ports i2c_scl]
set_property PACKAGE_PIN K19 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {i2c_scl i2c_sda}]

# GPIO31-39 provides nine software-controlled GPIO signals.
set ydrasil_gpio_pins [list A22 A21 C21 D21 C22 E21 D22 F21 F22]
for {set gpio_index 0} {$gpio_index < 9} {incr gpio_index} {
    set gpio_port [get_ports [format {gpio[%d]} $gpio_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_gpio_pins $gpio_index] $gpio_port
    set_property IOSTANDARD LVCMOS18 $gpio_port
}

set ydrasil_led_pins [list G24 E24 C24 E25 C26 F26 G25 E29]
for {set led_index 0} {$led_index < 8} {incr led_index} {
    set led_port [get_ports [format {led[%d]} $led_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_led_pins $led_index] $led_port
    set_property IOSTANDARD LVCMOS18 $led_port
}
