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
DATA_CELL_RE = re.compile(
    r"\b(?P<cell_type>FD[A-Z]+|LUT\d|CARRY\d|MUXF\d|RAMB\d+E\d|DSP\d+E\d|SRL\w+|RAM\w+|IBUF\w*|BUFG\w*|MMCME\d_\w+)\b"
)
RESOURCE_RE = re.compile(r"(?P<resource>\S+/\S+)\s*$")


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
    structure_signature: str


PATH_HEADERS = [
    "rank",
    "slack_ns",
    "status",
    "path_group",
    "source",
    "destination",
    "start_pattern",
    "end_pattern",
    "cause",
    "structure_signature",
    "logic_levels",
    "route_pct",
    "logic_pct",
    "data_delay_ns",
    "requirement_ns",
]


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
    value = re.sub(r"_rep__\d+", "_rep__*", value)
    value = re.sub(r"__\d+(?=/|$)", "__*", value)
    value = re.sub(r"_i_\d+(?=/|$)", "_i_*", value)
    value = re.sub(r"(?<=ramloop)\[[^\]]+\]", "[*]", value)
    value = re.sub(r"\[[^\]]+\]", "[*]", value)
    value = re.sub(r"genblk\d+", "genblk*", value)
    value = re.sub(r"(?<=/)[A-Za-z_]+[0-9]+(?=/)", lambda m: re.sub(r"\d+", "*", m.group(0)), value)
    return value


def normalize_struct_resource(value: str) -> str:
    value = normalize_endpoint(value)
    value = re.sub(r"(?<=_)\d+(?=/|$|_)", "*", value)
    value = re.sub(r"\d+(?=/|$)", "*", value)
    return value


def register_group(value: str) -> str:
    parts = normalize_endpoint(value).split("/")
    if len(parts) <= 2:
        return normalize_endpoint(value)
    leaf = parts[-1]
    leaf = re.sub(r"_reg(?:/.*)?$", "_reg", leaf)
    return "/".join(parts[:-1] + [leaf])


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


def data_path_lines(block: str) -> list[str]:
    sections = re.split(r"^\s*-{20,}.*$", block, flags=re.MULTILINE)
    if len(sections) >= 4:
        return sections[2].splitlines()
    if len(sections) >= 3:
        return sections[1].splitlines()
    else:
        return block.splitlines()


def extract_structure_signature(block: str) -> str:
    cells: list[str] = []
    for line in data_path_lines(block):
        cell_match = DATA_CELL_RE.search(line)
        resource_match = RESOURCE_RE.search(line)
        if not cell_match or not resource_match:
            continue
        cell_type = cell_match.group("cell_type")
        resource = normalize_struct_resource(resource_match.group("resource"))
        if resource.endswith("/C"):
            continue
        leaf = resource.rsplit("/", 1)[-1]
        pin = ""
        if (
            leaf in {"I", "O", "CI", "CO", "S", "DI", "DO", "D", "Q", "CE"}
            or re.fullmatch(r"[A-Z]+\[\*\]", leaf)
            or re.fullmatch(r"[A-Z]+\*", leaf)
        ):
            pin = f"/{leaf}"
            resource = resource.rsplit("/", 1)[0]
        short_resource = resource.split("/")[-1]
        cells.append(f"{cell_type}:{short_resource}{pin}")
    if not cells:
        return "no-structure"
    compact: list[str] = []
    for cell in cells:
        if compact and compact[-1] == cell:
            continue
        compact.append(cell)
    return ">".join(compact)


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
    structure_signature = extract_structure_signature(block)
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
        structure_signature=structure_signature,
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
        print(f"warning: timing report not found: {path}")
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    return [item for item in (parse_path(block) for block in split_paths(text)) if item is not None]


def group_key(path: TimingPath) -> tuple[str, str, str, str]:
    return (
        path.path_group,
        register_group(path.source),
        register_group(path.destination),
        path.structure_signature,
    )


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
    for (path_group, start_pattern, end_pattern, structure_signature), group in groups.items():
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
                "cause": worst.cause,
                "structure_signature": structure_signature,
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
        "structure_signature",
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


