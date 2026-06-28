#!/usr/bin/env python3
"""Summarize and group similar Vivado timing paths."""

from __future__ import annotations

import argparse
import csv
import re
import statistics
from dataclasses import dataclass
from pathlib import Path


SLACK_RE = re.compile(r"Slack\s*\((?P<status>[^)]*)\)\s*:\s*(?P<value>[-+]?\d+(?:\.\d+)?)ns")
FIELD_RE = re.compile(
    r"^\s*(Source|Destination|Path Group|Requirement|Data Path Delay|Logic Levels|Clock Path Skew|Clock Uncertainty):\s*(.*?)\s*$",
    re.MULTILINE,
)
NUMBER_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")
PERCENT_RE = re.compile(r"(logic|route)\s+[-+]?\d+(?:\.\d+)?ns\s+\(([-+]?\d+(?:\.\d+)?)%\)", re.IGNORECASE)


@dataclass
class TimingPath:
    slack: float
    status: str
    source: str
    destination: str
    path_group: str
    requirement: float | None
    data_delay: float | None
    logic_levels: int | None
    logic_pct: float | None
    route_pct: float | None
    cause: str


def first_number(value: str) -> float | None:
    match = NUMBER_RE.search(value)
    return float(match.group(0)) if match else None


def endpoint(value: str) -> str:
    value = value.strip()
    if " (" in value:
        value = value.split(" (", 1)[0]
    return value


def normalize_endpoint(value: str) -> str:
    value = endpoint(value)
    value = re.sub(r"\[[^\]]+\]", "[*]", value)
    value = re.sub(r"genblk\d+", "genblk*", value)
    value = re.sub(r"(?<=/)[A-Za-z_]+[0-9]+(?=/)", lambda m: re.sub(r"\d+", "*", m.group(0)), value)
    return value


def parent_block(value: str) -> str:
    parts = normalize_endpoint(value).split("/")
    if len(parts) <= 2:
        return normalize_endpoint(value)
    return "/".join(parts[:-1])


def classify(path_group: str, data_delay: float | None, logic_levels: int | None, route_pct: float | None, source: str, dest: str) -> str:
    text = f"{source} {dest}".lower()
    if route_pct is not None and route_pct >= 60.0:
        return "route-dominated"
    if logic_levels is not None and logic_levels >= 8:
        return "logic-depth"
    for block in ["ydrasil_div", "ydrasil_mul", "ydrasil_alu", "ydrasil_branch_predictor", "ydrasil_load_store_unit"]:
        if block in text:
            return block
    if data_delay is not None and data_delay > 0 and "clk" in path_group.lower():
        return "clock-group-critical"
    return "mixed"


def parse_path(block: str) -> TimingPath | None:
    slack_match = SLACK_RE.search(block)
    if not slack_match:
        return None

    fields = {name: value for name, value in FIELD_RE.findall(block)}
    source = endpoint(fields.get("Source", "unknown"))
    dest = endpoint(fields.get("Destination", "unknown"))
    path_group = fields.get("Path Group", "unknown")
    requirement = first_number(fields.get("Requirement", ""))
    data_delay_text = fields.get("Data Path Delay", "")
    data_delay = first_number(data_delay_text)

    logic_levels = None
    logic_text = fields.get("Logic Levels", "")
    logic_match = re.search(r"\d+", logic_text)
    if logic_match:
        logic_levels = int(logic_match.group(0))

    pct = {name.lower(): float(value) for name, value in PERCENT_RE.findall(data_delay_text)}
    logic_pct = pct.get("logic")
    route_pct = pct.get("route")

    cause = classify(path_group, data_delay, logic_levels, route_pct, source, dest)
    return TimingPath(
        slack=float(slack_match.group("value")),
        status=slack_match.group("status"),
        source=source,
        destination=dest,
        path_group=path_group,
        requirement=requirement,
        data_delay=data_delay,
        logic_levels=logic_levels,
        logic_pct=logic_pct,
        route_pct=route_pct,
        cause=cause,
    )


def split_paths(text: str) -> list[str]:
    matches = list(SLACK_RE.finditer(text))
    blocks: list[str] = []
    for idx, match in enumerate(matches):
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        blocks.append(text[start:end])
    return blocks


def load_paths(path: Path) -> list[TimingPath]:
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    return [item for item in (parse_path(block) for block in split_paths(text)) if item is not None]


def group_key(path: TimingPath) -> tuple[str, str, str, str]:
    return (path.path_group, parent_block(path.source), parent_block(path.destination), path.cause)


