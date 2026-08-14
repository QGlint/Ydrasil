#!/usr/bin/env python3
"""Validate and rank CoreMark SWOPT sweep samples.

The checker deliberately treats an incomplete sweep as normal: it validates
the records written so far and refreshes ranked.tsv after every completed
batch. Use --strict once the sweep has finished to require every case to pass.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Dict, Iterable, List, Tuple


SUMMARY_FIELDS = (
    "round",
    "case",
    "stage",
    "status",
    "cycles",
    "insts",
    "ipc",
    "itcm_bytes",
    "groups",
    "extra_cflags",
)
METRIC_RE = re.compile(
    r"^PERF_METRIC: CYCLES= *([0-9]+).*INSTS= *([0-9]+).*IPC= *([0-9.]+)",
    re.MULTILINE,
)
ASSERTION_RE = re.compile(r"^.*Assertion failed.*?: (.+)$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate and rank a CoreMark SWOPT sweep")
    parser.add_argument("sweep_dir", type=Path, help="sweep output directory")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail if the sweep is incomplete or any sample did not pass",
    )
    parser.add_argument("--quiet", action="store_true", help="suppress the one-line report")
    return parser.parse_args()


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def read_tsv(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != SUMMARY_FIELDS:
            found = "\\t".join(reader.fieldnames or ())
            raise ValueError(f"unexpected summary header: {found}")
        return list(reader)


def read_expected_cases(path: Path) -> set[str]:
    if not path.exists():
        return set()
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != ("case", "groups"):
            raise ValueError("unexpected cases.tsv header")
        return {row["case"] for row in reader}


def numeric(value: str) -> bool:
    return value.isdigit()


def read_status(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip() if path.exists() else "MISSING"


def check_pass_row(sweep_dir: Path, row: Dict[str, str], issues: List[Tuple[str, str, str]]) -> None:
    case = row["case"]
    round_name = row["round"]
    run_dir = sweep_dir / "runs" / round_name / case
    image_dir = sweep_dir / "images" / round_name / case
    log_dir = sweep_dir / "logs" / round_name
    hw_log = run_dir / "hw.log"

    for status_name in ("build", "run"):
        status_path = log_dir / f"{case}.{status_name}.status"
        value = read_status(status_path)
        if value != "PASS":
            issues.append((case, f"{status_name}_status", f"expected PASS, found {value}"))

    if not hw_log.exists():
        issues.append((case, "hw_log", "missing"))
        return
    text = hw_log.read_text(encoding="utf-8", errors="replace")
    for marker in ("Correct operation validated", "COREMARK DONE"):
        if marker not in text:
            issues.append((case, "hw_log", f"missing marker: {marker}"))
    metrics = METRIC_RE.findall(text)
    if not metrics:
        issues.append((case, "metric", "PERF_METRIC not found"))
    else:
        cycles, insts, ipc = metrics[-1]
        if (cycles, insts, ipc) != (row["cycles"], row["insts"], row["ipc"]):
            issues.append(
                (
                    case,
                    "metric",
                    f"summary={row['cycles']}/{row['insts']}/{row['ipc']} log={cycles}/{insts}/{ipc}",
                )
            )

    image = image_dir / "coremark_itcm.bin"
    if not image.exists():
        issues.append((case, "itcm_image", "missing"))
    elif not numeric(row["itcm_bytes"]) or image.stat().st_size != int(row["itcm_bytes"]):
        issues.append(
            (case, "itcm_bytes", f"summary={row['itcm_bytes']} actual={image.stat().st_size}")
        )


def classify_failure(sweep_dir: Path, row: Dict[str, str]) -> Tuple[str, str, str]:
    """Return build status, run status, and a stable high-level failure reason."""
    case = row["case"]
    round_name = row["round"]
    log_dir = sweep_dir / "logs" / round_name
    build_status = read_status(log_dir / f"{case}.build.status")
    run_status = read_status(log_dir / f"{case}.run.status")
    if build_status != "PASS":
        return build_status, run_status, f"build_{build_status.lower()}"
    if run_status != "PASS":
        hw_log = sweep_dir / "runs" / round_name / case / "hw.log"
        if not hw_log.exists():
            return build_status, run_status, "simulation_log_missing"
        text = hw_log.read_text(encoding="utf-8", errors="replace")
        assertion = ASSERTION_RE.findall(text)
        if assertion:
            return build_status, run_status, f"rtl_assertion: {assertion[-1]}"
        if "C++ timeout" in text and "COREMARK DONE" not in text:
            return build_status, run_status, "simulation_timeout"
        return build_status, run_status, "simulation_failed_without_assertion"
    return build_status, run_status, "summary_marked_fail"


def rank_key(row: Dict[str, str]) -> Tuple[int, int, str]:
    if row["status"] == "PASS" and numeric(row["cycles"]):
        return (0, int(row["cycles"]), row["case"])
    return (1, sys.maxsize, row["case"])


def render_tsv(rows: Iterable[Dict[str, str]]) -> str:
    output = ["\t".join(SUMMARY_FIELDS)]
    for row in rows:
        output.append("\t".join(row[field] for field in SUMMARY_FIELDS))
    return "\n".join(output) + "\n"


def main() -> int:
    args = parse_args()
    sweep_dir = args.sweep_dir.resolve()
    summary_path = sweep_dir / "summary.tsv"
    if not summary_path.exists():
        print(f"missing summary: {summary_path}", file=sys.stderr)
        return 2

    try:
        rows = read_tsv(summary_path)
        expected_cases = read_expected_cases(sweep_dir / "cases.tsv")
    except (OSError, ValueError) as error:
        print(f"unable to read sweep: {error}", file=sys.stderr)
        return 2

    issues: List[Tuple[str, str, str]] = []
    failures: List[Tuple[str, str, str, str, str]] = []
    seen_cases: set[str] = set()
    for row in rows:
        case = row["case"]
        if not case:
            issues.append(("<empty>", "case", "empty case name"))
            continue
        if case in seen_cases:
            issues.append((case, "case", "duplicate summary entry"))
        seen_cases.add(case)
        if expected_cases and case not in expected_cases:
            issues.append((case, "case", "not declared in cases.tsv"))
        if row["status"] not in {"PASS", "FAIL"}:
            issues.append((case, "status", f"unexpected value: {row['status']}"))
        if row["status"] == "PASS":
            if not all(numeric(row[field]) for field in ("cycles", "insts", "itcm_bytes")):
                issues.append((case, "summary", "PASS row has a non-numeric metric"))
            check_pass_row(sweep_dir, row, issues)
        elif row["status"] == "FAIL":
            build_status, run_status, reason = classify_failure(sweep_dir, row)
            failures.append((row["round"], case, build_status, run_status, reason))

    ranked_rows = sorted(rows, key=rank_key)
    write_atomic(sweep_dir / "ranked.tsv", render_tsv(ranked_rows))

    check_lines = ["case\tcheck\tdetail"]
    for case, check, detail in issues:
        check_lines.append(f"{case}\t{check}\t{detail}")
    write_atomic(sweep_dir / "validation.tsv", "\n".join(check_lines) + "\n")

    failure_lines = ["round\tcase\tbuild_status\trun_status\treason"]
    for failure in failures:
        failure_lines.append("\t".join(failure))
    write_atomic(sweep_dir / "failures.tsv", "\n".join(failure_lines) + "\n")

    pass_count = sum(row["status"] == "PASS" for row in rows)
    fail_count = sum(row["status"] == "FAIL" for row in rows)
    report = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "expected_cases": len(expected_cases) if expected_cases else None,
        "recorded_cases": len(rows),
        "pass_cases": pass_count,
        "failed_cases": fail_count,
        "validation_errors": len(issues),
        "failure_reasons": dict(sorted(Counter(reason for *_, reason in failures).items())),
        "complete": bool(expected_cases) and len(rows) == len(expected_cases),
    }
    write_atomic(sweep_dir / "validation.json", json.dumps(report, indent=2, sort_keys=True) + "\n")

    if not args.quiet:
        print(
            "[COREMARK CHECK] "
            f"recorded={report['recorded_cases']} pass={pass_count} fail={fail_count} "
            f"errors={len(issues)} complete={report['complete']}"
        )
    if args.strict and (issues or fail_count or not report["complete"]):
        return 1
    return 0 if not issues else 1


if __name__ == "__main__":
    raise SystemExit(main())
