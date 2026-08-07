# RT-Thread Nano v4.1.1 runtime subset

This directory is the minimal RT-Thread runtime required by the Ydrasil BSP:
the v4.1.1 kernel, RISC-V common port, public headers, and FinSH shell.
It was imported from the official `RT-Thread/rt-thread` `v4.1.1` tag
(`aab2428d4177a02cd3b0fd020e47a88de379a6ab`) under Apache-2.0.

The Ydrasil-specific startup, interrupt dispatch, timer, PLIC, and UART code
remains in `sw/bsp/rtthread`.  The Nano configuration is in
`sw/bsp/rtthread/rtconfig.h`.
