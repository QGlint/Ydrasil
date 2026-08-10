#!/usr/bin/env python3
"""Build a mutually-exclusive causal bubble report from execution_causal.csv."""

from __future__ import annotations

import argparse
import csv
import math
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


MASK_FIELDS = {
    "rs_valid_mask", "rs_ready_mask", "rs_candidate_mask", "rs_selected_mask",
    "rs_dep_mask", "rs_order_mask", "rs_resource_mask",
    "completion_wakeup_mask", "alloc_wakeup_mask", "select_wakeup_mask",
}
PC_FIELDS = {name for name in (
    "select_head_pc0", "select_head_pc1", "operand_pc0", "operand_pc1",
    "ex_pc0", "ex_pc1",
)}
RTL_LOCATIONS = {
    "producer_full": "ydrasil_ctrl.sv:355 and ydrasil_core_tb.sv causal ex-valid owner",
    "producer_full_dispatch_credit": "ydrasil_ctrl.sv:143-151,212-223 (queue release vs dispatch_ready)",
    "producer_full_release_dispatch": "ydrasil_ctrl.sv:143-151,212-223 (release edge before dispatch credit)",
    "execute_backpressure": "ydrasil_ctrl.sv:355",
    "redirect_frontend_refill": "ydrasil_if_stage.sv:471,663,702,718",
    "frontend_starvation": "ydrasil_if_stage.sv:663,702",
    "dispatch_to_rs_refill": "ydrasil_core.sv:629-706; ydrasil_issue_stage.sv:423-432",
    "select_refill": "ydrasil_issue_stage.sv Select head/skid queue",
    "select_queue_backpressure": "ydrasil_issue_stage.sv select_buf_push/head/skid",
    "selection_width": "ydrasil_issue_stage.sv:596-815",
    "dependency_wakeup_visibility": "ydrasil_issue_stage.sv:537-584,2290-2454",
    "dependency_wait": "ydrasil_issue_stage.sv:537-584,2290-2454",
    "order_wait": "ydrasil_issue_stage.sv:585-590",
    "lsu_resource_wait": "ydrasil_issue_stage.sv:620-643; ydrasil_load_store_unit.sv:234-410",
    "p1_resource_wait": "ydrasil_issue_stage.sv:652-703",
    "operand_block": "ydrasil_issue_stage.sv Select-to-Operand head",
    "singleton_bundle": "ydrasil_issue_stage.sv lane pairing/select bundle shape",
    "unclassified": "additional owner-edge probe required",
}


def number(text: str, field: str) -> int:
    if field in MASK_FIELDS or field in PC_FIELDS or field.endswith("_pc"):
        return int(text, 16) if text.lower().startswith("0x") else int(text, 16)
    return int(text, 10)


def bit_count(value: int) -> int:
    return value.bit_count()


@dataclass(frozen=True)
class Event:
    cycle: int
    slot: int
    category: str
    owner_pc: int | None
    owner_tag: int | None
    producer_pc: int | None
    producer_tag: int | None
    bank: int | None
    detail: str

    @property
    def edge_key(self) -> tuple[object, ...]:
        return (self.category, self.producer_pc, self.owner_pc, self.bank)


def entry(row: dict[str, int], index: int) -> dict[str, int]:
    prefix = f"rs{index}_"
    return {name[len(prefix):]: value for name, value in row.items()
            if name.startswith(prefix)}


def entries_for_mask(row: dict[str, int], mask: int) -> list[tuple[int, dict[str, int]]]:
    return [(index, entry(row, index)) for index in range(12) if mask & (1 << index)]


def oldest_entry(row: dict[str, int], mask: int) -> tuple[int, dict[str, int]] | None:
    choices = entries_for_mask(row, mask)
    if not choices:
        return None
    head = row["rob_head_tag"]
    # producer IDs include an epoch bit. Full-tag distance is preferred; the
    # slot-only fallback keeps malformed/recovery rows deterministic.
    def rank(item: tuple[int, dict[str, int]]) -> tuple[int, int]:
        index, item_entry = item
        tag = item_entry["tag"]
        return ((tag - head) & 0x1f, index)
    return min(choices, key=rank)


def owner_from_entry(
    row: dict[str, int], mask: int, tag_to_pc: dict[int, int]
) -> tuple[int | None, int | None, int | None, int | None, int | None]:
    selected = oldest_entry(row, mask)
    if selected is None:
        return None, None, None, None, None
    index, item = selected
    producer_tags = []
    if item["src0_tag_valid"] and not item["src0_ready"]:
        producer_tags.append(item["src0_prod"])
    if item["src1_tag_valid"] and not item["src1_ready"] and not item["store"]:
        producer_tags.append(item["src1_prod"])
    producer_tag = producer_tags[0] if producer_tags else None
    producer_pc = tag_to_pc.get(producer_tag) if producer_tag is not None else None
    return item["pc"], item["tag"], producer_pc, producer_tag, item["bank"]


