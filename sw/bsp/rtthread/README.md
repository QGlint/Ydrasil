# Ydrasil RT-Thread monitor BSP

This external BSP uses the trimmed RT-Thread 5.2.2 tree under `sw/`.

## Build

Required host tools are SCons 4.x and the repository's
`riscv64-unknown-elf-gcc` toolchain. The canonical entry point is:

```sh
make -C sw rtthread
```

The default image uses RV32IM with the `ilp32` ABI. RT-Thread, MSH and device
code use `-O2`; only the CoreMark sources receive the benchmark-tuned `-O3`
flag set. The FPU remains disabled. Outputs are written below
`build/app/rtthread/`:

- `rtthread.elf`, `rtthread.map` and `rtthread.dump`
- `rtthread.itcm` and `rtthread.dtcm` for RTL or FPGA memory loading
- matching binary images and intermediate objects

## Shell commands

- `help`: list built-in and board commands.
- `coremark [iterations]`: run CoreMark. With no argument it runs 10000
  iterations; a positive decimal argument selects the exact iteration count.
- `sensor [all|temp|imu]`: read the selected sensors, print their values and
  refresh the OLED. With no argument, `all` is used.

The BSP remains reusable. Set `RTTHREAD_APP=<directory-name>` to select another
manifest under `sw/apps/`.

## Monitor wiring

- UART0 is the 115200 baud MSH console.
- On the digital-twin board, LM75B I2C0 uses SCL `K20` and SDA `K19`;
  ATK-MS601M UART1 uses FPGA RX `G17` and TX `G18`; SSD1306 uses SCLK `B19`,
  bidirectional SDIO `B18`, GPIO1/DC `A18` and GPIO2/RESET_n `A20`.
- On the AG10/AH10 board, LM75B I2C0 uses SCL `E16` and SDA `F16`;
  ATK-MS601M UART1 uses FPGA RX `A13` and TX `C14`; SSD1306 uses SCLK `G13`,
  bidirectional SDIO `A15`, GPIO1/DC `B15` and GPIO2/RESET_n `C15`.
- FPGA UART1 RX connects to the sensor TX. UART1 TX remains available for
  configuration commands. The display CS input is tied directly to ground and
  does not consume an FPGA pin. SPI0 releases SDIO during read data phases.

The RISC-V port is integer-only. LM75B values preserve the sensor's 0.125 C
resolution. MS601M attitude frames use the reference driver's `55 55` upload
format and checksum, then convert roll, pitch and yaw to tenths of a degree.

Device and transport drivers live under `sw/app/driver`; sensor acquisition,
formatting and the four-line display layout live under `sw/app/sensor`. The
OLED driver links only the small 5x7 glyph subset used by those four lines.
Run the host-side sensor and framebuffer simulation with:

```sh
make driver_sim_test
```

## CoreMark isolation and clocks

RT-Thread's CLINT `mtime` remains in the 50 MHz APB domain because it is a
system tick source, not the benchmark clock. Moving it would add CDC work
without improving measurement. CoreMark uses the existing 64-bit monitor in
the CPU clock domain. `start_time()` disables interrupts before starting the
monitor; `stop_time()` stops the monitor, captures its stable cycle count and
restores the previous interrupt state. The measured interval therefore
excludes the 1 kHz tick, shell RX handling and background scheduling.

The monitor frequency is injected with `RTTHREAD_CPU_FREQ_HZ` (150 MHz unless
overridden). Synthesis memory staging derives it from `SYN_PLL_FREQ_MHZ`; for
example, the 225 MHz target embeds 225000000. The CPU-domain monitor count, not
the configured frequency, determines the measured cycle count. For field
overclock sweeps, rebuild with the applied frequency or convert the printed raw
cycle count externally when reusing one image at several frequencies.

The monitor `active` signal drives LED0 in hardware. It becomes active at the
start of the timed region and inactive before interrupts are restored.

## Memory image contract

The linker and RTL both define a 128 KiB ITCM and 64 KiB DTCM. The existing
generation is retained: `.itcm` contains one 64-bit value (16 hex digits) per
line and `.dtcm` one 32-bit value (8 hex digits) per line. The established
8-byte function/jump/label/loop alignment is also retained so control-flow
targets keep their current ITCM fetch-slot placement.

Profile and Utest targets remain available from the repository root:

```sh
make rtthread-coremark-build
make rtthread-coremark-sim
make rtthread-coremark-report
make rtthread-utest-build
make rtthread-utest-sim
make rtthread-utest-report
```

All current RT-Thread model targets use the physical 128 KiB ITCM width and
depth. CoreMark is an integer benchmark, so comparison runs use `FPU=0`.