def path_row(path: TimingPath, rank: int) -> dict[str, object]:
    return {
        "rank": rank,
        "slack_ns": path.slack,
        "status": path.status,
        "path_group": path.path_group,
        "source": path.source,
        "destination": path.destination,
        "start_pattern": register_group(path.source),
        "end_pattern": register_group(path.destination),
        "cause": path.cause,
        "structure_signature": path.structure_signature,
        "logic_levels": path.logic_levels,
        "route_pct": path.route_pct,
        "logic_pct": path.logic_pct,
        "data_delay_ns": path.data_delay,
        "requirement_ns": path.requirement,
    }


def write_paths_csv(paths: list[TimingPath], out: Path) -> None:
    sorted_paths = sorted(paths, key=lambda item: item.slack)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=PATH_HEADERS)
        writer.writeheader()
        for idx, path in enumerate(sorted_paths, start=1):
            writer.writerow(path_row(path, idx))


def dedupe_worst_paths(paths: list[TimingPath]) -> list[TimingPath]:
    groups: dict[tuple[str, str, str, str], TimingPath] = {}
    for path in paths:
        key = group_key(path)
        if key not in groups or path.slack < groups[key].slack:
            groups[key] = path
    return sorted(groups.values(), key=lambda item: item.slack)


def write_path_table(f, paths: list[TimingPath]) -> None:
    f.write("| Rank | Slack ns | Status | Cause | Route % | Logic Levels | Source | Destination | Structure |\n")
    f.write("| ---: | ---: | --- | --- | ---: | ---: | --- | --- | --- |\n")
    for idx, path in enumerate(paths, start=1):
        signature = path.structure_signature
        if len(signature) > 180:
            signature = f"{signature[:177]}..."
        f.write(
            "| {rank} | {slack} | {status} | {cause} | {route_pct} | {levels} | `{source}` | `{dest}` | `{signature}` |\n".format(
                rank=idx,
                slack=fmt(path.slack),
                status=path.status,
                cause=path.cause,
                route_pct=fmt(path.route_pct, 1),
                levels=fmt(path.logic_levels),
                source=path.source,
                dest=path.destination,
                signature=signature,
            )
        )


def write_markdown(
    rows: list[dict[str, object]],
    paths: list[TimingPath],
    out: Path,
    max_groups: int,
    raw_path_count: int,
) -> None:
    sorted_paths = sorted(paths, key=lambda item: item.slack)
    group_rows = rows[:max_groups]

    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        f.write("# Vivado Timing Violation Summary\n\n")
        if not paths:
            f.write("- Violating paths: 0\n\n")
            f.write("No setup timing violations were found in the parsed reports.\n")
            return

        f.write(f"- Raw violating paths: {raw_path_count}\n")
        f.write(f"- Representative violating paths: {len(paths)}\n")
        f.write(f"- Worst slack: {min(path.slack for path in paths):.3f} ns\n\n")

        f.write("## Violating Similar Path Groups\n\n")
        f.write("| Rank | Count | Worst Slack ns | Avg Slack ns | Cause | Route % | Logic Levels | Start Reg Group | End Reg Group | Structure |\n")
        f.write("| --- | ---: | ---: | ---: | --- | ---: | ---: | --- | --- | --- |\n")
        for idx, row in enumerate(group_rows, start=1):
            signature = str(row["structure_signature"])
            if len(signature) > 160:
                signature = f"{signature[:157]}..."
            f.write(
                "| {rank} | {count} | {worst} | {avg} | {cause} | {route_pct} | {levels} | `{start}` | `{end}` | `{signature}` |\n".format(
                    rank=idx,
                    count=row["count"],
                    worst=fmt(float(row["worst_slack_ns"])),
                    avg=fmt(float(row["avg_slack_ns"])),
                    cause=row["cause"],
                    route_pct=fmt(row["route_pct"] if row["route_pct"] != "" else None, 1),
                    levels=fmt(row["logic_levels"]),
                    start=row["start_pattern"],
                    end=row["end_pattern"],
                    signature=signature,
                )
            )

        f.write(f"\n## Worst Violating Paths (Top {len(sorted_paths)})\n\n")
        write_path_table(f, sorted_paths)

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


