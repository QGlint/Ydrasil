# RT-Thread CoreMark application

This application manifest builds the upstream CoreMark sources directly and
renames its entry point for the MSH `coremark` command.

The default Nano 3.1.5 monitor build keeps RT-Thread and application glue at
`-O2`, runs 15000 iterations and applies the measured best compiler flag set
only to the five CoreMark sources:

```sh
make -C sw rtthread
```

`RTTHREAD_CPU_FREQ_HZ` sets the image's default CPU frequency used to convert
the CPU-domain monitor count to seconds. For example:

```sh
make -C sw rtthread RTTHREAD_CPU_FREQ_HZ=200000000
```

The MSH command is `coremark [iterations]`. With no argument it runs 15000
iterations; a positive decimal argument selects the exact iteration count.
The raw 64-bit cycle count is always printed. Elapsed seconds and iterations
per second use software double precision on RV32IM; no FPU instructions or
hardware-FPU ABI are enabled. For board overclock sweeps, build with the
applied `RTTHREAD_CPU_FREQ_HZ`, or recalculate elapsed time from the raw cycle
count when reusing one image at several frequencies.

The dedicated eight-bit LED output follows the hardware CoreMark monitor and
does not consume GPIO outputs. All LEDs are off while idle and on throughout
the timed region: `0xff` on the active-high digital twin, or `0x00` on the
active-low AG10/AH10 board.

The tuned set includes `-O3 -funroll-loops`, aggressive inlining and the
project's tested loop/control/tree shaping options. The final 8-byte alignment
flags remain in force. Override `RTTHREAD_COREMARK_CORE_CFLAGS` only for an
explicit compiler sweep; the linker map and `.itcm` artifact remain the
authoritative size checks.

The monitor manifest also links the reusable display and angle-sensor drivers
from `sw/app/driver` and the `sensor` MSH application from `sw/app/sensor`.
RT-Thread initializes the OLED once at startup with `Ydrsail` and
`RT-Thread`; starting `sensor` replaces only the status line with the angle
page, and `sensor stop` restores it. Changed sensor data is rendered as one
centered complete frame at most every 200 ms and reported to the PC at most
every 500 ms; unchanged data produces no display or report traffic.

To select another RT-Thread application, create `sw/apps/<name>/SConscript`
and build with `RTTHREAD_APP=<name>`.