def classify_empty_lane(
    row: dict[str, int], prev: dict[str, int] | None, lane: int,
    redirect_until: int, tag_to_pc: dict[int, int],
) -> Event:
    cycle = row["cycle"]
    ex_valid = row[f"physical_exec{lane}"]
    ex_accept = row[f"ex_accept{lane}"]
    if ex_valid and not ex_accept:
        category = "producer_full" if row["producer_full"] else "execute_backpressure"
        return Event(cycle, lane, category, row[f"ex_pc{lane}"], row[f"ex_tag{lane}"],
                     None, None, lane, f"ex_valid=1,accept=0,producer_full={row['producer_full']}")

    # A committed ROB slot is visible in producer_full, but dispatch_ready can
    # still be based on the old queue_count. Charge only the release edge where
    # decode has work, no dispatch is accepted, and the immediately following
    # cycle accepts it. This is the concrete full->free->dispatch chain that
    # aggregate ROB/full counters double-count as RS/select refill.
    if (prev is not None and prev["producer_full"] and not row["producer_full"] and
            (row["decode_valid0"] or row["decode_valid1"]) and
            not (row["dispatch_accept0"] or row["dispatch_accept1"])):
        owner_lane = 0 if row["decode_valid0"] else 1
        owner_pc = row[f"operand_pc{owner_lane}"]
        owner_tag = row[f"operand_tag{owner_lane}"]
        return Event(cycle, lane, "producer_full_release_dispatch", owner_pc, owner_tag,
                     None, None, None,
                     "producer_full fell, decode valid, dispatch credit not visible")

    if row["producer_full"] and (row["decode_valid0"] or row["decode_valid1"]) and not (
            row["dispatch_accept0"] or row["dispatch_accept1"]):
        owner_lane = 0 if row["decode_valid0"] else 1
        return Event(cycle, lane, "producer_full_dispatch_credit",
                     row[f"operand_pc{owner_lane}"], row[f"operand_tag{owner_lane}"],
                     None, None, None,
                     "producer_full blocks dispatch while decode is valid")

    if row["redirect"] or row["branch_mispredict"] or cycle <= redirect_until:
        resolve_lane = 1 if row["physical_exec1"] else 0
        return Event(cycle, lane, "redirect_frontend_refill",
                     row[f"ex_pc{resolve_lane}"], row[f"ex_tag{resolve_lane}"],
                     None, None, None, "redirect-to-useful-execute control chain")

    if prev is None:
        return Event(cycle, lane, "unclassified", None, None, None, None, None,
                     "no preceding sampled cycle")

    head_slots = 2 if prev["select_head_valid"] and prev["select_head_pair"] else int(
        bool(prev["select_head_valid"]))
    operand_slots = prev["operand_accept0"] + prev["operand_accept1"]
    if head_slots > operand_slots:
        owner_lane = min(lane, head_slots - 1)
        return Event(cycle, lane, "operand_block",
                     prev[f"select_head_pc{owner_lane}"], prev[f"select_head_tag{owner_lane}"],
                     None, None, owner_lane,
                     f"head_slots={head_slots},operand_accept={operand_slots}")

    if not prev["select_head_valid"] and prev["select_push"]:
        owner = owner_from_entry(prev, prev["rs_selected_mask"], tag_to_pc)
        return Event(cycle, lane, "select_refill", *owner,
                     "head_empty=1 and selected uop pushed")

    selected_slots = bit_count(prev["rs_selected_mask"])
    candidate_mask = prev["rs_candidate_mask"] & 0x0fff
    candidate_slots = bit_count(candidate_mask)
    if candidate_slots > selected_slots and selected_slots < 2:
        owner = owner_from_entry(prev, candidate_mask & ~prev["rs_selected_mask"], tag_to_pc)
        return Event(cycle, lane, "selection_width", *owner,
                     f"candidates={candidate_slots},selected={selected_slots}")

    if prev["rs_selected_mask"] and not prev["select_push"]:
        owner = owner_from_entry(prev, prev["rs_selected_mask"], tag_to_pc)
        return Event(cycle, lane, "select_queue_backpressure", *owner,
                     "selected entry did not enter Select queue")

    dep_mask = prev["rs_dep_mask"]
    if dep_mask:
        wakeup = dep_mask & (prev["completion_wakeup_mask"] |
                             prev["alloc_wakeup_mask"] | prev["select_wakeup_mask"])
        category = "dependency_wakeup_visibility" if wakeup else "dependency_wait"
        owner = owner_from_entry(prev, wakeup or dep_mask, tag_to_pc)
        return Event(cycle, lane, category, *owner,
                     f"dep=0x{dep_mask:03x},same_cycle_wakeup=0x{wakeup:03x}")

    if prev["rs_order_mask"]:
        owner = owner_from_entry(prev, prev["rs_order_mask"], tag_to_pc)
        return Event(cycle, lane, "order_wait", *owner,
                     f"order_mask=0x{prev['rs_order_mask']:03x}")

    if prev["rs_resource_mask"]:
        owner = owner_from_entry(prev, prev["rs_resource_mask"], tag_to_pc)
        category = "lsu_resource_wait" if owner[4] == 1 else "p1_resource_wait"
        return Event(cycle, lane, category, *owner,
                     f"resource_mask=0x{prev['rs_resource_mask']:03x}")

    if not prev["rs_valid_mask"]:
        frontend_empty = not (prev["if_valid0"] or prev["if_valid1"] or
                              prev["decode_valid0"] or prev["decode_valid1"] or
                              prev["frontend_queue_count"])
        category = "frontend_starvation" if frontend_empty else "dispatch_to_rs_refill"
        return Event(cycle, lane, category, None, None, None, None, None,
                     "RS empty; front-end empty" if frontend_empty else "RS empty; front-end has work")

    if prev["select_head_valid"] and not prev["select_head_pair"] and operand_slots == 1:
        return Event(cycle, lane, "singleton_bundle", prev["select_head_pc0"],
                     prev["select_head_tag0"], None, None, 0, "single-uop Select bundle")

    return Event(cycle, lane, "unclassified", None, None, None, None, None,
                 "resident RS state has no observed next-edge blocker")