def fmt(value: float | int | None, digits: int = 3) -> str:
    if value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    return f"{value:.{digits}f}"


def write_csv(paths: list[TimingPath], out: Path) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, str, str], list[TimingPath]] = {}
    for path in paths:
        groups.setdefault(group_key(path), []).append(path)

    rows: list[dict[str, object]] = []
    for (path_group, start_pattern, end_pattern, cause), group in groups.items():
        worst = min(group, key=lambda item: item.slack)
        rows.append(
            {
                "path_group": path_group,
                "count": len(group),
                "worst_slack_ns": worst.slack,
                "avg_slack_ns": statistics.fmean(item.slack for item in group),
                "start_pattern": start_pattern,
                "end_pattern": end_pattern,
                "worst_start": worst.source,
                "worst_end": worst.destination,
                "cause": cause,
                "logic_levels": worst.logic_levels,
                "route_pct": worst.route_pct,
                "logic_pct": worst.logic_pct,
                "data_delay_ns": worst.data_delay,
                "requirement_ns": worst.requirement,
            }
        )

    rows.sort(key=lambda row: (float(row["worst_slack_ns"]), -int(row["count"])))
    out.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "path_group",
        "count",
        "worst_slack_ns",
        "avg_slack_ns",
        "start_pattern",
        "end_pattern",
        "worst_start",
        "worst_end",
        "cause",
        "logic_levels",
        "route_pct",
        "logic_pct",
        "data_delay_ns",
        "requirement_ns",
    ]
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_markdown(rows: list[dict[str, object]], paths: list[TimingPath], out: Path) -> None:
    violations = [path for path in paths if path.slack < 0]
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        f.write("# Vivado Timing Group Summary\n\n")
        if not paths:
            f.write("No timing paths were parsed. Check post_route_timing_paths.rpt.\n")
            return

        f.write(f"- Parsed paths: {len(paths)}\n")
        f.write(f"- Violating paths: {len(violations)}\n")
        f.write(f"- Worst slack: {min(path.slack for path in paths):.3f} ns\n\n")

        f.write("## Worst Similar Path Groups\n\n")
        f.write("| Rank | Count | Worst Slack ns | Avg Slack ns | Cause | Route % | Logic Levels | Start Pattern | End Pattern |\n")
        f.write("| --- | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |\n")
        for idx, row in enumerate(rows[:20], start=1):
            f.write(
                "| {rank} | {count} | {worst} | {avg} | {cause} | {route_pct} | {levels} | `{start}` | `{end}` |\n".format(
                    rank=idx,
                    count=row["count"],
                    worst=fmt(float(row["worst_slack_ns"])),
                    avg=fmt(float(row["avg_slack_ns"])),
                    cause=row["cause"],
                    route_pct=fmt(row["route_pct"] if row["route_pct"] != "" else None, 1),
                    levels=fmt(row["logic_levels"]),
                    start=row["start_pattern"],
                    end=row["end_pattern"],
                )
            )

        f.write("\n## Initial Diagnosis\n\n")
        cause_counts: dict[str, int] = {}
        for row in rows:
            cause_counts[str(row["cause"])] = cause_counts.get(str(row["cause"]), 0) + int(row["count"])
        for cause, count in sorted(cause_counts.items(), key=lambda item: (-item[1], item[0])):
            if cause == "route-dominated":
                note = "routing delay dominates; inspect placement distance, fanout, and congestion."
            elif cause == "logic-depth":
                note = "logic depth is high; consider pipelining or reducing combinational chains."
            elif cause.startswith("ydrasil_"):
                note = "critical endpoints cluster in this RTL block; inspect that combinational path."
            else:
                note = "mixed delay; inspect the worst concrete path before changing constraints or RTL."
            f.write(f"- {cause}: {count} paths, {note}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-dir", type=Path, default=Path("build/syn/reports"))
    parser.add_argument("--timing-report", type=Path, default=None)
    parser.add_argument("--csv", type=Path, default=None)
    parser.add_argument("--md", type=Path, default=None)
    args = parser.parse_args()

    report_dir = args.report_dir
    timing_report = args.timing_report or report_dir / "post_route_timing_paths.rpt"
    csv_out = args.csv or report_dir / "timing_groups.csv"
    md_out = args.md or report_dir / "timing_groups.md"

    paths = load_paths(timing_report)
    rows = write_csv(paths, csv_out)
    write_markdown(rows, paths, md_out)

    print(f"parsed {len(paths)} timing paths")
    print(f"wrote {csv_out}")
    print(f"wrote {md_out}")
    return 0 if paths else 1


if __name__ == "__main__":
    raise SystemExit(main())
