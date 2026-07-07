# Vivado Batch Synthesis

Run from the repository root:

```sh
make syn
```

The Makefile uses `vivado -mode batch`, so no GUI is started. By default it keeps
the checked-in `FPGA/Ydrasil_FPGA.xpr` as the 150 MHz baseline, copies it to a
frequency-specific staged project, generates an ordered source Tcl from Bender,
and passes a synthesis define such as `SYN_PLL_FREQ_150` or `SYN_PLL_FREQ_200`.
The define selects the RTL MMCM parameters in `ydrasil_clocking.sv`; the legacy
`pll` clk_wiz IP is not used by the batch flow. Reports are written under
`build/syn/pll150m/reports`, and similar timing paths are grouped into
`timing_groups.csv` and `timing_groups.md`.

The route reports include general post-route timing plus CPU-clock focused
reports named by `SYN_PLL_FREQ_MHZ`:

- `cpu150_clocks.rpt`
- `cpu150_timing_summary.rpt`
- `cpu150_timing_paths.rpt`
- `synth_clocks.rpt`
- `post_route_clock_interaction.rpt`
- `post_route_check_timing.rpt`

For 200 MHz:

```sh
make synf
```

The 200 MHz staged project, reports, checkpoints, copied bitstream, and manifest
are kept under `build/syn/pll200m/`.

Useful overrides:

```sh
make syn SYN_JOBS=40
make syn-vivado SYN_PLL_FREQ_MHZ=200 SYN_RUN_TO=synth
make syn-vivado SYN_RUN_TO=synth
make syn-vivado SYN_RUN_TO=bitstream
make syn-analyze
```

Use `make syn-vivado SYN_SYNC_SOURCES=0` to run the existing project fileset
without syncing Bender-managed RTL into the xpr.

The source preprocessor keeps the FPGA-specific `hw/ip/Xilinx_ip_wrapper/rtl`
modules and drops Bender sources that define the same module names. This avoids
duplicate `itcm`, `dtcm`, and `ydrmem_1r1w_ram` definitions while still using
Bender ordering for the core RTL.
