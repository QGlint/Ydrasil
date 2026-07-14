# Ydrasil riscv-dv generator

This integration uses only the riscv-dv Python generator path for the Ydrasil
RV32IM pipeline regression. It does not compile or run the upstream
SystemVerilog/UVM environment.

The generated profile is bare machine-mode RV32IM. Compressed, floating-point,
CSR-randomization, interrupt, illegal-instruction and unaligned-access tests are
disabled. `Zicsr` is present in the compiler architecture string only because
the generated startup reads `mhartid`.

## Regression commands

For an open-ended uniform random regression, start the continuous runner and
leave it active. It randomly allocates seeds that have never been used by the
current generator profile, prepares each program on demand, and keeps replacing
completed worker slots until a graceful stop is requested.

```bash
make riscv_dv_random
```

From another shell, inspect the active runner or request a graceful stop:

```bash
cat build/riscv-dv/runner.json
make riscv_dv_random_status
make riscv_dv_stop
```

Seed history is stored under `build/riscv-dv/history/` and survives normal
cleanup. Successful program images and traces are removed after comparison;
failure evidence and cumulative coverage are retained. Seed uniqueness is per
profile, so changing the architecture, instruction count, or generator sources
starts a new random history.

Any `FAIL`, `TIMEOUT`, or `ERROR` seed is also added to the profile's permanent
regression set. Later continuous runs replay that set before allocating new
random seeds. A seed stays in the set after it passes so fixed bugs remain
covered; `riscv_dv_random_status` lists the permanent set and last result.

Run a fixed number of seeds. Generation, ELF compilation and model compilation
are cached; rerunning the same command resumes the same suite without rebuilding
prepared seeds.

```bash
make riscv_dv_count RISCV_DV_NUM=2000
```

Request a graceful stop from another shell. No new seeds are launched, the at
most 20 active seeds are allowed to finish, partial coverage is merged, and a
coverage report is written.

```bash
make riscv_dv_stop
```

The same count command resumes seeds not recorded in the suite database. A
single failure can be rerun from its cached ELF and memory images:

```bash
make riscv_dv_repro RISCV_DV_SEED=21
```

Preparation and execution can also be separated explicitly. `riscv_dv_run`
has no dependency on `riscv_dv_prepare`, so it never regenerates a missing
program and instead reports an error.

```bash
make riscv_dv_prepare RISCV_DV_COUNT=2000
make riscv_dv_run RISCV_DV_COUNT=2000
```

## Storage controls

```bash
make riscv_dv_estimate RISCV_DV_COUNT=2000
make riscv_dv_cleanup
make riscv_dv_distclean
```

Successful per-seed logs and CSV traces are deleted immediately. Coverage is
merged in batches and the input databases are removed. Failed evidence is gzip
compressed and capped by `RISCV_DV_KEEP_FAILURES` (default 20); run and repro
directories are capped by `RISCV_DV_KEEP_RUNS` (default 5). Old generator
profiles are removed when the cache exceeds `RISCV_DV_MAX_CACHE_GB` (default
4 GiB), and preparation refuses a current profile projected beyond that limit.

Parallelism is hard-capped in the driver at 20; larger `RISCV_DV_JOBS` values
are rejected before work starts.
