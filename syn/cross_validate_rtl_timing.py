#!/usr/bin/env python3
"""Leave-one-archive-out validation for RTL timing path-family feedback.

Historical path families are learned from every archive except the holdout.
Independent structural predictions stored in the holdout are also eligible,
but only when their reason does not depend on archived timing observations.
This tests the combined pre-synthesis guard without training on the held-out
Vivado paths.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from rtl_timing_families import (
    archive_timing_csv,
    family_key,
    path_family,
    read_timing_csv,
)


REGISTER_ENDPOINTS = ("register_d", "register_ce", "register_control")
INDEPENDENT_REASON_PREFIXES = (
    "independent_structural_",
    "multiwrite_register_array_endpoint",
    "bram_clock_to_out_to_unregistered_ram_pin",
)


def load_archives(root: Path) -> list[dict[str, Any]]:
    archives = []
    seen_fingerprints: set[str] = set()
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        manifest_path = directory / "manifest.json"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            manifest = {}
        fingerprint = str(manifest.get("source_fingerprint") or directory.name)
        if fingerprint in seen_fingerprints:
            continue
        records = read_timing_csv(archive_timing_csv(directory, manifest))
        if not records:
            continue
        try:
            structure = json.loads(
                (directory / "structure.json").read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            structure = {}
        seen_fingerprints.add(fingerprint)
        archives.append({
            "name": directory.name,
            "fingerprint": fingerprint,
            "memory_geometry_profile": manifest.get("memory_geometry_profile"),
            "structure": structure,
            "records": records,
        })
    return archives


def in_scope(family: dict[str, str]) -> bool:
    return "other" not in {
        family.get("source_owner"),
        family.get("destination_owner"),
        family.get("endpoint_kind"),
    }


def add_prediction_variants(predicted: set[str], family: dict[str, str]) -> None:
    predicted.add(family["key"])
    if family["endpoint_kind"] not in REGISTER_ENDPOINTS:
        return
    for endpoint in REGISTER_ENDPOINTS:
        predicted.add(family_key(
            family["source_owner"],
            family["destination_owner"],
            family["launch_kind"],
            endpoint,
            family["launch_memory_role"],
        ))


def is_over_target(record: dict[str, Any], target_period_ns: float) -> bool:
    return (
        float(record.get("data_delay_ns", 0.0)) >= target_period_ns
        or float(record.get("slack_ns", 0.0)) < 0.0
        or str(record.get("status", "")).upper() == "VIOLATED"
    )


def independent_structure_risks(structure: dict[str, Any]) -> dict[str, dict[str, Any]]:
    predicted: dict[str, dict[str, Any]] = {}
    for risk in structure.get("hierarchical", {}).get("timing_path_risks", []):
        reasons = [str(reason) for reason in risk.get("reasons", [])]
        if not any(
            reason.startswith(INDEPENDENT_REASON_PREFIXES)
            for reason in reasons
        ):
            continue
        key = str(risk.get("key", ""))
        previous = predicted.get(key)
        if key and (
            previous is None
            or int(risk.get("structural_depth", 0))
            > int(previous.get("structural_depth", 0))
        ):
            predicted[key] = risk
    return predicted


def independent_structure_predictions(structure: dict[str, Any]) -> set[str]:
    return set(independent_structure_risks(structure))


def validate_holdout(
    held: dict[str, Any],
    training: list[dict[str, Any]],
    target_period_ns: float,
    definite_depth: int = 21,
    warning_period_ns: float = 4.5,
) -> dict[str, Any]:
    held_geometry = held.get("memory_geometry_profile")
    exact_geometry_training = [
        archive for archive in training
        if held_geometry is not None
        and archive.get("memory_geometry_profile") == held_geometry
    ]
    historical_predicted: set[str] = set()
    excluded_training_bram_paths = 0
    training_path_count = 0
    for archive in training:
        geometry_matches = archive in exact_geometry_training
        for record in archive["records"]:
            family = path_family(record)
            if not in_scope(family):
                continue
            if family["launch_kind"] == "bram_output" and not geometry_matches:
                excluded_training_bram_paths += 1
                continue
            training_path_count += 1
            add_prediction_variants(historical_predicted, family)

    structural_risks = independent_structure_risks(held["structure"])
    structural_predicted = set(structural_risks)
    structural_prediction_available = "timing_path_risks" in held[
        "structure"
    ].get("hierarchical", {})
    predicted = historical_predicted | structural_predicted

    scored: Counter[str] = Counter()
    covered: Counter[str] = Counter()
    missed: Counter[str] = Counter()
    out_of_scope: Counter[str] = Counter()
    bram_unscored: Counter[str] = Counter()
    covered_by_source: Counter[str] = Counter()
    observed_records: dict[str, list[dict[str, Any]]] = {}
    for record in held["records"]:
        family = path_family(record)
        key = family["key"]
        if not in_scope(family):
            if is_over_target(record, warning_period_ns):
                out_of_scope[key] += 1
            continue
        observed_records.setdefault(key, []).append(record)
        if not is_over_target(record, warning_period_ns):
            continue
        if (
            family["launch_kind"] == "bram_output"
            and not exact_geometry_training
            and key not in structural_predicted
        ):
            bram_unscored[key] += 1
            continue
        scored[key] += 1
        if key in predicted:
            covered[key] += 1
            historical_hit = key in historical_predicted
            structural_hit = key in structural_predicted
            if historical_hit and structural_hit:
                covered_by_source["historical_and_independent"] += 1
            elif historical_hit:
                covered_by_source["historical_only"] += 1
            else:
                covered_by_source["independent_only"] += 1
        else:
            missed[key] += 1

    scored_paths = sum(scored.values())
    covered_paths = sum(covered.values())
    observed_families = set(scored)
    covered_families = observed_families & predicted
    error_predicted = {
        key for key, risk in structural_risks.items()
        if int(risk.get("structural_depth", 0)) >= definite_depth
    }
    error_scored = error_predicted & set(observed_records)
    actually_over_target = {
        key for key, records in observed_records.items()
        if any(is_over_target(record, target_period_ns) for record in records)
    }
    error_true_positive = error_scored & actually_over_target
    error_false_positive = error_scored - actually_over_target
    return {
        "archive": held["name"],
        "fingerprint": held["fingerprint"],
        "warning_period_ns": warning_period_ns,
        "target_period_ns": target_period_ns,
        "training_archive_count": len(training),
        "training_path_count": training_path_count,
        "historical_predicted_family_count": len(historical_predicted),
        "independent_predicted_family_count": len(structural_predicted),
        "structural_prediction_available": structural_prediction_available,
        "predicted_family_count": len(predicted),
        "exact_geometry_training_archive_count": len(exact_geometry_training),
        "exact_geometry_training_archives": [item["name"] for item in exact_geometry_training],
        "excluded_training_bram_path_count": excluded_training_bram_paths,
        "scored_path_count": scored_paths,
        "covered_path_count": covered_paths,
        "covered_by_source": dict(sorted(covered_by_source.items())),
        "path_recall": covered_paths / scored_paths if scored_paths else None,
        "observed_family_count": len(observed_families),
        "covered_family_count": len(covered_families),
        "family_recall": len(covered_families) / len(observed_families) if observed_families else None,
        "definite_depth_threshold": definite_depth,
        "error_predicted_family_count": len(error_predicted),
        "error_scored_family_count": len(error_scored),
        "error_true_positive_family_count": len(error_true_positive),
        "error_false_positive_family_count": len(error_false_positive),
        "error_precision": (
            len(error_true_positive) / len(error_scored) if error_scored else None
        ),
        "error_false_positive_families": sorted(error_false_positive),
        "bram_unscored_path_count": sum(bram_unscored.values()),
        "out_of_scope_path_count": sum(out_of_scope.values()),
        "missed_families": [
            {"key": key, "path_count": count}
            for key, count in missed.most_common()
        ],
        "bram_unscored_families": [
            {"key": key, "path_count": count}
            for key, count in bram_unscored.most_common()
        ],
    }


def render_summary(result: dict[str, Any]) -> str:
    lines = [
        "RTL timing archive leave-one-out cross-validation",
        f"archive_root={result['archive_root']}",
        "Each held-out archive is excluded from its own training set.",
        "Warning recall is scored at the margin period; ERROR precision is scored at the target period.",
        "BRAM paths are scored only when another archive has an exact memory geometry profile.",
        "",
    ]
    for holdout in result["holdouts"]:
        lines.append(
            f"{holdout['archive']}: path_recall={holdout['path_recall']} "
            f"covered={holdout['covered_path_count']}/{holdout['scored_path_count']} "
            f"family_recall={holdout['family_recall']} "
            f"families={holdout['covered_family_count']}/{holdout['observed_family_count']} "
            f"bram_unscored={holdout['bram_unscored_path_count']} "
            f"out_of_scope={holdout['out_of_scope_path_count']}"
        )
        lines.append(
            f"  severe_error_precision={holdout['error_precision']} "
            f"true={holdout['error_true_positive_family_count']} "
            f"false={holdout['error_false_positive_family_count']} "
            f"scored={holdout['error_scored_family_count']} "
            f"depth_threshold={holdout['definite_depth_threshold']}"
        )
        lines.append(
            f"  prediction_sources historical={holdout['historical_predicted_family_count']} "
            f"independent={holdout['independent_predicted_family_count']} "
            f"structure_available={holdout['structural_prediction_available']} "
            f"covered={holdout['covered_by_source']}"
        )
        for missed in holdout["missed_families"]:
            lines.append(f"  missed {missed['key']} paths={missed['path_count']}")
    aggregate = result["aggregate"]
    lines.extend([
        "",
        f"aggregate_path_recall={aggregate['path_recall']} "
        f"covered={aggregate['covered_path_count']}/{aggregate['scored_path_count']}",
        f"aggregate_family_recall={aggregate['family_recall']} "
        f"families={aggregate['covered_family_count']}/{aggregate['observed_family_count']}",
        f"aggregate_bram_unscored={aggregate['bram_unscored_path_count']}",
        f"aggregate_error_precision={aggregate['error_precision']} "
        f"true={aggregate['error_true_positive_family_count']} "
        f"false={aggregate['error_false_positive_family_count']} "
        f"scored={aggregate['error_scored_family_count']}",
        f"acceptance={result['acceptance']['passed']} "
        f"failures={result['acceptance']['failures']}",
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive-root", type=Path, required=True)
    parser.add_argument("--target-period-ns", type=float, default=5.0)
    parser.add_argument("--warning-period-ns", type=float, default=4.5)
    parser.add_argument("--definite-depth", type=int, default=21)
    parser.add_argument("--min-aggregate-path-recall", type=float, default=0.95)
    parser.add_argument("--min-aggregate-family-recall", type=float, default=0.80)
    parser.add_argument("--min-holdout-path-recall", type=float, default=0.90)
    parser.add_argument("--min-holdout-scored-paths", type=int, default=100)
    parser.add_argument("--min-error-precision", type=float, default=0.90)
    parser.add_argument("--min-error-true-families", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary-output", type=Path, required=True)
    args = parser.parse_args()
    if args.warning_period_ns > args.target_period_ns:
        parser.error("--warning-period-ns must not exceed --target-period-ns")
    if not args.archive_root.is_dir():
        parser.error(f"archive root does not exist: {args.archive_root}")
    archives = load_archives(args.archive_root)
    if len(archives) < 2:
        parser.error("at least two distinct archives are required")
    holdouts = [
        validate_holdout(
            held,
            [item for item in archives if item is not held],
            args.target_period_ns,
            args.definite_depth,
            args.warning_period_ns,
        )
        for held in archives
    ]
    scored_paths = sum(item["scored_path_count"] for item in holdouts)
    covered_paths = sum(item["covered_path_count"] for item in holdouts)
    observed_families = sum(item["observed_family_count"] for item in holdouts)
    covered_families = sum(item["covered_family_count"] for item in holdouts)
    aggregate_path_recall = covered_paths / scored_paths if scored_paths else None
    aggregate_family_recall = (
        covered_families / observed_families if observed_families else None
    )
    error_scored_families = sum(
        item["error_scored_family_count"] for item in holdouts
    )
    error_true_positive_families = sum(
        item["error_true_positive_family_count"] for item in holdouts
    )
    error_false_positive_families = sum(
        item["error_false_positive_family_count"] for item in holdouts
    )
    error_precision = (
        error_true_positive_families / error_scored_families
        if error_scored_families else None
    )
    acceptance_failures = []
    if aggregate_path_recall is None or aggregate_path_recall < args.min_aggregate_path_recall:
        acceptance_failures.append(
            f"aggregate_path_recall<{args.min_aggregate_path_recall}"
        )
    if (
        aggregate_family_recall is None
        or aggregate_family_recall < args.min_aggregate_family_recall
    ):
        acceptance_failures.append(
            f"aggregate_family_recall<{args.min_aggregate_family_recall}"
        )
    if (
        error_precision is not None
        and error_precision < args.min_error_precision
    ):
        acceptance_failures.append(
            f"aggregate_error_precision<{args.min_error_precision}"
        )
    if error_true_positive_families < args.min_error_true_families:
        acceptance_failures.append(
            f"aggregate_error_true_families<{args.min_error_true_families}"
        )
    for holdout in holdouts:
        recall = holdout["path_recall"]
        if (
            holdout["structural_prediction_available"]
            and holdout["scored_path_count"] >= args.min_holdout_scored_paths
            and (recall is None or recall < args.min_holdout_path_recall)
        ):
            acceptance_failures.append(
                f"{holdout['archive']}:path_recall<{args.min_holdout_path_recall}"
            )
    result = {
        "schema_version": 2,
        "archive_root": str(args.archive_root.resolve()),
        "target_period_ns": args.target_period_ns,
        "warning_period_ns": args.warning_period_ns,
        "archive_count": len(archives),
        "method": (
            "leave_one_archive_out_historical_family_plus_holdout_independent_"
            "structural_prediction"
        ),
        "bram_policy": (
            "another_archive_requires_exact_non_null_memory_geometry_profile_"
            "unless_independently_predicted_from_holdout_structure"
        ),
        "holdouts": holdouts,
        "aggregate": {
            "scored_path_count": scored_paths,
            "covered_path_count": covered_paths,
            "path_recall": aggregate_path_recall,
            "observed_family_count": observed_families,
            "covered_family_count": covered_families,
            "family_recall": aggregate_family_recall,
            "bram_unscored_path_count": sum(item["bram_unscored_path_count"] for item in holdouts),
            "out_of_scope_path_count": sum(item["out_of_scope_path_count"] for item in holdouts),
            "error_scored_family_count": error_scored_families,
            "error_true_positive_family_count": error_true_positive_families,
            "error_false_positive_family_count": error_false_positive_families,
            "error_precision": error_precision,
        },
        "acceptance": {
            "passed": not acceptance_failures,
            "failures": acceptance_failures,
            "min_aggregate_path_recall": args.min_aggregate_path_recall,
            "min_aggregate_family_recall": args.min_aggregate_family_recall,
            "min_holdout_path_recall": args.min_holdout_path_recall,
            "min_holdout_scored_paths": args.min_holdout_scored_paths,
            "min_error_precision": args.min_error_precision,
            "min_error_true_families": args.min_error_true_families,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.summary_output.parent.mkdir(parents=True, exist_ok=True)
    args.summary_output.write_text(render_summary(result), encoding="utf-8")
    print(render_summary(result), end="")
    print(f"wrote {args.output}")
    print(f"wrote {args.summary_output}")
    return 0 if not acceptance_failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
