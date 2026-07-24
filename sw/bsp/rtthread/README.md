# Ydrasil RT-Thread BSP preparation

This is an external BSP for the trimmed RT-Thread 5.2.2 tree. The BSP stays
under `sw/bsp`; `RTT_ROOT` points to `sw/rt-thread-5.2.2`.

## Build

Required host tools:

- SCons 4.x
- `riscv64-unknown-elf-gcc`
- the RISC-V picolibc package and `picolibc.specs`

The canonical software entry point is `sw/Makefile`:

```sh
make -C sw rtthread
```

The direct SCons command remains useful for BSP bring-up, but application
builds should normally go through `sw/Makefile` so all software programs use
the same output and toolchain rules.

The default build uses RV32IM, the `ilp32` ABI and `-Os`. The FPU is disabled
and the resulting startup path contains no floating-point instructions. All
generated files are placed under `build/app/rtthread/`:

- `rtthread.elf` and `rtthread.map`
- `rtthread.dump`
- `rtthread.itcm` and `rtthread.dtcm` for RTL memory loading
- matching binary images and intermediate objects

## Application interface

The BSP does not contain benchmark sources. Set `RTT_APP` to an application
directory under `sw/apps`; that directory provides one `SConscript` manifest
which lists its source files with `DefineGroup`. Sources are compiled directly,
so a C file never includes another C file. The default `RTT_APP=default` keeps
`applications/main.c` as the RT-Thread user program.

For example, CoreMark is built as an external application with the existing
64 KiB simulation linker variant:

```sh
make -C sw rtthread-coremark-build-Os
```

To port another program, create `sw/apps/<name>/SConscript`, list its source
files, include paths and defines there, then select it with `RTT_APP=<name>`.
This keeps one RT-Thread BSP reusable for multiple applications.

## Current hardware boundary

`BSP_USING_SIM_CONSOLE` is enabled because the `0x80200060` write-only
simulation output register exists. FinSH is disabled because this endpoint has
no input path.

The following options are intentionally disabled until their hardware paths
are implemented and verified:

- `BSP_USING_MTIME_TICK`: MTIME/MTIMECMP and machine-timer interrupt
- `BSP_USING_UART0`: UART at `0x84004000`, including clock/reset and IRQ
- `BSP_USING_PLIC`: machine-external interrupt delivery

Do not enable timed RT-Thread services or automatic Utest execution before the
machine-timer path works. The Utest framework itself remains compiled in so
test cases can be added without restoring removed components.

No RTL change is part of this BSP preparation.

## CoreMark comparison

Run one CoreMark iteration under RT-Thread and bare metal with `-Os`, `-O2`
and `-O3`:

```sh
make -C sw/bsp/rtthread coremark-compare
```

The RT-Thread image needs more than the physical 16 KiB ITCM. The benchmark
target uses the repository's existing parameterized simulation flow with a
64 KiB ITCM model; it does not edit RTL source files. CoreMark is an integer
benchmark, so all comparison runs use `FPU=0`.