def load_and_classify(path: Path) -> tuple[list[Event], dict[str, int]]:
    events: list[Event] = []
    tag_to_pc: dict[int, int] = {}
    prev: dict[str, int] | None = None
    redirect_until = -1
    stats = {"rows": 0, "sample_cycles": 0, "retired": 0, "first_cycle": 0, "last_cycle": 0}
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        required = {"cycle", "sample_valid", "rs_valid_mask", "rs0_pc", "rs11_bank",
                    "select_head_pc0", "completion0_valid", "retire1_tag"}
        missing = sorted(required - set(reader.fieldnames or ()))
        if missing:
            raise SystemExit("causal CSV missing fields: " + ", ".join(missing))
        for raw in reader:
            row = {field: number(value, field) for field, value in raw.items()}
            stats["rows"] += 1
            if not row["sample_valid"] or row["reset"] or row["halted"]:
                prev = None
                continue
            stats["sample_cycles"] += 1
            if stats["sample_cycles"] == 1:
                stats["first_cycle"] = row["cycle"]
            stats["last_cycle"] = row["cycle"]
            stats["retired"] = max(stats["retired"], row["instret"])

            for index in range(12):
                item = entry(row, index)
                if item["valid"]:
                    tag_to_pc[item["tag"]] = item["pc"]
            for completion_lane in range(4):
                if row[f"completion{completion_lane}_valid"]:
                    # The PC mapping remains the latest live allocation for this
                    # full producer ID; epoch-qualified tags prevent stale reuse.
                    tag_to_pc.setdefault(row[f"completion{completion_lane}_tag"], 0)

            if row["redirect"] or row["branch_mispredict"]:
                redirect_until = row["cycle"] + 3

            for lane in range(2):
                if not row[f"ex_accept{lane}"]:
                    events.append(classify_empty_lane(
                        row, prev, lane, redirect_until, tag_to_pc))
            prev = row
    return events, stats


def runs(cycles: set[int]) -> int:
    return sum(1 for cycle in cycles if cycle - 1 not in cycles)


def pc_text(pc: int | None) -> str:
    return "-" if pc is None or pc == 0 else f"0x{pc:08x}"


