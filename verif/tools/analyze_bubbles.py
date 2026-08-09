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
WAKEUP_FIELDS = (
    "COMPLETION_ENTRIES",
    "ALLOC_ENTRIES",
    "SELECT_ENTRIES",
    "DTCM_LAUNCH",
    "DTCM_RESULT",
    "MDU_RESULT",
    "REPLAY",
    "P0_COMPLETION_CYCLES",
)
BANK_STATE_FIELDS = (
    "ALU_DEP", "P0_DEP", "P1_DEP", "ALU_ORDER", "P0_ORDER", "P1_ORDER",
    "ALU_RESOURCE", "P0_RESOURCE", "P1_RESOURCE", "ALU_READY", "P0_READY",
    "P1_READY", "ALU_CANDIDATE", "P0_CANDIDATE", "P1_CANDIDATE",
    "ALU_SELECTED", "P0_SELECTED", "P1_SELECTED",
)
COUPLING_PAIR_FIELDS = (
    "BANK_DEP", "BANK_ROB", "BANK_RESOURCE", "BANK_SELECT", "BANK_OPERAND",
    "ROB_DEP", "ROB_RESOURCE", "ROB_SELECT", "ROB_OPERAND", "DEP_RESOURCE",
    "DEP_SELECT", "DEP_OPERAND", "RESOURCE_SELECT", "SELECT_OPERAND",
    "BANK_DEP_SELECT", "BANK_ROB_SELECT", "DEP_SELECT_OPERAND",
)
LATENCY_FIELDS = ("B0_3", "B4_7", "B8_15", "B16_31", "B32_63", "B64P")
SELECT_QUEUE_FIELDS = (
    "HOL_SINGLE_HEAD_PAIR_SKID_CYCLES", "HOL_LOST_SLOTS", "PAIR_PUSH_CYCLES",
    "PAIR_HEAD_ISSUE_CYCLES", "PAIR_PUSH_BEHIND_SINGLE_HEAD_CYCLES",
    "PAIR_PUSH_BEHIND_SINGLE_HEAD_SLOTS", "STATE_EMPTY", "STATE_HEAD_SINGLE",
    "STATE_HEAD_PAIR", "STATE_SINGLE_SINGLE", "STATE_SINGLE_PAIR",
    "STATE_PAIR_SINGLE", "STATE_PAIR_PAIR",
)
SELECT_REFILL_BOUNDARY_FIELDS = (
    "HEAD_EMPTY_PUSH_CYCLES", "HEAD_EMPTY_PUSH_SLOTS",
    "HEAD_EMPTY_PAIR_SLOTS", "HEAD_EMPTY_SINGLE_SLOTS", "PUSHED_UOPS",
)
SELECT_REFILL_LIFECYCLES = (
    ("eligible in prior cycle", "ELIGIBLE"),
    ("dependency released", "DEPENDENCY"),
    ("order released", "ORDER"),
    ("resource released", "RESOURCE"),
    ("new/replaced RS entry", "NEW"),
    ("other", "OTHER"),
)
SELECT_REFILL_PRIOR_BITS = ("DEP", "ORDER", "RESOURCE")
SELECT_REFILL_PENDING_BITS = ("ALU", "LOAD", "MDU", "OTHER")
EX_VALID_HOLD_FIELDS = ("LANE0", "LANE1", "TOTAL")
SELECT_OPPORTUNITY_FIELDS = (
    "RAW_W0", "RAW_W1", "RAW_W2", "ACTUAL_W0", "ACTUAL_W1", "ACTUAL_W2",
    "RAW_ALU_ENTRIES", "RAW_P0_CYCLES", "RAW_P1_CYCLES",
    "DROP_ALU_ENTRIES", "DROP_P0_ENTRIES", "DROP_P1_ENTRIES",
    "WIDTH_GAP_SLOTS", "PAIR_CAPABLE_SINGLE_CYCLES",
    "PAIR_CAPABLE_SINGLE_LOST_SLOTS", "GAP_RECOVERY_CYCLES",
    "GAP_NO_PUSH_CYCLES", "GAP_POLICY_CYCLES",
)
SELECT_WIDTH_MATRIX_FIELDS = ("M00", "M01", "M02", "M10", "M11", "M12", "M20", "M21", "M22")
LOSS_COUPLING_FIELDS = ("CYCLES", "SLOTS", "MASK_BITS")
LOSS_COUPLING_BITS = (
    "BANK", "ROB_CAP", "DEP", "ORDER", "RESOURCE", "SELECT",
    "OPERAND", "RECOVERY", "FRONTEND", "ROB_HEAD", "LSU", "FU",
)
DEP_BLOCKER_BITS = ("ALU", "LOAD", "MDU", "OTHER", "UNTRACKED")
RS_DEPTH = 12
ROB_DEPTH = 12
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
# A non-overlapping expansion of PERF_SLOT_REASON.  The RS-bank parent is
# replaced by its bank leaves, and the front-end/issue parents by their
# existing slot-weighted details.  This is the report that must close to
# exactly two capacity slots per sampled cycle.
SLOT_LEAF_FIELDS = (
    ("executed lane 0", "EXECUTED_SLOT0"),
    ("executed lane 1", "EXECUTED_SLOT1"),
    ("flush", "FLUSH"),
    ("multicycle hold", "MUL_HOLD"),
    ("multi-cause control", "MULTI_CAUSE"),
    ("dependency", "DEPENDENCY"),
    ("LSU structural", "LSU_STRUCT"),
    ("producer full", "PRODUCER_FULL"),
    ("writeback backpressure", "WB"),
    ("CLINT/trap", "CLINT"),
    ("LSU serialize", "LSU_SERIALIZE"),
    ("control redirect", "NOIF_CONTROL_REDIRECT"),
    ("prediction redirect", "NOIF_PREDICT_REDIRECT"),
    ("FENCE refill", "NOIF_FENCE_REFILL"),
    ("memory response", "NOIF_MEM_RESPONSE"),
    ("fetch launch", "NOIF_FETCH_LAUNCH"),
    ("pending redirect", "NOIF_PENDING_REDIRECT"),
    ("IF/ID empty other", "NOIF_OTHER"),
    ("issue single lane", "ISSUE_SINGLE_LANE"),
    ("issue no execute", "ISSUE_NO_EXECUTE"),
    ("ROB block", "ROB_BLOCK"),
    ("recovery resync", "RECOVERY_RESYNC"),
    ("ALU local full", "ALU_LOCAL_FULL"),
    ("ALU credit stale", "ALU_CREDIT_STALE"),
    ("P0 local full", "P0_LOCAL_FULL"),
    ("P0 credit stale", "P0_CREDIT_STALE"),
    ("P1 local full", "P1_LOCAL_FULL"),
    ("P1 credit stale", "P1_CREDIT_STALE"),
    ("RS bank unclassified", "RS_BANK_UNCLASSIFIED"),
    ("RS pair limit", "RS_PAIR_LIMIT"),
    ("Select refill", "SELECT_REFILL"),
    ("RS dependency", "RS_DEPENDENCY"),
    ("RS order", "RS_ORDER"),
    ("RS resource", "RS_RESOURCE"),
    ("RS no candidate", "RS_NO_CANDIDATE"),
    ("RS empty", "RS_EMPTY"),
    ("decode block", "DECODE_BLOCK"),
    ("other unclassified", "OTHER_UNCLASSIFIED"),
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
P0_PIPELINE_FIELDS = (
    ("selectable/releasing", "SELECTABLE"),
    ("LSU credit/reservation blocked", "CREDIT_BLOCKED"),
    ("memory order blocked", "ORDER_BLOCKED"),
    ("all entries dependency blocked", "DEPENDENCY_BLOCKED"),
)
SINGLE_BUNDLE_FIELDS = (
    ("P0-only bundle", "P0_ONLY"),
    ("P1-only bundle", "P1_ONLY"),
    ("ALU-only bundle", "ALU_ONLY"),
    ("serial bundle", "SERIAL"),
    ("other singleton", "OTHER"),
)
SELECT_REFILL_FIELDS = (
    ("pair refill", "PAIR"),
    ("P0 singleton refill", "P0_SINGLE"),
    ("P1 singleton refill", "P1_SINGLE"),
    ("ALU singleton refill", "ALU_SINGLE"),
    ("serial refill", "SERIAL"),
    ("other refill", "OTHER"),
)
RS_DEPENDENCY_DETAIL_FIELDS = (
    ("source 0", "SRC0"),
    ("source 1", "SRC1"),
    ("both sources", "BOTH_SRC"),
    ("completion wakeup", "COMPLETION_WAKE"),
    ("allocation wakeup", "ALLOC_WAKE"),
    ("load entry", "LOAD"),
    ("multiply/divide entry", "MUL"),
    ("branch entry", "BRANCH"),
    ("other dependency", "OTHER"),
)
SINGLE_BUNDLE_OP_FIELDS = (
    ("ALU", "ALU"),
    ("load", "LOAD"),
    ("store", "STORE"),
    ("multiply/divide", "MUL"),
    ("CSR/system", "CSR_SYS"),
    ("other", "OTHER"),
)
SELECT_REFILL_SHAPE_FIELDS = (
    ("P0 + P1 pair", "P0_P1"),
    ("P0 + ALU pair", "P0_ALU"),
    ("P1 + ALU pair", "P1_ALU"),
    ("ALU + ALU pair", "ALU_ALU"),
    ("P0 singleton", "SINGLE_P0"),
    ("P1 singleton", "SINGLE_P1"),
    ("ALU singleton", "SINGLE_ALU"),
    ("serial singleton", "SERIAL"),
    ("other shape", "OTHER"),
)
RS_DEPENDENCY_WAKE_FIELDS = (
    ("both sources wake", "BOTH"),
    ("completion/allocation mixed", "MIXED"),
    ("source 0 completion", "SRC0_COMPLETION"),
    ("source 1 completion", "SRC1_COMPLETION"),
    ("source 0 allocation", "SRC0_ALLOC"),
    ("source 1 allocation", "SRC1_ALLOC"),
    ("no visible wakeup", "NONE"),
)
RS_DEPENDENCY_OP_FIELDS = (
    ("ALU", "ALU"),
    ("load", "LOAD"),
    ("store", "STORE"),
    ("multiply/divide", "MUL"),
    ("branch", "BRANCH"),
    ("other", "OTHER"),
)
ISSUE_SLOT_FIELDS = (
    ("dependency", "DEPENDENCY"),
    ("LSU structural", "LSU_STRUCT"),
    ("LSU serialize", "LSU_SERIALIZE"),
    ("single lane admission", "SINGLE_LANE"),
    ("no execute", "NO_EXECUTE"),
)
EX_SLOT_FIELDS = (
    ("accepted lane 0", "ACCEPT0"),
    ("accepted lane 1", "ACCEPT1"),
    ("branch drop lane 0", "BRANCH_DROP0"),
    ("branch drop lane 1", "BRANCH_DROP1"),
    ("multicycle drop lane 0", "MUL_DROP0"),
    ("multicycle drop lane 1", "MUL_DROP1"),
    ("pipeline empty lane 0", "PIPE_EMPTY0"),
    ("pipeline empty lane 1", "PIPE_EMPTY1"),
)
EX_EMPTY_FIELDS = (
    ("reset/pipeline fill", "RESET_PIPE"),
    ("recovery", "RECOVERY"),
    ("FENCE", "FENCE"),
    ("lane-B-only packet", "B_ONLY"),
    ("single-head packet", "SINGLE_HEAD"),
    ("Select refill", "SELECT_REFILL"),
    ("RS dependency", "RS_DEPENDENCY"),
    ("RS order", "RS_ORDER"),
    ("RS resource", "RS_RESOURCE"),
    ("RS no candidate", "RS_NO_CANDIDATE"),
    ("RS empty", "RS_EMPTY"),
    ("front-end empty", "FRONTEND_EMPTY"),
    ("launch snapshot mismatch", "LAUNCH_MISMATCH"),
    ("other", "OTHER"),
    ("unmapped source kind", "UNMAPPED"),
    ("unaccounted snapshot residual", "UNACCOUNTED_SNAPSHOT"),
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
        (f"wakeup_{field.lower()}", "PERF_WAKEUP", field)
        for field in WAKEUP_FIELDS
    )
    columns.extend(
        (f"bank_state_{field.lower()}", "PERF_RS_BANK_STATE", field)
        for field in BANK_STATE_FIELDS
    )
    columns.extend(
        (f"coupling_pair_{field.lower()}", "PERF_COUPLING_PAIR", field)
        for field in COUPLING_PAIR_FIELDS
    )
    for prefix, record in (
        ("latency_alloc_select", "PERF_LATENCY_ALLOC_SELECT"),
        ("latency_select_operand", "PERF_LATENCY_SELECT_OPERAND"),
        ("latency_operand_ex", "PERF_LATENCY_OPERAND_EX"),
        ("latency_alloc_complete", "PERF_LATENCY_ALLOC_COMPLETE"),
        ("latency_alloc_retire", "PERF_LATENCY_ALLOC_RETIRE"),
    ):
        columns.extend((f"{prefix}_{field.lower()}", record, field) for field in LATENCY_FIELDS)
    columns.extend(
        (f"select_queue_{field.lower()}", "PERF_SELECT_QUEUE", field)
        for field in SELECT_QUEUE_FIELDS
    )
    columns.extend(
        (f"select_refill_boundary_{field.lower()}", "PERF_SELECT_REFILL_BOUNDARY", field)
        for field in SELECT_REFILL_BOUNDARY_FIELDS
    )
    columns.extend(
        (f"select_refill_lifecycle_{lifecycle.lower()}_{data.lower()}",
         "PERF_SELECT_REFILL_LIFECYCLE_DATA", f"{lifecycle}_{data}")
        for _, lifecycle in SELECT_REFILL_LIFECYCLES
        for data in ("PENDING", "STORED")
    )
    columns.extend(
        (f"select_refill_lifecycle_{field.lower()}",
         "PERF_SELECT_REFILL_LIFECYCLE_DATA", field)
        for field in ("ACCOUNTED", "EXPECTED")
    )
    columns.extend(
        (f"select_refill_prior_m{mask}", "PERF_SELECT_REFILL_PRIOR_MASK", f"M{mask}")
        for mask in range(8)
    )
    columns.extend(
        (f"select_refill_prior_{field.lower()}",
         "PERF_SELECT_REFILL_PRIOR_MASK", field)
        for field in ("NEW", "OTHER", "ACCOUNTED", "EXPECTED")
    )
    columns.extend(
        (f"select_refill_pending_m{mask}",
         "PERF_SELECT_REFILL_PENDING_MASK", f"M{mask}")
        for mask in range(16)
    )
    columns.extend(
        (f"select_refill_pending_{field.lower()}",
         "PERF_SELECT_REFILL_PENDING_MASK", field)
        for field in ("ACCOUNTED", "EXPECTED")
    )
    columns.extend(
        (f"ex_valid_hold_{field.lower()}", "PERF_EX_VALID_HOLD", field)
        for field in EX_VALID_HOLD_FIELDS
    )
    columns.extend(
        (f"select_opportunity_{field.lower()}", "PERF_SELECT_OPPORTUNITY", field)
        for field in SELECT_OPPORTUNITY_FIELDS
    )
    columns.extend(
        (f"loss_coupling_{field.lower()}", "PERF_LOSS_COUPLING", field)
        for field in LOSS_COUPLING_FIELDS
    )
    columns.extend(
        (f"select_width_matrix_cycles_{field.lower()}",
         "PERF_SELECT_WIDTH_MATRIX_CYCLES", field)
        for field in SELECT_WIDTH_MATRIX_FIELDS
    )
    columns.extend(
        (f"select_width_matrix_slots_{field.lower()}",
         "PERF_SELECT_WIDTH_MATRIX_SLOTS", field)
        for field in SELECT_WIDTH_MATRIX_FIELDS
    )
    columns.extend(
        (f"rob_occ_o{index}", "PERF_ROB_OCCUPANCY", f"O{index}")
        for index in range(13)
    )
    # RS has twelve physical entries (0..11).  O12 is retained as an
    # explicit overflow/unclassified bucket because the testbench emits it
    # for closure; silently dropping it made the old report claim /10.
    columns.extend(
        (f"rs_occ_o{index}", "PERF_RS_OCCUPANCY", f"O{index}")
        for index in range(RS_DEPTH + 1)
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
        (f"slot_leaf_{field.lower()}", "PERF_SLOT_LEAF", field)
        for _, field in (*SLOT_LEAF_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"ex_slot_{field.lower()}", "PERF_EX_SLOT_STATE", field)
        for _, field in (*EX_SLOT_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"ex_empty_{field.lower()}", "PERF_EX_EMPTY_CAUSE", field)
        for _, field in (*EX_EMPTY_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
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
        (f"p0_pipeline_{field.lower()}", "PERF_P0_FULL_PIPELINE", field)
        for _, field in (*P0_PIPELINE_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"p0_credit_resv_c{credit}_r{reservation}",
         "PERF_P0_CREDIT_RESV_MATRIX", f"C{credit}_R{reservation}")
        for credit in range(3) for reservation in range(3)
    )
    columns.append(
        ("lsu_age_repair_cycles", "PERF_LSU_AGE_REPAIR", "CYCLES")
    )
    columns.extend(
        (f"single_bundle_{field.lower()}", "PERF_SINGLE_BUNDLE_DETAIL", field)
        for _, field in (*SINGLE_BUNDLE_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"select_refill_{field.lower()}", "PERF_SELECT_REFILL_DETAIL", field)
        for _, field in (*SELECT_REFILL_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"rs_dependency_detail_{field.lower()}", "PERF_RS_DEPENDENCY_DETAIL2", field)
        for _, field in (*RS_DEPENDENCY_DETAIL_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"single_bundle_op_{field.lower()}", "PERF_SINGLE_BUNDLE_OP", field)
        for _, field in (*SINGLE_BUNDLE_OP_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"select_refill_shape_{field.lower()}", "PERF_SELECT_REFILL_SHAPE", field)
        for _, field in (*SELECT_REFILL_SHAPE_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"rs_dependency_wake_{field.lower()}", "PERF_RS_DEPENDENCY_WAKE", field)
        for _, field in (*RS_DEPENDENCY_WAKE_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
    )
    columns.extend(
        (f"rs_dependency_op_{field.lower()}", "PERF_RS_DEPENDENCY_OP", field)
        for _, field in (*RS_DEPENDENCY_OP_FIELDS, ("accounted", "ACCOUNTED"), ("expected", "EXPECTED"))
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


def all_columns(
    programs: list[tuple[str, dict[str, dict[str, float]]]],
) -> list[tuple[str, str, str]]:
    """Return the detailed schema plus every field emitted by the RTL TB.

    The hand-curated schema is used for stable, readable columns.  A raw
    fallback is appended for fields from coverage/debug records and sparse
    masks so adding a new PERF line can never silently disappear from CSV.
    """
    columns = detailed_columns()
    known = {(record, field) for _, record, field in columns}
    records = {
        (record, field)
        for _, values in programs
        for record, fields in values.items()
        for field in fields
    }
    for record, field in sorted(records):
        if (record, field) in known:
            continue
        columns.append(
            (f"raw_{record.lower()}_{field.lower()}", record, field)
        )
    return columns


def write_csv(
    path: Path,
    programs: list[tuple[str, dict[str, dict[str, float]]]],
) -> None:
    columns = all_columns(programs)
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["program", *[name for name, _, _ in columns]])
        for program, records in programs:
            writer.writerow(
                [program, *[value(records, record, field) for _, record, field in columns]]
            )


def sparse_mask(records: dict[str, dict[str, float]], record: str) -> dict[int, float]:
    """Decode the M<number>=value form used for sparse coupling masks."""
    return {
        int(key[1:]): raw
        for key, raw in records.get(record, {}).items()
        if key.startswith("M") and key[1:].isdigit()
    }


def loss_coupling_pairs(
    records: dict[str, dict[str, float]],
) -> list[tuple[str, str, float]]:
    """Return pair intersections weighted by lost execution slots.

    The mask rows overlap by design.  Summing pair rows is therefore not a
    loss partition; it answers which architectural controls are asserted on
    the same lost-slot cycles.
    """
    masks = sparse_mask(records, "PERF_LOSS_COUPLING_MASK_SLOTS")
    pairs: list[tuple[str, str, float]] = []
    for left, left_name in enumerate(LOSS_COUPLING_BITS):
        for right in range(left + 1, len(LOSS_COUPLING_BITS)):
            total = sum(
                slots
                for mask, slots in masks.items()
                if (mask & (1 << left)) and (mask & (1 << right))
            )
            if total:
                pairs.append((left_name, LOSS_COUPLING_BITS[right], total))
    return sorted(pairs, key=lambda item: item[2], reverse=True)


def write_report(
    path: Path,
    programs: list[tuple[str, dict[str, dict[str, float]]]],
) -> None:
    # Keep the reference CoreMark run and every optimized profile in the
    # report.  The active performance image is
    # `coremark-opt/O3_app_unroll`, so restricting focus to the legacy
    # `coremark` directory silently turns all detailed causes into zeros.
    focus = [
        (name, records)
        for name, records in programs
        if name == "coremark" or name.startswith("coremark-opt/")
    ]
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
                value(records, "PERF_RS_OCCUPANCY", f"O{index}")
                for index in range(RS_DEPTH + 1)
            )
            rob_total = sum(
                value(records, "PERF_ROB_OCCUPANCY", f"O{index}") for index in range(13)
            )
            rs_average = (
                sum(
                    index * value(records, "PERF_RS_OCCUPANCY", f"O{index}")
                    for index in range(RS_DEPTH + 1)
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
                f"average {rs_average:.2f}/{RS_DEPTH}. ROB occupancy closure: "
                f"**{'PASS' if rob_total == sample else 'FAIL'}**, "
                f"average {rob_average:.2f}/{ROB_DEPTH}.\n\n"
            )

            target_ipc = 1.2
            target_cycles = insts / target_ipc if target_ipc else 0.0
            cycles_to_remove = cycles - target_cycles
            mean_rob_residence = rob_average / ipc if ipc else 0.0
            target_rob_occupancy = target_ipc * mean_rob_residence
            practical_rob_depth = int(target_rob_occupancy / 0.8 + 0.999999)
            score = value(records, "PERF_BENCHMARK", "COREMARK_SCORE")
            score456_cycles = cycles * score / 456.0 if score else 0.0
            score456_ipc = insts / score456_cycles if score456_cycles else 0.0
            projected_score = score * cycles / target_cycles if target_cycles else 0.0
            stream.write("### Throughput target budget\n\n")
            stream.write("| Target/evidence | Value | Architectural implication |\n")
            stream.write("|---|---:|---|\n")
            if score:
                stream.write(
                    f"| Current CoreMark score | {score:.6f} | Current measured baseline. |\n"
                )
                stream.write(
                    f"| Score 456 equivalent | {score456_cycles:.0f} cycles / IPC {score456_ipc:.4f} | "
                    f"Requires removing about {cycles - score456_cycles:.0f} cycles. |\n"
                )
            stream.write(
                f"| IPC 1.2 equivalent | {target_cycles:.0f} cycles"
                + (f" / projected score {projected_score:.2f}" if score else "")
                + f" | Requires removing about {cycles_to_remove:.0f} cycles ({pct(cycles_to_remove, cycles)}). |\n"
            )
            stream.write(
                f"| Measured mean ROB residence (Little's law) | {mean_rob_residence:.2f} cycles | "
                "Derived from average occupancy / retirement IPC. |\n"
            )
            stream.write(
                f"| Occupancy needed at IPC 1.2 with current residence | {target_rob_occupancy:.2f} entries | "
                f"Exceeds the {ROB_DEPTH}-entry ROB before any headroom. |\n"
            )
            stream.write(
                f"| ROB depth for <=80% average occupancy | {practical_rob_depth} entries | "
                "Either use this capacity class or reduce mean residence to <=8 cycles. |\n\n"
            )

            stream.write("### Decoupled control\n\n")
            stream.write("| Observation | Count | Denominator | Rate |\n")
            stream.write("|---|---:|---:|---:|\n")
            for field in CONTROL_FIELDS:
                count = value(records, "PERF_CONTROL_DECOUPLE", field)
                entry_metric = field.endswith("ENTRY_CYCLES")
                denominator = sample * RS_DEPTH if entry_metric else sample
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
            stream.write("### Wakeup source accounting\n\n")
            stream.write(
                "These counts are sampled from the RS entry completion-tag comparators and "
                "registered local token inputs. `COMPLETION_ENTRIES` is entry-weighted, so "
                "it can exceed the number of cycles.\n\n"
            )
            stream.write("| Source | Count | Sample rate |\n|---|---:|---:|\n")
            for field in WAKEUP_FIELDS:
                count = value(records, "PERF_WAKEUP", field)
                stream.write(
                    f"| {field.lower().replace('_', ' ')} | {int(count)} | "
                    f"{pct(count, sample)} |\n"
                )

            stream.write("\n### Coupled backend state (orthogonal)\n\n")
            stream.write(
                "The following values are not a partition. A cycle/entry is allowed to "
                "contribute to multiple columns, which is the required view for deciding "
                "whether a bank, ROB, dependency, or Select policy change removes the same stall.\n\n"
            )
            stream.write("| RS bank state | Entry-cycles |\n|---|---:|\n")
            for field in BANK_STATE_FIELDS:
                count = value(records, "PERF_RS_BANK_STATE", field)
                stream.write(f"| {field.lower().replace('_', ' ')} | {int(count)} |\n")
            stream.write("\n| Coupled predicates | Cycles |\n|---|---:|\n")
            for field in COUPLING_PAIR_FIELDS:
                count = value(records, "PERF_COUPLING_PAIR", field)
                stream.write(f"| {field.lower().replace('_', ' + ')} | {int(count)} |\n")
            stream.write(
                "\nA high `BANK_DEP_SELECT` count means increasing total RS entries alone will not "
                "help: the bank mapping and Select width must be changed together. A high "
                "`SELECT_OPERAND` count points at the extra Select/Operand boundary and its "
                "pair metadata contract.\n\n"
            )
            stream.write("### Producer lifetime latency\n\n")
            stream.write("| Lifetime | 0-3 | 4-7 | 8-15 | 16-31 | 32-63 | 64+ |\n|---|---:|---:|---:|---:|---:|---:|\n")
            for label, record in (
                ("allocate -> select", "PERF_LATENCY_ALLOC_SELECT"),
                ("select -> Operand", "PERF_LATENCY_SELECT_OPERAND"),
                ("Operand -> EX", "PERF_LATENCY_OPERAND_EX"),
                ("allocate -> completion", "PERF_LATENCY_ALLOC_COMPLETE"),
                ("allocate -> retire", "PERF_LATENCY_ALLOC_RETIRE"),
            ):
                values = [int(value(records, record, field)) for field in LATENCY_FIELDS]
                stream.write(f"| {label} | " + " | ".join(str(item) for item in values) + " |\n")
            stream.write(
                "\nThe lifetime table separates window/select delay from the one-cycle Operand "
                "boundary and from FU/ROB retirement latency; it must be used before choosing "
                "between flexible banking, wakeup changes, and retirement decoupling.\n\n"
            )
            stream.write("### Select/Operand bundle state\n\n")
            stream.write(
                "`HOL_SINGLE_HEAD_PAIR_SKID_CYCLES` is the exact case where the current "
                "two-cell bundle queue has a single uop at the head and a pair waiting in "
                "the skid cell. It is a direct measure of lost pairing opportunity, not a "
                "generic Select bubble.\n\n"
            )
            stream.write("| Queue state | Cycles |\n|---|---:|\n")
            for label, field in (
                ("empty", "STATE_EMPTY"),
                ("head single", "STATE_HEAD_SINGLE"),
                ("head pair", "STATE_HEAD_PAIR"),
                ("pair pushed behind singleton head", "PAIR_PUSH_BEHIND_SINGLE_HEAD_CYCLES"),
                ("single head + single skid", "STATE_SINGLE_SINGLE"),
                ("single head + pair skid", "STATE_SINGLE_PAIR"),
                ("pair head + single skid", "STATE_PAIR_SINGLE"),
                ("pair head + pair skid", "STATE_PAIR_PAIR"),
            ):
                stream.write(
                    f"| {label} | {int(value(records, 'PERF_SELECT_QUEUE', field))} |\n"
                )
            hol = value(records, "PERF_SELECT_QUEUE", "HOL_SINGLE_HEAD_PAIR_SKID_CYCLES")
            hol_lost = value(records, "PERF_SELECT_QUEUE", "HOL_LOST_SLOTS")
            pair_behind = value(
                records, "PERF_SELECT_QUEUE", "PAIR_PUSH_BEHIND_SINGLE_HEAD_SLOTS"
            )
            stream.write(
                f"\nBundle HOL: **{int(hol)} cycles**, **{int(hol_lost)} lost slots**; "
                f"pair-push-behind-single-head edges account for **{int(pair_behind)} "
                "lost slots**. A persistent skid state and an edge-level pair loss are "
                "different phenomena; only the latter is visible when the head is consumed "
                "on the same edge.\n\n"
            )
            refill_boundary = records.get("PERF_SELECT_REFILL_BOUNDARY", {})
            refill_slots = refill_boundary.get("HEAD_EMPTY_PUSH_SLOTS", 0)
            refill_uops = refill_boundary.get("PUSHED_UOPS", 0)
            refill_lifecycle = records.get(
                "PERF_SELECT_REFILL_LIFECYCLE_DATA", {}
            )
            refill_stored = sum(
                refill_lifecycle.get(f"{field}_STORED", 0)
                for _, field in SELECT_REFILL_LIFECYCLES
            )
            refill_pending = sum(
                refill_lifecycle.get(f"{field}_PENDING", 0)
                for _, field in SELECT_REFILL_LIFECYCLES
            )
            stream.write(
                "Select refill boundary: **%d cycles / %d lost slots**, split as "
                "**%d pair** and **%d singleton** push-slots. These are boundary events, "
                "not an equal number of recoverable cycles; load/completion data can "
                "arrive during the registered transit.\n\n"
                % (
                    int(refill_boundary.get("HEAD_EMPTY_PUSH_CYCLES", 0)),
                    int(refill_slots),
                    int(refill_boundary.get("HEAD_EMPTY_PAIR_SLOTS", 0)),
                    int(refill_boundary.get("HEAD_EMPTY_SINGLE_SLOTS", 0)),
                )
            )
            lifecycle_accounted = refill_lifecycle.get("ACCOUNTED", 0)
            lifecycle_expected = refill_lifecycle.get("EXPECTED", 0)
            stream.write(
                "Refill lifecycle/data closure: "
                f"**{'PASS' if lifecycle_accounted == lifecycle_expected == refill_uops else 'FAIL'}**, "
                f"accounted {int(lifecycle_accounted)}, expected {int(lifecycle_expected)}, "
                f"boundary uops {int(refill_uops)}. Registered-data uops are "
                f"**{int(refill_stored)} ({pct(refill_stored, refill_uops)})**; "
                f"completion-aligned/pending uops are **{int(refill_pending)} "
                f"({pct(refill_pending, refill_uops)})**. Only the registered-data "
                "subset directly supports a bank-local operand-ready/preselected slot; "
                "the pending subset requires producer-lifetime or alignment work.\n\n"
            )
            stream.write("| Prior-cycle lifecycle | Pending data | Registered data | Total |\n")
            stream.write("|---|---:|---:|---:|\n")
            for label, field in SELECT_REFILL_LIFECYCLES:
                pending = refill_lifecycle.get(f"{field}_PENDING", 0)
                stored = refill_lifecycle.get(f"{field}_STORED", 0)
                stream.write(
                    f"| {label} | {int(pending)} | {int(stored)} | "
                    f"{int(pending + stored)} |\n"
                )

            prior = records.get("PERF_SELECT_REFILL_PRIOR_MASK", {})
            prior_accounted = prior.get("ACCOUNTED", 0)
            prior_expected = prior.get("EXPECTED", 0)
            stream.write(
                "\nExact prior blocker-mask closure: "
                f"**{'PASS' if prior_accounted == prior_expected == refill_uops else 'FAIL'}**, "
                f"accounted {int(prior_accounted)}, expected {int(prior_expected)}. "
                "Unlike the lifecycle projection, this table preserves simultaneous "
                "dependency, order, and resource blockers.\n\n"
            )
            stream.write("| Prior blocker mask | Refill uops | Share |\n|---|---:|---:|\n")
            prior_rows = [(mask, prior.get(f"M{mask}", 0)) for mask in range(8)]
            prior_rows.extend(((8, prior.get("NEW", 0)), (9, prior.get("OTHER", 0))))
            for mask, count in sorted(prior_rows, key=lambda item: item[1], reverse=True):
                if mask < 8:
                    label = "+".join(
                        name for bit, name in enumerate(SELECT_REFILL_PRIOR_BITS)
                        if mask & (1 << bit)
                    ) or "eligible"
                else:
                    label = "new/replaced" if mask == 8 else "other"
                stream.write(f"| {label} | {int(count)} | {pct(count, refill_uops)} |\n")

            pending_masks = records.get("PERF_SELECT_REFILL_PENDING_MASK", {})
            pending_accounted = pending_masks.get("ACCOUNTED", 0)
            pending_expected = pending_masks.get("EXPECTED", 0)
            stream.write(
                "\nPending-producer mask closure: "
                f"**{'PASS' if pending_accounted == pending_expected == refill_uops else 'FAIL'}**, "
                f"accounted {int(pending_accounted)}, expected {int(pending_expected)}.\n\n"
            )
            stream.write("| Data still absent from registered storage | Refill uops | Share |\n")
            stream.write("|---|---:|---:|\n")
            for mask, count in sorted(
                ((mask, pending_masks.get(f"M{mask}", 0)) for mask in range(16)),
                key=lambda item: item[1], reverse=True,
            ):
                label = "+".join(
                    name for bit, name in enumerate(SELECT_REFILL_PENDING_BITS)
                    if mask & (1 << bit)
                ) or "none (all operands registered)"
                stream.write(f"| {label} | {int(count)} | {pct(count, refill_uops)} |\n")

            stream.write("### Loss-weighted coupling and Select opportunity\n\n")
            stream.write(
                "`PERF_COUPLING_MASK` above is a state histogram and is deliberately not "
                "a loss partition. The following mask is sampled only when an EX capacity "
                "slot is empty and is weighted by the number of lost slots. A row may match "
                "several architectural controls; pair totals below are intersections, not "
                "additive causes. Bits are BANK, ROB_CAP, DEP, ORDER, RESOURCE, SELECT, "
                "OPERAND, RECOVERY, FRONTEND, ROB_HEAD, LSU, FU.\n\n"
            )
            loss_cycles = value(records, "PERF_LOSS_COUPLING", "CYCLES")
            loss_slots = value(records, "PERF_LOSS_COUPLING", "SLOTS")
            mask_slots = sparse_mask(records, "PERF_LOSS_COUPLING_MASK_SLOTS")
            mask_cycles = sparse_mask(records, "PERF_LOSS_COUPLING_MASK_CYCLES")
            mask_sum = sum(mask_slots.values())
            stream.write(
                f"Loss-mask closure: **{'PASS' if mask_sum == loss_slots else 'FAIL'}**, "
                f"{int(loss_cycles)} loss cycles, {int(loss_slots)} loss slots, "
                f"weighted rows sum {int(mask_sum)}.\n\n"
            )
            stream.write("| Loss mask | Active controls | Cycles | Lost slots |\n|---:|---|---:|---:|\n")
            for mask, slots in sorted(mask_slots.items(), key=lambda item: item[1], reverse=True)[:16]:
                active = "+".join(
                    name for bit, name in enumerate(LOSS_COUPLING_BITS) if mask & (1 << bit)
                ) or "none"
                stream.write(
                    f"| 0x{mask:03x} | {active} | {int(mask_cycles.get(mask, 0))} | {int(slots)} |\n"
                )
            stream.write("\n| Coupled controls on lost slots | Lost slots | Share of loss mask |\n|---|---:|---:|\n")
            for left, right, slots in loss_coupling_pairs(records)[:16]:
                stream.write(f"| {left} + {right} | {int(slots)} | {pct(slots, loss_slots)} |\n")

            stream.write("\n| Control involvement | Lost slots with bit | Exclusive slots | Coupled slots |\n")
            stream.write("|---|---:|---:|---:|\n")
            for bit, name in enumerate(LOSS_COUPLING_BITS):
                involved = sum(
                    slots for mask, slots in mask_slots.items() if mask & (1 << bit)
                )
                exclusive = mask_slots.get(1 << bit, 0)
                stream.write(
                    f"| {name} | {int(involved)} | {int(exclusive)} | "
                    f"{int(involved - exclusive)} |\n"
                )

            opportunity = records.get("PERF_SELECT_OPPORTUNITY", {})
            stream.write("\n#### Select opportunity\n\n")
            stream.write(
                "`RAW_W*` is the width available from the three bank candidate vectors "
                "after resource/dependency predicates, while `ACTUAL_W*` is the width that "
                "crossed the registered Select/Operand boundary. This is a policy/bank "
                "opportunity metric, not a claim that every candidate is independent.\n\n"
            )
            stream.write("| Observation | Value |\n|---|---:|\n")
            for label, field in (
                ("raw width 0/1/2 cycles", "RAW_W0"),
                ("raw width 1 cycles", "RAW_W1"),
                ("raw width 2 cycles", "RAW_W2"),
                ("actual width 0 cycles", "ACTUAL_W0"),
                ("actual width 1 cycles", "ACTUAL_W1"),
                ("actual width 2 cycles", "ACTUAL_W2"),
                ("raw ALU candidate entries", "RAW_ALU_ENTRIES"),
                ("raw P0 candidate cycles", "RAW_P0_CYCLES"),
                ("raw P1 candidate cycles", "RAW_P1_CYCLES"),
                ("ALU candidates not selected", "DROP_ALU_ENTRIES"),
                ("P0 candidates not selected", "DROP_P0_ENTRIES"),
                ("P1 candidates not selected", "DROP_P1_ENTRIES"),
                ("Select width gap slots", "WIDTH_GAP_SLOTS"),
                ("pair-capable but singleton cycles", "PAIR_CAPABLE_SINGLE_CYCLES"),
                ("pair-capable singleton lost slots", "PAIR_CAPABLE_SINGLE_LOST_SLOTS"),
                ("gap during recovery", "GAP_RECOVERY_CYCLES"),
                ("gap with no Select push", "GAP_NO_PUSH_CYCLES"),
                ("gap with policy/bank push", "GAP_POLICY_CYCLES"),
            ):
                stream.write(f"| {label} | {int(opportunity.get(field, 0))} |\n")
            stream.write("\nSelect width matrix (raw width -> actual width):\n\n")
            stream.write("| Raw\\Actual | 0 | 1 | 2 |\n|---:|---:|---:|---:|\n")
            matrix_cycles = records.get("PERF_SELECT_WIDTH_MATRIX_CYCLES", {})
            matrix_slots = records.get("PERF_SELECT_WIDTH_MATRIX_SLOTS", {})
            for raw_width in range(3):
                cells = []
                for actual_width in range(3):
                    field = f"M{raw_width}{actual_width}"
                    cells.append(
                        f"{int(matrix_cycles.get(field, 0))} cyc / "
                        f"{int(matrix_slots.get(field, 0))} lost"
                    )
                stream.write(f"| {raw_width} | " + " | ".join(cells) + " |\n")

            rob_full = value(records, "PERF_CONTROL_DECOUPLE", "ROB_FULL")
            rob_head_wait = value(records, "PERF_ROB_HEAD_STATE", "WAIT_LOAD") + value(
                records, "PERF_ROB_HEAD_STATE", "WAIT_BRANCH"
            ) + value(records, "PERF_ROB_HEAD_STATE", "WAIT_MDU")
            p0_candidate = value(records, "PERF_RS_BANK_STATE", "P0_CANDIDATE")
            p0_selected = value(records, "PERF_RS_BANK_STATE", "P0_SELECTED")
            alloc_select_tail = sum(
                value(records, "PERF_LATENCY_ALLOC_SELECT", field)
                for field in ("B4_7", "B8_15", "B16_31", "B32_63", "B64P")
            )
            stream.write("\n#### Architecture decision gates\n\n")
            stream.write("| Evidence in current HEAD | What it rules in/out |\n|---|---|\n")
            stream.write(
                f"| ROB full {int(rob_full)} cycles ({pct(rob_full, sample)}) | "
                f"Capacity is not the first refill fix, but {ROB_DEPTH} entries cannot sustain IPC 1.2 "
                "at the measured residence time; a timing-partitioned 16-entry design is a later required gate. |\n"
            )
            stream.write(
                f"| ROB head waits in load/MDU/branch classes {int(rob_head_wait)} cycles | "
                "Retirement serialization must be analyzed separately from RS admission. |\n"
            )
            stream.write(
                f"| P0 candidate/selected entry-cycles {int(p0_candidate)}/{int(p0_selected)} | "
                "If the ratio is near one, P0 is not Select-starved; its bank dependency/order/credit pressure is the coupled target. |\n"
            )
            stream.write(
                f"| allocate->Select latency tail (4+ cycles) {int(alloc_select_tail)} | "
                "Window admission, wakeup visibility, bank mapping, and Select policy must be optimized as one path. |\n"
            )
            stream.write(
                f"| pair-capable singleton lost slots {int(opportunity.get('PAIR_CAPABLE_SINGLE_LOST_SLOTS', 0))} | "
                "A nonzero value supports flexible lane assignment/pair formation; it is not evidence for Operand skid merge by itself. |\n"
            )
            stream.write(
                f"| Select width gap: recovery {int(opportunity.get('GAP_RECOVERY_CYCLES', 0))}, "
                f"policy/bank {int(opportunity.get('GAP_POLICY_CYCLES', 0))} cycles | "
                "A zero policy/bank gap rules out Select priority as the explanation for the raw-width mismatch; keep recovery separate. |\n"
            )
            stream.write(
                f"| pair pushed behind singleton head {int(pair_behind)} lost slots | "
                "This is an edge-level cross-bundle pairing opportunity even though persistent skid state is zero. |\n"
            )
            stream.write(
                "\nThe RTL ownership behind these gates is the current `ydrasil_issue_stage.sv` "
                "12-entry RS split into ALU[0:3], P0/LSU[4:7], and P1[8:11], followed by "
                "the registered two-cell Select/Operand bundle. `ydrasil_ctrl.sv` owns the "
                "expanded in-order ROB head and retirement, while `ydrasil_load_store_unit.sv` "
                "owns LSU credit, store-buffer, and memory-response timing. The report keeps "
                "these ownership boundaries explicit so one counter cannot be mistaken for a "
                "single RTL root cause.\n\n"
            )
            stream.write("### 200 MHz and PPA guardrails\n\n")
            stream.write(
                "This report intentionally does not import an older post-route result. A "
                "200 MHz claim is valid only when timing/utilization/power are generated "
                "from the same current RTL hash and constraints (5.0 ns period). The "
                "following are architecture changes to evaluate while preserving that "
                "boundary:\n\n"
            )
            stream.write("| Current loss evidence | RTL direction | 200 MHz/PPA constraint |\n|---|---|---|\n")
            stream.write(
                f"| Head-empty boundary: {int(refill_stored)}/{int(refill_uops)} pushed uops already have registered data | "
                "Use the registered-data fraction to size bank-local operand prefetch; address the pending fraction at its producer lifetime instead of treating every refill event as recoverable. | "
                "Do not make raw Select drive RF/value resolution or EX in one cycle; preserve a register cut at the bank output. |\n"
            )
            stream.write(
                f"| DEP+ORDER overlap {int(loss_coupling_pairs(records)[0][2]) if loss_coupling_pairs(records) else 0} slots at top pair | "
                "Treat this primarily as dependency-driven residency of ordered entries; direct RS_ORDER loss is small, so do not relax ordering first. | "
                "Shorten load readiness lifetime and encode order with bank-local registered age/frontier tokens. |\n"
            )
            stream.write(
                f"| P0 full {int(value(records, 'PERF_LOCAL_CONTROL', 'P0_FULL'))} cycles; P0 candidate selected ratio near one | "
                "Add a P0 ingress elastic slot for same-cycle full+release and a small load-capable overflow path for dependency residency. | "
                "Keep ingress/overflow registered and P0-local; never feed current Select release combinationally to Fetch/Decode. |\n"
            )
            stream.write(
                f"| ROB head class waits {int(rob_head_wait)} cycles, ROB full {int(rob_full)} cycles | "
                "After refill and P0 fixes, use a 16-entry ROB or reduce mean residence below 8 cycles; load-head delay dominates. | "
                "Register head/head+1 metadata and isolate completion decode from rename-map clear before increasing depth. |\n"
            )
            stream.write(
                f"| branch mispredicts {int(value(records, 'PERF_BRANCH', 'MISPRED'))}, recovery loss slots {int(value(records, 'PERF_BACKEND_LOSS', 'FLUSH'))} | "
                "Keep recovery/resync as a separate term from steady-state OoO issue. | "
                "Do not count recovery bubbles as Select policy loss when sizing the issue network. |\n\n"
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

            for title, record, fields in (
                ("SINGLE_BUNDLE detail", "PERF_SINGLE_BUNDLE_DETAIL", SINGLE_BUNDLE_FIELDS),
                ("SELECT_REFILL detail", "PERF_SELECT_REFILL_DETAIL", SELECT_REFILL_FIELDS),
                ("RS_DEPENDENCY detail", "PERF_RS_DEPENDENCY_DETAIL2", RS_DEPENDENCY_DETAIL_FIELDS),
                ("SINGLE_BUNDLE operation class", "PERF_SINGLE_BUNDLE_OP", SINGLE_BUNDLE_OP_FIELDS),
                ("SELECT_REFILL shape", "PERF_SELECT_REFILL_SHAPE", SELECT_REFILL_SHAPE_FIELDS),
                ("RS_DEPENDENCY wakeup source", "PERF_RS_DEPENDENCY_WAKE", RS_DEPENDENCY_WAKE_FIELDS),
                ("RS_DEPENDENCY operation class", "PERF_RS_DEPENDENCY_OP", RS_DEPENDENCY_OP_FIELDS),
            ):
                detail_expected = value(records, record, "EXPECTED")
                detail_accounted = value(records, record, "ACCOUNTED")
                stream.write(
                    f"\n#### {title}\n\nClosure: **{'PASS' if detail_accounted == detail_expected else 'FAIL'}**, "
                    f"accounted {int(detail_accounted)}, expected {int(detail_expected)}.\n\n"
                )
                stream.write("| Leaf | Slots | Parent share |\n|---|---:|---:|\n")
                for label, field in sorted(
                    fields,
                    key=lambda item: value(records, record, item[1]),
                    reverse=True,
                ):
                    count = value(records, record, field)
                    stream.write(f"| {label} | {int(count)} | {pct(count, detail_expected)} |\n")

            dep_blocker_slots = sparse_mask(
                records, "PERF_RS_DEP_BLOCKER_MASK_SLOTS"
            )
            dep_blocker_total = sum(dep_blocker_slots.values())
            stream.write("\n#### RS dependency producer classes\n\n")
            stream.write(
                "This is an orthogonal producer-side view of `RS_DEPENDENCY_OP`: "
                "the latter names the blocked consumer, while this mask names all "
                "producer classes simultaneously blocking resident operands. "
                "`UNTRACKED` means the tag no longer maps to a live ROB generation; "
                "it is a readiness-lifetime observation, not an Operand correctness "
                "failure (`OPERAND_DEP_MISS` remains the contract check).\n\n"
            )
            stream.write(
                f"Mask closure: **{'PASS' if dep_blocker_total == value(records, 'PERF_BACKEND_LOSS', 'RS_DEPENDENCY') else 'FAIL'}**, "
                f"rows={int(dep_blocker_total)}, expected="
                f"{int(value(records, 'PERF_BACKEND_LOSS', 'RS_DEPENDENCY'))}.\n\n"
            )
            stream.write("| Blocker combination | Lost slots | Dependency share |\n")
            stream.write("|---|---:|---:|\n")
            for mask, slots in sorted(
                dep_blocker_slots.items(), key=lambda item: item[1], reverse=True
            ):
                if not slots:
                    continue
                active = "+".join(
                    name for bit, name in enumerate(DEP_BLOCKER_BITS)
                    if mask & (1 << bit)
                ) or "none"
                stream.write(
                    f"| {active} | {int(slots)} | {pct(slots, dep_blocker_total)} |\n"
                )
            stream.write("\n| Blocked producer operand class | Operand-entry cycles | Share |\n")
            stream.write("|---|---:|---:|\n")
            blocker_operands = records.get("PERF_RS_DEP_BLOCKER_OPERANDS", {})
            blocker_operand_total = blocker_operands.get("TOTAL", 0)
            for field in DEP_BLOCKER_BITS:
                source_field = "STALE" if field == "UNTRACKED" else field
                count = blocker_operands.get(source_field, 0)
                stream.write(
                    f"| {field.lower()} | {int(count)} | "
                    f"{pct(count, blocker_operand_total)} |\n"
                )

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
            leaf_expected = value(records, "PERF_SLOT_LEAF", "EXPECTED")
            leaf_accounted = sum(
                value(records, "PERF_SLOT_LEAF", field)
                for _, field in SLOT_LEAF_FIELDS
            )
            # Prefer the explicit TB total when present; the sum is retained
            # as an independent check against omitted/overlapping leaves.
            leaf_recorded = value(records, "PERF_SLOT_LEAF", "ACCOUNTED")
            stream.write("\n### Complete execution-slot leaf partition\n\n")
            stream.write(
                f"Closure: **{'PASS' if leaf_accounted == leaf_expected == leaf_recorded else 'FAIL'}**, "
                f"leaves={int(leaf_accounted)}, recorded={int(leaf_recorded)}, "
                f"expected={int(leaf_expected)} (two slots/cycle).\n\n"
            )
            stream.write("| Leaf cause | Slots | Capacity share |\n|---|---:|---:|\n")
            for label, field in sorted(
                SLOT_LEAF_FIELDS,
                key=lambda item: value(records, "PERF_SLOT_LEAF", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_SLOT_LEAF", field)
                stream.write(f"| {label} | {int(count)} | {pct(count, leaf_expected)} |\n")
            ex_expected = value(records, "PERF_EX_SLOT_STATE", "EXPECTED")
            ex_accounted = sum(
                value(records, "PERF_EX_SLOT_STATE", field)
                for _, field in EX_SLOT_FIELDS
            )
            ex_recorded = value(records, "PERF_EX_SLOT_STATE", "ACCOUNTED")
            stream.write("\n### Physical EX slot state (stage-aligned)\n\n")
            stream.write(
                f"Closure: **{'PASS' if ex_accounted == ex_expected == ex_recorded else 'FAIL'}**, "
                f"leaves={int(ex_accounted)}, recorded={int(ex_recorded)}, "
                f"expected={int(ex_expected)}. These states are sampled at EX, "
                "not inferred from current Issue/RS controls.\n\n"
            )
            stream.write("| EX state | Slots | Capacity share |\n|---|---:|---:|\n")
            for label, field in sorted(
                EX_SLOT_FIELDS,
                key=lambda item: value(records, "PERF_EX_SLOT_STATE", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_EX_SLOT_STATE", field)
                stream.write(f"| {label} | {int(count)} | {pct(count, ex_expected)} |\n")
            empty_expected = value(records, "PERF_EX_EMPTY_CAUSE", "EXPECTED")
            empty_accounted = sum(
                value(records, "PERF_EX_EMPTY_CAUSE", field)
                for _, field in EX_EMPTY_FIELDS
            )
            empty_recorded = value(records, "PERF_EX_EMPTY_CAUSE", "ACCOUNTED")
            alignment_residual = value(records, "PERF_EX_EMPTY_CAUSE", "UNACCOUNTED_SNAPSHOT")
            valid_hold = value(records, "PERF_EX_VALID_HOLD", "TOTAL")
            stream.write("\n### Stage-aligned EX pipeline-empty causes\n\n")
            stream.write(
                f"Closure: **{'PASS' if empty_accounted == empty_expected == empty_recorded and alignment_residual == valid_hold else 'FAIL'}**, "
                f"leaves={int(empty_accounted)}, recorded={int(empty_recorded)}, "
                f"expected={int(empty_expected)}. Each cause is from the "
                "registered source snapshot; valid packet holds are explicitly checked below.\n\n"
            )
            stream.write("| Empty-lane cause | Slots | Empty-slot share |\n|---|---:|---:|\n")
            for label, field in sorted(
                EX_EMPTY_FIELDS,
                key=lambda item: value(records, "PERF_EX_EMPTY_CAUSE", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_EX_EMPTY_CAUSE", field)
                stream.write(f"| {label} | {int(count)} | {pct(count, empty_expected)} |\n")
            stream.write(
                f"\nStage alignment residual: {int(alignment_residual)} slots; valid Operand/EX "
                f"holds observed in the registered EX packet: {int(valid_hold)} "
                "(lane0/lane1 = "
                f"{int(value(records, 'PERF_EX_VALID_HOLD', 'LANE0'))}/"
                f"{int(value(records, 'PERF_EX_VALID_HOLD', 'LANE1'))}). "
                "A nonzero residual is a real EX packet-hold state, not a missing "
                "frontend/RS cause; it must be optimized or explicitly excluded from "
                "the empty-slot partition.\n"
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
            p0_pipe_expected = value(records, "PERF_P0_FULL_PIPELINE", "EXPECTED")
            p0_pipe_accounted = value(records, "PERF_P0_FULL_PIPELINE", "ACCOUNTED")
            stream.write(
                "\nThe legacy table above assigns a whole full-bank sample by "
                "priority and can let one dependent entry hide another ready entry. "
                "The progressive table below asks whether any resident entry passes "
                "each successive RTL candidate gate.\n\n"
            )
            stream.write(
                f"Progressive P0 pipeline closure: **{'PASS' if p0_pipe_accounted == p0_pipe_expected else 'FAIL'}**, "
                f"accounted {int(p0_pipe_accounted)}, expected {int(p0_pipe_expected)}.\n\n"
            )
            stream.write("| Furthest P0 candidate gate reached | Slots | P0-full share |\n")
            stream.write("|---|---:|---:|\n")
            for label, field in sorted(
                P0_PIPELINE_FIELDS,
                key=lambda item: value(records, "PERF_P0_FULL_PIPELINE", item[1]),
                reverse=True,
            ):
                count = value(records, "PERF_P0_FULL_PIPELINE", field)
                stream.write(
                    f"| {label} | {int(count)} | {pct(count, p0_pipe_expected)} |\n"
                )
            credit_resv = records.get("PERF_P0_CREDIT_RESV_MATRIX", {})
            matrix_accounted = credit_resv.get("ACCOUNTED", 0)
            matrix_expected = credit_resv.get("EXPECTED", 0)
            stream.write(
                f"\nP0 LSU credit/reservation matrix closure: "
                f"**{'PASS' if matrix_accounted == matrix_expected else 'FAIL'}**, "
                f"accounted {int(matrix_accounted)}, expected {int(matrix_expected)}. "
                "Rows are registered LSU queue credits; columns are P0 selections "
                "reserved between Select and AGU enqueue.\n\n"
            )
            stream.write("| LSU credit | reservation 0 | reservation 1 | reservation 2 |\n")
            stream.write("|---:|---:|---:|---:|\n")
            for credit in range(3):
                counts = [
                    int(credit_resv.get(f"C{credit}_R{reservation}", 0))
                    for reservation in range(3)
                ]
                stream.write(
                    f"| {credit} | {counts[0]} | {counts[1]} | {counts[2]} |\n"
                )
            stream.write(
                "\nRegistered LSU queue age repairs: "
                f"**{int(value(records, 'PERF_LSU_AGE_REPAIR', 'CYCLES'))} cycles**. "
                "This counts a younger unsafe MMIO head being exchanged with "
                "an older registered request; it is a correctness/progress event, "
                "not an additive performance-loss bucket.\n"
            )
            p0_mix = records.get("PERF_P0_FULL_RESIDENT_MIX", {})
            p0_mix_expected = p0_mix.get("EXPECTED", 0)
            stream.write("\nP0-full resident composition:\n\n")
            stream.write("| Stores resident (remaining entries are loads) | Lost slots | Share |\n")
            stream.write("|---:|---:|---:|\n")
            for store_count in range(5):
                count = p0_mix.get(f"STORE{store_count}", 0)
                stream.write(
                    f"| {store_count} | {int(count)} | {pct(count, p0_mix_expected)} |\n"
                )
            blocked_ops = records.get("PERF_P0_FULL_BLOCKED_OP", {})
            blocked_expected = blocked_ops.get("EXPECTED", 0)
            stream.write("\n| P0 operation blocked at dispatch | Lost slots | Share |\n")
            stream.write("|---|---:|---:|\n")
            for field in ("LOAD", "STORE", "OTHER"):
                count = blocked_ops.get(field, 0)
                stream.write(
                    f"| {field.lower()} | {int(count)} | {pct(count, blocked_expected)} |\n"
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
