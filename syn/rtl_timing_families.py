#!/usr/bin/env python3
"""Normalize Vivado timing paths into reusable RTL structure families."""

from __future__ import annotations

import csv
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


OWNER_PATTERNS = (
    ("itcm", r"(?:^|/)u_(?:ydrasil_)?itcm(?:/|$)|(?:^|/)ydrasil_itcm(?:/|$)"),
    ("dtcm", r"(?:^|/)u_(?:ydrasil_)?dtcm(?:/|$)|(?:^|/)ydrasil_dtcm(?:/|$)"),
    ("branch_predictor", r"(?:^|/)u_ydrasil_branch_predictor(?:/|$)|(?:^|/)ydrasil_branch_predictor(?:/|$)"),
    ("fetch_queue", r"(?:^|/)u_fetch_queue(?:/|$)"),
    ("if_stage", r"(?:^|/)u_ydrasil_if_stage(?:/|$)|(?:^|/)ydrasil_if_stage(?:/|$)"),
    ("issue_stage", r"(?:^|/)u_ydrasil_issue_stage(?:/|$)|(?:^|/)ydrasil_issue_stage(?:/|$)"),
    ("value_file", r"(?:^|/)u_ydrasil_value_file(?:/|$)|(?:^|/)ydrasil_value_file(?:/|$)"),
    ("ctrl", r"(?:^|/)u_ctrl(?:/|$)|(?:^|/)ydrasil_ctrl(?:/|$)"),
    ("load_store_unit", r"(?:^|/)u_ydrasil_load_store_unit(?:/|$)|(?:^|/)ydrasil_load_store_unit(?:/|$)"),
    ("ex_block", r"(?:^|/)u_ydrasil_ex_block(?:/|$)|(?:^|/)ydrasil_ex_block(?:/|$)"),
    ("id_stage", r"(?:^|/)u_ydrasil_id_stage(?:/|$)|(?:^|/)ydrasil_id_stage(?:/|$)"),
    ("register_file", r"(?:^|/)u_ydrasil_registers(?:/|$)|(?:^|/)ydrasil_registers(?:/|$)"),
    ("csr", r"(?:^|/)u_ydrasil_registers_csr(?:/|$)|(?:^|/)ydrasil_registers_csr(?:/|$)"),
    ("core", r"(?:^|/)u_core(?:/|$)|(?:^|/)ydrasil_core(?:/|$)"),
)


def normalize_owner(resource: str | None) -> str:
    text = str(resource or "")
    for owner, pattern in OWNER_PATTERNS:
        if re.search(pattern, text):
            return owner
    return "other"


def launch_kind(resource: str | None) -> str:
    text = str(resource or "")
    if re.search(r"/(?:CLKARDCLK|CLKBWRCLK|CLK)$", text):
        return "bram_output" if "xpm_memory" in text or "mem_reg" in text else "memory_output"
    if re.search(r"/(?:O|DO(?:ADO|BDO)?)(?:\[[^]]+\])?$", text):
        return "memory_output" if re.search(r"(?:RAM[ABCD]|mem_reg|xpm_memory)", text) else "combinational"
    return "register_q"


def launch_memory_role(resource: str | None) -> str:
    if launch_kind(resource) != "bram_output":
        return "none"
    owner = normalize_owner(resource)
    if owner == "branch_predictor":
        return "predictor_bram"
    if owner in {"itcm", "dtcm"}:
        return owner
    return "other_bram"


def endpoint_kind(resource: str | None) -> str:
    text = str(resource or "")
    leaf = text.rsplit("/", 1)[-1]
    if re.match(r"(?:WADR|RADR|ADR|ADDR|ADDRBWRADDR)", leaf):
        return "ram_address"
    if re.match(r"(?:WE|WEN|ENBWREN|WSTRB)", leaf):
        return "ram_write_enable"
    if leaf == "I" or re.match(r"(?:DI|DIN|WDATA)", leaf):
        return "ram_write_data"
    if re.match(r"CE(?:\[[^]]+\])?$", leaf):
        return "register_ce"
    if re.match(r"D(?:\[[^]]+\])?$", leaf):
        return "register_d"
    if re.match(r"(?:R|S|CLR|SET|PRE|RSTB)(?:\[[^]]+\])?$", leaf):
        return "register_control"
    return "other"


