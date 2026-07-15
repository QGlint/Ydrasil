# Ydrasil riscv-dv generator

This integration uses only the riscv-dv Python generator path for the Ydrasil
RV32IM pipeline regression. It does not compile or run the upstream
SystemVerilog/UVM environment.

The generated profile is bare machine-mode RV32IM. Compressed, floating-point,
CSR-randomization, interrupt, illegal-instruction and unaligned-access tests are
disabled. `Zicsr` is present in the compiler architecture string only because
the generated startup reads `mhartid`.

## Regression commands

Run the full coverage regression. It reuses completed `coverage_all`, sort and
sort-opt suites when their inputs are unchanged, then starts the unbounded
20-worker random generator:

```bash
make regression
```

Stop the full regression from another shell. This requests the riscv-dv
graceful stop, waits for active random cases and the parent regression, then
merges all current-RTL suite coverage into `build/coverage-total/merged.dat`:

```bash
make regression_stop
```

The stop target also runs bounded riscv-dv cleanup; current history, permanent
failures and the current RTL's merged coverage are retained.

Any design RTL source change invalidates every static suite cache, rebuilds the
riscv-dv model, and gives random coverage a new RTL-specific database. Testbench
changes rebuild the simulation model but do not invalidate completed regression
suites or change the random coverage identity. Generator seed history and
permanent failing seeds remain global to the generator profile. Inputs changing
while a suite is running prevent that run from being recorded as complete.

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

Parallelism defaults to 20 and is hard-capped in the driver at 20. Override it,
for example with `RISCV_DV_JOBS=8`, when lower CPU usage is preferred; values
above 20 are rejected before work starts.
