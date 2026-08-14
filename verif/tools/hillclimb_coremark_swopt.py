#!/usr/bin/env python3
"""Greedily compose CoreMark compiler flags using deterministic RTL results."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Dict, List, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[2]
SWEEP = ROOT / "verif/tools/sweep_coremark_swopt.sh"
SUMMARY_FIELDS = (
    "round", "case", "stage", "status", "cycles", "insts", "ipc",
    "itcm_bytes", "groups", "extra_cflags",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Iteratively add the best strictly improving CoreMark CFLAGS delta"
    )
    parser.add_argument("--candidates", required=True, type=Path)
    parser.add_argument("--base-cflags", required=True)
    parser.add_argument("--base-cycles", required=True, type=int)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--parallel", type=int, default=40, choices=range(1, 41))
    parser.add_argument("--max-rounds", type=int, default=32)
    parser.add_argument(
        "--exclude-cases", default="", help="comma-separated candidate names already in the base stack"
    )
    return parser.parse_args()


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def read_candidates(path: Path, excluded: set[str]) -> List[Tuple[str, str]]:
    candidates: List[Tuple[str, str]] = []
    seen: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 2 or not all(fields):
                raise ValueError(f"{path}:{line_number}: expected case name and CFLAGS")
            name, flags = fields
            if name in seen:
                raise ValueError(f"{path}:{line_number}: duplicate case name {name}")
            seen.add(name)
            if name not in excluded:
                candidates.append((name, flags))
    if not candidates:
        raise ValueError("no candidates remain after exclusions")
    return candidates


def category(name: str) -> str:
    if name.startswith("branch_cost_"):
        return "branch_cost"
    if name.startswith("tune_"):
        return "tune"
    if name.startswith("small_data_"):
        return "small_data"
    if name.startswith("align_"):
        return "alignment"
    if name in {"if_conversion", "if_conversion_pair"}:
        return "if_conversion"
    if name in {"no_reorder_blocks", "reorder_blocks_simple"}:
        return "block_reorder"
    if name.startswith("ira_region_"):
        return "ira_region"
    return name


def write_candidates(path: Path, candidates: Sequence[Tuple[str, str]]) -> None:
    atomic_write(path, "".join(f"{name}\t{flags}\n" for name, flags in candidates))


def read_best(summary: Path) -> Tuple[str, int]:
    with summary.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != SUMMARY_FIELDS:
            raise ValueError(f"unexpected summary header: {summary}")
        passing = [
            row for row in reader
            if row["status"] == "PASS" and row["cycles"].isdigit()
        ]
    if not passing:
        raise ValueError(f"no passing samples: {summary}")
    best = min(passing, key=lambda row: (int(row["cycles"]), row["case"]))
    return best["case"], int(best["cycles"])


def write_state(path: Path, flags: str, cycles: int, remaining: Sequence[Tuple[str, str]], status: str) -> None:
    atomic_write(
        path,
        json.dumps(
            {
                "base_cflags": flags,
                "base_cycles": cycles,
                "remaining_candidates": [name for name, _ in remaining],
                "status": status,
            },
            indent=2,
            sort_keys=True,
        ) + "\n",
    )


def append_iteration(path: Path, row: Sequence[str]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write("\t".join(row) + "\n")


def main() -> int:
    args = parse_args()
    if args.base_cycles <= 0 or args.max_rounds <= 0:
        print("--base-cycles and --max-rounds must be positive", file=sys.stderr)
        return 2
    if not SWEEP.is_file():
        print(f"sweep script not found: {SWEEP}", file=sys.stderr)
        return 2

    excluded = {name for name in args.exclude_cases.split(",") if name}
    try:
        remaining = read_candidates(args.candidates.resolve(), excluded)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2

    out_dir = args.out_dir.resolve()
    if out_dir.exists():
        print(f"refusing to reuse output directory: {out_dir}", file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True)
    iterations = out_dir / "iterations.tsv"
    atomic_write(
        iterations,
        "iteration\tbaseline_cycles\tbest_case\tbest_cycles\tdelta_cycles\tresult\tstack_cflags\tscan_dir\n",
    )

    flags = args.base_cflags.strip()
    cycles = args.base_cycles
    write_state(out_dir / "state.json", flags, cycles, remaining, "running")

    for iteration in range(1, args.max_rounds + 1):
        if not remaining:
            append_iteration(iterations, [str(iteration), str(cycles), "", "", "0", "STOP_NO_CANDIDATES", flags, ""])
            write_state(out_dir / "state.json", flags, cycles, remaining, "stopped_no_candidates")
            return 0

        candidate_file = out_dir / f"iteration-{iteration:02d}.candidates.tsv"
        sweep_dir = out_dir / f"iteration-{iteration:02d}"
        log_path = out_dir / f"iteration-{iteration:02d}.log"
        write_candidates(candidate_file, remaining)
        command = [
            str(SWEEP), "--parallel", str(args.parallel), "--extra-cases", str(candidate_file),
            "--prefix-cflags", flags, "--out-dir", str(sweep_dir),
        ]
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            append_iteration(iterations, [str(iteration), str(cycles), "", "", "", "SWEEP_ERROR", flags, str(sweep_dir)])
            write_state(out_dir / "state.json", flags, cycles, remaining, "stopped_sweep_error")
            return result.returncode

        try:
            best_name, best_cycles = read_best(sweep_dir / "summary.tsv")
        except (OSError, ValueError) as error:
            print(error, file=sys.stderr)
            append_iteration(iterations, [str(iteration), str(cycles), "", "", "", "NO_PASS", flags, str(sweep_dir)])
            write_state(out_dir / "state.json", flags, cycles, remaining, "stopped_no_pass")
            return 1

        delta = best_cycles - cycles
        if delta >= 0:
            append_iteration(
                iterations,
                [str(iteration), str(cycles), best_name, str(best_cycles), str(delta), "STOP_NON_IMPROVING", flags, str(sweep_dir)],
            )
            write_state(out_dir / "state.json", flags, cycles, remaining, "stopped_non_improving")
            return 0

        selected_flags = dict(remaining)[best_name]
        flags = f"{flags} {selected_flags}".strip()
        cycles = best_cycles
        selected_category = category(best_name)
        remaining = [entry for entry in remaining if category(entry[0]) != selected_category]
        append_iteration(
            iterations,
            [str(iteration), str(cycles - delta), best_name, str(cycles), str(delta), "SELECTED", flags, str(sweep_dir)],
        )
        write_state(out_dir / "state.json", flags, cycles, remaining, "running")

    append_iteration(iterations, [str(args.max_rounds), str(cycles), "", "", "0", "STOP_MAX_ROUNDS", flags, ""])
    write_state(out_dir / "state.json", flags, cycles, remaining, "stopped_max_rounds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
