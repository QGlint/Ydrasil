#!/usr/bin/env bash
set -euo pipefail

# Parse each hw.log once in Python.  The old implementation ran a grep and a
# shell regex for every field in every log; this repository contains hundreds
# of historical logs, so that made report generation dominate the workflow.
root=${1:-build/sim/hw}
out_dir=${2:-build/PPA}
scope=${3:-${PERF_STATS_SCOPE:-all}}
exec python3 "$(dirname "$0")/collect_perf_stats.py" "$root" "$out_dir" "$scope"
