#!/usr/bin/env python3
"""Calibrate rtl-quickcheck metrics against Vivado reports.

The comparison is deliberately descriptive.  Vivado may flatten or move
logic across hierarchy, so the report never treats a hierarchy row as a
one-to-one prediction of the RTL module.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter
import hashlib
import json
import math
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RESOURCE_KEYS = ("lut", "logic_lut", "lutram", "srl", "ff", "ramb36", "ramb18", "dsp")
EXCLUDED_MODULES = {"dtcm", "itcm"}
DEFAULT_ROUTE_DOMINATED_FRACTION = 0.65


def structural_calibration_fingerprint(dataset: dict[str, Any]) -> str | None:
    rows = []
    for row in sorted(dataset.get("modules", []), key=lambda item: str(item.get("module", ""))):
        rows.append({
            key: row.get(key)
            for key in (
                "module",
                "rtl_register_bits",
                "rtl_max_depth",
                "rtl_cross_module_max_depth",
                "rtl_timing_depth_proxy",
                "rtl_endpoint_timing_depth_proxy",
                "rtl_input_boundary_max_depth",
                "rtl_data_boundary_max_depth",
                "rtl_control_boundary_max_depth",
                "rtl_output_boundary_max_depth",
                "rtl_weighted_combination_work",
                "rtl_packed_consumer_work",
                "rtl_memory_kind",
            )
        })
    if not rows:
        return None
    encoded = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def utc_mtime(path: Path) -> str | None:
    if not path.is_file():
        return None
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()


def comparison_provenance(
    structure_path: Path,
    structure: dict[str, Any],
    timing_paths: list[Path],
) -> dict[str, Any]:
    structure_provenance = structure.get("provenance", {})
    source_metadata_path = structure_provenance.get("source_metadata")
    source_metadata = None
    if source_metadata_path:
        try:
            source_metadata = json.loads(Path(source_metadata_path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            source_metadata = None
    sources = [Path(item) for item in (source_metadata or {}).get("sources", [])]
    source_mtimes = [path.stat().st_mtime for path in sources if path.is_file()]
    latest_source_mtime = max(source_mtimes, default=None)
    report_snapshots = []
    for path in timing_paths:
        mtime = path.stat().st_mtime if path.is_file() else None
        report_snapshots.append({
            "path": str(path),
            "available": path.is_file(),
            "mtime_utc": utc_mtime(path),
            "not_older_than_latest_rtl_source": (
                mtime >= latest_source_mtime
                if mtime is not None and latest_source_mtime is not None else None
            ),
        })

    repo_root = Path(__file__).resolve().parents[1]
    try:
        current_revision = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        current_revision = None
    try:
        rtl_status = subprocess.run(
            ["git", "-C", str(repo_root), "status", "--porcelain", "--", "hw/ip"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        rtl_status = "unknown"

    structure_revision = structure_provenance.get("git_revision")
    revision_matches = bool(
        structure_revision and current_revision and structure_revision == current_revision
    )
    report_freshness = [
        item["not_older_than_latest_rtl_source"]
        for item in report_snapshots
        if item["available"] and item["not_older_than_latest_rtl_source"] is not None
    ]
    if revision_matches and rtl_status == "" and report_freshness and all(report_freshness):
        status = "current_rtl_snapshot_and_reports_not_older_than_sources"
    elif report_freshness and not all(report_freshness):
        status = "report_predates_current_rtl_sources"
    elif structure_revision and current_revision and not revision_matches:
        status = "structure_revision_does_not_match_worktree"
    else:
        status = "unverified"
    return {
        "status": status,
        "structure": str(structure_path),
        "structure_mtime_utc": utc_mtime(structure_path),
        "structure_git_revision": structure_revision,
        "current_git_revision": current_revision,
        "structure_revision_matches_worktree": revision_matches,
        "rtl_worktree_dirty": bool(rtl_status),
        "rtl_worktree_status": rtl_status.splitlines() if rtl_status not in {"", "unknown"} else [],
        "source_fingerprint": structure_provenance.get("source_fingerprint"),
        "source_count": structure_provenance.get("source_count"),
        "latest_rtl_source_mtime_utc": (
            datetime.fromtimestamp(latest_source_mtime, timezone.utc).isoformat()
            if latest_source_mtime is not None else None
        ),
        "timing_reports": report_snapshots,
        "limitation": (
            "Vivado text reports do not embed a Git revision. Freshness proves the report is not older than the "
            "current RTL files, but exact source identity requires a synthesis-side source fingerprint."
        ),
    }


def parse_int(value: str) -> int:
    return int(value.replace(",", "").strip() or 0)


def parse_utilization(path: Path) -> dict[str, dict[str, Any]]:
    rows: dict[str, list[dict[str, Any]]] = {}
    if not path.is_file():
        return {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        fields = [field.strip() for field in line.strip().strip("|").split("|")]
        if len(fields) < 10 or fields[0] == "Instance" or not re.fullmatch(r"[0-9,]+", fields[2]):
            continue
        row = {"instance": fields[0], "module": fields[1]}
        for key, value in zip(RESOURCE_KEYS, fields[2:10]):
            try:
                row[key] = parse_int(value)
            except ValueError:
                row[key] = 0
        rows.setdefault(row["module"], []).append(row)

    result = {}
    for module, candidates in rows.items():
        def score(row: dict[str, Any]) -> tuple[int, int]:
            instance = row["instance"]
            # Prefer the actual Core_cpu/u_* row over Vivado's child detail
            # rows such as ``(u_ctrl)`` and generated RAM implementation rows.
            exact = 0
            if module == "ydrasil_core" and instance == "Core_cpu":
                exact = 100
            elif module.startswith("ydrasil_") and instance == "u_" + module[len("ydrasil_"):]:
                exact = 100
            elif instance.startswith("u_"):
                exact = 80
            elif instance.startswith("("):
                exact = 10
            return exact, sum(int(row.get(key, 0)) for key in RESOURCE_KEYS)

        result[module] = max(candidates, key=score)
    return result


def parse_logic_cells(block: str, declared: dict[str, int]) -> list[dict[str, Any]]:
    """Extract the data-path primitives counted by Vivado's Logic Levels row."""
    cells = []
    counted: Counter[str] = Counter()
    lines = block.splitlines()
    for number, line in enumerate(lines):
        if "(Prop_" not in line:
            continue
        fields = line.split()
        primitive = next(
            (
                token
                for index, token in enumerate(fields[:-1])
                if token in declared and fields[index + 1].startswith("(Prop_")
            ),
            None,
        )
        if primitive is None:
            continue
        resource = next((token for token in reversed(fields) if "/" in token), None)
        timing_text = line
        if resource is None:
            # RAMD/CARRY/RAMB rows wrap the delay and resource onto the next
            # line.  Stop before a new timing row if the expected continuation
            # is absent.
            for continuation in lines[number + 1:number + 3]:
                if "(Prop_" in continuation or re.match(r"^\s*-{10,}", continuation):
                    break
                timing_text += "\n" + continuation
                resource = next(
                    (token for token in reversed(continuation.split()) if "/" in token),
                    None,
                )
                if resource is not None:
                    break
        increment = re.search(r"\)\s+([-+]?\d+(?:\.\d+)?)", timing_text)
        # A cascaded RAMB can expose two propagation arcs while Vivado counts
        # the cascade as one logic level.  Retain both cells for inspection,
        # but only attribute the number of levels declared in the summary.
        counts_as_logic_level = counted[primitive] < declared[primitive]
        if counts_as_logic_level:
            counted[primitive] += 1
        cells.append({
            "primitive": primitive,
            "resource": resource,
            "counts_as_logic_level": counts_as_logic_level,
            "increment_ns": float(increment.group(1)) if increment else None,
        })
    return cells


