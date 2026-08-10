#!/usr/bin/env python3
"""Find actionable execution paths from the compact execution-wave probe.

This analyzer intentionally keeps raw predicates separate.  A cycle can be
dependency-blocked and producer-full at the same time; assigning that cycle to
one broad bucket is the source of most misleading bubble reports.  The report
therefore includes overlap, isolated evidence, release transitions, and a
conservative one-cycle upper bound for every predicate.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


CAUSES = (
    "redirect_cone",
    "producer_capacity",
    "lsu_credit",
    "operand_boundary",
    "select_refill",
    "selection_policy",
    "dependency_wakeup",
    "dependency_latency",
    "rs_refill",
    "frontend_starvation",
    "singleton_bundle",
    "execute_backpressure",
)

REQUIRED = {
    "cycle", "sample_valid", "reset", "halted", "physical_exec0", "physical_exec1",
    "ex_valid0", "ex_valid1", "ex_accept0", "ex_accept1", "producer_full",
    "rob_count", "retire0", "retire1", "if_valid0", "if_valid1", "decode_valid0",
    "decode_valid1", "dispatch_accept0", "dispatch_accept1", "frontend_queue_count",
    "fetch_req_valid", "fetch_resp_valid", "pending_redirect", "flush", "redirect",
    "branch_mispredict", "pipeline_flush", "recovery_pending", "select_push",
    "select_head_valid", "select_head_pair", "select_skid_valid", "operand_accept0",
    "operand_accept1", "rs_valid_mask", "rs_ready_mask", "rs_candidate_mask",
    "rs_selected_mask", "rs_dep_mask", "rs_order_mask", "rs_resource_mask",
    "completion_wakeup_mask", "alloc_wakeup_mask", "select_wakeup_mask",
    "lsu_credit", "lsu_reserved", "lsu_queue_count", "lsu_struct_stall",
    "selected_pc0", "selected_pc1", "selected_tag0", "selected_tag1",
    "ex_pc0", "ex_pc1", "ex_tag0", "ex_tag1",
}

MASKS = {
    "rs_valid_mask", "rs_ready_mask", "rs_candidate_mask", "rs_selected_mask",
    "rs_dep_mask", "rs_order_mask", "rs_resource_mask", "completion_wakeup_mask",
    "alloc_wakeup_mask", "select_wakeup_mask",
}

PCS = {"selected_pc0", "selected_pc1", "ex_pc0", "ex_pc1"}


def parse_value(raw: str, field: str) -> int:
    if raw.lower().startswith("0x") or field in MASKS or field in PCS or field.endswith("_pc"):
        return int(raw, 16)
    return int(raw, 10)


def pc_text(value: int) -> str:
    return "-" if not value else f"0x{value:08x}"


def bit_count(value: int) -> int:
    return value.bit_count()


def head_slots(row: dict[str, int]) -> int:
    return (2 if row["select_head_pair"] else 1) if row["select_head_valid"] else 0


def row_causes(row: dict[str, int], prev: dict[str, int] | None) -> set[str]:
    """Return necessary-condition predicates, not an exclusive diagnosis."""
    causes: set[str] = set()
    empty_slots = 2 - row["physical_exec0"] - row["physical_exec1"]
    if not empty_slots:
        return causes

    if (row["flush"] or row["redirect"] or row["branch_mispredict"] or
            row["pipeline_flush"] or row["recovery_pending"] or
            (prev is not None and (prev["pipeline_flush"] or prev["redirect"] or
                                   prev["recovery_pending"]))):
        causes.add("redirect_cone")

    decode_work = bool(row["decode_valid0"] or row["decode_valid1"])
    dispatch_none = not (row["dispatch_accept0"] or row["dispatch_accept1"])
    if row["producer_full"] and decode_work and dispatch_none:
        causes.add("producer_capacity")

    lsu_entries = row["rs_resource_mask"] & 0x0F0
    lsu_credit_blocked = (row["lsu_credit"] == 0 or
        (row["lsu_reserved"] > 0 and row["lsu_queue_count"] >= row["lsu_reserved"]))
    if lsu_entries and lsu_credit_blocked and row["lsu_struct_stall"]:
        causes.add("lsu_credit")

    if prev is not None:
        prev_head = head_slots(prev)
        prev_operand = prev["operand_accept0"] + prev["operand_accept1"]
        if prev_head > prev_operand:
            causes.add("operand_boundary")
        if not prev["select_head_valid"] and prev["select_push"]:
            causes.add("select_refill")
        if prev["rs_candidate_mask"] and not prev["rs_selected_mask"]:
            causes.add("selection_policy")
        wakeup = (prev["completion_wakeup_mask"] | prev["alloc_wakeup_mask"] |
                  prev["select_wakeup_mask"])
        if prev["rs_dep_mask"] & wakeup:
            causes.add("dependency_wakeup")
        if prev["rs_dep_mask"] and not (prev["rs_dep_mask"] & wakeup):
            causes.add("dependency_latency")
        if not prev["rs_valid_mask"] and (prev["decode_valid0"] or
                                           prev["decode_valid1"] or
                                           prev["frontend_queue_count"]):
            causes.add("rs_refill")
        if (not prev["rs_valid_mask"] and not prev["if_valid0"] and
                not prev["if_valid1"] and not prev["decode_valid0"] and
                not prev["decode_valid1"] and not prev["frontend_queue_count"] and
                not prev["fetch_req_valid"] and not prev["fetch_resp_valid"]):
            causes.add("frontend_starvation")
        if prev_head == 1 and prev_operand == 1:
            causes.add("singleton_bundle")

    if ((row["ex_valid0"] and not row["ex_accept0"]) or
            (row["ex_valid1"] and not row["ex_accept1"])):
        causes.add("execute_backpressure")
    return causes


@dataclass
class CauseStats:
    slots: int = 0
    cycles: int = 0
    isolated_slots: int = 0
    isolated_cycles: int = 0
    release_cycles: int = 0
    release_slots: int = 0
    next_cycle_progress: int = 0
    chains: int = 0
    pcs: Counter[str] | None = None

    def __post_init__(self) -> None:
        if self.pcs is None:
            self.pcs = Counter()


def run(input_path: Path, output_dir: Path, top: int = 25) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    stats = {cause: CauseStats() for cause in CAUSES}
    overlap: Counter[tuple[str, str]] = Counter()
    rows_count = 0
    sampled = 0
    total_empty = 0
    prev: dict[str, int] | None = None
    prev_causes: set[str] = set()
    prev_empty = 0
    event_rows: list[tuple[int, int, tuple[str, ...], str, str]] = []

    with input_path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        missing = sorted(REQUIRED - set(reader.fieldnames or ()))
        if missing:
            raise SystemExit("execution wave is missing: " + ", ".join(missing))
        for raw in reader:
            row = {field: parse_value(value, field) for field, value in raw.items()}
            rows_count += 1
            if not row["sample_valid"] or row["reset"] or row["halted"]:
                prev = None
                prev_causes = set()
                continue
            sampled += 1
            empty = 2 - row["physical_exec0"] - row["physical_exec1"]
            total_empty += empty
            causes = row_causes(row, prev)
            # A release is measured on the first cycle after a predicate was
            # active and the observed empty-slot count improves. This is a
            # state transition, rather than the start of a long raw run.
            if prev is not None:
                progressed = empty < prev_empty
                for released in prev_causes - causes:
                    stats[released].release_cycles += 1
                    stats[released].release_slots += prev_empty
                if progressed:
                    for released in prev_causes:
                        stats[released].next_cycle_progress += 1
            if causes:
                owner_pc = row["selected_pc0"] or row["selected_pc1"] or row["ex_pc0"] or row["ex_pc1"]
                event_rows.append((row["cycle"], empty, tuple(sorted(causes)), pc_text(owner_pc),
                                   f"rs=0x{row['rs_valid_mask']:03x},dep=0x{row['rs_dep_mask']:03x},"
                                   f"cand=0x{row['rs_candidate_mask']:03x},sel=0x{row['rs_selected_mask']:03x}"))
            for cause in causes:
                item = stats[cause]
                item.slots += empty
                item.cycles += 1
                if len(causes) == 1:
                    item.isolated_slots += empty
                    item.isolated_cycles += 1
                if cause in prev_causes:
                    pass
                else:
                    item.chains += 1
                for lane in range(2):
                    if row[f"selected_pc{lane}"]:
                        item.pcs[pc_text(row[f"selected_pc{lane}"])] += empty
            for left in sorted(causes):
                for right in sorted(causes):
                    if left < right:
                        overlap[(left, right)] += empty
            prev = row
            prev_causes = causes
            prev_empty = empty

    report = output_dir / "causal_path_report.md"
    lines = [
        "# Causal path execution analysis", "",
        "Each row keeps all necessary-condition predicates. A cycle with multiple predicates is counted in the overlap matrix and is not claimed as an independent gain. `isolated` is evidence that a single RTL boundary is sufficient to explain the observed empty slots; `release` is a predicate-to-progress transition, not a raw counter.", "",
        f"- Input: `{input_path}`", f"- CSV rows: {rows_count}",
        f"- Sampled cycles: {sampled}", f"- Empty physical slots: {total_empty}", "",
        "## Actionable paths", "",
        "| Path | all slots | all cycles | isolated slots | isolated cycles | chains | release cycles | next-cycle progress | top selected PCs |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for cause, item in sorted(stats.items(), key=lambda pair: (pair[1].isolated_slots, pair[1].slots), reverse=True):
        top_pcs = ", ".join(f"{pc}:{count}" for pc, count in item.pcs.most_common(3))
        lines.append(f"| `{cause}` | {item.slots} | {item.cycles} | {item.isolated_slots} | {item.isolated_cycles} | {item.chains} | {item.release_cycles} | {item.next_cycle_progress} | {top_pcs or '-'} |")

    lines += ["", "## Coupling matrix", "",
              "Cells are empty-slot weights for cycles where both predicates were true. Large cells are coupled causes and must not be added to either path's isolated opportunity.", "",
              "| Path A | Path B | overlap slots |", "|---|---|---:|"]
    for (left, right), count in overlap.most_common():
        lines.append(f"| `{left}` | `{right}` | {count} |")

    lines += ["", "## Highest-value isolated edges", "",
              "These are the top individual cycles where exactly one predicate was present. They are the first places to inspect in RTL; repeated PCs indicate a loop edge, not independent evidence.", "",
              "| Rank | Cycle | Empty slots | Path | PC | Evidence |", "|---:|---:|---:|---|---|---|"]
    isolated = [event for event in event_rows if len(event[2]) == 1]
    for rank, (cycle, empty, causes, pc, evidence) in enumerate(sorted(isolated, key=lambda event: event[1], reverse=True)[:top], 1):
        lines.append(f"| {rank} | {cycle} | {empty} | `{causes[0]}` | `{pc}` | `{evidence}` |")

    lines += ["", "## Decision rules", "",
              "- Do not use `all slots` as an IPC estimate; it includes coupled cycles.",
              "- A candidate is worth RTL work only when its isolated slots and release cycles are material, and the next-cycle progress count is nonzero.",
              "- `singleton_bundle` is a legal width-shape observation, not a free slot unless a second legal candidate is proven.",
              "- Redirect and dependency paths must be compared against the overlap matrix before changing predictor or wakeup logic.",
              "- Producer capacity is only actionable on a verified state transition. This report does not authorize same-cycle ROB reuse.", ""]
    report.write_text("\n".join(lines), encoding="utf-8")
    with (output_dir / "causal_path_events.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("cycle", "empty_slots", "paths", "pc", "evidence"))
        writer.writerows(event_rows)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--top", type=int, default=25)
    args = parser.parse_args()
    print(run(args.input, args.out_dir, args.top))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
