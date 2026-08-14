#!/usr/bin/env python3
"""Exhaustively evaluate a bounded compiler-flag subset lattice by layers.

Compiler optimization performance is not additive, so this records an exact
measured dynamic-programming table rather than estimating a parent state's
score from its children. Every non-empty subset is built and simulated once.
"""

from __future__ import annotations

import argparse
import csv
import itertools
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
    parser = argparse.ArgumentParser(description="Measure every subset of CoreMark compiler flag atoms")
    parser.add_argument("--atoms", required=True, type=Path)
    parser.add_argument("--base-cycles", required=True, type=int)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--parallel", type=int, default=40, choices=range(1, 41))
    return parser.parse_args()


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def read_atoms(path: Path) -> List[Tuple[str, str]]:
    atoms: List[Tuple[str, str]] = []
    seen: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 2 or not all(fields):
                raise ValueError(f"{path}:{line_number}: expected atom name and CFLAGS")
            name, flags = fields
            if name in seen:
                raise ValueError(f"{path}:{line_number}: duplicate atom {name}")
            seen.add(name)
            atoms.append((name, flags))
    if not atoms:
        raise ValueError("no DP atoms")
    return atoms


def write_candidates(path: Path, states: Sequence[Tuple[str, str]]) -> None:
    atomic_write(path, "".join(f"{name}\t{flags}\n" for name, flags in states))


def read_summary(path: Path) -> Dict[str, Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != SUMMARY_FIELDS:
            raise ValueError(f"unexpected summary header: {path}")
        return {row["case"]: row for row in reader}


def append_rows(path: Path, rows: Sequence[Sequence[str]]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        for row in rows:
            handle.write("\t".join(row) + "\n")


def main() -> int:
    args = parse_args()
    if args.base_cycles <= 0:
        print("--base-cycles must be positive", file=sys.stderr)
        return 2
    if not SWEEP.is_file():
        print(f"sweep script not found: {SWEEP}", file=sys.stderr)
        return 2
    try:
        atoms = read_atoms(args.atoms.resolve())
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    if len(atoms) > 12:
        print("refusing more than 12 atoms; subset lattice would be too large", file=sys.stderr)
        return 2

    out_dir = args.out_dir.resolve()
    if out_dir.exists():
        print(f"refusing to reuse output directory: {out_dir}", file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True)
    states_path = out_dir / "states.tsv"
    atomic_write(states_path, "layer\tstate\tstatus\tcycles\tflags\tscan_dir\n")
    all_results: List[Tuple[str, int, str]] = [("baseline", args.base_cycles, "")]

    for layer in range(1, len(atoms) + 1):
        states: List[Tuple[str, str]] = []
        for subset in itertools.combinations(atoms, layer):
            name = "__".join(atom[0] for atom in subset)
            flags = " ".join(atom[1] for atom in subset)
            states.append((name, flags))
        candidate_file = out_dir / f"layer-{layer:02d}.candidates.tsv"
        scan_dir = out_dir / f"layer-{layer:02d}"
        scan_log = out_dir / f"layer-{layer:02d}.log"
        write_candidates(candidate_file, states)
        command = [
            str(SWEEP), "--parallel", str(args.parallel), "--extra-cases", str(candidate_file),
            "--out-dir", str(scan_dir),
        ]
        with scan_log.open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            print(f"layer {layer} sweep failed: {scan_log}", file=sys.stderr)
            return result.returncode
        try:
            summary = read_summary(scan_dir / "summary.tsv")
        except (OSError, ValueError) as error:
            print(error, file=sys.stderr)
            return 1

        rows: List[List[str]] = []
        for name, flags in states:
            row = summary.get(name)
            if row is None:
                rows.append([str(layer), name, "MISSING", "N/A", flags, str(scan_dir)])
            else:
                rows.append([str(layer), name, row["status"], row["cycles"], flags, str(scan_dir)])
                if row["status"] == "PASS" and row["cycles"].isdigit():
                    all_results.append((name, int(row["cycles"]), flags))
        append_rows(states_path, rows)

        passing = [item for item in all_results if item[0] != "baseline"]
        best_name, best_cycles, best_flags = min(passing, key=lambda item: (item[1], item[0]))
        atomic_write(
            out_dir / "state.json",
            json.dumps(
                {
                    "atoms": [name for name, _ in atoms],
                    "completed_layers": layer,
                    "best_case": best_name,
                    "best_cycles": best_cycles,
                    "best_flags": best_flags,
                    "states_measured": len(all_results) - 1,
                },
                indent=2,
                sort_keys=True,
            ) + "\n",
        )

    best_name, best_cycles, best_flags = min(all_results, key=lambda item: (item[1], item[0]))
    atomic_write(
        out_dir / "best.tsv",
        "case\tcycles\tflags\n" + f"{best_name}\t{best_cycles}\t{best_flags}\n",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
