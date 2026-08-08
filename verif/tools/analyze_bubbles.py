#!/usr/bin/env python3
"""Build an architecture-oriented report for the decoupled OoO backend."""

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
        if match:
            fields = {
                key: float(raw) for key, raw in FIELD_RE.findall(match.group(2))
            }
            if fields:
                records[match.group(1)] = fields
    return records


def value(records: dict[str, dict[str, float]], record: str, field: str) -> float:
    return records.get(record, {}).get(field, 0.0)


def pct(part: float, total: float) -> str:
    return f"{100.0 * part / total:.2f}%" if total else "0.00%"


def selected_logs(root: Path) -> list[Path]:
    suites = ("coremark", "sort", "boundary", "rv32ui", "rv32um", "rv32uz", "rv32mi")
    return sorted(
        path
        for path in root.rglob("hw.log")
        if any(part.startswith(suites) for part in path.parts)
    )


CONTROL_FIELDS = (
    "DEP_TOKEN_ENTRY_CYCLES",
    "ORDER_TOKEN_ENTRY_CYCLES",
    "RESOURCE_ENTRY_CYCLES",
    "SELECTABLE_ENTRY_CYCLES",
    "RS_BANK_FULL",
    "RS_PAIR_BANK_LIMIT",
    "ROB_FULL",
    "LSU_CREDIT",
    "DIV_CREDIT",
    "SERIAL_GATE",
    "SELECT_WIDTH",
    "OPERAND_DEP_MISS",
    "RECOVERY",
    "RECOVERY_RESYNC",
)
LOCAL_CONTROL_FIELDS = (
    "ALU_ENTRY_CYCLES",
    "P0_ENTRY_CYCLES",
    "P1_ENTRY_CYCLES",
    "ALU_FULL",
    "P0_FULL",
    "P1_FULL",
    "ALU_DUE_SELECT",
    "DTCM_DUE_SELECT",
    "MDU_DUE_SELECT",
    "DTCM_LOCAL_WAKE",
    "MDU_LOCAL_WAKE",
    "RESIDENT_WAKE_ENTRIES",
    "RESIDENT_DUE_SELECT",
)
FLOW_FAMILIES = (
    ("rs_alloc", ("RS_ALLOC0", "RS_ALLOC1", "RS_ALLOC2")),
    ("select", ("SELECT0", "SELECT1", "SELECT2")),
    ("operand", ("OPERAND0", "OPERAND1", "OPERAND2")),
    ("complete", ("COMPLETE0", "COMPLETE1", "COMPLETE2", "COMPLETE3", "COMPLETE4")),
    ("retire", ("RETIRE0", "RETIRE1", "RETIRE2")),
)
HEAD_FIELDS = (
    ("empty", "EMPTY"),
    ("retire one", "RETIRE1"),
    ("retire two", "RETIRE2"),
    ("completion visible", "COMPLETE_VISIBLE"),
    ("not issued", "NOT_ISSUED"),
    ("wait ALU", "WAIT_ALU"),
    ("wait load", "WAIT_LOAD"),
    ("wait MDU", "WAIT_MDU"),
    ("wait store", "WAIT_STORE"),
    ("wait branch", "WAIT_BRANCH"),
    ("wait other", "WAIT_OTHER"),
)
LOSS_FIELDS = (
    ("recovery flush", "FLUSH"),
    ("Operand contract miss", "OPERAND_BLOCK"),
    ("single Operand bundle", "SINGLE_BUNDLE"),
    ("Select refill", "SELECT_REFILL"),
    ("RS dependency token", "RS_DEPENDENCY"),
    ("RS order token", "RS_ORDER"),
    ("RS resource credit", "RS_RESOURCE"),
    ("RS other", "RS_OTHER"),
    ("ROB full", "ROB_FULL"),
    ("RS refill", "RS_REFILL"),
    ("Decode refill", "DECODE_REFILL"),
    ("front end", "FRONTEND"),
    ("other", "OTHER"),
)
SLOT_REASON_FIELDS = (
    ("executed", "EXECUTED"),
    ("flush", "FLUSH"),
    ("multicycle hold", "MUL_HOLD"),
    ("multi-cause control", "MULTI_CAUSE"),
    ("dependency", "DEPENDENCY"),
    ("LSU structural", "LSU_STRUCT"),
    ("producer full", "PRODUCER_FULL"),
    ("writeback backpressure", "WB"),
    ("CLINT/trap", "CLINT"),
    ("LSU serialize", "LSU_SERIALIZE"),
    ("front end has no IF/ID", "NO_IF_VALID"),
    ("issue packet", "ISSUE"),
    ("other", "OTHER"),
)
NOIF_SLOT_FIELDS = (
    ("control redirect", "CONTROL_REDIRECT"),
    ("predict redirect", "PREDICT_REDIRECT"),
    ("fence refill", "FENCE_REFILL"),
    ("memory response", "MEM_RESPONSE"),
    ("fetch launch", "FETCH_LAUNCH"),
    ("pending redirect", "PENDING_REDIRECT"),
    ("other", "OTHER"),
)
BANK_BLOCK_FIELDS = (
    ("ALU local full", "ALU_LOCAL_FULL"),
    ("ALU credit stale", "ALU_CREDIT_STALE"),
    ("P0 local full", "P0_LOCAL_FULL"),
    ("P0 credit stale", "P0_CREDIT_STALE"),
    ("P1 local full", "P1_LOCAL_FULL"),
    ("P1 credit stale", "P1_CREDIT_STALE"),
    ("unclassified", "UNCLASSIFIED"),
)
P0_FULL_FIELDS = (
    ("dependency", "DEPENDENCY"),
    ("order", "ORDER"),
    ("resource", "RESOURCE"),
    ("ready/release", "READY_RELEASE"),
    ("no candidate", "NO_CANDIDATE"),
)
ISSUE_SLOT_FIELDS = (
    ("dependency", "DEPENDENCY"),
    ("LSU structural", "LSU_STRUCT"),
    ("LSU serialize", "LSU_SERIALIZE"),
    ("single lane admission", "SINGLE_LANE"),
    ("no execute", "NO_EXECUTE"),
)


