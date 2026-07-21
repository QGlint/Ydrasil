#!/usr/bin/env python3
"""Analyze uncovered Verilator points and incomplete signal toggles."""

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from coverage_summary import normalized_type, parse_points


POINT_TYPES = ("line", "toggle", "branch", "expr", "fsm_state", "fsm_arc")
CORE_POINT_TYPES = ("line", "branch", "expr")
TOGGLE_RE = re.compile(r"^(?P<bit>.+):(?P<direction>[01]->[01])$")
PACKED_INDEX_RE = re.compile(r"(?:\[[0-9]+\])+$")


@dataclass(frozen=True)
class ToggleBit:
    filename: str
    lineno: int
    column: int
    hierarchy: str
    signal: str
    bit: str
    rise: int
    fall: int

    @property
    def missing_directions(self) -> int:
        return int(self.rise == 0) + int(self.fall == 0)

    @property
    def state(self) -> str:
        if self.rise == 0 and self.fall == 0:
            return "NEVER"
        if self.rise == 0:
            return "NO_0_TO_1"
        if self.fall == 0:
            return "NO_1_TO_0"
        return "FULL"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--toggle-csv", type=Path, required=True)
    parser.add_argument("--point-csv", type=Path, required=True)
    parser.add_argument("--top", type=int, default=30)
    return parser.parse_args()


def scope(filename: str) -> str:
    path = filename.replace("\\", "/")
    name = Path(filename).name
    if "/dv/" in path or name.endswith("_tb.sv") or name == "ydrasil_commit_trace.sv":
        return "testbench"
    if "/jyd_fpga/rtl/" in path or name in {"counter.sv", "perip_bridge.sv", "display_seg.sv", "seg7.sv"}:
        return "peripheral"
    if "/ydrasil_core/rtl/" in path:
        return "core"
    return "memory"


def source_line(filename: str, lineno: int, cache: dict[str, list[str]]) -> str:
    if lineno < 1:
        return ""
    if filename not in cache:
        path = Path(filename)
        cache[filename] = (
            path.read_text(encoding="utf-8", errors="replace").splitlines()
            if path.is_file()
            else []
        )
    lines = cache[filename]
    return lines[lineno - 1].strip() if lineno <= len(lines) else ""


def hint(signal: str, text: str, point_scope: str) -> str:
    value = f"{signal} {text}".lower()
    if point_scope == "testbench":
        return "TESTBENCH"
    if point_scope == "peripheral":
        return "PERIPHERAL"
    if re.search(r"=\s*(?:[0-9]+'[bdh][0x]+|'0|0)\s*;", text.lower()):
        return "TIED_OFF_OR_CONSTANT"
    if any(word in value for word in ("debug", "dret")):
        return "DEBUG_PATH"
    if any(word in value for word in ("interrupt", "exception", "ecall", "ebreak", "mret", "csr_", "mcause", "mepc")):
        return "TRAP_OR_CSR"
    if any(word in value for word in ("mmio", "perip", "virtual_key", "virtual_sw")):
        return "MMIO_OR_BOARD_IO"
    if any(word in value for word in ("full", "state", "pending", "queue", "fifo")):
        return "STATE_OR_BACKPRESSURE"
    if any(word in value for word in ("addr", "target", "pc")):
        return "ADDRESS_RANGE"
    return "REVIEW"


def percent(hit: int, total: int) -> str:
    return f"{100.0 * hit / total:.1f}%" if total else "N/A"


def point_totals(points: list[dict[str, object]], wanted_scope: str | None = None) -> dict[str, tuple[int, int]]:
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for point in points:
        filename = str(point.get("filename", point.get("f", "")))
        if wanted_scope and scope(filename) != wanted_scope:
            continue
        kind = normalized_type(point)
        if kind not in POINT_TYPES:
            continue
        totals[kind][1] += 1
        totals[kind][0] += int(int(point["count"]) > 0)
    return {kind: tuple(totals[kind]) for kind in POINT_TYPES}


def toggle_bits(points: list[dict[str, object]]) -> list[ToggleBit]:
    directions: dict[tuple[str, int, int, str, str], dict[str, int]] = defaultdict(dict)
    for point in points:
        if normalized_type(point) != "toggle":
            continue
        descriptor = str(point.get("o", ""))
        match = TOGGLE_RE.match(descriptor)
        if not match:
            continue
        filename = str(point.get("filename", point.get("f", "")))
        lineno = int(point.get("lineno", point.get("l", 0)))
        column = int(point.get("column", point.get("n", 0)))
        hierarchy = str(point.get("hier", point.get("h", "")))
        bit = match.group("bit")
        key = (filename, lineno, column, hierarchy, bit)
        directions[key][match.group("direction")] = int(point["count"])

    result = []
    for (filename, lineno, column, hierarchy, bit), counts in directions.items():
        result.append(
            ToggleBit(
                filename=filename,
                lineno=lineno,
                column=column,
                hierarchy=hierarchy,
                signal=PACKED_INDEX_RE.sub("", bit),
                bit=bit,
                rise=counts.get("0->1", 0),
                fall=counts.get("1->0", 0),
            )
        )
    return result


