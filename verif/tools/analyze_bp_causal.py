#!/usr/bin/env python3
"""Attribute branch redirects to mutually exclusive front-end causes.

The testbench BP_TRACE cycle is aligned with execution_wave.csv cycle.  This
tool intentionally consumes those artifacts instead of modifying predictor RTL.
It reports the recovery slots following each redirect and the latency to the
first request, correct-target fetch/dispatch, and correct-target execution.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path


BP_RE = re.compile(r"(\w+)=([^\s]+)")


def number(value: str) -> int:
    return int(value, 0)


def bit(row: dict[str, str], name: str) -> bool:
    return number(row.get(name, "0")) != 0


def pc(row: dict[str, str], name: str) -> int:
    return number(row.get(name, "0"))


def load_wave(path: Path) -> tuple[list[dict[str, str]], dict[int, int]]:
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    by_cycle = {number(row["cycle"]): index for index, row in enumerate(rows)}
    return rows, by_cycle


def load_bp_trace(path: Path) -> list[dict[str, int]]:
    events: list[dict[str, int]] = []
    for line in path.read_text(errors="replace").splitlines():
        if not line.startswith("BP_TRACE:"):
            continue
        values = {key: number(value) for key, value in BP_RE.findall(line)}
        if "cycle" in values and "pc" in values:
            events.append(values)
    return events


def event_kind(event: dict[str, int]) -> str:
    # A BTB miss that is actually taken is a distinct actionable cause from a
    # direction error at a valid entry.  Target mismatch is checked first so
    # the categories remain disjoint if a future run exposes one.
    if event.get("target_mispredict", 0):
        return "target_mismatch"
    if event.get("actual_taken", 0) and not event.get("pred_hit", 0):
        return "btb_miss_taken"
    if event.get("dir_mispredict", 0):
        return "direction_mismatch"
    if event.get("mispredict", 0):
        return "other_mispredict"
    return "correct"


def first_after(
    rows: list[dict[str, str]],
    start: int,
    predicate,
    limit: int = 64,
) -> int | None:
    for index in range(start + 1, min(len(rows), start + 1 + limit)):
        if predicate(rows[index]):
            return index
    return None


def recovery_slots(rows: list[dict[str, str]], redirect_index: int) -> int:
    """Match TB control-refill accounting: redirect edge is flush separately."""
    slots = 0
    for row in rows[redirect_index + 1 :]:
        if bit(row, "if_valid0"):
            break
        slots += 2 - int(bit(row, "physical_exec0")) - int(bit(row, "physical_exec1"))
    return slots


def latency_row(rows: list[dict[str, str]], index: int, actual_next: int) -> dict[str, int | str]:
    predicates = {
        "first_req": lambda row: bit(row, "fetch_req_valid"),
        "first_resp": lambda row: bit(row, "fetch_resp_valid"),
        "target_fetch": lambda row: pc(row, "fetch_pc") == actual_next and (
            bit(row, "fetch_req_valid") or bit(row, "fetch_resp_valid")
        ),
        "target_dispatch": lambda row: pc(row, "fetch_pc") == actual_next and (
            bit(row, "dispatch_accept0") or bit(row, "dispatch_accept1")
        ),
        "any_execute": lambda row: bit(row, "physical_exec0") or bit(row, "physical_exec1"),
        "target_execute": lambda row: (
            bit(row, "physical_exec0") and pc(row, "ex_pc0") == actual_next
        ) or (
            bit(row, "physical_exec1") and pc(row, "ex_pc1") == actual_next
        ),
    }
    result: dict[str, int | str] = {}
    cycle = number(rows[index]["cycle"])
    for name, predicate in predicates.items():
        found = first_after(rows, index, predicate)
        result[name + "_cycle"] = number(rows[found]["cycle"]) if found is not None else ""
        result[name + "_delay"] = number(rows[found]["cycle"]) - cycle if found is not None else ""
    return result


def fmt_stats(values: list[int]) -> str:
    if not values:
        return "n/a"
    ordered = sorted(values)
    p95 = ordered[int(0.95 * (len(ordered) - 1))]
    return f"avg={statistics.mean(values):.2f}, p50={statistics.median(values):g}, p95={p95:g}, max={max(values)}"


def parse_perf(path: Path) -> dict[str, int | float]:
    result: dict[str, int | float] = {}
    for line in path.read_text(errors="replace").splitlines():
        # Other records reuse names such as CYCLES; only PERF_METRIC is the
        # benchmark-level denominator used in the report header.
        if not line.startswith("PERF_METRIC:"):
            continue
        for key, value in re.findall(r"([A-Z][A-Z0-9_]*)=([0-9]+(?:\.[0-9]+)?)", line):
            result[key] = float(value) if "." in value else int(value)
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wave", type=Path, help="execution_wave.csv")
    parser.add_argument("bp_trace", type=Path, help="testbench BP_TRACE log")
    parser.add_argument("--out-dir", type=Path, default=None)
    parser.add_argument("--perf-log", type=Path, default=None)
    args = parser.parse_args()
    out_dir = args.out_dir or args.wave.parent / "analysis" / "bp-causal"
    out_dir.mkdir(parents=True, exist_ok=True)

    rows, by_cycle = load_wave(args.wave)
    events = load_bp_trace(args.bp_trace)
    perf = parse_perf(args.perf_log) if args.perf_log else {}
    records: list[dict[str, int | str]] = []
    category = Counter()
    recovery = defaultdict(Counter)

    # Branch events are linked by the resolve cycle.  A branch mispredict must
    # also assert the wave redirect; a mismatch is reported instead of guessed.
    for event in events:
        if not event.get("mispredict", 0):
            continue
        cycle = event["cycle"]
        index = by_cycle.get(cycle)
        if index is None:
            continue
        kind = event_kind(event)
        row = rows[index]
        if not bit(row, "redirect") or not bit(row, "branch_mispredict"):
            kind = "trace_wave_mismatch"
        category[kind] += 1
        lat = latency_row(rows, index, event["actual_next"])
        rec: dict[str, int | str] = {
            "cycle": cycle,
            "pc": f"0x{event['pc']:08x}",
            "kind": kind,
            "pred_hit": event.get("pred_hit", 0),
            "pred_taken": event.get("pred_taken", 0),
            "actual_taken": event.get("actual_taken", 0),
            "pred_target": f"0x{event.get('pred_target', 0):08x}",
            "actual_next": f"0x{event['actual_next']:08x}",
            "flush_slots": 2,
            "recovery_slots": recovery_slots(rows, index),
        }
        rec.update(lat)
        for field in ("target_fetch_delay", "target_dispatch_delay", "target_execute_delay"):
            value = rec[field]
            if isinstance(value, int):
                recovery[kind][field] += value
        recovery[kind]["flush_slots"] += 2
        recovery[kind]["recovery_slots"] += int(rec["recovery_slots"])
        records.append(rec)

    # Redirects without a conditional branch resolve are direct jumps/traps.
    # They are kept separate so their recovery is not charged to the predictor.
    bp_cycles = {int(record["cycle"]) for record in records}
    for index, row in enumerate(rows):
        if not bit(row, "redirect") or number(row["cycle"]) in bp_cycles:
            continue
        kind = "redirect_other"
        category[kind] += 1
        recovery[kind]["flush_slots"] += 2
        recovery[kind]["recovery_slots"] += recovery_slots(rows, index)

    # pending_redirect is a useful probe for a predictor metadata correction;
    # charge it only when it actually leaves IF empty, matching no-if loss.
    pending_cycles = sum(bit(row, "pending_redirect") for row in rows)
    pending_runs = 0
    pending_empty_slots = 0
    active = False
    for row in rows:
        pending = bit(row, "pending_redirect")
        if pending and not active:
            pending_runs += 1
        active = pending
        if pending and not bit(row, "if_valid0") and not bit(row, "if_valid1"):
            pending_empty_slots += 2 - int(bit(row, "physical_exec0")) - int(bit(row, "physical_exec1"))

    csv_path = out_dir / "bp_causal_events.csv"
    columns = [
        "cycle", "pc", "kind", "pred_hit", "pred_taken", "actual_taken",
        "pred_target", "actual_next", "flush_slots", "recovery_slots",
        "first_req_cycle", "first_req_delay", "first_resp_cycle", "first_resp_delay",
        "target_fetch_cycle", "target_fetch_delay", "target_dispatch_cycle",
        "target_dispatch_delay", "any_execute_cycle", "any_execute_delay",
        "target_execute_cycle", "target_execute_delay",
    ]
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(records)

    report_path = out_dir / "bp_causal_report.md"
    cycles = perf.get("CYCLES", number(rows[-1]["cycle"]) - number(rows[0]["cycle"]))
    insts = perf.get("INSTS", "")
    ipc = perf.get("IPC", "")
    provenance = args.wave.parent / "provenance" / "git_head.txt"
    source_head = provenance.read_text().strip() if provenance.exists() else "unknown"
    pc_stats: dict[str, Counter[str]] = defaultdict(Counter)
    for record in records:
        pc_stats[str(record["pc"])]["events"] += 1
        pc_stats[str(record["pc"])]["slots"] += 2 + int(record["recovery_slots"])
    lines = [
        "# Branch redirect causal analysis",
        "",
        f"- Wave: `{args.wave}`",
        f"- BP trace: `{args.bp_trace}`",
        f"- Source HEAD captured by run: `{source_head}`",
        f"- Wave SHA256: `{sha256(args.wave)}`",
        f"- BP trace SHA256: `{sha256(args.bp_trace)}`",
        f"- Cycles/insts/IPC: `{cycles}` / `{insts}` / `{ipc}`",
        "- Categories are exclusive: `btb_miss_taken` -> `direction_mismatch` -> `target_mismatch`; non-conditional redirects are `redirect_other`.",
        "",
        "## Event summary",
        "",
        "| category | events | flush slots | recovery slots | slot-equivalent cycles | target fetch | target dispatch | target execute |",
        "|---|---:|---:|---:|---:|---|---|---|",
    ]
    for kind in ("btb_miss_taken", "direction_mismatch", "target_mismatch", "redirect_other", "trace_wave_mismatch"):
        n = category.get(kind, 0)
        if not n:
            continue
        stats = recovery[kind]
        fetch = [int(r["target_fetch_delay"]) for r in records if r["kind"] == kind and r["target_fetch_delay"] != ""]
        dispatch = [int(r["target_dispatch_delay"]) for r in records if r["kind"] == kind and r["target_dispatch_delay"] != ""]
        execute = [int(r["target_execute_delay"]) for r in records if r["kind"] == kind and r["target_execute_delay"] != ""]
        lines.append(f"| `{kind}` | {n} | {stats.get('flush_slots', 0)} | {stats.get('recovery_slots', 0)} | {(stats.get('flush_slots', 0) + stats.get('recovery_slots', 0)) / 2:.1f} | {fmt_stats(fetch)} | {fmt_stats(dispatch)} | {fmt_stats(execute)} |")
    lines += [
        "",
        "## Top mispredict PCs",
        "",
        "| PC | events | redirect slots |",
        "|---|---:|---:|",
    ]
    for branch_pc, stats in sorted(pc_stats.items(), key=lambda item: (-item[1]["slots"], -item[1]["events"], item[0]))[:12]:
        lines.append(f"| `{branch_pc}` | {stats['events']} | {stats['slots']} |")
    lines += [
        "",
        "## Predictor metadata edge",
        "",
        f"`pending_redirect` active cycles: **{pending_cycles}**, runs: **{pending_runs}**, rows with IF completely empty: **{pending_empty_slots // 2}** (slot estimate: **{pending_empty_slots}**). A zero empty count means this signal is not currently a front-end bubble cause.",
        "",
        "## Upper bounds",
        "",
        "The direct slot upper bound is `(flush_slots + recovery_slots) / 2` dual-issue cycles. The resolve-to-target-execute delay is a critical-path latency; subtracting one cycle per event is an optimistic lower bound for a perfect redirect and must not be added to the slot bound.",
    ]
    for kind in ("btb_miss_taken", "direction_mismatch"):
        delays = [int(r["target_execute_delay"]) for r in records if r["kind"] == kind and r["target_execute_delay"] != ""]
        if delays:
            lines.append(f"- `{kind}`: ideal c+1 target execute saves at most **{sum(max(0, d - 1) for d in delays)} cycles**; measured slot-equivalent recovery is **{(recovery[kind]['flush_slots'] + recovery[kind]['recovery_slots']) / 2:.1f} cycles**.")
    report_path.write_text("\n".join(lines) + "\n")
    print(report_path)
    print(csv_path)
    print("categories:", dict(category))


if __name__ == "__main__":
    main()