def detailed_columns() -> list[tuple[str, str, str]]:
    columns = [
        ("cycles", "PERF_METRIC", "CYCLES"),
        ("insts", "PERF_METRIC", "INSTS"),
        ("ipc", "PERF_METRIC", "IPC"),
        ("capacity_slots", "PERF_SLOT_ACCOUNT", "CAPACITY_SLOTS"),
        ("productive_slots", "PERF_SLOT_ACCOUNT", "PRODUCTIVE_SLOTS"),
        ("lost_slots", "PERF_SLOT_ACCOUNT", "LOST_SLOTS"),
        ("slot_ipc", "PERF_SLOT_ACCOUNT", "SLOT_IPC"),
    ]
    columns.extend(
        (f"control_{field.lower()}", "PERF_CONTROL_DECOUPLE", field)
        for field in CONTROL_FIELDS
    )
    columns.extend(
        (f"local_{field.lower()}", "PERF_LOCAL_CONTROL", field)
        for field in LOCAL_CONTROL_FIELDS
    )
    columns.extend(
        (f"rob_occ_o{index}", "PERF_ROB_OCCUPANCY", f"O{index}")
        for index in range(13)
    )
    columns.extend(
        (f"rs_occ_o{index}", "PERF_RS_OCCUPANCY", f"O{index}")
        for index in range(11)
    )
    for prefix, fields in FLOW_FAMILIES:
        columns.extend((f"flow_{prefix}_{field[-1]}", "PERF_PIPE_FLOW", field) for field in fields)
    columns.extend(
        (f"head_{field.lower()}", "PERF_ROB_HEAD_STATE", field)
        for _, field in HEAD_FIELDS
    )
    columns.extend(
        (f"loss_{field.lower()}", "PERF_BACKEND_LOSS", field)
        for _, field in LOSS_FIELDS
    )
    columns.extend(
        (f"slot_reason_{field.lower()}", "PERF_SLOT_REASON", field)
        for _, field in SLOT_REASON_FIELDS
    )
    columns.extend(
        (f"noif_slot_{field.lower()}", "PERF_NOIF_SLOT_DETAIL", field)
        for _, field in (*NOIF_SLOT_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"issue_slot_{field.lower()}", "PERF_ISSUE_SLOT_DETAIL", field)
        for _, field in (*ISSUE_SLOT_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"bank_block_{field.lower()}", "PERF_BANK_BLOCK_DETAIL", field)
        for _, field in (*BANK_BLOCK_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"p0_full_{field.lower()}", "PERF_P0_FULL_DETAIL", field)
        for _, field in (*P0_FULL_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (name, record, field)
        for name, record, field in (
            ("branches", "PERF_BRANCH", "BRANCHES"),
            ("mispredicts", "PERF_BRANCH", "MISPRED"),
            ("branch_accuracy", "PERF_BRANCH", "ACC"),
            ("wrong_direction_flush", "PERF_FRONTEND", "WRONG_DIR_FLUSH"),
            ("btb_miss_taken", "PERF_FRONTEND", "BTB_MISS_TAKEN"),
        )
    )
    return columns


def write_csv(
    path: Path,
    programs: list[tuple[str, dict[str, dict[str, float]]]],
) -> None:
    columns = detailed_columns()
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["program", *[name for name, _, _ in columns]])
        for program, records in programs:
            writer.writerow(
                [program, *[value(records, record, field) for _, record, field in columns]]
            )


