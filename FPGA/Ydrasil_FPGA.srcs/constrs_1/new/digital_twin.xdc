# Timing-only constraints for the generic ydrasil_soc implementation target.
# Board pin assignments are intentionally supplied through an explicit board
# overlay: the checked-in legacy GPIO map mixes incompatible bank voltages for
# the newer SoC top and prevents placement before timing can be evaluated.
create_clock -period 5.000 -name clk_in1_p [get_ports clk_in1_p]
set_input_jitter [get_clocks clk_in1_p] 0.050
