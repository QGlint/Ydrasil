#!/usr/bin/env python3
"""生成面向 SW 定向回归的 Verilator 覆盖率摘要。"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path


FOCUS_FILES = {
    "ydrasil_ins_decoder.sv",
    "ydrasil_id_stage.sv",
    "ydrasil_load_store_unit.sv",
    "ydrasil_mems.sv",
}
DISPLAY_TYPES = ("line", "toggle", "branch", "expr", "fsm_state", "fsm_arc")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--info", type=Path, required=True)
    parser.add_argument("--annotated", type=Path, required=True)
    parser.add_argument("--databases", type=int, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--uncovered", type=Path, required=True)
    return parser.parse_args()


def parse_points(path: Path) -> list[dict[str, object]]:
    points: list[dict[str, object]] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw.startswith("C "):
            continue
        fields: dict[str, object] = {}
        quote_end = raw.rfind("' ")
        if quote_end < 3:
            continue
        payload = raw[3:quote_end]
        for item in payload.split("\x01"):
            if "\x02" not in item:
                continue
            key, value = item.split("\x02", 1)
            fields[key] = int(value) if value.lstrip("-").isdigit() else value
        try:
            fields["count"] = int(raw.rsplit(maxsplit=1)[-1])
        except ValueError:
            continue
        points.append(fields)
    return points


def normalized_type(point: dict[str, object]) -> str:
    point_type = str(point.get("type", point.get("t", "")))
    if point_type == "block":
        return "line"
    if point_type.startswith("branch"):
        return "branch"
    if point_type.startswith("expr"):
        return "expr"
    if point_type.startswith("fsm_state"):
        return "fsm_state"
    if point_type.startswith("fsm_arc"):
        return "fsm_arc"
    return point_type


def lcov_counts(path: Path) -> tuple[int, int]:
    hit = total = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("DA:"):
            continue
        total += 1
        if int(line.split(",", 1)[1]) > 0:
            hit += 1
    return hit, total


def annotation_counts(path: Path) -> tuple[int, int]:
    covered = total = 0
    for source in path.rglob("*.sv"):
        for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
            match = re.match(r"^( |%)([0-9]+)[ \t]", line)
            if not match:
                continue
            total += 1
            if match.group(1) == " " and int(match.group(2)) > 0:
                covered += 1
    return covered, total


def source_text(filename: str, lineno: int) -> str:
    path = Path(filename)
    if not path.is_file() or lineno < 1:
        return ""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return lines[lineno - 1].strip() if lineno <= len(lines) else ""


def classify(text: str) -> str:
    lowered = text.lower()
    if "mmio" in lowered or "perip" in lowered:
        return "OUT_OF_SCOPE_MMIO"
    if re.search(r"op_lsu_s[bh]|issue_lsu_is_s[bh]|_s[bh]_data", lowered):
        return "OUT_OF_SCOPE_SB_SH"
    if "pending_store" in lowered or "store_pending" in lowered:
        return "UNREACHED_PENDING_STORE"
    if re.search(r"\bload\b|load_|is_load|op_lsu_l|rdata|wb_result", lowered):
        return "OUT_OF_SCOPE_LOAD"
    if "operator" in lowered:
        return "OUT_OF_SCOPE_OTHER_OP"
    return "REVIEW_SW_REACHABILITY"


def percent(hit: int, total: int) -> str:
    return f"{(100.0 * hit / total):.1f}" if total else "0.0"


def main() -> int:
    args = parse_args()
    points = parse_points(args.data)
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for point in points:
        kind = normalized_type(point)
        if kind in DISPLAY_TYPES:
            totals[kind][1] += 1
            if int(point["count"]) > 0:
                totals[kind][0] += 1

    annotation_hit, annotation_total = annotation_counts(args.annotated)
    lcov_hit, lcov_total = lcov_counts(args.info)

    lines = [f"[COVERAGE] Merging {args.databases} test databases", "Coverage Summary:"]
    for kind in DISPLAY_TYPES:
        hit, total = totals[kind]
        lines.append(f"  {kind:<10}: {percent(hit, total):>5}% ({hit:5d}/{total:5d})")
    lines.extend(
        [
            "Annotation Summary:",
            f"  lines with all attached points covered: "
            f"{100.0 * annotation_hit / annotation_total if annotation_total else 0.0:.2f}% "
            f"({annotation_hit}/{annotation_total})",
            f"See lines with '%00' in {args.annotated}",
            f"[COVERAGE] LCOV source-line coverage: {lcov_hit}/{lcov_total} "
            f"({percent(lcov_hit, lcov_total)}%)",
            f"[COVERAGE] Merged data: {args.data}",
            f"[COVERAGE] LCOV: {args.info}",
            f"[COVERAGE] Annotated RTL: {args.annotated}",
            f"[COVERAGE] Summary: {args.summary}",
        ]
    )

    uncovered_lines = [
        "SW 数据通路零命中点（自动初筛）",
        "分类仅用于缩小审查范围；REVIEW_SW_REACHABILITY 需要人工确认。",
    ]
    seen_uncovered: set[tuple[str, int, str]] = set()
    for point in points:
        if int(point["count"]) != 0:
            continue
        filename = str(point.get("filename", point.get("f", "")))
        if Path(filename).name not in FOCUS_FILES:
            continue
        lineno = int(point.get("lineno", point.get("l", 0)))
        text = source_text(filename, lineno)
        kind = normalized_type(point)
        key = (Path(filename).name, lineno, kind)
        if key in seen_uncovered:
            continue
        seen_uncovered.add(key)
        uncovered_lines.append(
            f"{classify(text):<24} {Path(filename).name}:{lineno} [{kind}] {text}"
        )
    if len(uncovered_lines) == 2:
        uncovered_lines.append("无零命中点。")

    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    args.uncovered.write_text("\n".join(uncovered_lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"[COVERAGE] SW-path review: {args.uncovered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
