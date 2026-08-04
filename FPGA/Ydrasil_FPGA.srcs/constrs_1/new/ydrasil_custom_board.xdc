# Custom board constraints for the common ydrasil_soc top.
set_property PACKAGE_PIN AG10 [get_ports clk_in1_p]
set_property PACKAGE_PIN AH10 [get_ports clk_in1_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {clk_in1_p clk_in1_n}]
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]
set_input_jitter [get_clocks clk_in1_p] 0.050

set_property PACKAGE_PIN H12 [get_ports rs232_rx]
set_property PACKAGE_PIN J12 [get_ports rs232_tx]
set_property PACKAGE_PIN J13 [get_ports uart_rst]
set_property IOSTANDARD LVCMOS33 [get_ports {rs232_rx rs232_tx uart_rst}]

# GPIO1-2: UART1. GPIO3-9: SPI0. GPIO10-11: I2C0.
set ydrasil_peripheral_ports [list uart1_rx uart1_tx spi_miso spi_sclk \
    spi_mosi {spi_cs_n[0]} {spi_cs_n[1]} {spi_cs_n[2]} {spi_cs_n[3]} \
    i2c_scl i2c_sda]
set ydrasil_peripheral_pins [list A13 C14 B14 G13 A15 B15 C15 E15 F15 E16 F16]
for {set pin_index 0} {$pin_index < [llength $ydrasil_peripheral_ports]} {incr pin_index} {
    set peripheral_port [get_ports [lindex $ydrasil_peripheral_ports $pin_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_peripheral_pins $pin_index] $peripheral_port
    set_property IOSTANDARD LVCMOS33 $peripheral_port
}

# GPIO12-20: nine software-controlled GPIO signals.
set ydrasil_gpio_pins [list G15 H15 H16 J16 J14 K16 K15 L16 L15]
for {set gpio_index 0} {$gpio_index < 9} {incr gpio_index} {
    set gpio_port [get_ports [format {gpio[%d]} $gpio_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_gpio_pins $gpio_index] $gpio_port
    set_property IOSTANDARD LVCMOS33 $gpio_port
}

# Eight dedicated custom-board LEDs.
set ydrasil_led_pins [list B12 A12 D13 B13 D11 C11 A11 C12]
for {set led_index 0} {$led_index < 8} {incr led_index} {
    set led_port [get_ports [format {led[%d]} $led_index]]
    set_property PACKAGE_PIN [lindex $ydrasil_led_pins $led_index] $led_port
    set_property IOSTANDARD LVCMOS33 $led_port
}
