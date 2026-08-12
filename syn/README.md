# Vivado Batch Synthesis

Run from the repository root:

```sh
make syn
```

The Makefile uses `vivado -mode batch`, so no GUI is started. On `servera437`,
the default flow synthesizes once and launches one 16-thread implementation run.
Set `SYN_WAY=full` to launch the first three strategies in parallel with 13
threads per run. The run with the highest WNS supplies the final reports,
checkpoint, and artifacts. Other hosts default to one implementation run. The
flow keeps
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
- `cpu150_timing_violations.rpt`
- `synth_clocks.rpt`
- `post_route_timing_summary.rpt`
- `post_route_timing_violations.rpt`

For 200 MHz:

```sh
make synf
```

The 200 MHz staged project, reports, checkpoints, copied bitstream, and manifest
are kept under `build/syn/pll200m/`.

Useful overrides:

```sh
make syn SYN_WAY=full
make synf SYN_WAY=full
make synf SYN_WAY=2
make synf SYN_WAY=4
make syn-extreme
make syn-vivado SYN_PLL_FREQ_MHZ=200 SYN_RUN_TO=synth
make syn-vivado SYN_RUN_TO=synth
make syn-vivado SYN_RUN_TO=bitstream
make syn-analyze
make synf SYN_FULL_REPORTS=1
make synf SYN_POST_ROUTE_PHYSOPT=1
```

The default bitstream flow uses a fast closeout: it reuses each implementation
run's recorded WNS and generated bitstream, writes the reports needed by timing
analysis, and skips repeated post-route physical optimization and extended
diagnostic reports. `SYN_FULL_REPORTS=1` restores clock-interaction, timing
checks, DRC, methodology, design-analysis, QoR, and CPU timing-summary reports.
Set `SYN_POST_ROUTE_PHYSOPT=1` to explicitly run one additional
`AggressiveExplore` pass and regenerate the selected bitstream.

The sweep's `Performance_ExplorePostRoutePhysOpt` step is disabled by default
because Vivado 2024.2 has a reproducible post-route `phys_opt_design` crash in
`libxv_power.so` on this design. Use `SYN_SWEEP_POST_ROUTE_PHYSOPT=1` only when
testing a Vivado update or a workaround. A failed implementation child is
reported and ignored so completed sweep runs can still produce the final
reports and artifacts.

`SYN_WAY` selects the implementation strategy: `0` (the default) is
`Performance_Explore`, `1` is `Performance_ExplorePostRoutePhysOpt`, `2` is
`Performance_NetDelay_high`, `3` is `Performance_ExploreWithRemap`, and `4`
uses the extreme per-step directives. `SYN_WAY=full` runs ways `0`, `1`, and `2`
in parallel; way `3` remains manual-only. `Performance_ExtraTimingOpt`,
`Performance_Retiming`, and `Performance_RefinePlacement` remain disabled
candidates. The log prints synthesis and implementation run times, followed by
the total Vivado flow time as its final line.

`make syn-extreme` runs only `impl_1` with the aggressive per-step directives
stored in the checked-in GUI project. Sweep results are recorded in
`implementation_sweep.csv`, `implementation_sweep.md`, and
`best_implementation.txt`.

Use `make syn-vivado SYN_SYNC_SOURCES=0` to run the existing project fileset
without syncing Bender-managed RTL into the xpr.

The source preprocessor keeps the FPGA-specific `hw/ip/Xilinx_ip_wrapper/rtl`
modules and drops Bender sources that define the same module names. This avoids
duplicate `itcm`, `dtcm`, and `ydrmem_1r1w_ram` definitions while still using
Bender ordering for the core RTL.
