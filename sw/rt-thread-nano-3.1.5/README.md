# RT-Thread Nano v3.1.5 frozen source subset

This directory is the Ydrasil runtime subset of the official RT-Thread Nano
repository. It was frozen from the exact upstream release below:

- repository: `git@github.com:RT-Thread/rtthread-nano.git`
- tag: `v3.1.5`
- commit: `9177e3e2f61794205565b2c53b0cb4ed2abcc43b`

The directory layout follows the former `rt-thread-nano-4.1.1` integration:
only the kernel, device layer, FinSH/MSH, common RISC-V port, headers, license
and build manifests required by the shared Ydrasil BSP are retained. Kernel,
FinSH and header sources come from the upstream tag. The device layer and
SCons manifests complete the Nano console integration; the RISC-V context port
adds only the `mscratch` interrupt-stack setup required by the Ydrasil BSP.
The BSP `finsh_config.h` compatibility shim remains outside this directory.

RT-Thread 5.2.2's `tools/` directory supplies SCons build helpers only; the
default image compiles and links the v3.1.5 runtime files in this directory.