def normalize_signal(resource: str | None) -> str:
    text = str(resource or "")
    parts = text.split("/")
    leaf = parts[-2] if len(parts) > 1 else parts[-1]
    leaf = re.sub(r"_reg(?:_rep(?:__\d+)?)?", "_q", leaf)
    leaf = re.sub(r"\[[^]]+\]", "[*]", leaf)
    leaf = re.sub(r"(?<=_)\d+(?=_|$)", "*", leaf)
    return leaf


def family_key(
    source_owner: str,
    destination_owner: str,
    launch: str,
    endpoint: str,
    memory_role: str = "none",
) -> str:
    launch_label = f"{launch}[{memory_role}]" if launch == "bram_output" else launch
    return f"{source_owner}->{destination_owner}|{launch_label}->{endpoint}"


def path_family(path: dict[str, Any]) -> dict[str, str]:
    source = str(path.get("source", ""))
    destination = str(path.get("destination", ""))
    source_owner = normalize_owner(source)
    destination_owner = normalize_owner(destination)
    launch = launch_kind(source)
    memory_role = launch_memory_role(source)
    endpoint = endpoint_kind(destination)
    return {
        "key": family_key(source_owner, destination_owner, launch, endpoint, memory_role),
        "source_owner": source_owner,
        "destination_owner": destination_owner,
        "launch_kind": launch,
        "launch_memory_role": memory_role,
        "endpoint_kind": endpoint,
        "source_signal": normalize_signal(source),
        "destination_signal": normalize_signal(destination),
    }


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = max(0.0, min(1.0, fraction)) * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def read_timing_csv(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    try:
        rows = list(csv.DictReader(path.read_text(encoding="utf-8", errors="replace").splitlines()))
    except OSError:
        return []
    records = []
    for row in rows:
        try:
            delay = float(row.get("data_delay_ns", ""))
            requirement = float(row.get("requirement_ns", "5.0") or 5.0)
            slack = float(row.get("slack_ns", requirement - delay))
            logic_levels = int(float(row.get("logic_levels", "0") or 0))
            route_pct = float(row.get("route_pct", "0") or 0.0)
        except (TypeError, ValueError):
            continue
        status = str(row.get("status", ""))
        if status and status.upper() != "VIOLATED" and delay < requirement:
            continue
        records.append({
            "source": str(row.get("source", "")).strip(),
            "destination": str(row.get("destination", "")).strip(),
            "data_delay_ns": delay,
            "requirement_ns": requirement,
            "slack_ns": slack,
            "logic_levels": logic_levels,
            "route_fraction": route_pct / 100.0,
            "structure_signature": row.get("structure_signature"),
            "status": status,
        })
    return records


def summarize_families(
    datasets: Iterable[tuple[str, Iterable[dict[str, Any]]]],
    target_period_ns: float = 5.0,
) -> dict[str, Any]:
    grouped: dict[str, list[tuple[str, dict[str, Any], dict[str, str]]]] = defaultdict(list)
    dataset_names: set[str] = set()
    for dataset, records in datasets:
        dataset_names.add(dataset)
        for record in records:
            family = path_family(record)
            grouped[family["key"]].append((dataset, record, family))

    families = []
    for key, samples in grouped.items():
        delays = [float(item[1].get("data_delay_ns", 0.0)) for item in samples]
        slacks = [float(item[1].get("slack_ns", target_period_ns - delays[index])) for index, item in enumerate(samples)]
        levels = [float(item[1].get("logic_levels", 0)) for item in samples]
        routes = [float(item[1].get("route_fraction", 0.0)) for item in samples]
        family = samples[0][2]
        source_signals = Counter(item[2]["source_signal"] for item in samples)
        destination_signals = Counter(item[2]["destination_signal"] for item in samples)
        designs = sorted({item[0] for item in samples})
        families.append({
            **{name: family[name] for name in (
                "key", "source_owner", "destination_owner", "launch_kind",
                "launch_memory_role", "endpoint_kind"
            )},
            "sample_count": len(samples),
            "design_count": len(designs),
            "designs": designs,
            "delay_ns_min": min(delays),
            "delay_ns_p50": percentile(delays, 0.50),
            "delay_ns_p95": percentile(delays, 0.95),
            "delay_ns_max": max(delays),
            "worst_slack_ns": min(slacks),
            "logic_levels_p95": percentile(levels, 0.95),
            "route_fraction_p50": percentile(routes, 0.50),
            "route_fraction_p95": percentile(routes, 0.95),
            "common_source_signals": [name for name, _ in source_signals.most_common(8)],
            "common_destination_signals": [name for name, _ in destination_signals.most_common(8)],
        })
    families.sort(key=lambda item: (item["worst_slack_ns"], -item["sample_count"], item["key"]))
    return {
        "schema_version": 1,
        "target_period_ns": target_period_ns,
        "dataset_count": len(dataset_names),
        "path_count": sum(len(samples) for samples in grouped.values()),
        "family_count": len(families),
        "families": families,
    }


def load_archive_training(
    root: Path | None,
    target_period_ns: float = 5.0,
    memory_geometry_profile: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not root or not root.is_dir():
        return summarize_families([], target_period_ns)
    datasets = []
    seen_fingerprints: set[str] = set()
    skipped = []
    bram_geometry_compatibility = []
    for archive in sorted(path for path in root.iterdir() if path.is_dir()):
        manifest_path = archive / "manifest.json"
        manifest: dict[str, Any] = {}
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
        fingerprint = str(manifest.get("source_fingerprint") or archive.name)
        if fingerprint in seen_fingerprints:
            skipped.append({"archive": archive.name, "reason": "duplicate_source_fingerprint"})
            continue
        csv_path = archive / "reports" / "cpu200_timing_paths.csv"
        records = read_timing_csv(csv_path)
        if not records:
            skipped.append({"archive": archive.name, "reason": "missing_or_empty_timing_csv"})
            continue
        archived_geometry = manifest.get("memory_geometry_profile")
        bram_path_count = sum(
            path_family(record)["launch_kind"] == "bram_output"
            for record in records
        )
        if memory_geometry_profile is not None and archived_geometry != memory_geometry_profile:
            before = len(records)
            records = [
                record for record in records
                if path_family(record)["launch_kind"] != "bram_output"
            ]
            compatibility = "missing_profile" if archived_geometry is None else "mismatch"
            bram_geometry_compatibility.append({
                "archive": archive.name,
                "status": compatibility,
                "eligible": False,
                "accepted_bram_path_count": 0,
                "excluded_bram_path_count": before - len(records),
            })
            skipped.append({
                "archive": archive.name,
                "reason": "bram_paths_excluded_memory_geometry_mismatch",
                "excluded_path_count": before - len(records),
            })
        else:
            bram_geometry_compatibility.append({
                "archive": archive.name,
                "status": "exact_match",
                "eligible": True,
                "accepted_bram_path_count": bram_path_count,
                "excluded_bram_path_count": 0,
            })
        seen_fingerprints.add(fingerprint)
        datasets.append((fingerprint, records))
    result = summarize_families(datasets, target_period_ns)
    result["archive_root"] = str(root)
    result["memory_geometry_profile"] = memory_geometry_profile
    result["skipped"] = skipped
    result["bram_geometry_compatibility"] = bram_geometry_compatibility
    result["bram_eligible_dataset_count"] = sum(
        bool(item["eligible"]) for item in bram_geometry_compatibility
    )
    result["bram_accepted_path_count"] = sum(
        int(item["accepted_bram_path_count"])
        for item in bram_geometry_compatibility
    )
    result["bram_excluded_path_count"] = sum(
        int(item["excluded_bram_path_count"])
        for item in bram_geometry_compatibility
    )
    return result