def analyze_sweep(report_dir: Path) -> None:
    sweep_csv = report_dir / "implementation_sweep.csv"
    best_file = report_dir / "best_implementation.txt"
    if not sweep_csv.is_file():
        return

    with sweep_csv.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError(f"empty implementation sweep: {sweep_csv}")

    completed: list[tuple[float, dict[str, str]]] = []
    for row in rows:
        wns = row.get("wns_ns", "").strip()
        status = row.get("status", "")
        if re.search(r"fail|error", status, re.IGNORECASE):
            continue
        if not wns:
            raise ValueError(f"successful run {row.get('run')} has no WNS in {sweep_csv}")
        completed.append((float(wns), row))
    if not completed:
        raise ValueError(f"no successful implementation result in {sweep_csv}")

    best_wns, best_row = max(completed, key=lambda item: item[0])
    selected: dict[str, str] = {}
    if best_file.is_file():
        for line in best_file.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                selected[key] = value
        if selected.get("run") != best_row["run"]:
            raise ValueError(
                f"Tcl selected {selected.get('run')}, but parsed best run is {best_row['run']}"
            )

    out = report_dir / "implementation_sweep.md"
    with out.open("w", encoding="utf-8") as f:
        f.write("# Implementation Run Sweep\n\n")
        f.write(f"Best run: `{best_row['run']}` ({best_wns:.3f} ns WNS)\n\n")
        f.write("| Run | Strategy | Status | WNS ns |\n")
        f.write("| --- | --- | --- | ---: |\n")
        for row in sorted(rows, key=lambda item: item["run"]):
            marker = " **(best)**" if row["run"] == best_row["run"] else ""
            f.write(
                f"| `{row['run']}`{marker} | `{row['strategy']}` | "
                f"{row['status']} | {row['wns_ns']} |\n"
            )
    print(f"best implementation run: {best_row['run']} (WNS {best_wns:.3f} ns)")
    print(f"wrote {out}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-dir", type=Path, default=Path("build/syn/reports"))
    parser.add_argument("--timing-report", type=Path, default=None)
    parser.add_argument("--violation-report", type=Path, default=None)
    parser.add_argument("--csv", type=Path, default=None)
    parser.add_argument("--md", type=Path, default=None)
    parser.add_argument("--paths-csv", type=Path, default=None)
    parser.add_argument("--violations-csv", type=Path, default=None)
    parser.add_argument("--max-groups", type=int, default=80)
    parser.add_argument("--max-violating-paths", type=int, default=500)
    args = parser.parse_args()

    report_dir = args.report_dir
    analyze_sweep(report_dir)
    timing_report = args.timing_report or report_dir / "post_route_timing_paths.rpt"
    violation_report = args.violation_report
    csv_out = args.csv or report_dir / "timing_groups.csv"
    md_out = args.md or report_dir / "timing_groups.md"
    paths_csv_out = args.paths_csv or report_dir / "timing_paths.csv"
    violations_csv_out = args.violations_csv or report_dir / "timing_violations.csv"

    violation_paths = load_paths(violation_report) if violation_report is not None else []
    source_paths = violation_paths if violation_paths else load_paths(timing_report)
    paths = sorted((path for path in source_paths if path.slack < 0), key=lambda item: item.slack)
    if args.max_violating_paths > 0:
        paths = paths[: args.max_violating_paths]
    rows = write_csv(paths, csv_out)
    representative_paths = dedupe_worst_paths(paths)
    write_paths_csv(representative_paths, paths_csv_out)
    write_paths_csv(representative_paths, violations_csv_out)
    write_markdown(rows, representative_paths, md_out, args.max_groups, len(paths))

    print(f"parsed {len(paths)} violating timing paths")
    print(f"deduped to {len(representative_paths)} representative paths")
    print(f"wrote {csv_out}")
    print(f"wrote {paths_csv_out}")
    print(f"wrote {violations_csv_out}")
    print(f"wrote {md_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
