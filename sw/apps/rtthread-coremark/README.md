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