def markdown_table(headers: tuple[str, ...], rows: list[tuple[object, ...]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    lines.extend("| " + " | ".join(str(item).replace("|", "\\|") for item in row) + " |" for row in rows)
    return lines


def main() -> int:
    args = parse_args()
    points = parse_points(args.data)
    bits = toggle_bits(points)
    source_cache: dict[str, list[str]] = {}

    totals = point_totals(points)
    core_totals = point_totals(points, "core")
    module_gaps: dict[tuple[str, str], int] = defaultdict(int)
    uncovered_points: list[tuple[str, str, int, str, str, str]] = []
    for point in points:
        if int(point["count"]) != 0:
            continue
        kind = normalized_type(point)
        if kind not in CORE_POINT_TYPES:
            continue
        filename = str(point.get("filename", point.get("f", "")))
        lineno = int(point.get("lineno", point.get("l", 0)))
        point_scope = scope(filename)
        text = source_line(filename, lineno, source_cache)
        module_gaps[(Path(filename).name, kind)] += 1
        uncovered_points.append((point_scope, kind, lineno, filename, text, hint("", text, point_scope)))

    grouped: dict[tuple[str, int, int, str, str], list[ToggleBit]] = defaultdict(list)
    for bit in bits:
        grouped[(bit.filename, bit.lineno, bit.column, bit.hierarchy, bit.signal)].append(bit)

    signal_rows = []
    for (filename, lineno, column, hierarchy, signal), signal_bits in grouped.items():
        missing = sum(bit.missing_directions for bit in signal_bits)
        if not missing:
            continue
        never = sum(bit.state == "NEVER" for bit in signal_bits)
        partial = sum(bit.state in {"NO_0_TO_1", "NO_1_TO_0"} for bit in signal_bits)
        text = source_line(filename, lineno, source_cache)
        signal_rows.append(
            {
                "scope": scope(filename),
                "module": Path(filename).name,
                "filename": filename,
                "line": lineno,
                "hierarchy": hierarchy,
                "signal": signal,
                "bits": len(signal_bits),
                "never": never,
                "partial": partial,
                "missing": missing,
                "hint": hint(signal, text, scope(filename)),
                "source": text,
            }
        )
    signal_rows.sort(
        key=lambda row: (
            -int(row["missing"]),
            -int(row["never"]),
            str(row["module"]),
            str(row["signal"]),
        )
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.toggle_csv.parent.mkdir(parents=True, exist_ok=True)
    args.point_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.toggle_csv.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(
            (
                "scope", "module", "line", "column", "hierarchy", "signal",
                "bit", "state", "count_0_to_1", "count_1_to_0", "hint", "source",
            )
        )
        incomplete_bits = (item for item in bits if item.missing_directions)
        for bit in sorted(
            incomplete_bits,
            key=lambda item: (
                scope(item.filename), Path(item.filename).name,
                item.lineno, item.bit,
            ),
        ):
            text = source_line(bit.filename, bit.lineno, source_cache)
            writer.writerow(
                (
                    scope(bit.filename), Path(bit.filename).name, bit.lineno,
                    bit.column, bit.hierarchy, bit.signal, bit.bit, bit.state,
                    bit.rise, bit.fall,
                    hint(bit.signal, text, scope(bit.filename)), text,
                )
            )

    with args.point_csv.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(("scope", "type", "module", "line", "hint", "source", "filename"))
        ordered_points = sorted(
            uncovered_points, key=lambda row: (row[0], row[3], row[2], row[1])
        )
        for point_scope, kind, lineno, filename, text, point_hint in ordered_points:
            writer.writerow(
                (point_scope, kind, Path(filename).name, lineno,
                 point_hint, text, filename)
            )

    states = ("FULL", "NEVER", "NO_0_TO_1", "NO_1_TO_0")
    bit_state_counts = {
        state: sum(bit.state == state for bit in bits) for state in states
    }
    core_bits = [bit for bit in bits if scope(bit.filename) == "core"]
    core_state_counts = {state: sum(bit.state == state for bit in core_bits) for state in bit_state_counts}

    report = [
        "# Verilator coverage gap analysis",
        "",
        f"Generated: {datetime.now().astimezone().isoformat(timespec='seconds')}",
        f"Data: `{args.data.resolve()}`",
        "",
        "## Coverage point summary",
        "",
    ]
    rows = []
    for kind in POINT_TYPES:
        hit, total = totals[kind]
        core_hit, core_total = core_totals[kind]
        rows.append(
            (kind, f"{hit}/{total}", percent(hit, total),
             f"{core_hit}/{core_total}", percent(core_hit, core_total))
        )
    report.extend(markdown_table(("Type", "All", "All %", "Core RTL", "Core RTL %"), rows))
    report.extend([
        "",
        "`line` above is Verilator block/line-point coverage. Annotated `%00` "
        "lines can also be caused by toggle, branch, or expression points.",
        "",
        "## Toggle direction analysis",
        "",
    ])
    toggle_rows = []
    toggle_sets = (
        ("All scopes", bits, bit_state_counts),
        ("Core RTL", core_bits, core_state_counts),
    )
    for label, collection, counts in toggle_sets:
        toggle_rows.append(
            (label, len(collection), counts["FULL"], counts["NEVER"],
             counts["NO_0_TO_1"], counts["NO_1_TO_0"])
        )
    report.extend(
        markdown_table(
            ("Scope", "Bits", "Both directions", "Never toggled",
             "Missing 0->1", "Missing 1->0"),
            toggle_rows,
        )
    )
    report.extend([
        "",
        "A never-toggled bit has zero counts in both directions. A one-way bit has exactly one missing direction.",
        "",
        "## Core RTL modules with uncovered control points",
        "",
    ])
    module_rows = []
    for module in sorted({module for module, _ in module_gaps}):
        values = [module_gaps[(module, kind)] for kind in CORE_POINT_TYPES]
        if any(values) and any(row[0] == "core" and Path(row[3]).name == module for row in uncovered_points):
            module_rows.append((module, *values, sum(values)))
    module_rows.sort(key=lambda row: (-int(row[-1]), str(row[0])))
    report.extend(markdown_table(("Module", "Line", "Branch", "Expr", "Total"), module_rows))

    core_control = [row for row in uncovered_points if row[0] == "core"]
    report.extend(["", "## Uncovered core line points", ""])
    line_rows = [
        (Path(filename).name, lineno, point_hint, f"`{text}`")
        for _, kind, lineno, filename, text, point_hint in core_control
        if kind == "line"
    ]
    report.extend(markdown_table(("Module", "Line", "Hint", "RTL"), line_rows) if line_rows else ["None."])

    report.extend(["", f"## Top {args.top} core signals with incomplete toggles", ""])
    core_signal_rows = [row for row in signal_rows if row["scope"] == "core"][: args.top]
    report.extend(markdown_table(
        ("Module:line", "Signal", "Bits", "Never", "One-way", "Missing dirs", "Hint"),
        [
            (f"{row['module']}:{row['line']}", row["signal"], row["bits"],
             row["never"], row["partial"], row["missing"], row["hint"])
            for row in core_signal_rows
        ],
    ))

    report.extend(["", "## Core small control/state signals with incomplete toggles", ""])
    small_control_rows = [
        row for row in signal_rows
        if row["scope"] == "core" and int(row["bits"]) <= 4 and int(row["never"]) > 0
    ][: args.top]
    report.extend(markdown_table(
        ("Module:line", "Signal", "Bits", "Never", "One-way", "Hint", "RTL"),
        [
            (f"{row['module']}:{row['line']}", row["signal"], row["bits"],
             row["never"], row["partial"], row["hint"], f"`{row['source']}`")
            for row in small_control_rows
        ],
    ))

    report.extend(["", "## Scope contribution to missing toggle directions", ""])
    scope_rows = []
    for point_scope in ("core", "peripheral", "memory", "testbench"):
        scoped = [bit for bit in bits if scope(bit.filename) == point_scope]
        scope_rows.append(
            (point_scope, len(scoped),
             sum(bit.missing_directions for bit in scoped),
             sum(bit.state == "NEVER" for bit in scoped))
        )
    report.extend(markdown_table(("Scope", "Bits", "Missing directions", "Never-toggled bits"), scope_rows))
    report.extend([
        "",
        "## Detailed artifacts",
        "",
        f"- Incomplete toggle bits: `{args.toggle_csv.resolve()}`",
        f"- Uncovered line/branch/expression points: `{args.point_csv.resolve()}`",
        "",
    ])
    args.output.write_text("\n".join(report), encoding="utf-8")
    print(f"Wrote {args.output}")
    print(f"Wrote {args.toggle_csv}")
    print(f"Wrote {args.point_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
