#!/usr/bin/env python3
"""Select and explain execution-bubble windows from a lightweight TB probe.

The input is deliberately a CSV rather than a simulator-specific waveform.  A
JSON sidecar binds the CSV to the design, RTL fingerprint, probe fingerprint,
and test provenance.  See ``schema_description()`` for the exact contract.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import json
import math
import re
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence


SCHEMA = "ydrasil.execution_wave.v2"
REQUIRED_METADATA = (
    "schema",
    "design",
    "rtl_sha256",
    "probe_sha256",
    "csv_sha256",
    "test_name",
    "simulator",
    "probe_instance",
    "generated_utc",
    "issue_width",
    "rob_depth",
    "benchmark_start_pc",
    "benchmark_stop_pc",
)

REQUIRED_COLUMNS = (
    "cycle",
    "instret",
    "fetch_pc",
    "issue_pc0",
    "issue_pc1",
    "ex_pc0",
    "ex_pc1",
    "if_valid0",
    "if_valid1",
    "decode_valid0",
    "decode_valid1",
    "dispatch_accept0",
    "dispatch_accept1",
    "rs_valid_mask",
    "rs_dep_mask",
    "rs_order_mask",
    "rs_resource_mask",
    "rs_ready_mask",
    "rs_candidate_mask",
    "rs_selected_mask",
    "select_valid0",
    "select_valid1",
    "select_push",
    "select_head_valid",
    "select_head_pair",
    "select_skid_valid",
    "operand_accept0",
    "operand_accept1",
    "ex_valid0",
    "ex_valid1",
    "ex_accept0",
    "ex_accept1",
    "retire0",
    "retire1",
    "rob_count",
    "producer_full",
    "lsu_credit",
    "lsu_reserved",
    "lsu_queue_count",
    "lsu_idle",
    "lsu_struct_stall",
    "serialize_stall",
    "mdu_available",
    "flush",
    "redirect",
    "recovery_pending",
    "frontend_queue_count",
    "fetch_req_valid",
    "fetch_resp_valid",
    "pending_redirect",
    "completion_wakeup_mask",
    "alloc_wakeup_mask",
    "select_wakeup_mask",
    "dtcm_wakeup",
    "mdu_wakeup",
    "dep_blocker_mask",
    "alu_credit",
    "p0_credit",
    "p1_credit",
    "reset",
    "sample_valid",
    "halted",
    "physical_exec0",
    "physical_exec1",
    "branch_mispredict",
    "direct_fire",
    "direct_pair",
    "retire_pc0",
    "retire_pc1",
    "issue_tag0",
    "issue_tag1",
    "ex_tag0",
    "ex_tag1",
    "selected_pc0",
    "selected_pc1",
    "selected_tag0",
    "selected_tag1",
    "head0_b_only",
    "pipeline_flush",
    "fence_issue",
    "trap_redirect",
)
OPTIONAL_COLUMNS: tuple[str, ...] = ()
PC_COLUMNS = {
    "fetch_pc", "issue_pc0", "issue_pc1", "ex_pc0", "ex_pc1",
    "retire_pc0", "retire_pc1",
    "selected_pc0", "selected_pc1",
}
MASK_COLUMNS = {
    "rs_valid_mask",
    "rs_dep_mask",
    "rs_order_mask",
    "rs_resource_mask",
    "rs_ready_mask",
    "rs_candidate_mask",
    "rs_selected_mask",
    "completion_wakeup_mask",
    "alloc_wakeup_mask",
    "select_wakeup_mask",
    "dep_blocker_mask",
}
BOOL_COLUMNS = {
    "if_valid0", "if_valid1", "decode_valid0", "decode_valid1",
    "dispatch_accept0", "dispatch_accept1", "select_valid0", "select_valid1",
    "select_push", "select_head_valid", "select_head_pair", "select_skid_valid",
    "operand_accept0", "operand_accept1", "ex_valid0", "ex_valid1",
    "ex_accept0", "ex_accept1", "retire0", "retire1", "producer_full",
    "lsu_idle", "lsu_struct_stall", "serialize_stall",
    "mdu_available", "flush", "redirect", "recovery_pending",
    "fetch_req_valid", "fetch_resp_valid", "pending_redirect", "dtcm_wakeup",
    "mdu_wakeup", "reset", "sample_valid", "halted",
    "physical_exec0", "physical_exec1", "branch_mispredict", "direct_fire", "direct_pair",
    "head0_b_only", "pipeline_flush", "fence_issue", "trap_redirect",
}
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


CAUSE_INFO = {
    "recovery_redirect": (
        "Flush/redirect recovery removes useful execute work.",
        "Reduce redirect-to-refill latency and evaluate predictor accuracy; compare flush-to-first-execute cycles.",
    ),
    "producer_backpressure": (
        "An execute valid is held while the producer/writeback side is full.",
        "Add or rebalance producer/WB buffering or ports; verify fewer ex_valid&&!ex_accept cycles.",
    ),
    "direct_pair_lost_slot": (
        "The direct path selected a pair but one or more physical execution slots were unused.",
        "Preserve both direct-selected uops across the Operand/FU boundary; measure direct_pair physical lost slots.",
    ),
    "direct_operand_boundary": (
        "Direct selection fired but neither Operand lane accepted work and no physical execution occurred.",
        "Add or repair the direct-select to Operand bypass/ready path; measure direct_fire with empty Operand acceptance.",
    ),
    "direct_execute_boundary": (
        "Direct selection and Operand acceptance did not produce physical execution in that cycle.",
        "Remove the direct Operand-to-FU boundary bubble or add a skid/bypass; measure direct-fire to physical-exec latency.",
    ),
    "execute_accept_backpressure": (
        "Execute valid is not accepted without the producer-full qualifier.",
        "Trace the execute accept fan-in and add the missing downstream busy probe before changing width.",
    ),
    "operand_to_physical_gap": (
        "E-1 Operand-accepted work has no PC-matched physical execution at E.",
        "Repair the Operand-to-FU handoff or replay path; require fewer E-1 accepted PCs missing at physical EX cycle E.",
    ),
    "operand_stage_block": (
        "The Select head contains work but Operand accepts fewer head slots.",
        "Relieve Operand read/forwarding conflicts; measure select-head valid/pair slots not accepted.",
    ),
    "handoff_invariant": (
        "Observed Select/Operand handoff violates a current-RTL ready/push invariant.",
        "Treat this as a probe or RTL assertion failure; do not size queues from it until the invariant is resolved.",
    ),
    "select_refill_boundary": (
        "The Select head is empty while newly selected work is pushed into the buffer.",
        "Evaluate a proven select-push to Operand bypass; require fewer head-empty refill bubbles without timing regression.",
    ),
    "singleton_bundle_slot": (
        "Operand accepted one uop from a singleton bundle, leaving the other physical lane intentionally unused.",
        "Preserve bundle shape and lane eligibility; only widen pairing after selected/Operand lane masks prove a legal second uop.",
    ),
    "select_queue_backpressure": (
        "RS selected an entry but the select queue did not accept a push.",
        "Add select-queue bypass/capacity or remove head-of-line blocking; measure selected-without-push cycles.",
    ),
    "selection_arbitration": (
        "Candidate work exists but no RS entry was selected.",
        "Fix bank/arbitration exclusions or widen selection only where candidate masks prove parallel work.",
    ),
    "candidate_policy": (
        "Ready RS work exists but policy/resource filtering removed all candidates.",
        "Inspect candidate qualification and bank pairing rules; compare ready and candidate masks per entry.",
    ),
    "wakeup_visibility": (
        "Dependency-blocked work coincides with a completion/allocation/select wakeup.",
        "Add same-cycle wakeup-to-select bypass or earlier wakeup; measure wakeup-to-ready latency.",
    ),
    "dependency_block": (
        "Resident RS work is blocked on operands without a visible same-cycle wakeup.",
        "Shorten producer latency or improve forwarding; identify dep_blocker_mask producer classes first.",
    ),
    "order_block": (
        "RS entries are prevented by ordering/serialization constraints.",
        "Refine memory disambiguation or serialization scope; verify correctness with order-stress tests.",
    ),
    "fence_pipeline": (
        "A FENCE instruction flushes or serializes the issue pipeline across the observed phase.",
        "Reduce fence drain/refill latency only where software ordering permits; measure fence-to-next-physical-EX cycles.",
    ),
    "lsu_structural": (
        "Ready work is blocked by LSU credit, reservation, queue, or structural state.",
        "Increase the proven limiting LSU credit/queue/port or release it earlier; rerun the same windows.",
    ),
    "mdu_structural": (
        "Resource-blocked work coincides with an unavailable MDU.",
        "Pipeline or duplicate MDU capacity only if MDU-tagged blockers dominate sampled slots.",
    ),
    "resource_block": (
        "RS work is blocked by a resource without a more specific resource qualifier.",
        "Add per-entry FU/resource tags, then change only the resource dominating bubble slots.",
    ),
    "rob_capacity": (
        "The ROB is full, preventing refill behind the execution gap.",
        "Increase retire throughput or ROB depth; compare ROB-full duration and retirement width.",
    ),
    "frontend_starvation": (
        "No IF/decode/queued front-end work is available to refill the backend.",
        "Reduce fetch response and redirect latency or deepen the fetch queue; measure fetch-to-dispatch gaps.",
    ),
    "frontend_refill_boundary": (
        "Front-end activity exists but has not reached decode/backend work.",
        "Add a front-end/decode bypass or queue capacity where the raw stage-valid transition stalls.",
    ),
    "issue_window_empty": (
        "The issue window is empty despite being in the measurement interval.",
        "Measure dispatch-to-RS refill latency and remove the first empty-boundary stage.",
    ),
    "unclassified": (
        "Current probes do not explain the unused execute slot.",
        "Add downstream accept-reason and per-entry resource-class probes before proposing an IPC change.",
    ),
    "phase_boundary": (
        "The first stable cycle has no in-interval E-1 source cycle for phase attribution.",
        "Do not optimize from this boundary cycle; extend the measurement interval if it is material.",
    ),
}
CAUSE_CODES = {name: index + 1 for index, name in enumerate(CAUSE_INFO)}


class AnalysisError(ValueError):
    """Raised when provenance, schema, or sampling cannot be trusted."""


@dataclass(frozen=True)
class Provenance:
    path: Path
    values: dict[str, object]

    @property
    def issue_width(self) -> int:
        return int(self.values["issue_width"])

    @property
    def rob_depth(self) -> int:
        return int(self.values["rob_depth"])


@dataclass(frozen=True)
class WaveRow:
    values: dict[str, int]

    def __getitem__(self, key: str) -> int:
        return self.values[key]

    @property
    def cycle(self) -> int:
        return self.values["cycle"]


@dataclass(frozen=True)
class Diagnosis:
    executed_slots: int
    bubble_slots: int
    cause: str
    evidence: str
    accepted_slots: int
    source_cycle: int | None
    source_operand_accept_slots: int
    pc_matched_slots: int
    missing_expected_keys: tuple[tuple[int, int], ...]
    direct_selected_slots: int
    direct_selected_keys: tuple[tuple[int, int], ...]
    direct_operand_matched_slots: int
    direct_t1_physical_matched_slots: int
    direct_t1_target_lane_empty_slots: int
    direct_physical_matched_slots: int
    direct_advanceable_slots: int


@dataclass
class Sample:
    rows: list[WaveRow]
    diagnoses: list[Diagnosis]
    context_before: WaveRow | None = None
    context_two_before: WaveRow | None = None
    rank: int = 0

    @property
    def start_cycle(self) -> int:
        return self.rows[0].cycle

    @property
    def end_cycle(self) -> int:
        return self.rows[-1].cycle

    @property
    def bubble_slots(self) -> int:
        return sum(item.bubble_slots for item in self.diagnoses)

    @property
    def executed_slots(self) -> int:
        return sum(item.executed_slots for item in self.diagnoses)

    @property
    def accepted_slots(self) -> int:
        return sum(item.accepted_slots for item in self.diagnoses)

    @property
    def source_operand_accept_slots(self) -> int:
        return sum(item.source_operand_accept_slots for item in self.diagnoses)

    @property
    def pc_tag_matched_slots(self) -> int:
        return sum(item.pc_matched_slots for item in self.diagnoses)

    @property
    def capacity_slots(self) -> int:
        return self.bubble_slots + self.executed_slots

    @property
    def bubble_density(self) -> float:
        return self.bubble_slots / self.capacity_slots if self.capacity_slots else 0.0

    @property
    def retired_insts(self) -> int:
        return sum(row["retire0"] + row["retire1"] for row in self.rows)

    @property
    def ipc(self) -> float:
        return self.retired_insts / len(self.rows)

    @property
    def cause_slots(self) -> Counter[str]:
        return Counter(
            {cause: slots for cause, slots in Counter(
                diagnosis.cause for diagnosis in self.diagnoses
                for _ in range(diagnosis.bubble_slots)
            ).items() if cause != "executed"}
        )

    @property
    def primary_cause(self) -> str:
        counts = self.cause_slots
        return max(counts, key=lambda cause: (counts[cause], -CAUSE_CODES.get(cause, 999))) if counts else "unclassified"


@dataclass(frozen=True)
class Candidate:
    rows: list[WaveRow]
    diagnoses: list[Diagnosis]
    context_before: WaveRow | None
    context_two_before: WaveRow | None

    @property
    def start(self) -> int:
        return self.rows[0].cycle

    @property
    def end(self) -> int:
        return self.rows[-1].cycle

    @property
    def score(self) -> int:
        return sum(item.bubble_slots for item in self.diagnoses)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def default_metadata_path(csv_path: Path) -> Path:
    preferred = csv_path.with_suffix(".metadata.json")
    appended = Path(str(csv_path) + ".metadata.json")
    if preferred.exists() or not appended.exists():
        return preferred
    return appended


def load_provenance(
    csv_path: Path,
    metadata_path: Path | None = None,
    *,
    expected_design: str = "Ydrasil",
    expected_rtl_sha256: str | None = None,
    expected_probe_sha256: str | None = None,
) -> Provenance:
    metadata_path = metadata_path or default_metadata_path(csv_path)
    if not metadata_path.exists():
        raise AnalysisError(f"metadata sidecar not found: {metadata_path}")
    if metadata_path.resolve().parent != csv_path.resolve().parent:
        raise AnalysisError("metadata sidecar must be in the same directory as the probe CSV")
    try:
        values = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AnalysisError(f"cannot read metadata JSON {metadata_path}: {exc}") from exc
    if not isinstance(values, dict):
        raise AnalysisError("metadata JSON must be an object")
    missing = [key for key in REQUIRED_METADATA if key not in values]
    if missing:
        raise AnalysisError(f"metadata missing required keys: {', '.join(missing)}")
    if values["schema"] != SCHEMA:
        raise AnalysisError(f"unsupported probe schema {values['schema']!r}; expected {SCHEMA!r}")
    if values["design"] != expected_design:
        raise AnalysisError(
            f"probe design {values['design']!r} does not match expected design {expected_design!r}"
        )
    for key in ("rtl_sha256", "probe_sha256", "csv_sha256"):
        raw = str(values[key])
        if not SHA256_RE.fullmatch(raw):
            raise AnalysisError(f"metadata {key} must be a 64-digit SHA-256 hex string")
        values[key] = raw.lower()
    actual_csv_hash = sha256_file(csv_path)
    if values["csv_sha256"] != actual_csv_hash:
        raise AnalysisError(
            f"CSV hash mismatch: metadata={values['csv_sha256']} actual={actual_csv_hash}"
        )
    for expected, key in (
        (expected_rtl_sha256, "rtl_sha256"),
        (expected_probe_sha256, "probe_sha256"),
    ):
        if expected is not None:
            if not SHA256_RE.fullmatch(expected):
                raise AnalysisError(f"expected {key} is not a 64-digit SHA-256 hex string")
            if values[key] != expected.lower():
                raise AnalysisError(
                    f"{key} mismatch: metadata={values[key]} expected={expected.lower()}"
                )
    try:
        issue_width = int(values["issue_width"])
        rob_depth = int(values["rob_depth"])
    except (TypeError, ValueError) as exc:
        raise AnalysisError("metadata issue_width and rob_depth must be integers") from exc
    if issue_width != 2:
        raise AnalysisError("schema v2 contains two execute lanes and therefore requires issue_width=2")
    if rob_depth <= 0:
        raise AnalysisError("metadata rob_depth must be positive")
    for key in ("benchmark_start_pc", "benchmark_stop_pc"):
        try:
            int(str(values[key]), 0)
        except (TypeError, ValueError) as exc:
            raise AnalysisError(f"metadata {key} must be an integer or 0x-prefixed PC") from exc
    if "clock_period_ns" in values:
        try:
            clock_period_ns = int(values["clock_period_ns"])
        except (TypeError, ValueError) as exc:
            raise AnalysisError("metadata clock_period_ns must be an integer") from exc
        if clock_period_ns < 2:
            raise AnalysisError("metadata clock_period_ns must be at least 2")
    if "xlen" in values:
        try:
            xlen = int(values["xlen"])
        except (TypeError, ValueError) as exc:
            raise AnalysisError("metadata xlen must be an integer") from exc
        if xlen not in (32, 64):
            raise AnalysisError("metadata xlen must be 32 or 64")
    for key in ("test_name", "simulator", "probe_instance"):
        if not isinstance(values[key], str) or not values[key].strip():
            raise AnalysisError(f"metadata {key} must be a non-empty string")
    try:
        generated = str(values["generated_utc"]).replace("Z", "+00:00")
        generated_time = datetime.fromisoformat(generated)
    except ValueError as exc:
        raise AnalysisError("metadata generated_utc must be an ISO-8601 timestamp") from exc
    if generated_time.utcoffset() is None or generated_time.utcoffset().total_seconds() != 0:
        raise AnalysisError("metadata generated_utc must include a UTC offset")

    # A copied probe source may be placed beside the CSV.  When present, bind
    # its bytes as well; otherwise --expect-probe-sha256 provides the external
    # trust anchor used by the orchestration flow.
    if "probe_file" in values:
        probe_name = Path(str(values["probe_file"]))
        if probe_name.is_absolute() or probe_name.name != str(probe_name):
            raise AnalysisError("metadata probe_file must be a basename in the CSV directory")
        probe_path = csv_path.parent / probe_name
        if not probe_path.is_file():
            raise AnalysisError(f"metadata probe_file not found: {probe_path}")
        if sha256_file(probe_path) != values["probe_sha256"]:
            raise AnalysisError("probe_file hash does not match metadata probe_sha256")
    return Provenance(metadata_path, values)


def parse_number(raw: str, column: str, line: int) -> int:
    text = raw.strip().replace("_", "")
    if not text:
        raise AnalysisError(f"line {line}: empty value in {column}")
    try:
        if column in MASK_COLUMNS:
            value = int(text[2:], 16) if text.lower().startswith("0x") else int(text, 16)
        elif column in PC_COLUMNS:
            value = int(text[2:], 16) if text.lower().startswith("0x") else int(text, 16)
        else:
            value = int(text, 10)
    except ValueError as exc:
        raise AnalysisError(f"line {line}: invalid integer {raw!r} in {column}") from exc
    if value < 0:
        raise AnalysisError(f"line {line}: {column} must be non-negative")
    if column in BOOL_COLUMNS and value not in (0, 1):
        raise AnalysisError(f"line {line}: {column} must be 0 or 1")
    return value


def load_rows(path: Path) -> tuple[list[WaveRow], list[str]]:
    try:
        stream = path.open(newline="", encoding="utf-8-sig")
    except OSError as exc:
        raise AnalysisError(f"cannot open probe CSV {path}: {exc}") from exc
    with stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None:
            raise AnalysisError("probe CSV has no header")
        if len(set(reader.fieldnames)) != len(reader.fieldnames):
            raise AnalysisError("probe CSV header contains duplicate columns")
        missing = [name for name in REQUIRED_COLUMNS if name not in reader.fieldnames]
        if missing:
            raise AnalysisError(f"probe CSV missing required columns: {', '.join(missing)}")
        unknown = [
            name for name in reader.fieldnames
            if name not in REQUIRED_COLUMNS and name not in OPTIONAL_COLUMNS
        ]
        if unknown:
            raise AnalysisError(f"probe CSV has unknown columns for schema v2: {', '.join(unknown)}")
        rows: list[WaveRow] = []
        previous_cycle: int | None = None
        previous_instret: int | None = None
        for line, raw_row in enumerate(reader, 2):
            if None in raw_row:
                raise AnalysisError(f"line {line}: too many CSV values")
            parsed = {
                name: parse_number(raw_row[name] or "", name, line)
                for name in reader.fieldnames
            }
            if parsed["rs_candidate_mask"] > 0xFFFF:
                raise AnalysisError(f"line {line}: rs_candidate_mask exceeds its 16-bit schema width")
            if parsed["direct_pair"] and not parsed["direct_fire"]:
                raise AnalysisError(f"line {line}: direct_pair requires direct_fire")
            if parsed["sample_valid"] and parsed["reset"]:
                raise AnalysisError(f"line {line}: sample_valid cannot be 1 while reset is 1")
            if parsed["sample_valid"] and parsed["halted"]:
                raise AnalysisError(f"line {line}: sample_valid cannot be 1 while halted is 1")
            cycle = parsed["cycle"]
            if previous_cycle is not None and cycle != previous_cycle + 1:
                raise AnalysisError(
                    f"line {line}: cycle must be contiguous; got {cycle} after {previous_cycle}"
                )
            if previous_instret is not None and parsed["instret"] < previous_instret:
                raise AnalysisError(f"line {line}: instret decreased")
            rows.append(WaveRow(parsed))
            previous_cycle = cycle
            previous_instret = parsed["instret"]
    if not rows:
        raise AnalysisError("probe CSV contains no cycles")
    return rows, list(reader.fieldnames)


def asserted(row: WaveRow, names: Iterable[str]) -> list[str]:
    return [name for name in names if row.values.get(name, 0)]


def diagnose_cycle(
    row: WaveRow,
    source: WaveRow | None = None,
    direct_source: WaveRow | None = None,
    issue_width: int = 2,
) -> Diagnosis:
    accepted = sum(
        bool(row[f"ex_valid{lane}"]) and bool(row[f"ex_accept{lane}"])
        for lane in range(issue_width)
    )
    executed = sum(bool(row[f"physical_exec{lane}"]) for lane in range(issue_width))
    bubbles = issue_width - executed
    source_lane_keys: list[tuple[int, int] | None] = [None] * issue_width
    if source is not None:
        if source["operand_accept0"]:
            source_lane_keys[0] = (source["issue_pc0"], source["issue_tag0"])
        if source["operand_accept1"]:
            issue_lane = 0 if source["head0_b_only"] else 1
            source_lane_keys[1] = (
                source[f"issue_pc{issue_lane}"], source[f"issue_tag{issue_lane}"]
            )
    physical_lane_keys: list[tuple[int, int] | None] = [
        (row[f"ex_pc{lane}"], row[f"ex_tag{lane}"])
        if row[f"physical_exec{lane}"] else None
        for lane in range(issue_width)
    ]
    matched_slots = sum(
        expected is not None and expected == physical
        for expected, physical in zip(source_lane_keys, physical_lane_keys)
    )
    missing_keys = tuple(
        expected for expected, physical in zip(source_lane_keys, physical_lane_keys)
        if expected is not None and expected != physical
    )
    direct_selected_keys: list[tuple[int, int]] = []
    if direct_source is not None and direct_source["direct_fire"]:
        direct_slots = 2 if direct_source["direct_pair"] else 1
        direct_selected_keys = [
            (direct_source[f"selected_pc{lane}"], direct_source[f"selected_tag{lane}"])
            for lane in range(direct_slots)
        ]
    remaining_direct = Counter(direct_selected_keys)
    direct_operand_lane_keys: list[tuple[int, int] | None] = [None] * issue_width
    for lane, key in enumerate(source_lane_keys):
        if key is not None and remaining_direct[key]:
            direct_operand_lane_keys[lane] = key
            remaining_direct[key] -= 1
    direct_operand_matches = sum(key is not None for key in direct_operand_lane_keys)
    direct_t1_physical_matches = sum(
        key is not None
        and source is not None
        and source[f"physical_exec{lane}"]
        and key == (source[f"ex_pc{lane}"], source[f"ex_tag{lane}"])
        for lane, key in enumerate(direct_operand_lane_keys)
    )
    direct_t1_target_lane_empty_slots = sum(
        key is not None and source is not None and not source[f"physical_exec{lane}"]
        for lane, key in enumerate(direct_operand_lane_keys)
    )
    direct_physical_matches = sum(
        key is not None and key == physical_lane_keys[lane]
        for lane, key in enumerate(direct_operand_lane_keys)
    )
    direct_advanceable_slots = sum(
        key is not None
        and source is not None
        and not source[f"physical_exec{lane}"]
        and key == physical_lane_keys[lane]
        for lane, key in enumerate(direct_operand_lane_keys)
    )

    def diagnosis(cause: str, evidence: str) -> Diagnosis:
        return Diagnosis(
            executed,
            bubbles,
            cause,
            evidence,
            accepted,
            source.cycle if source is not None else None,
            sum(key is not None for key in source_lane_keys),
            matched_slots,
            missing_keys,
            len(direct_selected_keys),
            tuple(direct_selected_keys),
            direct_operand_matches,
            direct_t1_physical_matches,
            direct_t1_target_lane_empty_slots,
            direct_physical_matches,
            direct_advanceable_slots,
        )

    if not bubbles:
        if missing_keys:
            missing = ",".join(f"0x{pc:08x}/t{tag}" for pc, tag in missing_keys)
            return diagnosis("executed", f"physical lanes full; unmatched E-1 PC/tags={missing}")
        return diagnosis("executed", "both physical execute lanes active")

    # Fence must precede pipeline_flush attribution: an accepted fence has an
    # intentional no-FU cycle, followed by a flush-empty cycle.
    fence = [f"E.{name}" for name in asserted(row, ("fence_issue",))]
    if source is not None:
        fence.extend(f"E-1.{name}" for name in asserted(source, ("fence_issue",)))
    if direct_source is not None:
        fence.extend(f"T.{name}" for name in asserted(direct_source, ("fence_issue",)))
    if fence:
        return diagnosis("fence_pipeline", "+".join(fence))

    trap = [f"E.{name}" for name in asserted(row, ("trap_redirect",))]
    if source is not None:
        trap.extend(f"E-1.{name}" for name in asserted(source, ("trap_redirect",)))
    if direct_source is not None:
        trap.extend(f"T.{name}" for name in asserted(direct_source, ("trap_redirect",)))
    if trap:
        return diagnosis("recovery_redirect", "+".join(trap))

    if source is None:
        return diagnosis("phase_boundary", "no stable E-1 source cycle")

    source_operand_slots = source["operand_accept0"] + source["operand_accept1"]
    phase_evidence = (
        f"E={row.cycle},E-1={source.cycle},operand={source_operand_slots},"
        f"physical={executed},pc_match={matched_slots}"
    )
    # Only E-1 pipeline_flush is in the physical-E kill cone.  Front-end
    # pending_redirect and same-E redirect/flush are deliberately excluded.
    if source["pipeline_flush"]:
        return diagnosis("recovery_redirect", "E-1.pipeline_flush")

    if source["recovery_pending"] and source_operand_slots == 0:
        return diagnosis("recovery_redirect", "E-1.recovery_pending with no Operand acceptance")

    if direct_selected_keys:
        direct_evidence = (
            f"T={direct_source.cycle},E-1={source.cycle},E={row.cycle},"
            f"selected={len(direct_selected_keys)},operand_match={direct_operand_matches},"
            f"physical_match={direct_physical_matches}"
        )
        if direct_operand_matches < len(direct_selected_keys):
            return diagnosis("direct_operand_boundary", direct_evidence)
        if direct_physical_matches < len(direct_selected_keys):
            cause = "direct_pair_lost_slot" if len(direct_selected_keys) == 2 else "direct_execute_boundary"
            return diagnosis(cause, direct_evidence)

    if missing_keys:
        missing = ",".join(f"0x{pc:08x}/t{tag}" for pc, tag in missing_keys)
        return diagnosis("operand_to_physical_gap", phase_evidence + f",missing={missing}")

    if source_operand_slots == 1 and matched_slots == 1:
        accepted_lane = 0 if source["operand_accept0"] else 1
        return diagnosis(
            "singleton_bundle_slot",
            f"E-1.single_operand_lane={accepted_lane},E-1.head0_b_only={source['head0_b_only']}",
        )

    source_head_slots = 2 if source["select_head_valid"] and source["select_head_pair"] else int(
        bool(source["select_head_valid"])
    )
    if source_head_slots > source_operand_slots:
        return diagnosis(
            "handoff_invariant",
            f"E-1.select_head_slots={source_head_slots},E-1.operand_accept={source_operand_slots}",
        )

    if (source["select_valid0"] or source["select_valid1"] or source["rs_selected_mask"]) and not source["select_push"]:
        return diagnosis(
            "handoff_invariant",
            "E-1.selected_valid/rs_selected without E-1.select_push",
        )

    if not source["select_head_valid"] and source["select_push"]:
        return diagnosis("select_refill_boundary", "E-1.select_head_valid=0+E-1.select_push")

    if source["rs_candidate_mask"] and not source["rs_selected_mask"]:
        return diagnosis("selection_arbitration", "E-1.rs_candidate_mask&&!E-1.rs_selected_mask")

    if source["rs_ready_mask"] and not source["rs_candidate_mask"]:
        return diagnosis("candidate_policy", "E-1.rs_ready_mask&&!E-1.rs_candidate_mask")

    wakeup_mask = (
        source["completion_wakeup_mask"]
        | source["alloc_wakeup_mask"]
        | source["select_wakeup_mask"]
    )
    wakeup_intersection = source["rs_dep_mask"] & wakeup_mask
    if wakeup_intersection:
        evidence = f"E-1.rs_dep_mask&wakeup_mask=0x{wakeup_intersection:x}"
        if source["dtcm_wakeup"]:
            evidence += "+dtcm_wakeup(unqualified)"
        if source["mdu_wakeup"]:
            evidence += "+mdu_wakeup(unqualified)"
        return diagnosis("wakeup_visibility", evidence)

    if source["rs_dep_mask"] or source["dep_blocker_mask"]:
        evidence = asserted(source, ("rs_dep_mask", "dep_blocker_mask"))
        return diagnosis("dependency_block", "+".join(f"E-1.{name}" for name in evidence))

    if source["rs_order_mask"] or source["serialize_stall"]:
        evidence = asserted(source, ("rs_order_mask", "serialize_stall"))
        return diagnosis("order_block", "+".join(f"E-1.{name}" for name in evidence))

    if source["rs_resource_mask"]:
        lsu_entries = source["rs_resource_mask"] & 0x0F0
        lsu_predicate = source["lsu_credit"] == 0 or (
            source["lsu_reserved"] > 0
            and source["lsu_queue_count"] >= source["lsu_reserved"]
        )
        if lsu_entries and lsu_predicate:
            return diagnosis(
                "lsu_structural",
                f"E-1.rs_resource_mask&0x0f0=0x{lsu_entries:x},"
                f"lsu_credit={source['lsu_credit']},lsu_reserved={source['lsu_reserved']},"
                f"lsu_queue_count={source['lsu_queue_count']}",
            )
        return diagnosis("resource_block", "E-1.rs_resource_mask without proven LSU predicate")

    if source["rob_count"] >= source.values.get("rob_depth", math.inf):
        return diagnosis("rob_capacity", "E-1.rob_count>=rob_depth")

    frontend_empty = not any(
        (
            source["if_valid0"], source["if_valid1"], source["decode_valid0"],
            source["decode_valid1"], source["frontend_queue_count"],
        )
    )
    if frontend_empty and not source["rs_valid_mask"]:
        return diagnosis("frontend_starvation", "E-1.IF/decode/frontend_queue/RS empty")
    if not (
        source["decode_valid0"] or source["decode_valid1"] or source["rs_valid_mask"]
    ) and any(
        (source["frontend_queue_count"], source["fetch_req_valid"], source["fetch_resp_valid"])
    ):
        return diagnosis("frontend_refill_boundary", "E-1.fetch/queue active before decode")
    if not source["rs_valid_mask"]:
        return diagnosis("issue_window_empty", "E-1.rs_valid_mask=0")
    return diagnosis("unclassified", "E-1.RS resident without observed blocker/candidate")


def diagnose_rows(rows: Sequence[WaveRow], provenance: Provenance) -> list[Diagnosis]:
    result: list[Diagnosis] = []
    for index, row in enumerate(rows):
        augmented = WaveRow({**row.values, "rob_depth": provenance.rob_depth})
        source: WaveRow | None = None
        if index and row["sample_valid"] and rows[index - 1]["sample_valid"]:
            source = WaveRow({**rows[index - 1].values, "rob_depth": provenance.rob_depth})
        direct_source: WaveRow | None = None
        if (
            index >= 2
            and row["sample_valid"]
            and rows[index - 1]["sample_valid"]
            and rows[index - 2]["sample_valid"]
        ):
            direct_source = WaveRow({**rows[index - 2].values, "rob_depth": provenance.rob_depth})
        result.append(diagnose_cycle(augmented, source, direct_source, provenance.issue_width))
    return result


def stable_segments(rows: Sequence[WaveRow]) -> list[list[WaveRow]]:
    if not any(row["sample_valid"] for row in rows):
        raise AnalysisError(
            "sample_valid is never 1; benchmark start PC was not observed or measurement state was not armed"
        )
    eligible = [
        bool(row["sample_valid"])
        and not bool(row["reset"])
        and not bool(row["halted"])
        for row in rows
    ]
    segments: list[list[WaveRow]] = []
    current: list[WaveRow] = []
    for row, keep in zip(rows, eligible):
        if keep:
            current.append(row)
        elif current:
            segments.append(current)
            current = []
    if current:
        segments.append(current)
    if not segments:
        raise AnalysisError("no stable execution cycles remain after measurement filtering")
    return segments


def build_candidates(
    segments: Sequence[Sequence[WaveRow]],
    diagnoses_by_cycle: dict[int, Diagnosis],
    window_cycles: int,
    min_bubble_density: float,
    issue_width: int,
) -> list[Candidate]:
    if window_cycles <= 0:
        raise AnalysisError("window_cycles must be positive")
    if not 0.0 <= min_bubble_density <= 1.0:
        raise AnalysisError("min_bubble_density must be between 0 and 1")
    candidates: list[Candidate] = []
    minimum_slots = math.ceil(window_cycles * issue_width * min_bubble_density)
    for segment in segments:
        if len(segment) < window_cycles:
            continue
        diagnoses = [diagnoses_by_cycle[row.cycle] for row in segment]
        running = sum(item.bubble_slots for item in diagnoses[:window_cycles])
        for start in range(0, len(segment) - window_cycles + 1):
            if start:
                running += diagnoses[start + window_cycles - 1].bubble_slots
                running -= diagnoses[start - 1].bubble_slots
            if running >= minimum_slots:
                candidates.append(Candidate(
                    list(segment[start:start + window_cycles]),
                    diagnoses[start:start + window_cycles],
                    segment[start - 1] if start else None,
                    segment[start - 2] if start >= 2 else None,
                ))
    return sorted(candidates, key=lambda item: (item.end, item.start))


def choose_non_overlapping(candidates: Sequence[Candidate], count: int, allow_fewer: bool = False) -> list[Sample]:
    if count <= 0:
        raise AnalysisError("sample count must be positive")
    if not candidates:
        raise AnalysisError("no window meets the requested bubble-density threshold")
    ends = [candidate.end for candidate in candidates]
    predecessors = [bisect.bisect_left(ends, candidate.start) - 1 for candidate in candidates]
    n = len(candidates)
    negative = -10**18
    previous = [0] * (n + 1)
    take_flags: list[bytearray] = [bytearray(n)]
    achievable = 0
    for selected_count in range(1, count + 1):
        current = [negative] * (n + 1)
        flags = bytearray(n)
        for i, candidate in enumerate(candidates, 1):
            skip_score = current[i - 1]
            base = previous[predecessors[i - 1] + 1]
            take_score = base + candidate.score if base != negative else negative
            if take_score > skip_score:
                current[i] = take_score
                flags[i - 1] = 1
            else:
                current[i] = skip_score
        take_flags.append(flags)
        previous = current
        if current[n] == negative:
            break
        achievable = selected_count
    target = min(count, achievable) if allow_fewer else count
    if achievable < count and not allow_fewer:
        raise AnalysisError(
            f"only {achievable} non-overlapping windows meet the threshold; requested {count}. "
            "Capture more stable cycles, lower --min-bubble-density, or use --allow-fewer."
        )
    if target == 0:
        raise AnalysisError("no non-overlapping sample could be selected")

    # Recompute DP layers only if the requested exact layer was not the last
    # achievable one.  Normally target == count and flags already cover it.
    i = n
    k = target
    chosen: list[Candidate] = []
    while k > 0 and i > 0:
        if take_flags[k][i - 1]:
            candidate = candidates[i - 1]
            chosen.append(candidate)
            i = predecessors[i - 1] + 1
            k -= 1
        else:
            i -= 1
    if k:
        raise AnalysisError("internal error reconstructing non-overlapping samples")
    samples = [
        Sample(
            candidate.rows,
            candidate.diagnoses,
            candidate.context_before,
            candidate.context_two_before,
        )
        for candidate in reversed(chosen)
    ]
    ranked = sorted(samples, key=lambda item: (-item.bubble_density, -item.bubble_slots, item.start_cycle))
    for rank, sample in enumerate(ranked, 1):
        sample.rank = rank
    return ranked


def evidence_counts(sample: Sample) -> Counter[str]:
    counts: Counter[str] = Counter()
    for diagnosis in sample.diagnoses:
        if diagnosis.bubble_slots:
            counts[diagnosis.evidence] += diagnosis.bubble_slots
    return counts


def direct_metrics_from_diagnoses(diagnoses: Iterable[Diagnosis]) -> dict[str, int]:
    phase_diagnoses = [item for item in diagnoses if item.direct_selected_slots]
    pc_patterns = Counter(
        tuple(pc for pc, _ in item.direct_selected_keys) for item in phase_diagnoses
    )
    return {
        "direct_fire_cycles": len(phase_diagnoses),
        "direct_pair_cycles": sum(item.direct_selected_slots == 2 for item in phase_diagnoses),
        "direct_selected_slots": sum(item.direct_selected_slots for item in phase_diagnoses),
        "direct_operand_pc_tag_matched_slots": sum(
            item.direct_operand_matched_slots for item in phase_diagnoses
        ),
        "direct_t1_physical_pc_tag_matched_slots": sum(
            item.direct_t1_physical_matched_slots for item in phase_diagnoses
        ),
        "direct_t1_target_lane_empty_slots": sum(
            item.direct_t1_target_lane_empty_slots for item in phase_diagnoses
        ),
        "direct_physical_pc_tag_matched_slots": sum(
            item.direct_physical_matched_slots for item in phase_diagnoses
        ),
        "direct_conservative_missing_slots": sum(
            item.direct_selected_slots - item.direct_physical_matched_slots
            for item in phase_diagnoses
        ),
        "direct_conservative_advanceable_slots": sum(
            item.direct_advanceable_slots for item in phase_diagnoses
        ),
        "direct_conservative_advanceable_events": sum(
            item.direct_advanceable_slots > 0 for item in phase_diagnoses
        ),
        "direct_fire_physical_bubble_cycles": sum(
            bool(item.bubble_slots) for item in phase_diagnoses
        ),
        "direct_fire_empty_operand_cycles": sum(
            item.direct_operand_matched_slots == 0 for item in phase_diagnoses
        ),
        "direct_pair_lost_slots": sum(
            item.direct_selected_slots - item.direct_physical_matched_slots
            for item in phase_diagnoses if item.direct_selected_slots == 2
        ),
        "direct_unique_pc_patterns": len(pc_patterns),
        "direct_repeated_pattern_events": sum(count - 1 for count in pc_patterns.values()),
    }


def direct_metrics(sample: Sample) -> dict[str, int]:
    return direct_metrics_from_diagnoses(sample.diagnoses)


def write_summary(path: Path, samples: Sequence[Sample]) -> None:
    fields = (
        "rank", "start_cycle", "end_cycle", "cycles", "start_pc", "end_pc",
        "capacity_slots", "physical_executed_slots", "architectural_accept_slots",
        "phase_operand_accept_slots", "phase_pc_tag_matched_slots", "phase_missing_slots",
        "bubble_slots", "bubble_density",
        "retired_insts", "ipc", "primary_cause", "primary_cause_slots",
        "cause_breakdown", "top_raw_evidence", "direct_fire_cycles", "direct_pair_cycles",
        "direct_selected_slots", "direct_operand_pc_tag_matched_slots",
        "direct_t1_physical_pc_tag_matched_slots", "direct_physical_pc_tag_matched_slots",
        "direct_t1_target_lane_empty_slots",
        "direct_conservative_missing_slots", "direct_conservative_advanceable_slots",
        "direct_conservative_advanceable_events", "direct_unique_pc_patterns",
        "direct_repeated_pattern_events",
        "direct_fire_physical_bubble_cycles", "direct_fire_empty_operand_cycles",
        "direct_pair_lost_slots",
    )
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for sample in sorted(samples, key=lambda item: item.rank):
            causes = sample.cause_slots
            evidence = evidence_counts(sample)
            writer.writerow({
                "rank": sample.rank,
                "start_cycle": sample.start_cycle,
                "end_cycle": sample.end_cycle,
                "cycles": len(sample.rows),
                "start_pc": f"0x{sample.rows[0]['fetch_pc']:08x}",
                "end_pc": f"0x{sample.rows[-1]['fetch_pc']:08x}",
                "capacity_slots": sample.capacity_slots,
                "physical_executed_slots": sample.executed_slots,
                "architectural_accept_slots": sample.accepted_slots,
                "phase_operand_accept_slots": sample.source_operand_accept_slots,
                "phase_pc_tag_matched_slots": sample.pc_tag_matched_slots,
                "phase_missing_slots": sample.source_operand_accept_slots - sample.pc_tag_matched_slots,
                "bubble_slots": sample.bubble_slots,
                "bubble_density": f"{sample.bubble_density:.6f}",
                "retired_insts": sample.retired_insts,
                "ipc": f"{sample.ipc:.6f}",
                "primary_cause": sample.primary_cause,
                "primary_cause_slots": causes[sample.primary_cause],
                "cause_breakdown": ";".join(f"{name}:{slots}" for name, slots in causes.most_common()),
                "top_raw_evidence": ";".join(f"{name}:{slots}" for name, slots in evidence.most_common(5)),
                **direct_metrics(sample),
            })


def display_value(name: str, value: int) -> str | int:
    if name in MASK_COLUMNS or name in PC_COLUMNS:
        return f"0x{value:x}"
    return value


def write_sample_csv(path: Path, sample: Sample, columns: Sequence[str]) -> None:
    derived = (
        "sample_rank", "in_sample", "sample_offset", "phase_source_cycle",
        "phase_operand_accept_slots", "phase_pc_tag_match_slots", "phase_missing_pc_tags",
        "direct_selected_slots", "direct_operand_pc_tag_matches",
        "direct_t1_physical_pc_tag_matches", "direct_t1_target_lane_empty_slots",
        "direct_t2_physical_pc_tag_matches", "direct_advanceable_slots",
        "physical_executed_slots", "architectural_accept_slots", "bubble_slots",
        "cause", "cause_evidence",
    )
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=(*derived, *columns))
        writer.writeheader()
        for context, offset, label in (
            (sample.context_two_before, -2, "T source for direct phase"),
            (sample.context_before, -1, "E-1 source for physical phase"),
        ):
            if context is None:
                continue
            context_output: dict[str, str | int] = {
                "sample_rank": sample.rank,
                "in_sample": 0,
                "sample_offset": offset,
                "phase_source_cycle": "",
                "phase_operand_accept_slots": "",
                "phase_pc_tag_match_slots": "",
                "phase_missing_pc_tags": "",
                "direct_selected_slots": "",
                "direct_operand_pc_tag_matches": "",
                "direct_t1_physical_pc_tag_matches": "",
                "direct_t1_target_lane_empty_slots": "",
                "direct_t2_physical_pc_tag_matches": "",
                "direct_advanceable_slots": "",
                "physical_executed_slots": "",
                "architectural_accept_slots": "",
                "bubble_slots": "",
                "cause": "phase_context",
                "cause_evidence": label,
            }
            context_output.update({name: display_value(name, context[name]) for name in columns})
            writer.writerow(context_output)
        for offset, (row, diagnosis) in enumerate(zip(sample.rows, sample.diagnoses)):
            output: dict[str, str | int] = {
                "sample_rank": sample.rank,
                "in_sample": 1,
                "sample_offset": offset,
                "phase_source_cycle": diagnosis.source_cycle if diagnosis.source_cycle is not None else "",
                "phase_operand_accept_slots": diagnosis.source_operand_accept_slots,
                "phase_pc_tag_match_slots": diagnosis.pc_matched_slots,
                "phase_missing_pc_tags": ";".join(
                    f"0x{pc:08x}/t{tag}" for pc, tag in diagnosis.missing_expected_keys
                ),
                "direct_selected_slots": diagnosis.direct_selected_slots,
                "direct_operand_pc_tag_matches": diagnosis.direct_operand_matched_slots,
                "direct_t1_physical_pc_tag_matches": diagnosis.direct_t1_physical_matched_slots,
                "direct_t1_target_lane_empty_slots": diagnosis.direct_t1_target_lane_empty_slots,
                "direct_t2_physical_pc_tag_matches": diagnosis.direct_physical_matched_slots,
                "direct_advanceable_slots": diagnosis.direct_advanceable_slots,
                "physical_executed_slots": diagnosis.executed_slots,
                "architectural_accept_slots": diagnosis.accepted_slots,
                "bubble_slots": diagnosis.bubble_slots,
                "cause": diagnosis.cause,
                "cause_evidence": diagnosis.evidence,
            }
            output.update({name: display_value(name, row[name]) for name in columns})
            writer.writerow(output)


def vcd_identifier(index: int) -> str:
    alphabet = "".join(chr(code) for code in range(33, 127))
    result = ""
    while True:
        result = alphabet[index % len(alphabet)] + result
        index = index // len(alphabet) - 1
        if index < 0:
            return result


def vcd_bits(value: int, width: int) -> str:
    return f"b{value & ((1 << width) - 1):0{width}b}"


def write_vcd(
    path: Path,
    samples: Sequence[Sample],
    columns: Sequence[str],
    provenance: Provenance,
) -> None:
    chronological = sorted(samples, key=lambda item: item.start_cycle)
    first_cycle = min(
        min(
            context.cycle for context in
            (sample.context_two_before, sample.context_before)
            if context is not None
        ) if sample.context_two_before is not None or sample.context_before is not None
        else sample.start_cycle
        for sample in chronological
    )
    period = int(provenance.values.get("clock_period_ns", 10))
    if period < 2:
        raise AnalysisError("metadata clock_period_ns must be at least 2 when provided")
    all_rows = [row for sample in samples for row in sample.rows]
    all_rows.extend(
        context
        for sample in samples
        for context in (sample.context_two_before, sample.context_before)
        if context is not None
    )
    signal_names = [
        "clock", "sample_active", "sample_rank", "primary_cause_code",
        "physical_executed_slots", "architectural_accept_slots", "bubble_slots", *columns,
    ]
    widths: dict[str, int] = {
        "clock": 1,
        "sample_active": 1,
        "sample_rank": max(1, max(sample.rank for sample in samples).bit_length()),
        "primary_cause_code": max(1, max(CAUSE_CODES.values()).bit_length()),
        "physical_executed_slots": 2,
        "architectural_accept_slots": 2,
        "bubble_slots": 2,
    }
    for name in columns:
        maximum = max(row[name] for row in all_rows)
        if name == "cycle" or name == "instret":
            widths[name] = 64
        elif name in PC_COLUMNS:
            widths[name] = int(provenance.values.get("xlen", 32))
        else:
            widths[name] = max(1, maximum.bit_length())
    identifiers = {name: vcd_identifier(index) for index, name in enumerate(signal_names)}

    events: dict[int, dict[str, int]] = {}
    # Emit E-1 phase context before selected events.  If a context cycle is
    # itself part of an adjacent selected window, the selected event below
    # takes precedence and remains sample_active.
    for sample in chronological:
        for context in (sample.context_two_before, sample.context_before):
            if context is None:
                continue
            time = (context.cycle - first_cycle) * period
            event = events.setdefault(time, {})
            event.setdefault("clock", 1)
            event.setdefault("sample_active", 0)
            event.setdefault("sample_rank", sample.rank)
            event.update(context.values)
            events.setdefault(time + period // 2, {}).setdefault("clock", 0)
    for sample in chronological:
        for row, diagnosis in zip(sample.rows, sample.diagnoses):
            time = (row.cycle - first_cycle) * period
            event = events.setdefault(time, {})
            event.update({
                "clock": 1,
                "sample_active": 1,
                "sample_rank": sample.rank,
                "primary_cause_code": CAUSE_CODES.get(diagnosis.cause, 0),
                "physical_executed_slots": diagnosis.executed_slots,
                "architectural_accept_slots": diagnosis.accepted_slots,
                "bubble_slots": diagnosis.bubble_slots,
            })
            event.update(row.values)
            events.setdefault(time + period // 2, {})["clock"] = 0
        next_cycle = sample.end_cycle + 1
        events.setdefault((next_cycle - first_cycle) * period, {})["sample_active"] = 0

    with path.open("w", encoding="ascii") as stream:
        stream.write("$date generated by analyze_execution_wave.py $end\n")
        stream.write("$version Ydrasil execution bubble analyzer $end\n")
        stream.write("$timescale 1ns $end\n")
        stream.write(f"$comment schema={SCHEMA} test={provenance.values['test_name']} $end\n")
        stream.write("$scope module execution_bubble_samples $end\n")
        for name in signal_names:
            stream.write(f"$var wire {widths[name]} {identifiers[name]} {name} $end\n")
        stream.write("$upscope $end\n$enddefinitions $end\n")
        previous: dict[str, int] = {}
        for time in sorted(events):
            stream.write(f"#{time}\n")
            for name in signal_names:
                if name not in events[time]:
                    continue
                value = events[time][name]
                if previous.get(name) == value:
                    continue
                previous[name] = value
                if widths[name] == 1:
                    stream.write(f"{value & 1}{identifiers[name]}\n")
                else:
                    stream.write(f"{vcd_bits(value, widths[name])} {identifiers[name]}\n")


def markdown_escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def write_report(
    path: Path,
    samples: Sequence[Sample],
    provenance: Provenance,
    warnings: Sequence[str],
    *,
    window_cycles: int,
    min_bubble_density: float,
    full_direct: dict[str, int],
    stable_cycle_count: int,
    stable_retired_insts: int,
) -> None:
    total_causes: Counter[str] = Counter()
    sample_direct: Counter[str] = Counter()
    for sample in samples:
        total_causes.update(sample.cause_slots)
        sample_direct.update(direct_metrics(sample))
    sample_patterns = Counter(
        tuple(
            (diagnosis.cause, diagnosis.executed_slots, diagnosis.source_operand_accept_slots)
            for diagnosis in sample.diagnoses
        )
        for sample in samples
    )
    lines = [
        "# Execution bubble waveform analysis",
        "",
        "## Provenance",
        "",
        f"- Schema: `{provenance.values['schema']}`",
        f"- Design: `{provenance.values['design']}`",
        f"- RTL SHA-256: `{provenance.values['rtl_sha256']}`",
        f"- Probe SHA-256: `{provenance.values['probe_sha256']}`",
        f"- Test: `{provenance.values['test_name']}`",
        f"- Benchmark retire-PC interval: `{provenance.values['benchmark_start_pc']}` to "
        f"`{provenance.values['benchmark_stop_pc']}`",
        f"- Simulator / instance: `{provenance.values['simulator']}` / `{provenance.values['probe_instance']}`",
        "",
        "The CSV byte hash was checked against the sidecar before analysis. "
        "RTL/probe fingerprints are external trust anchors when their expected values are supplied on the CLI.",
        "",
        "## Sampling method",
        "",
        f"Each window contains {window_cycles} cycles. Bubble density is unused physical execute slots / "
        f"({window_cycles} cycles x {provenance.issue_width} lanes); the admission threshold was "
        f"{min_bubble_density:.1%}. An exact weighted-interval selection maximizes total bubble slots "
        "while preventing overlap. Each physical execution cycle E is attributed from E-1 Operand acceptance; "
        "accepted and executed uops must match on both PC and ROB tag. Causes are assigned cycle-by-cycle "
        "from raw signals, not from aggregate counters or same-cycle pipeline comparisons.",
        "",
    ]
    if warnings:
        lines.extend(("### Warnings", ""))
        lines.extend(f"- {warning}" for warning in warnings)
        lines.append("")
    lines.extend((
        "## Selected windows",
        "",
        "| Rank | Cycles | Bubble density | IPC | Primary cause | Raw evidence | Targeted IPC experiment |",
        "|---:|:---|---:|---:|:---|:---|:---|",
    ))
    for sample in sorted(samples, key=lambda item: item.rank):
        evidence = ", ".join(f"{key} ({value} slots)" for key, value in evidence_counts(sample).most_common(3))
        recommendation = CAUSE_INFO[sample.primary_cause][1]
        lines.append(
            f"| {sample.rank} | {sample.start_cycle}-{sample.end_cycle} | {sample.bubble_density:.1%} | "
            f"{sample.ipc:.3f} | `{sample.primary_cause}` | {markdown_escape(evidence)} | "
            f"{markdown_escape(recommendation)} |"
        )
    repeated_samples = sum(count - 1 for count in sample_patterns.values())
    lines.extend((
        "",
        f"These are worst-density windows, not independent observations: {len(sample_patterns)} unique "
        f"cause/throughput patterns cover {len(samples)} samples ({repeated_samples} repeated samples). "
        "Repeated loop windows must not be treated as additional statistical confidence.",
    ))
    lines.extend((
        "",
        "## Root-cause priority",
        "",
        "| Cause | Bubble slots | Signal-based interpretation | IPC action and falsification metric |",
        "|:---|---:|:---|:---|",
    ))
    for cause, slots in total_causes.most_common():
        interpretation, recommendation = CAUSE_INFO[cause]
        lines.append(
            f"| `{cause}` | {slots} | {markdown_escape(interpretation)} | {markdown_escape(recommendation)} |"
        )
    direct_events = full_direct["direct_fire_cycles"]
    advanceable_events = full_direct["direct_conservative_advanceable_events"]
    current_ipc = stable_retired_insts / stable_cycle_count if stable_cycle_count else 0.0
    optimistic_cycles = stable_cycle_count - advanceable_events
    optimistic_ipc = stable_retired_insts / optimistic_cycles if optimistic_cycles > 0 else current_ipc
    repeated_direct = full_direct["direct_repeated_pattern_events"]
    lines.extend((
        "",
        "## Full-benchmark direct-path opportunity",
        "",
        "| Metric | Count | Interpretation |",
        "|:---|---:|:---|",
        f"| Direct-fire / pair events | {direct_events} / {full_direct['direct_pair_cycles']} | All stable `sample_valid` phase chains, not only selected windows. |",
        f"| Raw selected slots | {full_direct['direct_selected_slots']} | Identity originates at selected PC+ROB tag in cycle T. |",
        f"| T+1 Operand PC+tag matches | {full_direct['direct_operand_pc_tag_matched_slots']} | Selected identity reached the mapped Operand lane. |",
        f"| T+1 same-lane physical PC+tag matches | {full_direct['direct_t1_physical_pc_tag_matched_slots']} | Already executed early; exclude these from opportunity. |",
        f"| T+1 mapped physical-lane empty slots | {full_direct['direct_t1_target_lane_empty_slots']} | Lane availability check; PC mismatch alone does not prove availability. |",
        f"| T+2 same-lane physical PC+tag matches | {full_direct['direct_physical_pc_tag_matched_slots']} | Normal eventual execution after the fixed pipeline phase. |",
        f"| Conservative advanceable slots / events | {full_direct['direct_conservative_advanceable_slots']} / {advanceable_events} | T+1 target lane empty and the identical uop physically executes at T+2. |",
        f"| Unique / repeated direct PC patterns | {full_direct['direct_unique_pc_patterns']} / {repeated_direct} | "
        f"{(100.0 * repeated_direct / direct_events if direct_events else 0.0):.2f}% of events repeat a prior PC pattern; events are not independent. |",
        "",
        f"Trace-only lower bound: 0 IPC (the change may only shift an empty slot). Extremely optimistic upper bound: "
        f"{current_ipc:.6f} -> {optimistic_ipc:.6f} (+{optimistic_ipc - current_ipc:.6f}, "
        f"+{(100.0 * (optimistic_ipc / current_ipc - 1.0) if current_ipc else 0.0):.3f}%), assuming one entire cycle is saved "
        f"for every one of {advanceable_events} events. This bound uses events, not slots, and is not a performance prediction.",
        "",
        "The concrete experiment is an identity-preserving selected-to-Operand/FU bypass. It is supported only if "
        "T+1 same-lane physical executions rise, total benchmark cycles fall, and T+2 executions are not duplicated.",
        "",
        "### Sample-only direct metrics",
        "",
        f"The 15 selected windows contain {sample_direct['direct_fire_cycles']} direct events and "
        f"{sample_direct['direct_conservative_advanceable_slots']} conservative advanceable slots. "
        "These sample-only counts locate GTKWave evidence and must not be extrapolated as benchmark totals.",
    ))
    lines.extend((
        "",
        "## Artifacts",
        "",
        "- `execution_bubble_summary.csv`: one row per ranked window.",
        "- `samples/sample_NN_cycles.csv`: every raw probe signal plus the per-cycle cause and evidence.",
        "- `execution_bubble_samples.vcd`: selected cycles only; open in GTKWave and use `sample_active` / `sample_rank` to navigate gaps.",
        "",
        "A cause is actionable only when its proposed change reduces that cause's raw evidence and bubble slots on the same workload. "
        "If `unclassified` is material, capture additional accept-reason/resource-class signals before modifying the RTL.",
        "",
    ))
    path.write_text("\n".join(lines), encoding="utf-8")


def schema_description() -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "metadata_required": list(REQUIRED_METADATA),
        "csv_required_columns": list(REQUIRED_COLUMNS),
        "csv_optional_columns": list(OPTIONAL_COLUMNS),
        "encoding": {
            "masks": "hexadecimal, with or without 0x",
            "pcs": "hexadecimal, 0x prefix recommended",
        "other": "unsigned decimal; Boolean fields are 0 or 1",
        },
        "sidecar": "<input stem>.metadata.json in the same directory; --metadata may override only the basename",
    }


def analyze(
    csv_path: Path,
    output_dir: Path,
    *,
    metadata_path: Path | None = None,
    sample_count: int = 15,
    window_cycles: int = 32,
    min_bubble_density: float = 0.25,
    expected_design: str = "Ydrasil",
    expected_rtl_sha256: str | None = None,
    expected_probe_sha256: str | None = None,
    allow_fewer: bool = False,
) -> list[Sample]:
    provenance = load_provenance(
        csv_path,
        metadata_path,
        expected_design=expected_design,
        expected_rtl_sha256=expected_rtl_sha256,
        expected_probe_sha256=expected_probe_sha256,
    )
    rows, columns = load_rows(csv_path)
    diagnoses = diagnose_rows(rows, provenance)
    diagnoses_by_cycle = {row.cycle: diagnosis for row, diagnosis in zip(rows, diagnoses)}
    segments = stable_segments(rows)
    stable_cycle_count = sum(len(segment) for segment in segments)
    stable_retired_insts = sum(
        row["retire0"] + row["retire1"] for segment in segments for row in segment
    )
    full_direct = direct_metrics_from_diagnoses(
        diagnoses_by_cycle[row.cycle] for segment in segments for row in segment
    )
    required_stable_cycles = sample_count * window_cycles
    if not allow_fewer and stable_cycle_count < required_stable_cycles:
        raise AnalysisError(
            f"stable sample_valid interval has {stable_cycle_count} cycles; at least "
            f"{required_stable_cycles} are required for {sample_count} non-overlapping "
            f"{window_cycles}-cycle samples"
        )
    candidates = build_candidates(
        segments,
        diagnoses_by_cycle,
        window_cycles,
        min_bubble_density,
        provenance.issue_width,
    )
    samples = choose_non_overlapping(candidates, sample_count, allow_fewer)

    output_dir.mkdir(parents=True, exist_ok=True)
    samples_dir = output_dir / "samples"
    samples_dir.mkdir(parents=True, exist_ok=True)
    write_summary(output_dir / "execution_bubble_summary.csv", samples)
    for sample in samples:
        write_sample_csv(samples_dir / f"sample_{sample.rank:02d}_cycles.csv", sample, columns)
    write_report(
        output_dir / "execution_bubble_report.md",
        samples,
        provenance,
        (),
        window_cycles=window_cycles,
        min_bubble_density=min_bubble_density,
        full_direct=full_direct,
        stable_cycle_count=stable_cycle_count,
        stable_retired_insts=stable_retired_insts,
    )
    write_vcd(output_dir / "execution_bubble_samples.vcd", samples, columns, provenance)
    return samples


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Select non-overlapping high-bubble execution windows and explain them from raw TB probes."
    )
    parser.add_argument("input", nargs="?", type=Path, help="execution probe CSV")
    parser.add_argument("--metadata", type=Path, help="JSON provenance sidecar (must be beside input)")
    parser.add_argument("--output-dir", type=Path, help="artifact directory")
    parser.add_argument("--samples", type=int, default=15, help="number of non-overlapping samples (default: 15)")
    parser.add_argument("--window-cycles", type=int, default=32, help="cycles per sample (default: 32)")
    parser.add_argument(
        "--min-bubble-density", type=float, default=0.25,
        help="minimum unused execute-slot fraction (default: 0.25)",
    )
    parser.add_argument("--expect-design", default="Ydrasil", help="expected metadata design identity")
    parser.add_argument("--expect-rtl-sha256", help="trusted expected RTL fingerprint")
    parser.add_argument("--expect-probe-sha256", help="trusted expected probe fingerprint")
    parser.add_argument("--allow-fewer", action="store_true", help="emit all available samples if fewer than requested")
    parser.add_argument("--print-schema", action="store_true", help="print the JSON input contract and exit")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.print_schema:
        print(json.dumps(schema_description(), indent=2))
        return 0
    if args.input is None:
        parser.error("input CSV is required unless --print-schema is used")
    output_dir = args.output_dir or args.input.parent / f"{args.input.stem}_bubble_analysis"
    try:
        samples = analyze(
            args.input,
            output_dir,
            metadata_path=args.metadata,
            sample_count=args.samples,
            window_cycles=args.window_cycles,
            min_bubble_density=args.min_bubble_density,
            expected_design=args.expect_design,
            expected_rtl_sha256=args.expect_rtl_sha256,
            expected_probe_sha256=args.expect_probe_sha256,
            allow_fewer=args.allow_fewer,
        )
    except AnalysisError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(f"selected {len(samples)} non-overlapping execution-bubble windows")
    print(f"summary: {output_dir / 'execution_bubble_summary.csv'}")
    print(f"report:  {output_dir / 'execution_bubble_report.md'}")
    print(f"wave:    {output_dir / 'execution_bubble_samples.vcd'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
