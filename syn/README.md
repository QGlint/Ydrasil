# Vivado Batch Synthesis

Run from the repository root:

```sh
make syn
```

The Makefile uses `vivado -mode batch`, so no GUI is started. By default it creates
`build/syn/.venv`, generates an ordered source Tcl from Bender, runs synthesis and
implementation through `route_design`, writes Vivado reports under
`build/syn/reports`, and groups similar timing paths into `timing_groups.csv` and
`timing_groups.md`.

The route reports include general post-route timing plus 150 MHz CPU-clock
focused reports:

- `cpu150_clocks.rpt`
- `cpu150_timing_summary.rpt`
- `cpu150_timing_paths.rpt`
- `post_route_clock_interaction.rpt`
- `post_route_check_timing.rpt`

Useful overrides:

```sh
make syn SYN_JOBS=40
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