def write_report(
    path: Path,
    programs: list[tuple[str, dict[str, dict[str, float]]]],
) -> None:
    focus = [(name, records) for name, records in programs if name == "coremark"]
    with path.open("w") as stream:
        stream.write("# Decoupled backend performance analysis\n\n")
        stream.write(
            "The measured backend is `ID -> Issue (RS/Select) -> Operand -> EX -> WB`. "
            "`RS_ALLOC` is an event at the Issue input, not an extra pipeline stage. "
            "Dependency readiness is held in each RS entry and is not a centralized architectural-register table.\n\n"
        )
        if not focus:
            stream.write("No CoreMark log containing `PERF_CONTROL_DECOUPLE` was found.\n")
            return

        for program, records in focus:
            cycles = value(records, "PERF_METRIC", "CYCLES")
            insts = value(records, "PERF_METRIC", "INSTS")
            ipc = value(records, "PERF_METRIC", "IPC")
            sample = value(records, "PERF_PIPE_FLOW", "SAMPLE") or cycles
            lost = value(records, "PERF_SLOT_ACCOUNT", "LOST_SLOTS")
            stream.write(
                f"## {program}\n\n{int(cycles)} cycles, {int(insts)} retired instructions, "
                f"IPC {ipc:.4f}, lost execution slots {int(lost)}.\n\n"
            )

            stream.write("### Pipeline flow\n\n")
            stream.write("| Boundary | Histogram | Average uops/cycle | Closure |\n")
            stream.write("|---|---|---:|---|\n")
            for label, fields in FLOW_FAMILIES:
                counts = [value(records, "PERF_PIPE_FLOW", field) for field in fields]
                total = sum(counts)
                average = (
                    sum(index * count for index, count in enumerate(counts)) / sample
                    if sample
                    else 0.0
                )
                histogram = ", ".join(
                    f"{index}:{int(count)}" for index, count in enumerate(counts)
                )
                stream.write(
                    f"| {label} | {histogram} | {average:.4f} | "
                    f"{'PASS' if total == sample else 'FAIL'} |\n"
                )

            rs_total = sum(
                value(records, "PERF_RS_OCCUPANCY", f"O{index}") for index in range(11)
            )
            rob_total = sum(
                value(records, "PERF_ROB_OCCUPANCY", f"O{index}") for index in range(13)
            )
            rs_average = (
                sum(
                    index * value(records, "PERF_RS_OCCUPANCY", f"O{index}")
                    for index in range(11)
                )
                / sample
                if sample
                else 0.0
            )
            rob_average = (
                sum(
                    index * value(records, "PERF_ROB_OCCUPANCY", f"O{index}")
                    for index in range(13)
                )
                / sample
                if sample
                else 0.0
            )
            stream.write(
                f"\nRS occupancy closure: **{'PASS' if rs_total == sample else 'FAIL'}**, "
                f"average {rs_average:.2f}/10. ROB occupancy closure: "
                f"**{'PASS' if rob_total == sample else 'FAIL'}**, average {rob_average:.2f}/12.\n\n"
            )

            stream.write("### Decoupled control\n\n")
            stream.write("| Observation | Count | Denominator | Rate |\n")
            stream.write("|---|---:|---:|---:|\n")
            for field in CONTROL_FIELDS:
                count = value(records, "PERF_CONTROL_DECOUPLE", field)
                entry_metric = field.endswith("ENTRY_CYCLES")
                denominator = sample * 10 if entry_metric else sample
                stream.write(
                    f"| {field.lower().replace('_', ' ')} | {int(count)} | "
                    f"{int(denominator)} | {pct(count, denominator)} |\n"
                )
            operand_miss = value(
                records, "PERF_CONTROL_DECOUPLE", "OPERAND_DEP_MISS"
            )
            stream.write(
                "\n`OPERAND_DEP_MISS` should be zero: a nonzero value means Select admitted a uop "
                "whose value/epoch contract was not satisfied at Operand.\n\n"
            )
            stream.write("### Local wakeup paths\n\n")
            stream.write("| Observation | Count | Sample |\n")
            stream.write("|---|---:|---:|\n")
            for field in LOCAL_CONTROL_FIELDS:
                count = value(records, "PERF_LOCAL_CONTROL", field)
                stream.write(
                    f"| {field.lower().replace('_', ' ')} | {int(count)} | "
                    f"{pct(count, sample)} |\n"
                )
            stream.write(
                "\n`DTCM_DUE_SELECT` and `RESIDENT_DUE_SELECT` count consumers "
                "that entered Select on a local narrow-token path.\n\n"
            )

            expected_loss = value(records, "PERF_BACKEND_LOSS", "EXPECTED")
            accounted_loss = sum(
                value(records, "PERF_BACKEND_LOSS", field) for _, field in LOSS_FIELDS
            )
            stream.write("### Lost slots\n\n")
            stream.write(
                f"Closure: **{'PASS' if accounted_loss == expected_loss else 'FAIL'}**, "
                f"accounted {int(accounted_loss)}, expected {int(expected_loss)}.\n\n"
            )
            stream.write("| Cause | Slots | Lost slots |\n|---|---:|---:|\n")
            for label, field in sorted(
                LOSS_FIELDS,
                key=lambda item: value(records, "PERF_BACKEND_LOSS", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_BACKEND_LOSS", field)
                stream.write(f"| {label} | {int(count)} | {pct(count, expected_loss)} |\n")

            slot_expected = value(records, "PERF_SLOT_REASON", "EXPECTED")
            slot_accounted = value(records, "PERF_SLOT_REASON", "ACCOUNTED")
            stream.write("\n### Complete execution-slot reason partition\n\n")
            stream.write(
                f"Closure: **{'PASS' if slot_accounted == slot_expected else 'FAIL'}**, "
                f"accounted {int(slot_accounted)}, expected {int(slot_expected)} "
                "(two capacity slots per sampled cycle).\n\n"
            )
            stream.write("| Cause | Slots | Capacity share |\n|---|---:|---:|\n")
            for label, field in sorted(
                SLOT_REASON_FIELDS,
                key=lambda item: value(records, "PERF_SLOT_REASON", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_SLOT_REASON", field)
                stream.write(
                    f"| {label} | {int(count)} | {pct(count, slot_expected)} |\n"
                )
            noif_expected = value(records, "PERF_NOIF_SLOT_DETAIL", "EXPECTED")
            noif_accounted = value(records, "PERF_NOIF_SLOT_DETAIL", "ACCOUNTED")
            stream.write(
                f"\nNO_IF_VALID detail closure: **{'PASS' if noif_accounted == noif_expected else 'FAIL'}**, "
                f"accounted {int(noif_accounted)}, expected {int(noif_expected)}.\n"
            )
            issue_expected = value(records, "PERF_ISSUE_SLOT_DETAIL", "EXPECTED")
            issue_accounted = value(records, "PERF_ISSUE_SLOT_DETAIL", "ACCOUNTED")
            stream.write(
                f"ISSUE detail closure: **{'PASS' if issue_accounted == issue_expected else 'FAIL'}**, "
                f"accounted {int(issue_accounted)}, expected {int(issue_expected)}.\n"
            )
            bank_expected = value(records, "PERF_BANK_BLOCK_DETAIL", "EXPECTED")
            bank_accounted = value(records, "PERF_BANK_BLOCK_DETAIL", "ACCOUNTED")
            stream.write(
                f"RS bank detail closure: **{'PASS' if bank_accounted == bank_expected else 'FAIL'}**, "
                f"accounted {int(bank_accounted)}, expected {int(bank_expected)}.\n"
            )
            stream.write("| RS bank cause | Slots | Bank-block share |\n|---|---:|---:|\n")
            for label, field in sorted(
                BANK_BLOCK_FIELDS,
                key=lambda item: value(records, "PERF_BANK_BLOCK_DETAIL", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_BANK_BLOCK_DETAIL", field)
                stream.write(
                    f"| {label} | {int(count)} | {pct(count, bank_expected)} |\n"
                )
            p0_expected = value(records, "PERF_P0_FULL_DETAIL", "EXPECTED")
            p0_accounted = value(records, "PERF_P0_FULL_DETAIL", "ACCOUNTED")
            stream.write(
                f"\nP0-full detail closure: **{'PASS' if p0_accounted == p0_expected else 'FAIL'}**, "
                f"accounted {int(p0_accounted)}, expected {int(p0_expected)}.\n"
            )
            stream.write("| P0-full cause | Slots | P0-full share |\n|---|---:|---:|\n")
            for label, field in sorted(
                P0_FULL_FIELDS,
                key=lambda item: value(records, "PERF_P0_FULL_DETAIL", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_P0_FULL_DETAIL", field)
                stream.write(
                    f"| {label} | {int(count)} | {pct(count, p0_expected)} |\n"
                )

            head_total = sum(
                value(records, "PERF_ROB_HEAD_STATE", field) for _, field in HEAD_FIELDS
            )
            stream.write(
                f"\n### ROB head\n\nClosure: **{'PASS' if head_total == sample else 'FAIL'}**.\n\n"
            )
            stream.write("| State | Cycles | Sample |\n|---|---:|---:|\n")
            for label, field in sorted(
                HEAD_FIELDS,
                key=lambda item: value(records, "PERF_ROB_HEAD_STATE", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_ROB_HEAD_STATE", field)
                stream.write(f"| {label} | {int(count)} | {pct(count, sample)} |\n")

            branches = value(records, "PERF_BRANCH", "BRANCHES")
            mispredicts = value(records, "PERF_BRANCH", "MISPRED")
            stream.write(
                f"\nBranch prediction: {int(branches)} resolutions, {int(mispredicts)} "
                f"mispredicts, accuracy {pct(branches - mispredicts, branches)}.\n"
            )
            if operand_miss:
                stream.write(
                    "\nPriority finding: fix the Select-to-Operand readiness contract before "
                    "tuning RS depth or front-end prediction.\n"
                )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path("build/sim/hw"))
    parser.add_argument("out_dir", nargs="?", type=Path, default=Path("build/PPA"))
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    programs: list[tuple[str, dict[str, dict[str, float]]]] = []
    for log in selected_logs(args.root):
        records = parse_log(log)
        if "PERF_CONTROL_DECOUPLE" in records:
            programs.append((str(log.relative_to(args.root).parent), records))

    write_csv(args.out_dir / "perf_bubble_detail.csv", programs)
    write_report(args.out_dir / "perf_bubble_analysis.md", programs)


if __name__ == "__main__":
    main()
