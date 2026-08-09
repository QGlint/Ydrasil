#!/usr/bin/env python3
"""Fast, single-pass collector for the architecture performance records."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

from analyze_bubbles import (
    all_columns,
    parse_log,
    selected_logs,
    value,
    write_csv,
    write_report,
)


COREMARK_RE = re.compile(r"^CoreMark 1\.0\s*:\s*([0-9.]+)")


def coremark_score(path: Path) -> str:
    score = ""
    for line in path.read_text(errors="replace").splitlines():
        match = COREMARK_RE.match(line)
        if match:
            score = match.group(1)
    return score


def in_scope(program: str, scope: str) -> bool:
    if scope in ("all", ""):
        return True
    if scope in ("coremark", "coremark-only"):
        # `coremark-opt/*` contains comparison/rewrite artifacts from older
        # runs.  The current HEAD baseline is the exact `coremark` log;
        # include optimized profiles only when explicitly requested.
        return program == "coremark"
    if scope in ("coremark-all", "coremark-profiles"):
        return program == "coremark" or program.startswith("coremark-opt/")
    if scope.startswith("prefix:"):
        return program.startswith(scope.removeprefix("prefix:"))
    return program == scope


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/sim/hw")
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("build/PPA")
    scope = sys.argv[3] if len(sys.argv) > 3 else "all"
    out_dir.mkdir(parents=True, exist_ok=True)

    programs: list[tuple[str, dict[str, dict[str, float]], Path]] = []
    for log in selected_logs(root):
        program = str(log.relative_to(root).parent)
        if not in_scope(program, scope):
            continue
        records = parse_log(log)
        if "PERF_CONTROL_DECOUPLE" in records:
            score = coremark_score(log)
            if score:
                records["PERF_BENCHMARK"] = {"COREMARK_SCORE": float(score)}
            programs.append((program, records, log))

    # The detailed CSV/report share the same parsed records, so no second log
    # scan is needed.  Keep the historical filename for existing Make targets.
    records_only = [(program, records) for program, records, _ in programs]
    write_csv(out_dir / "perf_bubble_detail.csv", records_only)
    write_report(out_dir / "perf_bubble_analysis.md", records_only)

    columns = all_columns(records_only)
    with (out_dir / "perf_stats.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["program", "cycles", "insts", "ipc", "coremark_score"] +
                        [name for name, _, _ in columns[3:]])
        for program, records, log in programs:
            row = [
                program,
                value(records, "PERF_METRIC", "CYCLES"),
                value(records, "PERF_METRIC", "INSTS"),
                value(records, "PERF_METRIC", "IPC"),
                coremark_score(log),
            ]
            row.extend(value(records, record, field) for _, record, field in columns[3:])
            writer.writerow(row)

    summary_path = out_dir / "perf_stats_summary.log"
    with summary_path.open("w") as stream:
        stream.write("PPA performance statistics\n")
        stream.write(f"Root: {root}\nScope: {scope}\n")
        stream.write(f"Logs: {len(programs)}\nCSV: {out_dir / 'perf_stats.csv'}\n\n")
        for program, records, _ in programs:
            stream.write(
                f"{program:40s} IPC={value(records, 'PERF_METRIC', 'IPC'):.4f} "
                f"cycles={int(value(records, 'PERF_METRIC', 'CYCLES'))} "
                f"ROB_FULL={int(value(records, 'PERF_CONTROL_DECOUPLE', 'ROB_FULL'))} "
                f"score={coremark_score(next(log for p, _, log in programs if p == program)) or '-'}\n"
            )
    print(f"[PPA] Performance CSV: {out_dir / 'perf_stats.csv'}")
    print(f"[PPA] Performance summary: {summary_path}")


if __name__ == "__main__":
    main()