def write_report(events: list[Event], stats: dict[str, int],
                 report_path: Path, event_path: Path, samples_path: Path, top: int) -> None:
    class_slots = Counter(event.category for event in events)
    class_cycles: dict[str, set[int]] = defaultdict(set)
    edge_slots = Counter(event.edge_key for event in events)
    edge_cycles: dict[tuple[object, ...], set[int]] = defaultdict(set)
    for event in events:
        class_cycles[event.category].add(event.cycle)
        edge_cycles[event.edge_key].add(event.cycle)

    with event_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("cycle", "slot", "category", "producer_pc", "producer_tag",
                         "consumer_pc", "consumer_tag", "bank", "detail"))
        for event in events:
            writer.writerow((event.cycle, event.slot, event.category,
                             pc_text(event.producer_pc), event.producer_tag,
                             pc_text(event.owner_pc), event.owner_tag, event.bank, event.detail))

    edge_order = sorted(edge_slots, key=lambda key: (runs(edge_cycles[key]), edge_slots[key]), reverse=True)
    selected_cycles: list[int] = []
    for key in edge_order:
        for cycle in sorted(edge_cycles[key]):
            if all(abs(cycle - prior) > 4 for prior in selected_cycles):
                selected_cycles.append(cycle)
                if len(selected_cycles) == 15:
                    break
        if len(selected_cycles) == 15:
            break
    with samples_path.open("w", newline="", encoding="utf-8") as stream:
        # The event ledger is intentionally the source of truth. Keeping all
        # 280-column rows in Python costs >1 GB on a CoreMark run; the compact
        # sample file lists each center/category and lets GTKWave/CSV tooling
        # fetch the five-cycle context from the original causal CSV.
        fields = ["sample_rank", "sample_center", "category", "producer_pc",
                  "consumer_pc", "bank", "detail"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for rank, center in enumerate(selected_cycles, 1):
            event = next(item for item in events if item.cycle == center)
            writer.writerow({"sample_rank": rank, "sample_center": center,
                             "category": event.category,
                             "producer_pc": pc_text(event.producer_pc),
                             "consumer_pc": pc_text(event.owner_pc),
                             "bank": event.bank, "detail": event.detail})

    total_slots = len(events)
    total_cycles = stats["sample_cycles"]
    retired = stats["retired"]
    lines = [
        "# Causal execution bubble report", "",
        "This report assigns each unaccepted physical lane to exactly one next blocking edge. "
        "Repeated masks are not independently accumulated. Consecutive events on the same "
        "producer-PC -> consumer-PC edge form one chain; `1-cycle marginal` counts chains, "
        "which is the maximum gain from shortening that edge by one cycle.", "",
        f"- Sampled cycles: {total_cycles}",
        f"- Sample interval: {stats['first_cycle']}..{stats['last_cycle']}",
        f"- Cumulative instret at stop: {retired}",
        f"- Mutually exclusive empty slots: {total_slots}", "",
        "## Mutually exclusive causes", "",
        "| Cause | Empty slots | Distinct cycles | Chains / 1-cycle marginal | Full-removal cycle upper bound | RTL edge |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for category, slots in class_slots.most_common():
        cycles = class_cycles[category]
        marginal = runs(cycles)
        lines.append(f"| `{category}` | {slots} | {len(cycles)} | {marginal} | "
                     f"{math.ceil(slots / 2)} | {RTL_LOCATIONS.get(category, '-')} |")
    lines += ["", "## Top critical edges", "",
              "| Rank | Edge | Empty slots | Affected cycles | 1-cycle marginal |", "|---:|---|---:|---:|---:|"]
    for rank, key in enumerate(edge_order[:top], 1):
        category, producer_pc, consumer_pc, bank = key
        cycles = edge_cycles[key]
        source = pc_text(producer_pc)
        consumer = pc_text(consumer_pc)
        lines.append(f"| {rank} | `{category}` {source} -> {consumer} bank={bank if bank is not None else '-'} "
                     f"| {edge_slots[key]} | {len(cycles)} | {runs(cycles)} |")
    lines += ["", "## Interpretation limits", "",
              "- `1-cycle marginal` is a critical-edge upper bound, not an IPC promise; independent edges can still converge downstream.",
              "- Completion tags are epoch-qualified, but producer PC is reconstructed from the latest live RS allocation with that full tag.",
              "- Front-end control chains use a three-cycle redirect cone. The top redirect edges must be checked against the detailed predictor trace before changing GSHARE.",
              "- `singleton_bundle` records legal bundle shape and should not be treated as recoverable unless a second legal candidate is present.", "",
              f"Event ledger: `{event_path.name}`", "",
              f"15 local five-cycle samples: `{samples_path.name}`", ""]
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--out-dir", type=Path)
    parser.add_argument("--top", type=int, default=30)
    args = parser.parse_args()
    out_dir = args.out_dir or args.input.parent / "causal-analysis"
    out_dir.mkdir(parents=True, exist_ok=True)
    events, stats = load_and_classify(args.input)
    write_report(events, stats, out_dir / "causal_bubble_report.md",
                 out_dir / "causal_events.csv", out_dir / "causal_top15_samples.csv", args.top)
    print(out_dir / "causal_bubble_report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
