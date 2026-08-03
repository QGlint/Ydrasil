# RT-Thread CoreMark application

This directory is an RT-Thread application manifest. It lists the CoreMark
sources and the existing Ydrasil console adapter directly; it does not include
one C source file from another C source file.

To add another RT-Thread application, create `sw/apps/<name>/SConscript`, list
its source files in `DefineGroup`, and build it with:

```sh
make -C sw rtthread RTT_APP=<name> \
  RTTHREAD_OUTPUT_DIR="$PWD/build/app/<name>"
```

For a size-conscious CoreMark build, keep RT-Thread and the application glue
at `-Os` while optimizing only the five CoreMark algorithm sources:

```sh
make -C sw rtthread RTTHREAD_APP=rtthread-coremark \
  RTTHREAD_OPT=-Os RTTHREAD_COREMARK_CORE_CFLAGS='-O3'
```

`-funroll-loops` can be added to the per-CoreMark setting when benchmark score
is more important than ITCM usage. The linker map and the `.itcm` artifact are
the authoritative size checks.
