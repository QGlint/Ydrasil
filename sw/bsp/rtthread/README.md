# Ydrasil RT-Thread BSP preparation

This is an external BSP for the trimmed RT-Thread 5.2.2 tree. The BSP stays
under `sw/bsp`; `RTT_ROOT` points to `sw/rt-thread-5.2.2`.

## Build

Required host tools:

- SCons 4.x
- `riscv64-unknown-elf-gcc`
- the RISC-V picolibc package and `picolibc.specs`

Run from this directory:

```sh
scons -j4
```

The build uses RV32IMF, the `ilp32f` ABI and `-Os`. It produces:

- `rtthread.elf` and `rtthread.map`
- `rtthread.dump`
- `rtthread.itcm` and `rtthread.dtcm` for RTL memory loading
- matching binary images

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
