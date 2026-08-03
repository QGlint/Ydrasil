#!/usr/bin/env python3
"""Calibrate rtl-quickcheck metrics against Vivado reports.

The comparison is deliberately descriptive.  Vivado may flatten or move
logic across hierarchy, so the report never treats a hierarchy row as a
one-to-one prediction of the RTL module.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any


RESOURCE_KEYS = ("lut", "logic_lut", "lutram", "srl", "ff", "ramb36", "ramb18", "dsp")
EXCLUDED_MODULES = {"dtcm", "itcm"}


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

    path_pattern = re.compile(
        r"^\s*Source:\s+([^\n]+).*?^\s*Destination:\s+([^\n]+).*?"
        r"^\s*Data Path Delay:\s*([-+]?\d+(?:\.\d+)?)ns.*?"
        r"^\s*Logic Levels:\s*(\d+)",
        re.M | re.S,
    )
    for match in path_pattern.finditer(text):
        result["paths"].append({
            "source": match.group(1).strip(),
            "destination": match.group(2).strip(),
            "data_path_delay_ns": float(match.group(3)),
            "logic_levels": int(match.group(4)),
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


def path_modules(path: dict[str, Any], module_names: set[str]) -> set[str]:
    text = f"{path.get('source', '')} {path.get('destination', '')}"
    result = set()
    for module in module_names:
        aliases = {f"u_{module}"}
        if module.startswith("ydrasil_"):
            aliases.add("u_" + module[len("ydrasil_"):])
        if any(f"/{alias}/" in text for alias in aliases):
            result.add(module)
    return result


def rank(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=lambda item: values[item])
    result = [0.0] * len(values)
    for position, index in enumerate(order):
        result[index] = float(position + 1)
    return result


def spearman(pairs: list[tuple[float, float]]) -> float | None:
    if len(pairs) < 3:
        return None
    left = rank([item[0] for item in pairs])
    right = rank([item[1] for item in pairs])
    mean = (len(pairs) + 1) / 2
    numerator = sum((a - mean) * (b - mean) for a, b in zip(left, right))
    denominator_left = math.sqrt(sum((a - mean) ** 2 for a in left))
    denominator_right = math.sqrt(sum((b - mean) ** 2 for b in right))
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
        endpoint_timing_depth_proxy = max(
            input_boundary_depth,
            combination.get("output_path_max_depth", 0),
        )
        row = {
            "module": name,
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
            "vivado_logic_path_count": (timing_paths or {}).get(name, {}).get("path_count", 0),
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
    for row in rows:
        paths = paths_by_module.get(row["module"], [])
        if not paths:
            continue
        if actual == "max":
            observed = max(item["logic_levels"] for item in paths)
        else:
            worst = max(paths, key=lambda item: item["data_path_delay_ns"])
            observed = worst["logic_levels"]
        predicted = float(row[predictor])
        error = abs(predicted - observed)
        pairs.append((predicted, float(observed)))
        absolute_errors.append(error)
        relative_errors.append(error / observed if observed else 0.0)
        modules.append(row["module"])
    return {
        "n": len(pairs),
        "modules": sorted(modules),
        "spearman": spearman(pairs),
        "mae": sum(absolute_errors) / len(absolute_errors) if absolute_errors else None,
        "mape": sum(relative_errors) / len(relative_errors) if relative_errors else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--structure", type=Path, required=True)
    parser.add_argument("--utilization", type=Path, required=True)
    parser.add_argument("--timing", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    structure = json.loads(args.structure.read_text(encoding="utf-8"))
    utilization = parse_utilization(args.utilization)
    timing = [parse_timing(path) for path in args.timing]
    module_names = {
        str(module.get("name"))
        for module in structure.get("modules", [])
        if module.get("name")
    }
    timing_paths: dict[str, dict[str, Any]] = {}
    for report in timing:
        for path_info in report.get("paths", []):
            for module in path_modules(path_info, module_names):
                item = timing_paths.setdefault(module, {
                    "logic_levels_max": 0,
                    "path_count": 0,
                    "worst_delay_ns": 0.0,
                    "worst_delay_logic_levels": 0,
                })
                item["logic_levels_max"] = max(item["logic_levels_max"], path_info["logic_levels"])
                item["path_count"] += 1
                if path_info["data_path_delay_ns"] > item["worst_delay_ns"]:
                    item.update({
                        "worst_delay_ns": path_info["data_path_delay_ns"],
                        "worst_delay_logic_levels": path_info["logic_levels"],
                        "worst_delay_source": path_info["source"],
                        "worst_delay_destination": path_info["destination"],
                    })
    rows = module_metrics(structure, utilization, timing_paths)
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
        report_rows = [row for row in rows if row["module"] in report_paths]
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
        timing_report_comparisons.append({
            "report": report.get("report"),
            "path_count": len(report.get("paths", [])),
            "module_path_counts": {
                module: len(paths)
                for module, paths in sorted(report_paths.items())
            },
            "reliability": report_reliability,
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

    result = {
        "structure": str(args.structure),
        "utilization": str(args.utilization),
        "timing": timing,
        "timing_report_comparisons": timing_report_comparisons,
        "modules": rows,
        "fanout_calibration": fanout_calibration[:100],
        "excluded_modules": sorted(EXCLUDED_MODULES | {name for name in utilization if str(name).startswith("ydrmem")}),
        "reliability": {
            "all_module_register_bits_vs_ff_spearman": spearman([(float(row["rtl_register_bits"]), float(row["vivado"]["ff"])) for row in rows if row["rtl_register_bits"]]),
            "all_module_weighted_work_vs_lut_spearman": spearman([(float(row["rtl_weighted_combination_work"]), float(row["vivado"]["lut"])) for row in rows if row["rtl_weighted_combination_work"]]),
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
            "hierarchy_warning": "ydrasil_core and ydrasil_ex_block Vivado rows include child hierarchy; compare stage rows as trends, not exact local counts.",
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("module,rtl_reg_bits,vivado_ff,reg_to_ff,rtl_depth,rtl_cross_depth,rtl_timing_depth_proxy,rtl_endpoint_timing_depth_proxy,rtl_input_to_register,rtl_input_to_control,rtl_q_to_boundary,rtl_q_to_d,rtl_q_to_output,rtl_q_to_child_input,rtl_q_to_comb_sink,vivado_path_logic_levels_max,vivado_worst_delay_logic_levels,rtl_work,rtl_packed_consumer_work,vivado_lut")
    for row in sorted(rows, key=lambda item: item["module"]):
        ratio = row["register_to_ff_ratio"]
        ratio_text = "" if ratio is None else f"{ratio:.3f}"
        print(f"{row['module']},{row['rtl_register_bits']},{row['vivado']['ff']},{ratio_text},"
              f"{row['rtl_max_depth']},{row['rtl_cross_module_max_depth']},{row['rtl_timing_depth_proxy']},{row['rtl_endpoint_timing_depth_proxy']},{row['rtl_input_to_register_max_depth']},{row['rtl_input_to_control_max_depth']},{row['rtl_register_to_boundary_max_depth']},{row['rtl_register_q_to_d_max_depth']},{row['rtl_register_q_to_output_max_depth']},{row['rtl_register_q_to_child_input_max_depth']},{row['rtl_register_q_to_combination_sink_max_depth']},{row['vivado_path_logic_levels_max'] or ''},{row['vivado_worst_delay_logic_levels'] or ''},{row['rtl_weighted_combination_work']},"
              f"{row['rtl_packed_consumer_work']},{row['vivado']['lut']}")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
