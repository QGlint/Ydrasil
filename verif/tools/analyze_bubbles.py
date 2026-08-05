#!/usr/bin/env python3
"""Build a detailed, architecture-oriented bubble report from simulation logs."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


PERF_RE = re.compile(r"^([A-Z][A-Z0-9_]*):\s*(.*)$")
FIELD_RE = re.compile(r"([A-Z][A-Z0-9_]*)=\s*([0-9]+(?:\.[0-9]+)?)")


def parse_log(path: Path) -> dict[str, dict[str, float]]:
    records: dict[str, dict[str, float]] = {}
    for line in path.read_text(errors="replace").splitlines():
        match = PERF_RE.match(line)
        if not match:
            continue
        fields = {key: float(value) for key, value in FIELD_RE.findall(match.group(2))}
        if fields:
            records[match.group(1)] = fields
    return records


def value(records: dict[str, dict[str, float]], record: str, field: str) -> float:
    return records.get(record, {}).get(field, 0.0)


def pct(part: float, total: float) -> str:
    return f"{100.0 * part / total:.2f}%" if total else "0.00%"


def signed_counter(value_: float, bits: int = 32) -> int:
    raw = int(value_)
    return raw - (1 << bits) if raw >= (1 << (bits - 1)) else raw


def selected_logs(root: Path) -> list[Path]:
    suites = ("coremark", "sort", "boundary", "rv32ui", "rv32um", "rv32uz", "rv32mi")
    return sorted(path for path in root.rglob("hw.log") if any(part.startswith(suites) for part in path.parts))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path("build/sim/hw"))
    parser.add_argument("out_dir", nargs="?", type=Path, default=Path("build/PPA"))
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    programs: list[tuple[str, dict[str, dict[str, float]]]] = []
    for log in selected_logs(args.root):
        records = parse_log(log)
        if "PERF_CYCLE_ACCOUNT" in records:
            programs.append((str(log.relative_to(args.root).parent), records))

    detailed_csv = args.out_dir / "perf_bubble_detail.csv"
    columns = [
        ("cycles", "PERF_METRIC", "CYCLES"), ("insts", "PERF_METRIC", "INSTS"),
        ("ipc", "PERF_METRIC", "IPC"), ("issue", "PERF_CYCLE_ACCOUNT", "ISSUE"),
        ("capacity_slots", "PERF_SLOT_ACCOUNT", "CAPACITY_SLOTS"),
        ("productive_slots", "PERF_SLOT_ACCOUNT", "PRODUCTIVE_SLOTS"),
        ("lost_slots", "PERF_SLOT_ACCOUNT", "LOST_SLOTS"),
        ("slot_ipc", "PERF_SLOT_ACCOUNT", "SLOT_IPC"),
        ("flush", "PERF_CYCLE_ACCOUNT", "FLUSH"), ("mul_hold", "PERF_CYCLE_ACCOUNT", "MUL_HOLD"),
        ("scoreboard", "PERF_CYCLE_ACCOUNT", "SCOREBOARD"), ("lsu_struct", "PERF_CYCLE_ACCOUNT", "LSU_STRUCT"),
        ("lsu_serialize", "PERF_CYCLE_ACCOUNT", "LSU_SERIALIZE"),
        ("producer_full", "PERF_CYCLE_ACCOUNT", "PRODUCER_FULL"), ("wb", "PERF_CYCLE_ACCOUNT", "WB"),
        ("clint", "PERF_CYCLE_ACCOUNT", "CLINT"), ("multi", "PERF_CYCLE_ACCOUNT", "MULTI"),
        ("no_if_valid", "PERF_CYCLE_ACCOUNT", "NO_IF_VALID"), ("other", "PERF_CYCLE_ACCOUNT", "OTHER"),
        ("noif_control_redirect", "PERF_NOIF_DETAIL", "CONTROL_REDIRECT"),
        ("noif_predict_redirect", "PERF_NOIF_DETAIL", "PREDICT_REDIRECT"),
        ("noif_fence_refill", "PERF_NOIF_DETAIL", "FENCE_REFILL"),
        ("noif_mem_response", "PERF_NOIF_DETAIL", "MEM_RESPONSE"),
        ("noif_fetch_launch", "PERF_NOIF_DETAIL", "FETCH_LAUNCH"),
        ("noif_pending_redirect", "PERF_NOIF_DETAIL", "PENDING_REDIRECT"),
        ("noif_other", "PERF_NOIF_DETAIL", "OTHER"),
        ("other_issue_refill", "PERF_OTHER_DETAIL", "ISSUE_REFILL"),
        ("other_decode_refill", "PERF_OTHER_DETAIL", "DECODE_REFILL"),
        ("other_issue_blocked", "PERF_OTHER_DETAIL", "ISSUE_BLOCKED"),
        ("other_unclassified", "PERF_OTHER_DETAIL", "OTHER"),
        ("decode_refill_after_control", "PERF_DECODE_REFILL_DETAIL", "AFTER_CONTROL"),
        ("decode_refill_after_predict", "PERF_DECODE_REFILL_DETAIL", "AFTER_PREDICT"),
        ("decode_refill_after_fence", "PERF_DECODE_REFILL_DETAIL", "AFTER_FENCE"),
        ("decode_refill_after_supply", "PERF_DECODE_REFILL_DETAIL", "AFTER_SUPPLY"),
        ("load_use", "PERF_SCOREBOARD_DETAIL", "LOAD_USE"), ("alu_use", "PERF_SCOREBOARD_DETAIL", "ALU_USE"),
        ("mul_div_use", "PERF_SCOREBOARD_DETAIL", "MUL_DIV_USE"),
        ("branch_wait", "PERF_SCOREBOARD_DETAIL", "BRANCH_SRC_WAIT"),
        ("store_addr_wait", "PERF_SCOREBOARD_DETAIL", "STORE_ADDR_WAIT"),
        ("store_data_wait", "PERF_SCOREBOARD_DETAIL", "STORE_DATA_WAIT"),
        ("pending_alu", "PERF_PENDING_DETAIL", "ALU"), ("pending_load", "PERF_PENDING_DETAIL", "LOAD"),
        ("pending_mul", "PERF_PENDING_DETAIL", "MUL"), ("ready_but_stall", "PERF_PENDING_DETAIL", "READY_BUT_STALL"),
        ("load_to_alu", "PERF_LOAD_DETAIL", "TO_ALU"), ("load_to_branch", "PERF_LOAD_DETAIL", "TO_BRANCH"),
        ("load_to_load", "PERF_LOAD_DETAIL", "TO_LOAD"), ("load_to_store", "PERF_LOAD_DETAIL", "TO_STORE"),
        ("load_to_mul", "PERF_LOAD_DETAIL", "TO_MUL"),
        ("alu_to_alu", "PERF_ALU_DETAIL", "TO_ALU"), ("alu_to_branch", "PERF_ALU_DETAIL", "TO_BRANCH"),
        ("alu_to_load", "PERF_ALU_DETAIL", "TO_LOAD"), ("alu_to_store", "PERF_ALU_DETAIL", "TO_STORE"),
        ("alu_to_mul", "PERF_ALU_DETAIL", "TO_MUL"),
        ("pred_redirect", "PERF_FRONTEND", "PRED_TAKEN_REDIRECT"),
        ("wrong_dir_flush", "PERF_FRONTEND", "WRONG_DIR_FLUSH"),
        ("btb_miss_taken", "PERF_FRONTEND", "BTB_MISS_TAKEN"),
        ("branches", "PERF_BRANCH", "BRANCHES"), ("mispred", "PERF_BRANCH", "MISPRED"),
        ("stb_lookup", "PERF_LSU_STB", "LOOKUP"), ("stb_hit", "PERF_LSU_STB", "HIT"),
        ("occ2", "PERF_PRODUCER_STATE", "OCC2"), ("both_wait", "PERF_PRODUCER_STATE", "BOTH_WAIT"),
    ]
    with detailed_csv.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["program", *[item[0] for item in columns]])
        for program, records in programs:
            writer.writerow([program, *[value(records, record, field) for _, record, field in columns]])

    focus = [(name, records) for name, records in programs if name == "coremark"]
    report = args.out_dir / "perf_bubble_analysis.md"
    with report.open("w") as stream:
        stream.write("# Pipeline bubble analysis\n\n")
        stream.write("Generated from the final `PERF_*` record in each simulation log. ")
        stream.write("The top-level cycle partition is mutually exclusive and checked for closure. ")
        stream.write("Diagnostic event families overlap and must not be summed.\n\n")
        stream.write("## Counting model\n\n")
        stream.write("The primary-cause priority is `flush > multicycle hold > multi-cause decode stall > scoreboard > LSU structural > producer full > WB > CLINT > LSU serialize > no IF valid > issue > other`. ")
        stream.write("This makes the partition exclusive, but a higher-priority cause masks lower-priority causes in that table. ")
        stream.write("`ISSUE` is productive admission, not a bubble; `OTHER` and `NO_IF_VALID` are complete buckets but not complete root-cause classifications.\n\n")
        stream.write("Subset/overlap rules used below:\n\n")
        stream.write("- `branch/store wait` are consumer-role subsets of scoreboard cycles and may overlap producer-kind counters.\n")
        stream.write("- producer-to-consumer cells are subsets of their producer-use row; two source operands can make producer-kind rows overlap in one cycle.\n")
        stream.write("- pending producer kinds are selected by an `if/else` chain and are mutually exclusive with each other. Pending-tail explicitly excludes same-cycle issue hazards.\n")
        stream.write("- `ready but stalled`, complete-visible, and registered-visible are cross-cutting state observations, not additional lost cycles.\n")
        stream.write("- branch mispredicts are a subset of resolved branches; store-buffer hits are a subset of store-buffer lookups.\n")
        stream.write("- the legacy cause histogram has exact SB/LSU/PF intersections only when WB and CLINT are both low. `WB_ANY` and `CLINT_ANY` are overlapping marginals.\n\n")
        for program, records in focus:
            cycles = value(records, "PERF_METRIC", "CYCLES")
            insts = value(records, "PERF_METRIC", "INSTS")
            ipc = value(records, "PERF_METRIC", "IPC")
            capacity = value(records, "PERF_SLOT_ACCOUNT", "CAPACITY_SLOTS")
            productive = value(records, "PERF_SLOT_ACCOUNT", "PRODUCTIVE_SLOTS")
            lost = value(records, "PERF_SLOT_ACCOUNT", "LOST_SLOTS")
            slot_ipc = value(records, "PERF_SLOT_ACCOUNT", "SLOT_IPC")
            stream.write(f"## {program}\n\n{int(cycles)} cycles, {int(insts)} retired instructions, IPC {ipc:.4f}. ")
            if capacity:
                stream.write(f"Dual-slot capacity={int(capacity)}, productive slots={int(productive)}, lost slots={int(lost)}, slot utilization={slot_ipc:.4f}.\n\n")
            else:
                stream.write("Dual-slot accounting is unavailable in this log.\n\n")
            partition = [(label, value(records, "PERF_CYCLE_ACCOUNT", key)) for label, key in (
                ("scoreboard dependency", "SCOREBOARD"), ("front-end invalid", "NO_IF_VALID"),
                ("unclassified/issue gap", "OTHER"), ("control flush", "FLUSH"),
                ("multicycle EX hold", "MUL_HOLD"), ("LSU structural", "LSU_STRUCT"),
                ("LSU serialization", "LSU_SERIALIZE"),
                ("producer slots full", "PRODUCER_FULL"), ("overlapping causes", "MULTI"),
                ("WB backpressure", "WB"), ("CLINT serialization", "CLINT"),
                ("productive issue", "ISSUE"))]
            accounted = value(records, "PERF_CYCLE_ACCOUNT", "ACCOUNTED")
            sample_cycles = value(records, "PERF_CYCLE_ACCOUNT", "SAMPLE_CYCLES") or cycles
            arch_delta_field = ("ARCH_CYCLE_DELTA" if "ARCH_CYCLE_DELTA" in records.get("PERF_CYCLE_ACCOUNT", {})
                                else "CYCLE_DELTA")
            arch_delta = signed_counter(value(records, "PERF_CYCLE_ACCOUNT", arch_delta_field))
            closed = accounted == sample_cycles and sum(count for _, count in partition) == sample_cycles
            stream.write("### Complete exclusive cycle partition\n\n")
            stream.write(f"Closure: **{'PASS' if closed else 'FAIL'}**, accounted={int(accounted)}, sample_cycles={int(sample_cycles)}. ")
            stream.write(f"Architectural mcycle={int(cycles)}, mcycle-sample delta={int(arch_delta)}.\n\n")
            stream.write("| Primary bucket | Cycles | Total cycles |\n|---|---:|---:|\n")
            for label, count in sorted(partition, key=lambda item: item[1], reverse=True):
                stream.write(f"| {label} | {int(count)} | {pct(count, cycles)} |\n")
            stream.write("\nThis table is exhaustive for sampled cycles, but it is priority-attributed rather than causally independent. ")
            stream.write("A mechanism's removable-cycle upper bound is its exclusive bucket plus only overlapping buckets proven to contain that mechanism.\n")
            has_supply_detail = "PERF_NOIF_DETAIL" in records and "PERF_OTHER_DETAIL" in records
            supply_unclassified = (value(records, "PERF_NOIF_DETAIL", "OTHER") +
                                   value(records, "PERF_OTHER_DETAIL", "OTHER"))
            root_status = "COMPLETE" if closed and has_supply_detail and supply_unclassified == 0 else "PARTIAL"
            stream.write(f"\nDefined-taxonomy completeness: **{root_status}**. `NO_IF_VALID`={int(value(records, 'PERF_CYCLE_ACCOUNT', 'NO_IF_VALID'))}, ")
            stream.write(f"`OTHER`={int(value(records, 'PERF_CYCLE_ACCOUNT', 'OTHER'))}, unclassified children={int(supply_unclassified)}.\n")

            stream.write("\n### Front-end and pipeline-supply gaps\n\n")
            noif_parent = value(records, "PERF_CYCLE_ACCOUNT", "NO_IF_VALID")
            other_parent = value(records, "PERF_CYCLE_ACCOUNT", "OTHER")
            if not has_supply_detail:
                stream.write("The current log predates the sub-cause counters. Rerun simulation to split these parent buckets.\n")
            else:
                noif_parts = [("resolved control redirect refill", "CONTROL_REDIRECT"),
                              ("predicted-taken redirect refill", "PREDICT_REDIRECT"),
                              ("FENCE.I refill", "FENCE_REFILL"),
                              ("memory response arrives while queue empty", "MEM_RESPONSE"),
                              ("first fetch launch while queue empty", "FETCH_LAUNCH"),
                              ("pending predicted target", "PENDING_REDIRECT"),
                              ("unclassified front-end empty", "OTHER")]
                noif_sum = sum(value(records, "PERF_NOIF_DETAIL", key) for _, key in noif_parts)
                stream.write(f"`NO_IF_VALID` child closure: **{'PASS' if noif_sum == noif_parent else 'FAIL'}**, children={int(noif_sum)}, parent={int(noif_parent)}.\n\n")
                stream.write("| NO_IF_VALID child (exclusive priority) | Cycles | Parent |\n|---|---:|---:|\n")
                for label, key in noif_parts:
                    count = value(records, "PERF_NOIF_DETAIL", key)
                    stream.write(f"| {label} | {int(count)} | {pct(count, noif_parent)} |\n")
                other_parts = [("issue register refill from decode FIFO", "ISSUE_REFILL"),
                               ("decode FIFO refill from IF queue", "DECODE_REFILL"),
                               ("valid issue unable to advance", "ISSUE_BLOCKED"),
                               ("unclassified supply gap", "OTHER")]
                other_sum = sum(value(records, "PERF_OTHER_DETAIL", key) for _, key in other_parts)
                stream.write(f"\n`OTHER` child closure: **{'PASS' if other_sum == other_parent else 'FAIL'}**, children={int(other_sum)}, parent={int(other_parent)}.\n\n")
                stream.write("| OTHER child (exclusive) | Cycles | Parent |\n|---|---:|---:|\n")
                for label, key in other_parts:
                    count = value(records, "PERF_OTHER_DETAIL", key)
                    stream.write(f"| {label} | {int(count)} | {pct(count, other_parent)} |\n")
                if "PERF_DECODE_REFILL_DETAIL" in records:
                    decode_parent = value(records, "PERF_OTHER_DETAIL", "DECODE_REFILL")
                    decode_parts = [("after resolved control redirect", "AFTER_CONTROL"),
                                    ("after predicted redirect", "AFTER_PREDICT"),
                                    ("after FENCE.I", "AFTER_FENCE"),
                                    ("after ordinary front-end supply gap", "AFTER_SUPPLY")]
                    decode_sum = sum(value(records, "PERF_DECODE_REFILL_DETAIL", key) for _, key in decode_parts)
                    stream.write(f"\nDecode-refill cross-sequence closure: **{'PASS' if decode_sum == decode_parent else 'FAIL'}**, children={int(decode_sum)}, parent={int(decode_parent)}.\n\n")
                    stream.write("| Decode refill sequence subset | Cycles | Decode refill |\n|---|---:|---:|\n")
                    for label, key in decode_parts:
                        count = value(records, "PERF_DECODE_REFILL_DETAIL", key)
                        stream.write(f"| {label} | {int(count)} | {pct(count, decode_parent)} |\n")
                stream.write("\nRedirect refill has priority over request-state labels, so those rows are exclusive attributions. ")
                stream.write("A redirect-refill cycle can physically also contain a fetch launch or memory response.\n")

            hist = records.get("PERF_CAUSE_HIST", {})
            stream.write("\n### Decode-stall intersections\n\n")
            stream.write("The 32-bin bitmap covers SB/LSU structural/PF/WB/CLINT. LSU serialization is independently primary-attributed and is not a bitmap dimension.\n\n")
            stream.write("| Exact combination (WB=0, CLINT=0) | Cycles | Relation |\n|---|---:|---|\n")
            for label, key, relation in (
                ("SB only", "SB", "exclusive bin"), ("LSU only", "LSU", "exclusive bin"),
                ("LSU & SB", "LSU_SB", "intersection"), ("PF only", "PF", "exclusive bin"),
                ("PF & SB", "PF_SB", "intersection"), ("PF & LSU", "PF_LSU", "intersection"),
                ("PF & LSU & SB", "PF_LSU_SB", "three-way intersection")):
                stream.write(f"| {label} | {int(hist.get(key, 0.0))} | {relation} |\n")
            stream.write(f"\nAggregated overlapping marginals: WB_ANY={int(hist.get('WB_ANY', 0.0))}, ")
            stream.write(f"CLINT_ANY={int(hist.get('CLINT_ANY', 0.0))}. ")
            if "PERF_CAUSE_HIST_FULL" in records:
                stream.write("The log contains all 32 raw bitmask bins. Pairwise intersections (including higher-order intersections) are:\n\n")
                full_hist = records["PERF_CAUSE_HIST_FULL"]
                signals = (("SB", 0), ("LSU", 1), ("PF", 2), ("WB", 3), ("CLINT", 4))
                stream.write("| A | B | A & B cycles |\n|---|---|---:|\n")
                for left_index, (left_name, left_bit) in enumerate(signals):
                    for right_name, right_bit in signals[left_index + 1:]:
                        intersection = sum(
                            full_hist.get(f"H{mask:02d}", 0.0)
                            for mask in range(32)
                            if mask & (1 << left_bit) and mask & (1 << right_bit)
                        )
                        stream.write(f"| {left_name} | {right_name} | {int(intersection)} |\n")
            else:
                stream.write("This legacy log does not contain all 32 raw bins, so WB/CLINT intersections cannot be reconstructed exactly; rerun simulation with the updated testbench.\n")
            stream.write("\n### Scoreboard diagnosis\n\n| Signal | Cycles/events | Scoreboard cycles |\n|---|---:|---:|\n")
            scoreboard = value(records, "PERF_STALL", "SCOREBOARD")
            details = [("load producer use", "PERF_SCOREBOARD_DETAIL", "LOAD_USE"),
                       ("ALU producer use", "PERF_SCOREBOARD_DETAIL", "ALU_USE"),
                       ("MUL/DIV producer use", "PERF_SCOREBOARD_DETAIL", "MUL_DIV_USE"),
                       ("pending load tail", "PERF_PENDING_DETAIL", "LOAD"),
                       ("pending MUL tail", "PERF_PENDING_DETAIL", "MUL"),
                       ("branch source wait", "PERF_SCOREBOARD_DETAIL", "BRANCH_SRC_WAIT"),
                       ("store address wait", "PERF_SCOREBOARD_DETAIL", "STORE_ADDR_WAIT"),
                       ("store data wait", "PERF_SCOREBOARD_DETAIL", "STORE_DATA_WAIT"),
                       ("ready producer but still stalled", "PERF_PENDING_DETAIL", "READY_BUT_STALL")]
            for label, record, field in details:
                count = value(records, record, field)
                stream.write(f"| {label} | {int(count)} | {pct(count, scoreboard)} |\n")
            pending_sum = sum(value(records, "PERF_PENDING_DETAIL", field) for field in ("ALU", "LOAD", "MUL", "OTHER"))
            pending_tail = value(records, "PERF_LOAD_DETAIL", "PENDING_TAIL")
            stream.write(f"\nPending-kind partition check: {int(pending_sum)} classified events vs {int(pending_tail)} pending-tail events")
            stream.write(" (PASS).\n" if pending_sum == pending_tail else " (FAIL: counter definitions or sampling differ).\n")
            stream.write("\nProducer-to-consumer events (overlapping):\n\n| Producer | ALU | Branch | Load | Store | MUL |\n|---|---:|---:|---:|---:|---:|\n")
            for producer, record in (("load", "PERF_LOAD_DETAIL"), ("ALU", "PERF_ALU_DETAIL")):
                vals = [int(value(records, record, key)) for key in ("TO_ALU", "TO_BRANCH", "TO_LOAD", "TO_STORE", "TO_MUL")]
                stream.write(f"| {producer} | {' | '.join(map(str, vals))} |\n")
            branches = value(records, "PERF_BRANCH", "BRANCHES")
            mispred = value(records, "PERF_BRANCH", "MISPRED")
            lookup = value(records, "PERF_LSU_STB", "LOOKUP")
            hit = value(records, "PERF_LSU_STB", "HIT")
            stream.write(f"\nFront end: {int(mispred)}/{int(branches)} branch mispredicts ({pct(mispred, branches)}), ")
            stream.write(f"{int(value(records, 'PERF_FRONTEND', 'BTB_MISS_TAKEN'))} taken BTB misses. ")
            stream.write(f"LSU store-buffer forwarding hit rate: {int(hit)}/{int(lookup)} ({pct(hit, lookup)}).\n\n")

    print(f"[PPA] Detailed bubble CSV: {detailed_csv}")
    print(f"[PPA] Bubble analysis: {report}")


if __name__ == "__main__":
    main()
