#!/usr/bin/env python3
"""Build a detailed, architecture-oriented bubble report from simulation logs."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


PERF_RE = re.compile(r"^([A-Z][A-Z0-9_]*):\s*(.*)$")
FIELD_RE = re.compile(r"([A-Z][A-Z0-9_]*)=\s*([0-9]+(?:\.[0-9]+)?)")

PRIMARY_BUCKETS = (
    ("dual issue", "ISSUE2"),
    ("single issue", "ISSUE1"),
    ("control flush", "FLUSH"),
    ("multicycle EX hold", "MUL_HOLD"),
    ("multiple decode blockers", "MULTI"),
    ("scoreboard dependency", "SCOREBOARD"),
    ("LSU structural", "LSU_STRUCT"),
    ("producer slots full", "PRODUCER_FULL"),
    ("writeback backpressure", "WB"),
    ("CLINT serialization", "CLINT"),
    ("LSU/CSR serialization", "SERIALIZE"),
    ("issue-to-EX pipeline advance", "ISSUE_ADVANCE"),
    ("IF empty after resolved control", "IF_CONTROL"),
    ("IF empty after prediction", "IF_PREDICT"),
    ("IF empty after FENCE.I", "IF_FENCE"),
    ("IF empty awaiting response", "IF_RESPONSE"),
    ("IF empty at request launch", "IF_LAUNCH"),
    ("IF empty with pending redirect", "IF_PENDING"),
    ("IF empty fallback", "IF_OTHER"),
    ("issue register refill", "ISSUE_REFILL"),
    ("decode/front-end refill", "DECODE_REFILL"),
    ("issue blocked fallback", "ISSUE_BLOCKED"),
    ("unclassified fallback", "OTHER"),
)

DECODE_STALL_BITS = (
    (0, "scoreboard"),
    (1, "LSU structural"),
    (2, "producer full"),
    (3, "writeback"),
    (4, "CLINT"),
)

PAIR_BUCKETS = (
    ("eligible", "ELIGIBLE"),
    ("RAW dependency", "REJECT_RAW"),
    ("WAW dependency", "REJECT_WAW"),
    ("exclusive resource", "REJECT_RESOURCE"),
    ("serializing instruction", "REJECT_SERIAL"),
    ("branch plus memory", "REJECT_CONTROL_MEMORY"),
    ("lane assignment", "REJECT_LANE"),
    ("fallback", "REJECT_OTHER"),
)


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


def decode_mask_label(mask: int) -> str:
    return " + ".join(label for bit, label in DECODE_STALL_BITS if mask & (1 << bit))


def selected_logs(root: Path) -> list[Path]:
    # A caller may scope analysis to one simulation result directory.
    if (root / "hw.log").is_file():
        return [root / "hw.log"]
    suites = ("coe_loop5", "coe_loop_lina", "coremark", "sort", "boundary", "rv32ui", "rv32um", "rv32uz", "rv32mi")
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
            relative_parent = log.relative_to(args.root).parent
            name = args.root.name if str(relative_parent) == "." else str(relative_parent)
            programs.append((name, records))

    detailed_csv = args.out_dir / "perf_bubble_detail.csv"
    columns = [
        ("cycles", "PERF_METRIC", "CYCLES"), ("insts", "PERF_METRIC", "INSTS"),
        ("ipc", "PERF_METRIC", "IPC"),
        *[(f"primary_{key.lower()}", "PERF_PRIMARY_CYCLE", key)
          for _, key in PRIMARY_BUCKETS],
        ("primary_accounted", "PERF_PRIMARY_CYCLE", "ACCOUNTED"),
        ("primary_sample_cycles", "PERF_PRIMARY_CYCLE", "SAMPLE_CYCLES"),
        ("primary_closure_errors", "PERF_PRIMARY_CYCLE", "CLOSURE_ERRORS"),
        *[(f"decode_h{mask:02d}", "PERF_DECODE_STALL_EXACT", f"H{mask:02d}")
          for mask in range(1, 32)],
        ("decode_stall_cycles", "PERF_DECODE_STALL_EXACT", "STALL_CYCLES"),
        ("decode_exact_sum", "PERF_DECODE_STALL_EXACT", "EXACT_SUM"),
        ("decode_closure_errors", "PERF_DECODE_STALL_EXACT", "CLOSURE_ERRORS"),
        ("pair_candidate", "PERF_PAIR_DETAIL", "CANDIDATE"),
        *[(f"pair_{key.lower()}", "PERF_PAIR_DETAIL", key)
          for _, key in PAIR_BUCKETS],
        ("pair_accounted", "PERF_PAIR_DETAIL", "ACCOUNTED"),
        ("pair_closure_errors", "PERF_PAIR_DETAIL", "CLOSURE_ERRORS"),
        ("slot0_exec", "PERF_SLOT_DETAIL", "SLOT0_EXEC"),
        ("slot1_exec", "PERF_SLOT_DETAIL", "SLOT1_EXEC"),
        ("slot1_no_pair", "PERF_SLOT_DETAIL", "SLOT1_NO_PAIR"),
        ("slot1_scoreboard_replay", "PERF_SLOT_DETAIL", "SLOT1_SCOREBOARD_REPLAY"),
        ("slot1_lsu_replay", "PERF_SLOT_DETAIL", "SLOT1_LSU_REPLAY"),
        ("slot_closure_errors", "PERF_SLOT_DETAIL", "CLOSURE_ERRORS"),
        ("window_dispatch", "PERF_ISSUE_WINDOW", "DISPATCH"),
        ("window_select", "PERF_ISSUE_WINDOW", "SELECT"),
        ("window_select_two", "PERF_ISSUE_WINDOW", "SELECT_TWO"),
        ("window_nonadj_pair", "PERF_ISSUE_WINDOW", "NONADJ_PAIR"),
        ("window_bypass_consumed", "PERF_ISSUE_WINDOW", "BYPASS_CONSUMED"),
        ("window_scheduled_bypass", "PERF_ISSUE_WINDOW", "SCHEDULED_BYPASS"),
        ("window_registered_wakeup", "PERF_ISSUE_WINDOW", "REGISTERED_WAKEUP"),
        ("window_registered_alu_wakeup", "PERF_ISSUE_WINDOW", "REGISTERED_ALU_WAKEUP"),
        ("window_registered_lsu_wakeup", "PERF_ISSUE_WINDOW", "REGISTERED_LSU_WAKEUP"),
        ("window_registered_mdu_wakeup", "PERF_ISSUE_WINDOW", "REGISTERED_MDU_WAKEUP"),
        ("window_reserved_bypass_plan", "PERF_ISSUE_WINDOW", "RESERVED_BYPASS_PLAN"),
        ("window_reserved_bypass_issue", "PERF_ISSUE_WINDOW", "RESERVED_BYPASS_ISSUE"),
        ("window_reserved_bypass_cancel", "PERF_ISSUE_WINDOW", "RESERVED_BYPASS_CANCEL"),
        ("window_ingress_occ0", "PERF_ISSUE_WINDOW", "INGRESS_OCC0"),
        ("window_ingress_occ1", "PERF_ISSUE_WINDOW", "INGRESS_OCC1"),
        ("window_ingress_occ2", "PERF_ISSUE_WINDOW", "INGRESS_OCC2"),
        ("window_ingress_credit_admit", "PERF_ISSUE_WINDOW", "INGRESS_CREDIT_ADMIT"),
        ("window_ingress_to_station", "PERF_ISSUE_WINDOW", "INGRESS_TO_STATION"),
        ("window_full_station_refill", "PERF_ISSUE_WINDOW", "FULL_STATION_REFILL"),
        ("window_admission_backpressure", "PERF_ISSUE_WINDOW", "ADMISSION_BACKPRESSURE"),
        ("window_ingress_flush_drain", "PERF_ISSUE_WINDOW", "INGRESS_FLUSH_DRAIN"),
        ("window_completion_latency", "PERF_ISSUE_WINDOW", "COMPLETION_LATENCY"),
        ("issue", "PERF_CYCLE_ACCOUNT", "ISSUE"),
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

    # The architectural comparison uses the optimized CoreMark image.  Keep
    # legacy coremark only when an optimized result is unavailable.
    focus_names = {"coe_loop5", "coe_loop_lina", "coremark-opt/O2"}
    if not any(name == "coremark-opt/O2" for name, _ in programs):
        focus_names.add("coremark")
    focus = [(name, records) for name, records in programs if name in focus_names]
    if not focus and len(programs) == 1:
        focus = programs
    report = args.out_dir / "perf_bubble_analysis.md"
    with report.open("w") as stream:
        stream.write("# Pipeline bubble analysis\n\n")
        stream.write("Generated from the final `PERF_*` record in each simulation log. ")
        stream.write("The top-level cycle partition is mutually exclusive and checked for closure. ")
        stream.write("Diagnostic event families overlap and must not be summed.\n\n")
        stream.write("## Counting model\n\n")
        stream.write("Policy 2 first records productive execution as `ISSUE2` or `ISSUE1`; only cycles with no accepted instruction are attributed to a blocking or refill reason. ")
        stream.write("The no-EX-accept priority is `flush > multicycle hold > exact multi-signal decode block > single decode block > serialize > issue-stage advance > IF-empty detail > issue/decode refill > blocked fallback > other`. ")
        stream.write("Exactly one primary bucket is selected per sampled cycle. Fallback buckets preserve accounting closure but a nonzero fallback means semantic root-cause coverage is partial.\n\n")
        stream.write("Subset/overlap rules used below:\n\n")
        stream.write("- `branch/store wait` are consumer-role subsets of scoreboard cycles and may overlap producer-kind counters.\n")
        stream.write("- producer-to-consumer cells are subsets of their producer-use row; two source operands can make producer-kind rows overlap in one cycle.\n")
        stream.write("- pending producer kinds are selected by an `if/else` chain and are mutually exclusive with each other. Pending-tail explicitly excludes same-cycle issue hazards.\n")
        stream.write("- `ready but stalled`, complete-visible, and registered-visible are cross-cutting state observations, not additional lost cycles.\n")
        stream.write("- branch mispredicts are a subset of resolved branches; store-buffer hits are a subset of store-buffer lookups.\n")
        stream.write("- exact decode masks are mutually exclusive combinations; marginals derived from them overlap and are explicitly diagnostic.\n")
        stream.write("- pair rejection buckets are priority-attributed and mutually exclusive for each ready ID decision.\n")
        stream.write("- legacy `PERF_CAUSE_HIST*` records are diagnostic compatibility data and never participate in primary closure.\n\n")
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
            has_primary = "PERF_PRIMARY_CYCLE" in records
            if has_primary:
                partition = [(label, value(records, "PERF_PRIMARY_CYCLE", key))
                             for label, key in PRIMARY_BUCKETS]
                accounted = value(records, "PERF_PRIMARY_CYCLE", "ACCOUNTED")
                sample_cycles = value(records, "PERF_PRIMARY_CYCLE", "SAMPLE_CYCLES") or cycles
                closure_errors = value(records, "PERF_PRIMARY_CYCLE", "CLOSURE_ERRORS")
                arch_delta = int(cycles - sample_cycles)
                closed = (closure_errors == 0 and accounted == sample_cycles and
                          sum(count for _, count in partition) == sample_cycles)
            else:
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
                closure_errors = 0
                closed = accounted == sample_cycles and sum(count for _, count in partition) == sample_cycles
            stream.write("### Complete exclusive cycle partition\n\n")
            stream.write(f"Source: `{'PERF_PRIMARY_CYCLE' if has_primary else 'PERF_CYCLE_ACCOUNT (legacy)'}`. ")
            stream.write(f"Closure: **{'PASS' if closed else 'FAIL'}**, accounted={int(accounted)}, sample_cycles={int(sample_cycles)}, errors={int(closure_errors)}. ")
            stream.write(f"Architectural mcycle={int(cycles)}, mcycle-sample delta={int(arch_delta)}.\n\n")
            stream.write("| Primary bucket | Cycles | Total cycles |\n|---|---:|---:|\n")
            for label, count in sorted(partition, key=lambda item: item[1], reverse=True):
                stream.write(f"| {label} | {int(count)} | {pct(count, cycles)} |\n")
            stream.write("\nThis table is exhaustive for sampled cycles, but it is priority-attributed rather than causally independent. ")
            stream.write("A mechanism's removable-cycle upper bound is its exclusive bucket plus only overlapping buckets proven to contain that mechanism.\n")
            has_supply_detail = "PERF_NOIF_DETAIL" in records and "PERF_OTHER_DETAIL" in records
            if has_primary:
                fallback = (value(records, "PERF_PRIMARY_CYCLE", "IF_OTHER") +
                            value(records, "PERF_PRIMARY_CYCLE", "ISSUE_BLOCKED") +
                            value(records, "PERF_PRIMARY_CYCLE", "OTHER"))
            else:
                fallback = (value(records, "PERF_NOIF_DETAIL", "OTHER") +
                            value(records, "PERF_OTHER_DETAIL", "OTHER"))
            root_status = "COMPLETE" if closed and fallback == 0 else "PARTIAL"
            stream.write(f"\nDefined-taxonomy completeness: **{root_status}**; fallback-attributed cycles={int(fallback)}.\n")

            stream.write("\n### Front-end and pipeline-supply gaps\n\n")
            noif_parent = value(records, "PERF_CYCLE_ACCOUNT", "NO_IF_VALID")
            other_parent = value(records, "PERF_CYCLE_ACCOUNT", "OTHER")
            if has_primary:
                stream.write("Front-end and refill causes are already first-class exclusive rows in the primary table. ")
                stream.write("The legacy detail records below are retained only for sequence diagnostics and use the older attribution priority.\n")
            elif not has_supply_detail:
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

            stream.write("\n### Decode-stall intersections\n\n")
            exact = records.get("PERF_DECODE_STALL_EXACT", {})
            if exact:
                exact_sum = sum(exact.get(f"H{mask:02d}", 0.0) for mask in range(1, 32))
                stall_cycles = exact.get("STALL_CYCLES", 0.0)
                exact_errors = exact.get("CLOSURE_ERRORS", 0.0)
                exact_closed = (exact_sum == stall_cycles == exact.get("EXACT_SUM", exact_sum)
                                and exact_errors == 0)
                stream.write("Each row is one exact, mutually exclusive combination of SB/LSU/PF/WB/CLINT. ")
                stream.write(f"Closure: **{'PASS' if exact_closed else 'FAIL'}**, exact_sum={int(exact_sum)}, stall_cycles={int(stall_cycles)}, errors={int(exact_errors)}.\n\n")
                stream.write("| Mask | Exact combination | Cycles | Stall cycles |\n|---:|---|---:|---:|\n")
                for mask in range(1, 32):
                    count = exact.get(f"H{mask:02d}", 0.0)
                    if count:
                        stream.write(f"| {mask:02d} | {decode_mask_label(mask)} | {int(count)} | {pct(count, stall_cycles)} |\n")
                stream.write("\nDerived marginals below overlap and are diagnostic only:\n\n")
                stream.write("| Signal | Cycles with signal | Decode-stall cycles |\n|---|---:|---:|\n")
                for bit, label in DECODE_STALL_BITS:
                    marginal = sum(exact.get(f"H{mask:02d}", 0.0)
                                   for mask in range(1, 32) if mask & (1 << bit))
                    stream.write(f"| {label} | {int(marginal)} | {pct(marginal, stall_cycles)} |\n")
            else:
                hist = records.get("PERF_CAUSE_HIST_FULL", {})
                stream.write("This legacy log has no nonzero-mask closure record. `PERF_CAUSE_HIST_FULL` is shown only as compatibility diagnostic data; its H00 bin includes all non-stall cycles.\n\n")
                stream.write("| Mask | Exact combination | Cycles |\n|---:|---|---:|\n")
                for mask in range(1, 32):
                    count = hist.get(f"H{mask:02d}", 0.0)
                    if count:
                        stream.write(f"| {mask:02d} | {decode_mask_label(mask)} | {int(count)} |\n")

            stream.write("\n### Static-pair decisions\n\n")
            pair = records.get("PERF_PAIR_DETAIL", {})
            if pair:
                candidate = pair.get("CANDIDATE", 0.0)
                pair_sum = sum(pair.get(key, 0.0) for _, key in PAIR_BUCKETS)
                pair_closed = (pair_sum == candidate == pair.get("ACCOUNTED", pair_sum)
                               and pair.get("CLOSURE_ERRORS", 0.0) == 0)
                stream.write(f"Closure: **{'PASS' if pair_closed else 'FAIL'}**, candidates={int(candidate)}, accounted={int(pair_sum)}. ")
                stream.write("A candidate is sampled once when ID is ready, so downstream stall residency does not multiply the count.\n\n")
                stream.write("| Primary decision | Pairs | Candidates |\n|---|---:|---:|\n")
                for label, key in PAIR_BUCKETS:
                    count = pair.get(key, 0.0)
                    stream.write(f"| {label} | {int(count)} | {pct(count, candidate)} |\n")
            else:
                stream.write("Pair-decision instrumentation is unavailable in this legacy log.\n")

            stream.write("\n### Execute-slot detail\n\n")
            slot = records.get("PERF_SLOT_DETAIL", {})
            if slot:
                slot_sum = slot.get("SLOT0_EXEC", 0.0) + slot.get("SLOT1_EXEC", 0.0)
                slot_closed = (slot_sum == slot.get("PRODUCTIVE_SLOTS", slot_sum)
                               and slot.get("CLOSURE_ERRORS", 0.0) == 0)
                stream.write(f"Closure: **{'PASS' if slot_closed else 'FAIL'}**, slot0={int(slot.get('SLOT0_EXEC', 0.0))}, slot1={int(slot.get('SLOT1_EXEC', 0.0))}, productive={int(slot.get('PRODUCTIVE_SLOTS', 0.0))}.\n\n")
                stream.write("| Observation | Events | Sample cycles |\n|---|---:|---:|\n")
                for label, key in (("slot 0 accepted", "SLOT0_EXEC"),
                                   ("slot 1 accepted / pair executed", "SLOT1_EXEC"),
                                   ("slot 0 accepted without slot 1", "SLOT1_NO_PAIR"),
                                   ("slot 1 scoreboard replay", "SLOT1_SCOREBOARD_REPLAY"),
                                   ("slot 1 LSU replay", "SLOT1_LSU_REPLAY")):
                    count = slot.get(key, 0.0)
                    stream.write(f"| {label} | {int(count)} | {pct(count, sample_cycles)} |\n")
            else:
                stream.write("Execute-slot detail is unavailable in this legacy log.\n")

            window = records.get("PERF_ISSUE_WINDOW", {})
            stream.write("\n### Issue-window architecture observations\n\n")
            if window:
                sample = sample_cycles or 1.0
                stream.write("| Observation | Events | Sample cycles |\n|---|---:|---:|\n")
                for label, key in (
                    ("ingress empty occupancy cycles", "INGRESS_OCC0"),
                    ("ingress one-entry occupancy cycles", "INGRESS_OCC1"),
                    ("ingress full occupancy cycles", "INGRESS_OCC2"),
                    ("dispatch admitted under full-station ingress credit", "INGRESS_CREDIT_ADMIT"),
                    ("older ingress uops transferred into station", "INGRESS_TO_STATION"),
                    ("new uops refilling a selected full-station slot", "FULL_STATION_REFILL"),
                    ("frontend cycles blocked by full station and ingress", "ADMISSION_BACKPRESSURE"),
                    ("ingress uops discarded by flush/trap boundary", "INGRESS_FLUSH_DRAIN"),
                    ("preplanned local bypass", "SCHEDULED_BYPASS"),
                    ("preplanned bypass consumed by issue", "BYPASS_CONSUMED"),
                    ("registered completion wakeup", "REGISTERED_WAKEUP"),
                    ("registered ALU wakeup", "REGISTERED_ALU_WAKEUP"),
                    ("registered LSU wakeup", "REGISTERED_LSU_WAKEUP"),
                    ("registered MDU wakeup", "REGISTERED_MDU_WAKEUP"),
                    ("registered local-bypass reservation", "RESERVED_BYPASS_PLAN"),
                    ("reserved local bypass issued", "RESERVED_BYPASS_ISSUE"),
                    ("reserved local bypass cancelled", "RESERVED_BYPASS_CANCEL"),
                    ("oldest entry completion captured for next-cycle visibility", "COMPLETION_LATENCY"),
                    ("non-adjacent pair", "NONADJ_PAIR"),
                ):
                    count = window.get(key, 0.0)
                    stream.write(f"| {label} | {int(count)} | {pct(count, sample)} |\n")
                backpressure = window.get("ADMISSION_BACKPRESSURE", 0.0)
                stream.write("\nIngress admission pressure: ")
                stream.write(f"full station+ingress backpressure={int(backpressure)} ")
                stream.write(f"({pct(backpressure, sample)} of sampled cycles). ")
                stream.write("Ingress occupancy and transfer counters describe the registered ")
                stream.write("admission boundary; they are not themselves lost cycles or part of the mutually exclusive primary-cycle partition.\n")
            else:
                stream.write("Issue-window architecture counters are unavailable in this legacy log.\n")
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