def parse_timing(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {"report": str(path), "available": path.is_file(), "net_fanout": {}, "paths": []}
    if not path.is_file():
        return result
    text = path.read_text(encoding="utf-8", errors="replace")
    def first_float(pattern: str) -> float | None:
        match = re.search(pattern, text, re.I)
        if not match:
            return None
        return float(match.group(1))

    result["wns_ns"] = first_float(r"Slack \([^)]*\)\s*:\s*([-+]?\d+(?:\.\d+)?)ns")
    result["tns_ns"] = first_float(r"Total Negative Slack \(TNS\).*?([-+]?\d+(?:\.\d+)?)ns")
    summary = re.search(
        r"WNS\(ns\).*?TNS\(ns\).*?\n\s*[- ]+\n\s*([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)",
        text,
        re.S,
    )
    if summary:
        result["wns_ns"] = float(summary.group(1))
        result["tns_ns"] = float(summary.group(2))
    result["data_path_delay_ns"] = first_float(r"Data Path Delay:\s*([-+]?\d+(?:\.\d+)?)ns")
    result["logic_levels"] = first_float(r"Logic Levels:\s*(\d+)")
    source = re.search(r"^\s*Source:\s+(.+)$", text, re.M)
    destination = re.search(r"^\s*Destination:\s+(.+)$", text, re.M)
    if source:
        result["critical_source"] = source.group(1).strip()
    if destination:
        result["critical_destination"] = destination.group(1).strip()

    def parse_path_delays(block: str) -> dict[str, float | str | None]:
        match = re.search(
            r"Data Path Delay:\s*([-+]?\d+(?:\.\d+)?)ns\s*"
            r"\(logic\s+([-+]?\d+(?:\.\d+)?)ns\s*\(([-+]?\d+(?:\.\d+)?)%\)\s*"
            r"route\s+([-+]?\d+(?:\.\d+)?)ns\s*\(([-+]?\d+(?:\.\d+)?)%\)\)",
            block,
        )
        if not match:
            return {
                "logic_delay_ns": None,
                "route_delay_ns": None,
                "logic_fraction": None,
                "route_fraction": None,
            }
        return {
            "logic_delay_ns": float(match.group(2)),
            "route_delay_ns": float(match.group(4)),
            "logic_fraction": float(match.group(3)) / 100.0,
            "route_fraction": float(match.group(5)) / 100.0,
        }

    path_pattern = re.compile(
        r"^\s*Source:\s+([^\n]+).*?^\s*Destination:\s+([^\n]+).*?"
        r"^\s*Data Path Delay:\s*([-+]?\d+(?:\.\d+)?)ns.*?"
        r"^\s*Logic Levels:\s*(\d+)(?:\s+\(([^)\n]*)\))?",
        re.M | re.S,
    )
    path_matches = list(path_pattern.finditer(text))
    for number, match in enumerate(path_matches):
        end = path_matches[number + 1].start() if number + 1 < len(path_matches) else len(text)
        declared = {
            primitive: int(count)
            for primitive, count in re.findall(r"([A-Za-z][A-Za-z0-9_]*)=(\d+)", match.group(5) or "")
        }
        cells = parse_logic_cells(text[match.end():end], declared)
        path_delays = parse_path_delays(text[match.start():end])
        destination_text = match.group(2).strip()
        endpoint_pin = (
            "CE" if re.search(r"/CE(?:\[[^]]+\])?$", destination_text)
            else "D" if re.search(r"/D(?:\[[^]]+\])?$", destination_text)
            else "other"
        )
        result["paths"].append({
            "source": match.group(1).strip(),
            "destination": match.group(2).strip(),
            "data_path_delay_ns": float(match.group(3)),
            "logic_levels": int(match.group(4)),
            "endpoint_pin": endpoint_pin,
            **path_delays,
            "declared_primitives": declared,
            "parsed_logic_levels": sum(bool(cell["counts_as_logic_level"]) for cell in cells),
            "physical_timing_arc_count": len(cells),
            "logic_cells": cells,
        })
    # Keep the maximum observed fanout per RTL spelling.  The report can list
    # replicated nets (for example fetchq_count_q_reg[1]_rep__0_4).
    for match in re.finditer(r"net \(fo=(\d+),[^)]*\).*?\s([A-Za-z_][A-Za-z0-9_$./\[\]-]*)\s*$", text, re.M):
        fanout = int(match.group(1))
        net = match.group(2)
        base = net.rsplit("/", 1)[-1]
        base = re.sub(r"_reg(?:\[[^]]+\])?", "", base)
        base = re.sub(r"_rep__.*$", "", base)
        result["net_fanout"][base] = max(fanout, int(result["net_fanout"].get(base, 0)))
    return result


def parse_timing_csv(path: Path) -> dict[str, Any]:
    """Read the compact Vivado path CSV emitted by syn/analyze_timing.py."""
    result: dict[str, Any] = {
        "report": str(path),
        "format": "vivado_timing_csv",
        "available": path.is_file(),
        "net_fanout": {},
        "paths": [],
    }
    if not path.is_file():
        return result
    try:
        records = list(csv.DictReader(path.read_text(encoding="utf-8", errors="replace").splitlines()))
    except OSError:
        return result
    for row in records:
        try:
            delay = float(row.get("data_delay_ns", ""))
            levels = int(float(row.get("logic_levels", "0")))
        except (TypeError, ValueError):
            continue
        destination = str(row.get("destination", "")).strip()
        endpoint_pin = (
            "CE" if re.search(r"/CE(?:\[[^]]+\])?$", destination)
            else "D" if re.search(r"/D(?:\[[^]]+\])?$", destination)
            else "other"
        )
        route_fraction = None
        logic_fraction = None
        try:
            route_fraction = float(row.get("route_pct", "")) / 100.0
        except (TypeError, ValueError):
            pass
        try:
            logic_fraction = float(row.get("logic_pct", "")) / 100.0
        except (TypeError, ValueError):
            pass
        result["paths"].append({
            "source": str(row.get("source", "")).strip(),
            "destination": destination,
            "data_path_delay_ns": delay,
            "logic_levels": levels,
            "endpoint_pin": endpoint_pin,
            "logic_delay_ns": delay * logic_fraction if logic_fraction is not None else None,
            "route_delay_ns": delay * route_fraction if route_fraction is not None else None,
            "logic_fraction": logic_fraction,
            "route_fraction": route_fraction,
            "cause": row.get("cause"),
            "structure_signature": row.get("structure_signature"),
            "slack_ns": float(row["slack_ns"]) if row.get("slack_ns") else None,
            "status": row.get("status"),
            "path_group": row.get("path_group"),
            "declared_primitives": {},
            "parsed_logic_levels": levels,
            "physical_timing_arc_count": 0,
            "logic_cells": [],
            "module_logic_levels": {},
            "module_hier_logic_levels": {},
            "unattributed_logic_levels": levels,
        })
    result["path_count"] = len(result["paths"])
    result["logic_level_parse_coverage"] = {
        "path_count": len(result["paths"]),
        "exact_path_count": len(result["paths"]),
        "exact_path_ratio": 1.0 if result["paths"] else None,
        "under_parsed_path_count": 0,
        "over_parsed_path_count": 0,
        "declared_logic_levels": sum(item["logic_levels"] for item in result["paths"]),
        "parsed_logic_levels": sum(item["logic_levels"] for item in result["paths"]),
        "parsed_level_ratio": 1.0 if result["paths"] else None,
        "primitive_count_delta": {},
        "unattributed_logic_levels": 0,
        "attributed_logic_levels": 0,
        "attributed_level_ratio": None,
        "unattributed_primitives": {},
    }
    return result


def module_alias_map(module_names: set[str]) -> dict[str, str]:
    aliases = {}
    for module in sorted(module_names):
        candidates = {f"u_{module}"}
        if module.startswith("ydrasil_"):
            candidates.add("u_" + module[len("ydrasil_"):])
        if module == "ydrasil_core":
            candidates.add("Core_cpu")
        for alias in candidates:
            aliases.setdefault(alias, module)
    return aliases


def hierarchy_modules(resource: str | None, aliases: dict[str, str]) -> list[str]:
    if not resource:
        return []
    result = []
    for segment in resource.split("/"):
        module = aliases.get(segment)
        if module is not None and (not result or result[-1] != module):
            result.append(module)
    return result


def endpoint_module(resource: str | None, aliases: dict[str, str]) -> str | None:
    modules = hierarchy_modules(resource, aliases)
    return modules[-1] if modules else None


def attribute_timing_report(report: dict[str, Any], module_names: set[str]) -> None:
    aliases = module_alias_map(module_names)
    if report.get("format") == "vivado_timing_csv":
        for path in report.get("paths", []):
            path["source_module"] = endpoint_module(path.get("source"), aliases)
            path["destination_module"] = endpoint_module(path.get("destination"), aliases)
        return
    declared_total = 0
    parsed_total = 0
    exact_paths = 0
    under_paths = 0
    over_paths = 0
    declared_primitives: Counter[str] = Counter()
    parsed_primitives: Counter[str] = Counter()
    unattributed_primitives: Counter[str] = Counter()
    for path in report.get("paths", []):
        path["source_module"] = endpoint_module(path.get("source"), aliases)
        path["destination_module"] = endpoint_module(path.get("destination"), aliases)
        local_counts: Counter[str] = Counter()
        hierarchical_counts: Counter[str] = Counter()
        unattributed = 0
        for cell in path.get("logic_cells", []):
            modules = hierarchy_modules(cell.get("resource"), aliases)
            cell["module_hierarchy"] = modules
            cell["module"] = modules[-1] if modules else None
            if not cell.get("counts_as_logic_level", True):
                continue
            if modules:
                local_counts[modules[-1]] += 1
                hierarchical_counts.update(set(modules))
            else:
                unattributed += 1
                unattributed_primitives[cell["primitive"]] += 1
            parsed_primitives[cell["primitive"]] += 1
        path["module_logic_levels"] = dict(sorted(local_counts.items()))
        path["module_hier_logic_levels"] = dict(sorted(hierarchical_counts.items()))
        path["unattributed_logic_levels"] = unattributed
        declared = int(path.get("logic_levels", 0))
        parsed = int(path.get("parsed_logic_levels", 0))
        declared_total += declared
        parsed_total += parsed
        declared_primitives.update(path.get("declared_primitives", {}))
        if parsed == declared:
            exact_paths += 1
        elif parsed < declared:
            under_paths += 1
        else:
            over_paths += 1
    path_count = len(report.get("paths", []))
    primitive_delta = {
        primitive: declared_primitives[primitive] - parsed_primitives[primitive]
        for primitive in sorted(set(declared_primitives) | set(parsed_primitives))
        if declared_primitives[primitive] != parsed_primitives[primitive]
    }
    report["logic_level_parse_coverage"] = {
        "path_count": path_count,
        "exact_path_count": exact_paths,
        "exact_path_ratio": exact_paths / path_count if path_count else None,
        "under_parsed_path_count": under_paths,
        "over_parsed_path_count": over_paths,
        "declared_logic_levels": declared_total,
        "parsed_logic_levels": parsed_total,
        "parsed_level_ratio": parsed_total / declared_total if declared_total else None,
        "primitive_count_delta": primitive_delta,
        "unattributed_logic_levels": sum(unattributed_primitives.values()),
        "attributed_logic_levels": parsed_total - sum(unattributed_primitives.values()),
        "attributed_level_ratio": (
            (parsed_total - sum(unattributed_primitives.values())) / parsed_total
            if parsed_total else None
        ),
        "unattributed_primitives": dict(sorted(unattributed_primitives.items())),
    }


def path_modules(path: dict[str, Any], module_names: set[str]) -> set[str]:
    aliases = module_alias_map(module_names)
    result = set(hierarchy_modules(path.get("source"), aliases))
    result.update(hierarchy_modules(path.get("destination"), aliases))
    return result


def rank(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=lambda item: values[item])
    result = [0.0] * len(values)
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and values[order[end]] == values[order[start]]:
            end += 1
        average_rank = ((start + 1) + end) / 2
        for position in range(start, end):
            result[order[position]] = average_rank
        start = end
    return result


def spearman(pairs: list[tuple[float, float]]) -> float | None:
    if len(pairs) < 3:
        return None
    left = rank([item[0] for item in pairs])
    right = rank([item[1] for item in pairs])
    left_mean = sum(left) / len(left)
    right_mean = sum(right) / len(right)
    numerator = sum((a - left_mean) * (b - right_mean) for a, b in zip(left, right))
    denominator_left = math.sqrt(sum((a - left_mean) ** 2 for a in left))
    denominator_right = math.sqrt(sum((b - right_mean) ** 2 for b in right))
    return numerator / (denominator_left * denominator_right) if denominator_left and denominator_right else 0.0


def module_metrics(
    structure: dict[str, Any],
    utilization: dict[str, dict[str, Any]],
    timing_paths: dict[str, dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    rows = []
    for module in structure.get("modules", []):
        name = module.get("name")
        if name in EXCLUDED_MODULES or str(name).startswith("ydrmem"):
            continue
        actual = utilization.get(name)
        if not actual:
            continue
        combination = module.get("combination", {})
        timing_depth_proxy = max(
            combination.get("register_to_boundary_max_depth", 0),
            combination.get("output_path_max_depth", 0),
        )
        # Separate endpoint-oriented cones from the conservative all-cone
        # proxy.  Vivado paths ending at CE use an input-to-control cone;
        # paths ending at D use an input/child-output-to-register cone.
        input_boundary_depth = max(
            combination.get("input_to_register_max_depth", 0),
            combination.get("child_output_to_register_max_depth", 0),
            combination.get("input_to_control_max_depth", 0),
            combination.get("child_output_to_control_max_depth", 0),
        )
        data_boundary_depth = max(
            combination.get("input_to_register_max_depth", 0),
            combination.get("child_output_to_register_max_depth", 0),
        )
        control_boundary_depth = max(
            combination.get("input_to_control_max_depth", 0),
            combination.get("child_output_to_control_max_depth", 0),
        )
        endpoint_timing_depth_proxy = max(
            input_boundary_depth,
            combination.get("output_path_max_depth", 0),
        )
        output_boundary_depth = max(
            combination.get("output_path_max_depth", 0),
            combination.get("register_q_to_output_max_depth", 0),
        )
        row = {
            "module": name,
            "rtl_memory_kind": module.get("memory_timing", {}).get("kind", "unknown"),
            "rtl_storage_bits_interpretation": module.get("memory_timing", {}).get("storage_bits_interpretation"),
            "rtl_synthesis_timing_excluded": module.get("memory_timing", {}).get("simulation_model_excluded_from_synthesis_risk", False),
            "rtl_register_bits": module.get("register_bits", 0),
            "rtl_register_count": module.get("register_count", 0),
            "rtl_max_depth": combination.get("max_depth", 0),
            "rtl_cross_module_max_depth": combination.get("cross_module_max_depth", combination.get("max_depth", 0)),
            "rtl_cross_module_depth_delta": combination.get("cross_module_depth_delta", 0),
            "rtl_cross_module_uncut_count": combination.get("cross_module_uncut_count", 0),
            "rtl_cross_module_unknown_count": combination.get("cross_module_unknown_count", 0),
            "rtl_register_to_boundary_max_depth": combination.get("register_to_boundary_max_depth", 0),
            "rtl_register_q_to_d_max_depth": combination.get("register_q_to_d_max_depth", 0),
            "rtl_register_q_to_control_max_depth": combination.get("register_q_to_control_max_depth", 0),
            "rtl_register_q_to_output_max_depth": combination.get("register_q_to_output_max_depth", 0),
            "rtl_register_q_to_child_input_max_depth": combination.get("register_q_to_child_input_max_depth", 0),
            "rtl_register_q_to_combination_sink_max_depth": combination.get("register_q_to_combination_sink_max_depth", 0),
            "rtl_register_q_to_any_boundary_max_depth": combination.get("register_q_to_any_boundary_max_depth", 0),
            "rtl_input_to_register_max_depth": combination.get("input_to_register_max_depth", 0),
            "rtl_child_output_to_register_max_depth": combination.get("child_output_to_register_max_depth", 0),
            "rtl_input_to_control_max_depth": combination.get("input_to_control_max_depth", 0),
            "rtl_child_output_to_control_max_depth": combination.get("child_output_to_control_max_depth", 0),
            "rtl_q_to_control_path_max_depth": combination.get("q_to_control_path_max_depth", 0),
            "rtl_input_boundary_max_depth": input_boundary_depth,
            "rtl_data_boundary_max_depth": data_boundary_depth,
            "rtl_control_boundary_max_depth": control_boundary_depth,
            "rtl_output_boundary_max_depth": output_boundary_depth,
            # This is the closest local proxy for a Q-to-endpoint timing cone;
            # ``rtl_max_depth`` also includes input-only and dead combinational
            # cones that Vivado's path report may never time.
            "rtl_timing_depth_proxy": timing_depth_proxy,
            "rtl_endpoint_timing_depth_proxy": endpoint_timing_depth_proxy,
            "rtl_operator_count": combination.get("operator_count", 0),
            "rtl_conditional_count": combination.get("conditional_count", 0),
            "rtl_max_expression_width": combination.get("max_expression_width", 0),
            "rtl_weighted_combination_work": combination.get("weighted_combination_work", 0),
            "rtl_packed_read_work": combination.get("packed_read_work", 0),
            "rtl_packed_consumer_work": combination.get("packed_consumer_work", 0),
            "vivado": {key: actual.get(key, 0) for key in RESOURCE_KEYS},
            "vivado_instance": actual.get("instance"),
            "vivado_path_logic_levels_max": (timing_paths or {}).get(name, {}).get("logic_levels_max"),
            "vivado_worst_delay_ns": (timing_paths or {}).get(name, {}).get("worst_delay_ns"),
            "vivado_worst_delay_logic_levels": (timing_paths or {}).get(name, {}).get("worst_delay_logic_levels"),
            "vivado_worst_delay_source": (timing_paths or {}).get(name, {}).get("worst_delay_source"),
            "vivado_worst_delay_destination": (timing_paths or {}).get(name, {}).get("worst_delay_destination"),
            "vivado_logic_delay_ns_max": (timing_paths or {}).get(name, {}).get("logic_delay_ns_max"),
            "vivado_route_delay_ns_max": (timing_paths or {}).get(name, {}).get("route_delay_ns_max"),
            "vivado_route_fraction_max": (timing_paths or {}).get(name, {}).get("route_fraction_max"),
            "vivado_route_dominated_path_count": (timing_paths or {}).get(name, {}).get("route_dominated_path_count", 0),
            "vivado_over_period_path_count": (timing_paths or {}).get(name, {}).get("over_period_path_count", 0),
            "vivado_logic_path_count": (timing_paths or {}).get(name, {}).get("path_count", 0),
            "vivado_local_logic_levels_max": (timing_paths or {}).get(name, {}).get("local_logic_levels_max"),
            "vivado_local_worst_delay_logic_levels": (timing_paths or {}).get(name, {}).get("local_worst_delay_logic_levels"),
            "vivado_local_path_count": (timing_paths or {}).get(name, {}).get("local_path_count", 0),
        }
        rtl_bits = float(row["rtl_register_bits"] or 0)
        vivado_ff = float(actual.get("ff", 0) or 0)
        row["register_to_ff_ratio"] = vivado_ff / rtl_bits if rtl_bits else None
        rows.append(row)
    return rows


def timing_module_paths(
    report: dict[str, Any],
    module_names: set[str],
) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for path_info in report.get("paths", []):
        for module in path_modules(path_info, module_names):
            result.setdefault(module, []).append(path_info)
    return result


def timing_local_module_paths(report: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for path_info in report.get("paths", []):
        for module, levels in path_info.get("module_logic_levels", {}).items():
            if levels:
                result.setdefault(module, []).append(path_info)
    return result


def timing_metric_stats(
    rows: list[dict[str, Any]],
    paths_by_module: dict[str, list[dict[str, Any]]],
    predictor: str,
    actual: str,
) -> dict[str, Any]:
    pairs = []
    absolute_errors = []
    relative_errors = []
    modules = []
    samples = []
    for row in rows:
        paths = paths_by_module.get(row["module"], [])
        if not paths:
            continue
        if actual == "max":
            selected = max(paths, key=lambda item: item["logic_levels"])
            observed = selected["logic_levels"]
        else:
            selected = max(paths, key=lambda item: item["data_path_delay_ns"])
            observed = selected["logic_levels"]
        predicted = float(row[predictor])
        error = abs(predicted - observed)
        pairs.append((predicted, float(observed)))
        absolute_errors.append(error)
        relative_errors.append(error / observed if observed else 0.0)
        modules.append(row["module"])
        samples.append({
            "module": row["module"],
            "predicted": predicted,
            "observed_path_logic_levels": observed,
            "path_count": len(paths),
            "source": selected.get("source"),
            "destination": selected.get("destination"),
            "data_path_delay_ns": selected.get("data_path_delay_ns"),
            "logic_delay_ns": selected.get("logic_delay_ns"),
            "route_delay_ns": selected.get("route_delay_ns"),
            "route_fraction": selected.get("route_fraction"),
        })
    return {
        "n": len(pairs),
        "modules": sorted(modules),
        "spearman": spearman(pairs),
        "mae": sum(absolute_errors) / len(absolute_errors) if absolute_errors else None,
        "mape": sum(relative_errors) / len(relative_errors) if relative_errors else None,
        "samples": sorted(samples, key=lambda item: item["module"]),
    }


def timing_local_metric_stats(
    rows: list[dict[str, Any]],
    paths_by_module: dict[str, list[dict[str, Any]]],
    predictor: str,
    actual: str,
) -> dict[str, Any]:
    pairs = []
    absolute_errors = []
    relative_errors = []
    samples = []
    for row in rows:
        module = row["module"]
        paths = paths_by_module.get(module, [])
        if not paths:
            continue
        if actual == "max":
            selected = max(paths, key=lambda item: item["module_logic_levels"].get(module, 0))
        else:
            selected = max(paths, key=lambda item: item["data_path_delay_ns"])
        observed = int(selected["module_logic_levels"].get(module, 0))
        predicted = float(row[predictor])
        error = abs(predicted - observed)
        pairs.append((predicted, float(observed)))
        absolute_errors.append(error)
        if observed:
            relative_errors.append(error / observed)
        samples.append({
            "module": module,
            "predicted": predicted,
            "observed_local_logic_levels": observed,
            "path_count": len(paths),
            "source": selected.get("source"),
            "destination": selected.get("destination"),
        })
    return {
        "n": len(pairs),
        "spearman": spearman(pairs),
        "mae": sum(absolute_errors) / len(absolute_errors) if absolute_errors else None,
        "mape_nonzero": sum(relative_errors) / len(relative_errors) if relative_errors else None,
        "samples": sorted(samples, key=lambda item: item["module"]),
    }


def endpoint_pin(path: dict[str, Any]) -> str:
    destination = str(path.get("destination", ""))
    if re.search(r"/CE(?:\[[^]]+\])?$", destination):
        return "CE"
    if re.search(r"/D(?:\[[^]]+\])?$", destination):
        return "D"
    return "other"


def timing_role_stats(
    rows: list[dict[str, Any]],
    report: dict[str, Any],
    role: str,
    predictor: str,
) -> dict[str, Any]:
    paths_by_module: dict[str, list[dict[str, Any]]] = {}
    for path in report.get("paths", []):
        source = path.get("source_module")
        destination = path.get("destination_module")
        pin = endpoint_pin(path)
        module = None
        if role == "cross_module_destination_d" and source != destination and pin == "D":
            module = destination
        elif role == "cross_module_destination_ce" and source != destination and pin == "CE":
            module = destination
        elif role == "same_module_q_to_d" and source == destination and pin == "D":
            module = destination
        elif role == "same_module_q_to_ce" and source == destination and pin == "CE":
            module = destination
        elif role == "cross_module_source_output" and source != destination:
            module = source
        if module and path.get("module_logic_levels", {}).get(module, 0):
            paths_by_module.setdefault(module, []).append(path)
    return timing_local_metric_stats(rows, paths_by_module, predictor, "max")


def timing_endpoint_stats(
    rows: list[dict[str, Any]],
    report: dict[str, Any],
    role: str,
    predictor: str,
) -> dict[str, Any]:
    """Compare a module's boundary depth with path-wide levels at its endpoint.

    This intentionally uses the destination module for D/CE paths.  A path can
    traverse several RTL instances after Vivado flattening; attributing the
    whole path to every touched child obscures whether the destination boundary
    was structurally deep.
    """
    paths_by_module: dict[str, list[dict[str, Any]]] = {}
    for path in report.get("paths", []):
        pin = path.get("endpoint_pin") or endpoint_pin(path)
        if role == "destination_d" and pin != "D":
            continue
        if role == "destination_ce" and pin != "CE":
            continue
        if role == "destination_clocked" and pin not in {"D", "CE"}:
            continue
        module = path.get("destination_module")
        if module:
            paths_by_module.setdefault(module, []).append(path)
    return timing_metric_stats(rows, paths_by_module, predictor, "max")


def memory_primitive_calibration(report: dict[str, Any]) -> dict[str, Any]:
    primitives = ("RAMD32", "RAMB18E1", "RAMB36E1")
    result = {}
    for primitive in primitives:
        records = []
        for path in report.get("paths", []):
            cells = [
                cell for cell in path.get("logic_cells", [])
                if cell.get("primitive") == primitive
            ]
            if not cells:
                continue
            increments = [float(cell["increment_ns"]) for cell in cells if cell.get("increment_ns") is not None]
            records.append({
                "source": path.get("source"),
                "destination": path.get("destination"),
                "declared_logic_levels": int(path.get("declared_primitives", {}).get(primitive, 0)),
                "physical_timing_arcs": len(cells),
                "primitive_increment_ns": sum(increments) if increments else None,
                "path_logic_levels": path.get("logic_levels"),
                "path_data_delay_ns": path.get("data_path_delay_ns"),
            })
        increments = [item["primitive_increment_ns"] for item in records if item["primitive_increment_ns"] is not None]
        if records:
            result[primitive] = {
                "path_count": len(records),
                "declared_logic_level_count": sum(item["declared_logic_levels"] for item in records),
                "physical_timing_arc_count": sum(item["physical_timing_arcs"] for item in records),
                "primitive_increment_ns_min": min(increments) if increments else None,
                "primitive_increment_ns_mean": sum(increments) / len(increments) if increments else None,
                "primitive_increment_ns_max": max(increments) if increments else None,
                "path_data_delay_ns_max": max(float(item["path_data_delay_ns"]) for item in records),
                "path_logic_levels_max": max(int(item["path_logic_levels"]) for item in records),
                "worst_paths": sorted(
                    records,
                    key=lambda item: -float(item["path_data_delay_ns"]),
                )[:10],
            }
    return result


def route_delay_calibration(
    report: dict[str, Any],
    module_names: set[str],
    target_period_ns: float,
    route_dominated_fraction: float,
) -> dict[str, Any]:
    paths = [
        path for path in report.get("paths", [])
        if path_modules(path, module_names) or path.get("module_logic_levels")
    ]
    clocked = [path for path in paths if path.get("endpoint_pin") in {"D", "CE"}]
    calibrated = [
        path for path in clocked
        if path.get("logic_delay_ns") is not None and path.get("route_delay_ns") is not None
    ]
    over_target = [path for path in clocked if float(path.get("data_path_delay_ns", 0.0)) >= target_period_ns]
    route_dominated = [
        path for path in calibrated
        if float(path.get("route_fraction", 0.0)) >= route_dominated_fraction
    ]

    def correlation(key: str, selected_paths: list[dict[str, Any]] | None = None) -> float | None:
        selected_paths = calibrated if selected_paths is None else selected_paths
        return spearman([
            (float(path.get("logic_levels", 0)), float(path[key]))
            for path in selected_paths
            if path.get(key) is not None
        ])

    def is_memory_path(path: dict[str, Any]) -> bool:
        primitives = path.get("declared_primitives", {})
        if any(str(name).startswith(("RAMB", "RAMD")) for name in primitives):
            return True
        signature = str(path.get("structure_signature") or "")
        endpoints = f"{path.get('source', '')} {path.get('destination', '')}"
        return bool(
            re.search(r"\b(?:RAMB|RAMD)\w*[:/]", signature)
            or "xpm_memory" in endpoints
        )

    memory_paths = [path for path in calibrated if is_memory_path(path)]
    ordinary_paths = [path for path in calibrated if not is_memory_path(path)]

    def worst_path(paths_to_rank: list[dict[str, Any]]) -> dict[str, Any] | None:
        if not paths_to_rank:
            return None
        path = max(paths_to_rank, key=lambda item: float(item.get("data_path_delay_ns", 0.0)))
        return {
            "source": path.get("source"),
            "destination": path.get("destination"),
            "source_module": path.get("source_module"),
            "destination_module": path.get("destination_module"),
            "endpoint_pin": path.get("endpoint_pin"),
            "data_path_delay_ns": path.get("data_path_delay_ns"),
            "logic_delay_ns": path.get("logic_delay_ns"),
            "route_delay_ns": path.get("route_delay_ns"),
            "route_fraction": path.get("route_fraction"),
            "logic_levels": path.get("logic_levels"),
        }

    route_fractions = [float(path["route_fraction"]) for path in calibrated]
    return {
        "target_period_ns": target_period_ns,
        "route_dominated_fraction_threshold": route_dominated_fraction,
        "core_attributed_path_count": len(paths),
        "clocked_endpoint_path_count": len(clocked),
        "clocked_endpoint_over_target_count": len(over_target),
        "route_delay_parsed_path_count": len(calibrated),
        "route_dominated_path_count": len(route_dominated),
        "route_dominated_over_target_count": sum(
            float(path.get("data_path_delay_ns", 0.0)) >= target_period_ns
            for path in route_dominated
        ),
        "cause_counts": dict(sorted(Counter(
            str(path.get("cause"))
            for path in clocked
            if path.get("cause")
        ).items())),
        "route_fraction_mean": sum(route_fractions) / len(route_fractions) if route_fractions else None,
        "logic_levels_vs_total_delay_spearman": correlation("data_path_delay_ns"),
        "logic_levels_vs_logic_delay_spearman": correlation("logic_delay_ns"),
        "logic_levels_vs_route_delay_spearman": correlation("route_delay_ns"),
        "memory_path_count": len(memory_paths),
        "non_memory_path_count": len(ordinary_paths),
        "memory_logic_levels_vs_logic_delay_spearman": correlation("logic_delay_ns", memory_paths),
        "non_memory_logic_levels_vs_logic_delay_spearman": correlation("logic_delay_ns", ordinary_paths),
        "worst_clocked_path": worst_path(clocked),
        "worst_route_dominated_path": worst_path(route_dominated),
        "interpretation": (
            "Structural depth should follow logic levels and logic delay. Route delay is placement- and fanout-dependent; "
            "route-dominated failures require the structural fanout/memory warnings in addition to depth."
        ),
    }


def historical_calibration(root: Path | None, current: dict[str, Any]) -> dict[str, Any]:
    """Combine raw calibration samples from archived source snapshots."""
    datasets = [("current", current)]
    skipped = []
    current_fingerprint = current.get("provenance", {}).get("source_fingerprint")
    seen_fingerprints = {current_fingerprint} if current_fingerprint else set()
    current_structural_fingerprint = structural_calibration_fingerprint(current)
    seen_structural_fingerprints = (
        {current_structural_fingerprint} if current_structural_fingerprint else set()
    )
    if root and root.is_dir():
        for comparison_path in sorted(root.glob("*/vivado-compare.json")):
            try:
                archived = json.loads(comparison_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                skipped.append({"path": str(comparison_path), "reason": str(exc)})
                continue
            fingerprint = archived.get("provenance", {}).get("source_fingerprint")
            if not fingerprint:
                manifest_path = comparison_path.parent / "manifest.json"
                try:
                    fingerprint = json.loads(manifest_path.read_text(encoding="utf-8")).get("source_fingerprint")
                except (OSError, json.JSONDecodeError):
                    pass
            if fingerprint and fingerprint in seen_fingerprints:
                skipped.append({
                    "path": str(comparison_path),
                    "reason": "duplicate_source_fingerprint",
                })
                continue
            structural_fingerprint = structural_calibration_fingerprint(archived)
            if structural_fingerprint and structural_fingerprint in seen_structural_fingerprints:
                skipped.append({
                    "path": str(comparison_path),
                    "reason": "duplicate_structural_calibration_fingerprint",
                    "source_fingerprint": fingerprint,
                })
                continue
            if fingerprint:
                seen_fingerprints.add(fingerprint)
            if structural_fingerprint:
                seen_structural_fingerprints.add(structural_fingerprint)
            datasets.append((str(comparison_path.parent), archived))

    def post_route_comparison(dataset: dict[str, Any]) -> dict[str, Any] | None:
        candidates = [
            item for item in dataset.get("timing_report_comparisons", [])
            if Path(str(item.get("report", ""))).name == "post_route_timing_summary.rpt"
        ]
        return candidates[0] if candidates else None

    endpoint_pairs: dict[str, list[tuple[float, float]]] = {
        "destination_d": [],
        "destination_clocked": [],
    }
    endpoint_samples: dict[str, list[dict[str, Any]]] = {
        "destination_d": [],
        "destination_clocked": [],
    }
    register_pairs = []
    work_pairs = []
    dataset_reports = []
    for dataset_name, dataset in datasets:
        comparison = post_route_comparison(dataset)
        if comparison:
            dataset_reports.append({
                "dataset": dataset_name,
                "source_fingerprint": dataset.get("provenance", {}).get("source_fingerprint"),
                "report": comparison.get("report"),
                "wns_ns": comparison.get("wns_ns"),
            })
            stage_endpoint = comparison.get("endpoint_path_reliability", {}).get("stage_timed", {})
            for role in endpoint_pairs:
                for sample in stage_endpoint.get(role, {}).get("samples", []):
                    predicted = float(sample.get("predicted", 0.0))
                    observed = float(sample.get("observed_path_logic_levels", 0.0))
                    endpoint_pairs[role].append((predicted, observed))
                    endpoint_samples[role].append({"dataset": dataset_name, **sample})
        for row in dataset.get("modules", []):
            if row.get("module") == "xpm_lutram_1r1w" or row.get("rtl_synthesis_timing_excluded"):
                continue
            rtl_bits = float(row.get("rtl_register_bits", 0.0) or 0.0)
            rtl_work = float(row.get("rtl_weighted_combination_work", 0.0) or 0.0)
            vivado = row.get("vivado", {})
            if rtl_bits:
                register_pairs.append((rtl_bits, float(vivado.get("ff", 0.0) or 0.0)))
            if rtl_work:
                work_pairs.append((rtl_work, float(vivado.get("lut", 0.0) or 0.0)))

    def pair_stats(pairs: list[tuple[float, float]]) -> dict[str, Any]:
        errors = [abs(predicted - observed) for predicted, observed in pairs]
        return {
            "n": len(pairs),
            "spearman": spearman(pairs),
            "mae": sum(errors) / len(errors) if errors else None,
        }

    return {
        "root": str(root) if root else None,
        "current_structural_calibration_fingerprint": current_structural_fingerprint,
        "dataset_count_including_current": len(datasets),
        "historical_dataset_count": max(0, len(datasets) - 1),
        "datasets": dataset_reports,
        "skipped": skipped,
        "stage_destination_d": {
            **pair_stats(endpoint_pairs["destination_d"]),
            "samples": endpoint_samples["destination_d"],
        },
        "stage_destination_clocked": {
            **pair_stats(endpoint_pairs["destination_clocked"]),
            "samples": endpoint_samples["destination_clocked"],
        },
        "register_bits_vs_ff": pair_stats(register_pairs),
        "weighted_work_vs_lut": pair_stats(work_pairs),
        "interpretation": (
            "Archives with the same source fingerprint as the current sample are skipped to avoid double weighting. "
            "Each later RTL version contributes its endpoint samples to the combined ranking."
        ),
    }


def timing_risk_validation(
    structure: dict[str, Any],
    report: dict[str, Any],
    module_names: set[str],
) -> dict[str, Any]:
    period_ns = float(structure.get("summary", {}).get("target_period_ns", 5.0))
    observed: dict[str, dict[str, Any]] = {}
    over_period_paths = 0
    for path in report.get("paths", []):
        if float(path.get("data_path_delay_ns", 0.0)) < period_ns:
            continue
        over_period_paths += 1
        modules = path_modules(path, module_names)
        modules.update(path.get("module_logic_levels", {}))
        for module in modules:
            item = observed.setdefault(module, {
                "path_count": 0,
                "max_data_path_delay_ns": 0.0,
                "max_logic_levels": 0,
            })
            item["path_count"] += 1
            item["max_data_path_delay_ns"] = max(
                item["max_data_path_delay_ns"], float(path.get("data_path_delay_ns", 0.0))
            )
            item["max_logic_levels"] = max(item["max_logic_levels"], int(path.get("logic_levels", 0)))
    possible = set()
    definite = set()
    excluded = set()
    for module in structure.get("modules", []):
        name = str(module.get("name", ""))
        flags = module.get("risk_flags", {})
        if flags.get("simulation_memory_model_excluded"):
            excluded.add(name)
            continue
        if flags.get("possible_target_period_failure"):
            possible.add(name)
        if flags.get("definite_target_period_failure"):
            definite.add(name)
    observed_modules = set(observed) - excluded

    def classification(flagged: set[str]) -> dict[str, Any]:
        matched = flagged & observed_modules
        missed = observed_modules - flagged
        return {
            "flagged_modules": sorted(flagged),
            "flagged_and_observed_modules": sorted(matched),
            "observed_not_flagged_modules": sorted(missed),
            "flagged_not_observed_in_selected_paths": sorted(flagged - observed_modules),
            "observed_module_recall": len(matched) / len(observed_modules) if observed_modules else None,
        }

    return {
        "target_period_ns": period_ns,
        "selected_path_count": len(report.get("paths", [])),
        "data_path_over_target_count": over_period_paths,
        "observed_modules": dict(sorted(observed.items())),
        "possible_flag_validation": classification(possible),
        "definite_flag_validation": classification(definite),
        "interpretation": (
            "Recall is measured only against paths selected into this Vivado report. "
            "A flagged module absent from the report is unobserved, not a proven false positive."
        ),
    }


def render_summary(result: dict[str, Any]) -> str:
    provenance = result.get("provenance", {})
    lines = [
        "RTL structure / Vivado reliability summary",
        f"structure: {result.get('structure')}",
        f"provenance_status={provenance.get('status')} "
        f"revision_match={provenance.get('structure_revision_matches_worktree')} "
        f"rtl_dirty={provenance.get('rtl_worktree_dirty')} "
        f"calibration_compatibility={provenance.get('calibration_compatibility')}",
        "Spearman samples are small; use them as ranking evidence, not an absolute timing model.",
        "",
    ]
    for comparison in result.get("timing_report_comparisons", []):
        coverage = comparison.get("logic_level_parse_coverage", {})
        risk = comparison.get("timing_risk_validation", {})
        local = comparison.get("local_logic_level_reliability", {}).get("stage_timed", {})
        boundary = local.get("rtl_input_boundary_max_depth_vs_local_max_logic_levels", {})
        endpoint = comparison.get("endpoint_path_reliability", {}).get("stage_timed", {})
        endpoint_d = endpoint.get("destination_d", {})
        endpoint_clocked = endpoint.get("destination_clocked", {})
        route = comparison.get("route_delay_calibration", {})
        possible = risk.get("possible_flag_validation", {})
        definite = risk.get("definite_flag_validation", {})
        lines.extend([
            f"REPORT {comparison.get('report')}",
            f"format={comparison.get('format')} wns_ns={comparison.get('wns_ns')} "
            f"tns_ns={comparison.get('tns_ns')} max_data_delay_ns={comparison.get('max_data_path_delay_ns')}",
            f"paths={comparison.get('path_count', 0)} "
            f"logic_parse_exact={coverage.get('exact_path_count', 0)}/{coverage.get('path_count', 0)} "
            f"attributed_ratio={coverage.get('attributed_level_ratio')}",
            f"stage_input_boundary_vs_local_max: n={boundary.get('n')} "
            f"spearman={boundary.get('spearman')} mae={boundary.get('mae')}",
            f"stage_destination_D_boundary_vs_path_levels: n={endpoint_d.get('n')} "
            f"spearman={endpoint_d.get('spearman')} mae={endpoint_d.get('mae')}",
            f"stage_destination_DCE_boundary_vs_path_levels: n={endpoint_clocked.get('n')} "
            f"spearman={endpoint_clocked.get('spearman')} mae={endpoint_clocked.get('mae')}",
            f"core_clocked_paths={route.get('clocked_endpoint_path_count')} "
            f"over_target={route.get('clocked_endpoint_over_target_count')} "
            f"route_dominated={route.get('route_dominated_path_count')} "
            f"logic_levels_vs_logic_delay={route.get('logic_levels_vs_logic_delay_spearman')} "
            f"logic_levels_vs_total_delay={route.get('logic_levels_vs_total_delay_spearman')}",
            f"memory_paths={route.get('memory_path_count')} "
            f"memory_levels_vs_logic_delay={route.get('memory_logic_levels_vs_logic_delay_spearman')} "
            f"non_memory_paths={route.get('non_memory_path_count')} "
            f"non_memory_levels_vs_logic_delay={route.get('non_memory_logic_levels_vs_logic_delay_spearman')}",
            f"possible_5ns_observed_recall={possible.get('observed_module_recall')} "
            f"missed={possible.get('observed_not_flagged_modules', [])}",
            f"definite_5ns_observed_recall={definite.get('observed_module_recall')} "
            f"matched={definite.get('flagged_and_observed_modules', [])}",
        ])
        for primitive, memory in comparison.get("memory_primitive_calibration", {}).items():
            lines.append(
                f"{primitive}: paths={memory.get('path_count')} "
                f"primitive_increment_ns_mean={memory.get('primitive_increment_ns_mean')} "
                f"path_delay_ns_max={memory.get('path_data_delay_ns_max')}"
            )
        lines.append("")
    lines.extend([
        "INTERPRETATION",
        "- input/child-output to destination D/CE versus path-wide logic levels is the primary cross-module depth ranking.",
        "- local primitive ownership remains diagnostic only; it is not the primary fit metric after Vivado flattening.",
        "- route-dominated paths require fanout and FPGA-memory warnings in addition to structural depth.",
        "- local primitive ownership is hierarchy-name based and can move after Vivado flattening.",
        "- possible is a conservative design-time warning; definite requires a loop or the configured high-depth threshold.",
        "- ydrmem storage is a simulation model and is excluded from synthesis-risk and FF correlation.",
    ])
    fanout = result.get("fanout_calibration_summary", {})
    history = result.get("historical_calibration", {})
    historical_clocked = history.get("stage_destination_clocked", {})
    lines.extend([
        f"- fanout calibration: n={fanout.get('matched_signal_count')} "
        f"raw_reads_spearman={fanout.get('read_references_vs_vivado_fanout_spearman')} "
        f"transitive_spearman={fanout.get('transitive_read_estimate_vs_vivado_fanout_spearman')}.",
        "- weak fanout correlation means RTL fanout remains a conservative warning, never a definite timing verdict.",
        f"- historical calibration: datasets={history.get('dataset_count_including_current')} "
        f"archived={history.get('historical_dataset_count')} "
        f"DCE_n={historical_clocked.get('n')} "
        f"DCE_spearman={historical_clocked.get('spearman')} "
        f"DCE_mae={historical_clocked.get('mae')}.",
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--structure", type=Path, required=True)
    parser.add_argument("--utilization", type=Path, required=True)
    parser.add_argument("--timing", type=Path, action="append", default=[])
    parser.add_argument("--timing-csv", type=Path, action="append", default=[])
    parser.add_argument(
        "--route-dominated-fraction",
        type=float,
        default=DEFAULT_ROUTE_DOMINATED_FRACTION,
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary-output", type=Path, default=None)
    parser.add_argument("--history-root", type=Path, default=None)
    args = parser.parse_args()

    structure = json.loads(args.structure.read_text(encoding="utf-8"))
    utilization = parse_utilization(args.utilization)
    target_period_ns = float(structure.get("summary", {}).get("target_period_ns", 5.0))
    module_names = {
        str(module.get("name"))
        for module in structure.get("modules", [])
        if module.get("name")
    }
    timing = [parse_timing(path) for path in args.timing]
    timing.extend(parse_timing_csv(path) for path in args.timing_csv)
    for report in timing:
        attribute_timing_report(report, module_names)
    timing_paths: dict[str, dict[str, Any]] = {}
    for report in timing:
        for path_info in report.get("paths", []):
            for module in path_modules(path_info, module_names):
                item = timing_paths.setdefault(module, {
                    "logic_levels_max": 0,
                    "path_count": 0,
                    "worst_delay_ns": 0.0,
                    "worst_delay_logic_levels": 0,
                    "logic_delay_ns_max": 0.0,
                    "route_delay_ns_max": 0.0,
                    "route_fraction_max": 0.0,
                    "route_dominated_path_count": 0,
                    "over_period_path_count": 0,
                })
                item["logic_levels_max"] = max(item["logic_levels_max"], path_info["logic_levels"])
                item["path_count"] += 1
                logic_delay = path_info.get("logic_delay_ns")
                route_delay = path_info.get("route_delay_ns")
                route_fraction = path_info.get("route_fraction")
                if logic_delay is not None:
                    item["logic_delay_ns_max"] = max(item["logic_delay_ns_max"], float(logic_delay))
                if route_delay is not None:
                    item["route_delay_ns_max"] = max(item["route_delay_ns_max"], float(route_delay))
                if route_fraction is not None:
                    item["route_fraction_max"] = max(item["route_fraction_max"], float(route_fraction))
                    if float(route_fraction) >= args.route_dominated_fraction:
                        item["route_dominated_path_count"] += 1
                if float(path_info.get("data_path_delay_ns", 0.0)) >= target_period_ns:
                    item["over_period_path_count"] += 1
                if path_info["data_path_delay_ns"] > item["worst_delay_ns"]:
                    item.update({
                        "worst_delay_ns": path_info["data_path_delay_ns"],
                        "worst_delay_logic_levels": path_info["logic_levels"],
                        "worst_delay_source": path_info["source"],
                        "worst_delay_destination": path_info["destination"],
                    })
            for module, local_levels in path_info.get("module_logic_levels", {}).items():
                item = timing_paths.setdefault(module, {
                    "logic_levels_max": 0,
                    "path_count": 0,
                    "worst_delay_ns": 0.0,
                    "worst_delay_logic_levels": 0,
                    "logic_delay_ns_max": 0.0,
                    "route_delay_ns_max": 0.0,
                    "route_fraction_max": 0.0,
                    "route_dominated_path_count": 0,
                    "over_period_path_count": 0,
                })
                item["local_logic_levels_max"] = max(
                    int(item.get("local_logic_levels_max", 0)),
                    int(local_levels),
                )
                item["local_path_count"] = int(item.get("local_path_count", 0)) + 1
                if path_info["data_path_delay_ns"] > float(item.get("local_worst_delay_ns", 0.0)):
                    item.update({
                        "local_worst_delay_ns": path_info["data_path_delay_ns"],
                        "local_worst_delay_logic_levels": local_levels,
                    })
    rows = module_metrics(structure, utilization, timing_paths)
    resource_correlation_rows = [
        row for row in rows
        if row["module"] != "xpm_lutram_1r1w" and not row["rtl_synthesis_timing_excluded"]
    ]
    stage_names = {
        "ydrasil_ctrl", "ydrasil_if_stage", "ydrasil_issue_stage",
        "ydrasil_load_store_unit", "ydrasil_ex_block", "ydrasil_id_stage",
    }
    stage_rows = [row for row in rows if row["module"] in stage_names]
    register_pairs = [(float(row["rtl_register_bits"]), float(row["vivado"]["ff"])) for row in stage_rows if row["rtl_register_bits"]]
    work_pairs = [(float(row["rtl_weighted_combination_work"]), float(row["vivado"]["lut"])) for row in stage_rows if row["rtl_weighted_combination_work"]]
    packed_pairs = [(float(row["rtl_packed_consumer_work"]), float(row["vivado"]["lut"])) for row in stage_rows if row["rtl_packed_consumer_work"]]
    logic_level_rows = [row for row in stage_rows if row.get("vivado_worst_delay_logic_levels")]
    local_depth_level_pairs = [(float(row["rtl_max_depth"]), float(row["vivado_worst_delay_logic_levels"])) for row in logic_level_rows]
    cross_depth_level_pairs = [(float(row["rtl_cross_module_max_depth"]), float(row["vivado_worst_delay_logic_levels"])) for row in logic_level_rows]
    timing_proxy_level_pairs = [(float(row["rtl_timing_depth_proxy"]), float(row["vivado_worst_delay_logic_levels"])) for row in logic_level_rows]
    endpoint_proxy_level_pairs = [(float(row["rtl_endpoint_timing_depth_proxy"]), float(row["vivado_worst_delay_logic_levels"])) for row in logic_level_rows]
    timing_report_comparisons = []
    predictor_names = (
        "rtl_max_depth",
        "rtl_timing_depth_proxy",
        "rtl_endpoint_timing_depth_proxy",
        "rtl_input_boundary_max_depth",
    )
    for report in timing:
        report_paths = timing_module_paths(report, module_names)
        local_report_paths = timing_local_module_paths(report)
        report_rows = [
            row for row in rows
            if row["module"] in report_paths or row["module"] in local_report_paths
        ]
        scopes = {
            "all_timed": report_rows,
            "stage_timed": [row for row in report_rows if row["module"] in stage_names],
        }
        report_reliability = {}
        for scope_name, scope_rows in scopes.items():
            report_reliability[scope_name] = {
                f"{predictor}_vs_{actual}_logic_levels": timing_metric_stats(
                    scope_rows, report_paths, predictor, actual
                )
                for predictor in predictor_names
                for actual in ("max", "worst")
            }
        local_reliability = {}
        for scope_name, scope_rows in scopes.items():
            local_reliability[scope_name] = {
                f"{predictor}_vs_local_{actual}_logic_levels": timing_local_metric_stats(
                    scope_rows, local_report_paths, predictor, actual
                )
                for predictor in predictor_names
                for actual in ("max", "worst")
            }
        role_specs = {
            "cross_module_destination_d": "rtl_data_boundary_max_depth",
            "cross_module_destination_ce": "rtl_control_boundary_max_depth",
            "same_module_q_to_d": "rtl_register_q_to_d_max_depth",
            "same_module_q_to_ce": "rtl_q_to_control_path_max_depth",
            "cross_module_source_output": "rtl_output_boundary_max_depth",
        }
        role_reliability = {
            scope_name: {
                role: timing_role_stats(scope_rows, report, role, predictor)
                for role, predictor in role_specs.items()
            }
            for scope_name, scope_rows in scopes.items()
        }
        endpoint_role_specs = {
            "destination_d": "rtl_data_boundary_max_depth",
            "destination_ce": "rtl_control_boundary_max_depth",
            # D and CE share the conservative input-boundary proxy.  This is
            # the stable comparison when a small selected-path report does not
            # contain enough samples to split the endpoint types.
            "destination_clocked": "rtl_input_boundary_max_depth",
        }
        endpoint_reliability = {
            scope_name: {
                role: timing_endpoint_stats(scope_rows, report, role, predictor)
                for role, predictor in endpoint_role_specs.items()
            }
            for scope_name, scope_rows in scopes.items()
        }
        timing_report_comparisons.append({
            "report": report.get("report"),
            "format": report.get("format", "vivado_timing_report"),
            "wns_ns": report.get("wns_ns"),
            "tns_ns": report.get("tns_ns"),
            "max_data_path_delay_ns": max(
                (float(path.get("data_path_delay_ns", 0.0)) for path in report.get("paths", [])),
                default=None,
            ),
            "path_count": len(report.get("paths", [])),
            "logic_level_parse_coverage": report.get("logic_level_parse_coverage"),
            "memory_primitive_calibration": memory_primitive_calibration(report),
            "route_delay_calibration": route_delay_calibration(
                report,
                module_names,
                target_period_ns,
                args.route_dominated_fraction,
            ),
            "timing_risk_validation": timing_risk_validation(structure, report, module_names),
            "module_path_counts": {
                module: len(paths)
                for module, paths in sorted(report_paths.items())
            },
            "module_local_path_counts": {
                module: len(paths)
                for module, paths in sorted(local_report_paths.items())
            },
            "reliability": report_reliability,
            "local_logic_level_reliability": local_reliability,
            "path_role_reliability": role_reliability,
            "endpoint_path_reliability": endpoint_reliability,
        })
    fanout_actual = {}
    for report in timing:
        for name, value in report.get("net_fanout", {}).items():
            fanout_actual[name] = max(value, int(fanout_actual.get(name, 0)))

    signal_estimates = {}
    for module in structure.get("modules", []):
        signals = module.get("fanout_signals") or module.get("fanout_hotspots", [])
        for item in signals:
            signal_estimates.setdefault(item["name"], []).append({
                "module": module.get("name"),
                "read_references": item.get("read_references", 0),
                "estimated_bit_fanout": item.get("estimated_bit_fanout", 0),
                "transitive_read_estimate": item.get("transitive_read_estimate", 0),
                "fanout_risk_score": item.get("fanout_risk_score", 0),
            })
    fanout_calibration = []
    for name, actual in sorted(fanout_actual.items(), key=lambda item: -item[1]):
        estimates = signal_estimates.get(name)
        if estimates:
            by_report = {
                report["report"]: report.get("net_fanout", {}).get(name)
                for report in timing
                if name in report.get("net_fanout", {})
            }
            fanout_calibration.append({
                "signal": name,
                "vivado_fanout": actual,
                "vivado_fanout_by_report": by_report,
                "rtl_estimates": estimates,
            })

    fanout_pairs: dict[str, list[tuple[float, float]]] = {
        "read_references": [],
        "estimated_bit_fanout": [],
        "transitive_read_estimate": [],
        "fanout_risk_score": [],
    }
    for item in fanout_calibration:
        for key, pairs in fanout_pairs.items():
            pairs.append((
                float(max(estimate.get(key, 0) for estimate in item["rtl_estimates"])),
                float(item["vivado_fanout"]),
            ))
    fanout_calibration_summary = {
        "matched_signal_count": len(fanout_calibration),
        **{
            f"{key}_vs_vivado_fanout_spearman": spearman(pairs)
            for key, pairs in fanout_pairs.items()
        },
        "interpretation": (
            "Fanout is strongly transformed by synthesis replication, enable promotion, and packed-field lowering. "
            "Treat the RTL estimate as a conservative route-risk trigger, not a physical fanout predictor."
        ),
    }

    result = {
        "structure": str(args.structure),
        "provenance": comparison_provenance(
            args.structure,
            structure,
            [*args.timing, *args.timing_csv],
        ),
        "utilization": str(args.utilization),
        "timing": timing,
        "timing_report_comparisons": timing_report_comparisons,
        "modules": rows,
        "fanout_calibration": fanout_calibration[:100],
        "fanout_calibration_summary": fanout_calibration_summary,
        "excluded_modules": sorted(EXCLUDED_MODULES | {name for name in utilization if str(name).startswith("ydrmem")}),
        "excluded_resource_correlation_modules": ["xpm_lutram_1r1w", "ydrmem*"],
        "reliability": {
            "all_module_register_bits_vs_ff_spearman": spearman([(float(row["rtl_register_bits"]), float(row["vivado"]["ff"])) for row in resource_correlation_rows if row["rtl_register_bits"]]),
            "all_module_weighted_work_vs_lut_spearman": spearman([(float(row["rtl_weighted_combination_work"]), float(row["vivado"]["lut"])) for row in resource_correlation_rows if row["rtl_weighted_combination_work"]]),
            "register_bits_vs_ff_spearman": spearman(register_pairs),
            "weighted_combination_work_vs_lut_spearman": spearman(work_pairs),
            "packed_consumer_work_vs_lut_spearman": spearman(packed_pairs),
            "local_depth_vs_vivado_path_logic_levels_spearman": spearman(local_depth_level_pairs),
            "cross_depth_vs_vivado_path_logic_levels_spearman": spearman(cross_depth_level_pairs),
            "timing_depth_proxy_vs_vivado_path_logic_levels_spearman": spearman(timing_proxy_level_pairs),
            "endpoint_timing_depth_proxy_vs_vivado_path_logic_levels_spearman": spearman(endpoint_proxy_level_pairs),
            "logic_level_scope_modules": [row["module"] for row in logic_level_rows],
            "stage_scope": sorted(stage_names),
            "register_bit_interpretation": "RTL state upper bound; Vivado can optimize unused or constant state and can report hierarchy-contained child state.",
            "fanout_interpretation": "estimated_bit_fanout is a packed-width weighted AST estimate, not physical Vivado fanout; replication and enable promotion require synthesis.",
            "depth_interpretation": "max_depth is a structural dependency depth. Wide mux/conditional work and routing are separate effects.",
            "timing_depth_proxy_interpretation": "timing_depth_proxy=max(register_to_boundary_max_depth, output_path_max_depth); it is a local Q-to-boundary estimate and is still not a physical Vivado path level count.",
            "endpoint_timing_depth_proxy_interpretation": "endpoint_timing_depth_proxy=max(input/child-output to D or CE, output_path); use it when comparing a path entering a module or ending at a module output. It deliberately excludes unrelated internal Q-to-D cones.",
            "cross_module_depth_interpretation": "cross_module_max_depth carries child combinational output path depth across CELL boundaries; a registered child output is a cut, while a combinational or unknown output is kept on the path.",
            "vivado_logic_level_interpretation": "Vivado logic levels are path-wide. Per-module values are the maximum level of a path touching that module, not a local module-only measurement.",
            "vivado_worst_delay_interpretation": "vivado_worst_delay_logic_levels is the logic-level count of the highest-delay parsed path touching a module; it is still path-wide and can cross the module boundary.",
            "vivado_local_logic_level_interpretation": "module_logic_levels attributes each mapped primitive to the deepest recognizable RTL instance. This removes path-wide double counting but remains sensitive to Vivado flattening and cell renaming.",
            "path_role_interpretation": "Destination D/CE and source-output comparisons use only the primitive levels locally attributed to that endpoint role. They are more specific than whole-path comparisons but have small sample counts.",
            "memory_interpretation": "RAMD32 and RAMB36E1 are calibrated as FPGA macros. Cascaded RAMB timing arcs are retained physically but counted once when Vivado declares one logic level; simulation-memory storage bits are excluded from FF correlation.",
            "timing_risk_interpretation": "5 ns risk recall is checked only against paths present in each Vivado report; report selection makes absence inconclusive.",
            "hierarchy_warning": "ydrasil_core and ydrasil_ex_block Vivado rows include child hierarchy; compare stage rows as trends, not exact local counts.",
        },
    }
    result["provenance"]["structural_calibration_fingerprint"] = (
        structural_calibration_fingerprint(result)
    )
    result["historical_calibration"] = historical_calibration(args.history_root, result)
    structurally_equivalent_archive = any(
        item.get("reason") == "duplicate_structural_calibration_fingerprint"
        for item in result["historical_calibration"].get("skipped", [])
    )
    result["provenance"]["calibration_compatibility"] = (
        "structurally_equivalent_to_archived_report_snapshot"
        if structurally_equivalent_archive
        else "exact_source_freshness_only"
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.summary_output:
        args.summary_output.parent.mkdir(parents=True, exist_ok=True)
        args.summary_output.write_text(render_summary(result), encoding="utf-8")
    print("module,rtl_reg_bits,vivado_ff,reg_to_ff,rtl_depth,rtl_cross_depth,rtl_timing_depth_proxy,rtl_endpoint_timing_depth_proxy,rtl_input_to_register,rtl_input_to_control,rtl_q_to_boundary,rtl_q_to_d,rtl_q_to_output,rtl_q_to_child_input,rtl_q_to_comb_sink,vivado_path_logic_levels_max,vivado_worst_delay_logic_levels,vivado_local_logic_levels_max,rtl_work,rtl_packed_consumer_work,vivado_lut")
    for row in sorted(rows, key=lambda item: item["module"]):
        ratio = row["register_to_ff_ratio"]
        ratio_text = "" if ratio is None else f"{ratio:.3f}"
        print(f"{row['module']},{row['rtl_register_bits']},{row['vivado']['ff']},{ratio_text},"
              f"{row['rtl_max_depth']},{row['rtl_cross_module_max_depth']},{row['rtl_timing_depth_proxy']},{row['rtl_endpoint_timing_depth_proxy']},{row['rtl_input_to_register_max_depth']},{row['rtl_input_to_control_max_depth']},{row['rtl_register_to_boundary_max_depth']},{row['rtl_register_q_to_d_max_depth']},{row['rtl_register_q_to_output_max_depth']},{row['rtl_register_q_to_child_input_max_depth']},{row['rtl_register_q_to_combination_sink_max_depth']},{row['vivado_path_logic_levels_max'] or ''},{row['vivado_worst_delay_logic_levels'] or ''},{row['vivado_local_logic_levels_max'] or ''},{row['rtl_weighted_combination_work']},"
              f"{row['rtl_packed_consumer_work']},{row['vivado']['lut']}")
    print(f"wrote {args.output}")
    if args.summary_output:
        print(f"wrote {args.summary_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
