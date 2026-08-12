#!/usr/bin/env python3
"""Aggregate routed timing CSVs into architecture-level path families.

This script consumes the compact CSVs emitted by ``syn/analyze_timing.py``.
The grouped CSV supplies raw-path coverage, while the violation CSV supplies
unique-pin representatives.  Keeping both counts prevents a single bad path
and a broad endpoint population from looking equivalent.
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SUMMARY_ROW_RE = re.compile(
    r"^\s*(?P<wns>-?\d+(?:\.\d+)?)\s+"
    r"(?P<tns>-?\d+(?:\.\d+)?)\s+"
    r"(?P<failing>\d+)\s+(?P<total>\d+)",
    re.MULTILINE,
)
FREQUENCY_RE = re.compile(r"cpu(?P<frequency>\d+(?:p\d+)?)_timing_groups\.csv$")
NUMERIC_INDEX_RE = re.compile(r"\[\d+\]")
REPLICA_RE = re.compile(r"_rep(?:__\d+)?")
ROUTE_STATUS_RE = {
    "routable": re.compile(r"# of routable nets\.+\s*:\s*(\d+)"),
    "fully_routed": re.compile(r"# of fully routed nets\.+\s*:\s*(\d+)"),
    "routing_errors": re.compile(r"# of nets with routing errors\.+\s*:\s*(\d+)"),
}
MAX_CONGESTION_RE = re.compile(
    r"(North|South|East|West) Dir\s+\S+ Area, Max Cong = ([\d.]+)%"
)
EFFECTIVE_CONGESTION_RE = re.compile(
    r"Direction:\s*(North|South|East|West).*?Effective congestion level:\s*(\d+)",
    re.DOTALL,
)


FAMILY_GUIDANCE = {
    "DTCM response -> Operand/FU":
        "Separate BRAM formatting, source selection, and class-local FU capture; preserve the fixed-latency load-use phase.",
    "RS/Select -> Select head":
        "Reduce bank-to-head payload muxing and release/wakeup fan-in; keep the registered Select boundary.",
    "Operand/Value -> FU input":
        "Keep class and physical-lane operand registers independent so synthesis cannot merge them into a shared wide mux.",
    "Dispatch/Decode -> RS":
        "Predecode narrow allocation/control fields and keep full payload writes local to each RS bank.",
    "Wakeup -> RS ready":
        "Use bank-local registered wakeup tokens and remove queue/recovery state from the ready-FF cone.",
    "Predictor -> Fetch/Redirect":
        "Factor bank-local prediction bits and FetchQ enables without adding a prediction stage.",
    "Predictor feedback/index":
        "Precompute or register history hashes while preserving the current speculative-history cycle.",
    "ITCM -> FetchQ/Frontend":
        "Reduce ITCM response-to-FetchQ write muxing and duplicate lane-local control near the payload RAMs.",
    "Frontend control":
        "Split FetchQ payload, count, and redirect state enables; avoid one wide global next-state mux.",
    "Frontend -> ITCM request":
        "Keep redirect/next-PC selection local to the ITCM address register and avoid distributing full target state across RAM banks.",
    "ROB/Rename/Retire":
        "Partition latest-map and retire updates by bank; remove broad head/commit priority muxes.",
    "Rename/ROB -> RS metadata":
        "Keep rename-tag updates bank-local and separate RS metadata enables from full-uop allocation writes.",
    "Recovery/ROB -> LSU":
        "Move recovery qualification to narrow valid metadata and avoid rewriting full queue/store payloads.",
    "Recovery/ROB -> Execute":
        "Use local registered kill/valid state instead of distributing ROB head state into FU controls.",
    "LSU queue/store internal":
        "Keep queue, store buffer, and forwarding updates in independent registered cells with narrow selects.",
    "Completion network":
        "Partition completion metadata/data by producer class and remove consumers that already have a local reservation.",
    "Execute/Completion -> ROB done":
        "Generate producer-done bits beside each registered producer and merge only narrow valid/tag tokens at the ROB boundary.",
    "Retire -> Register File":
        "Decode retire writes per physical register-file bank and keep write enables independent from the data path.",
    "Predictor maintenance":
        "Keep clear/invalidate controls local to predictor banks and off the prediction lookup path.",
    "Branch resolution/redirect":
        "Keep registered branch resolution, predictor training, and redirect enables local; distribute narrow tokens instead of full branch payloads.",
    "Exception/recovery control":
        "Partition recovery state updates by consumer and replace wide asynchronous set/reset cones with local valid control where legal.",
    "RS -> Select wakeup token":
        "Partition wakeup IDs, valids, and release credits per Select bank; avoid recomputing all tokens from the full RS payload.",
    "AGU/LSU request path":
        "Register request identity and queue-field enables independently; keep full address/data payloads out of shared queue control muxes.",
    "MDU/Execute internal":
        "Inspect divider normalization/state enables and keep MDU inputs local; pipeline only if latency semantics allow it.",
    "Reset/control distribution":
        "Prefer local synchronous valid clearing where legal and replicate reset/control sources physically.",
    "CSR path":
        "Keep CSR operand/result state local and remove unrelated FU values from the CSR input mux.",
    "Miscellaneous":
        "Inspect the listed source, destination, and structure signature before choosing an RTL change.",
}


@dataclass
class TimingSummary:
    wns_ns: float | None = None
    tns_ns: float | None = None
    failing_endpoints: int | None = None
    total_endpoints: int | None = None


@dataclass
class RouteHealth:
    routable_nets: int | None = None
    fully_routed_nets: int | None = None
    routing_errors: int | None = None
    max_congestion_pct: dict[str, float] | None = None
    effective_congestion_level: dict[str, int] | None = None
    no_high_level_windows: bool | None = None


@dataclass
class FamilyStats:
    raw_paths: int = 0
    fine_groups: int = 0
    representatives: int = 0
    worst_slack_ns: float | None = None
    weighted_slack_sum: float = 0.0
    weighted_slack_count: int = 0
    worst_source: str = ""
    worst_destination: str = ""
    worst_structure: str = ""
    route_pct_sum: float = 0.0
    route_pct_count: int = 0
    route_pct_ge_80: int = 0

    def observe_group(self, row: dict[str, str]) -> None:
        count = parse_int(row.get("count"))
        worst = parse_float(row.get("worst_slack_ns"))
        average = parse_float(row.get("avg_slack_ns"))
        self.raw_paths += count
        self.fine_groups += 1
        if average is not None and count:
            self.weighted_slack_sum += average * count
            self.weighted_slack_count += count
        self._observe_worst(
            worst,
            row.get("worst_start", ""),
            row.get("worst_end", ""),
            row.get("structure_signature", ""),
        )

    def observe_representative(self, row: dict[str, str]) -> None:
        self.representatives += 1
        route_pct = parse_float(row.get("route_pct"))
        if route_pct is not None:
            self.route_pct_sum += route_pct
            self.route_pct_count += 1
            self.route_pct_ge_80 += int(route_pct >= 80.0)
        self._observe_worst(
            parse_float(row.get("slack_ns")),
            row.get("source", ""),
            row.get("destination", ""),
            row.get("structure_signature", ""),
        )

    def _observe_worst(
        self, slack: float | None, source: str, destination: str, structure: str
    ) -> None:
        if slack is None:
            return
        if self.worst_slack_ns is None or slack < self.worst_slack_ns:
            self.worst_slack_ns = slack
            self.worst_source = source
            self.worst_destination = destination
            self.worst_structure = structure

    @property
    def weighted_average_slack_ns(self) -> float | None:
        if not self.weighted_slack_count:
            return None
        return self.weighted_slack_sum / self.weighted_slack_count

    @property
    def average_route_pct(self) -> float | None:
        if not self.route_pct_count:
            return None
        return self.route_pct_sum / self.route_pct_count


@dataclass
class EndpointStats:
    raw_paths: int = 0
    representatives: int = 0
    worst_slack_ns: float | None = None

    def observe_group(self, row: dict[str, str]) -> None:
        self.raw_paths += parse_int(row.get("count"))
        self._observe(parse_float(row.get("worst_slack_ns")))

    def observe_representative(self, row: dict[str, str]) -> None:
        self.representatives += 1
        self._observe(parse_float(row.get("slack_ns")))

    def _observe(self, slack: float | None) -> None:
        if slack is not None and (
            self.worst_slack_ns is None or slack < self.worst_slack_ns
        ):
            self.worst_slack_ns = slack


@dataclass
class Dataset:
    name: str
    frequency_mhz: float
    report_dir: Path
    summary: TimingSummary
    route_health: RouteHealth
    families: dict[str, FamilyStats]
    endpoint_families: dict[str, dict[str, EndpointStats]]
    representative_buckets: dict[str, int]

    @property
    def route_pct_count(self) -> int:
        return sum(stats.route_pct_count for stats in self.families.values())

    @property
    def route_pct_ge_80(self) -> int:
        return sum(stats.route_pct_ge_80 for stats in self.families.values())


def parse_float(value: str | None) -> float | None:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def parse_int(value: str | None) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return 0


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open(newline="", encoding="utf-8", errors="replace") as stream:
        return list(csv.DictReader(stream))


def owner(resource: str) -> str:
    text = resource.lower()
    ordered = (
        ("reset", "u_cpu_reset_sync"),
        ("dtcm", "/u_dtcm/"),
        ("itcm", "/u_itcm/"),
        ("predictor", "u_ydrasil_branch_predictor"),
        ("fetch_queue", "u_fetch_queue"),
        ("frontend", "u_ydrasil_if_stage"),
        ("rs", "g_rs_entry"),
        ("value_file", "u_value_file"),
        ("issue", "u_ydrasil_issue_stage"),
        ("ctrl", "/u_ctrl/"),
        ("lsu", "u_ydrasil_load_store_unit"),
        ("completion", "u_completion_ctrl"),
        ("divider", "u_ydrasil_div"),
        ("multiplier", "u_ydrasil_mul"),
        ("execute", "u_ydrasil_execute_stage"),
        ("exception", "u_ydrasil_exception_stage"),
        ("csr", "u_ydrasil_csr_stage"),
        ("mems", "u_ydrasil_mems"),
    )
    for name, marker in ordered:
        if marker in text:
            return name
    if "u_soc_core/u_core" in text:
        return "core"
    return "other"


def signal_family(resource: str) -> str:
    parts = resource.rsplit("/", 2)
    if len(parts) >= 2:
        text = parts[-2]
        if parts[-1].startswith(("ADDRARDADDR", "ADDRBWRADDR")):
            text += "/" + parts[-1]
    else:
        text = resource
    text = re.sub(r"_reg_\d+(?:_\d+)*$", "_q", text)
    text = re.sub(r"_reg(?=\[|$)", "", text)
    text = NUMERIC_INDEX_RE.sub("[*]", text)
    text = REPLICA_RE.sub("_rep", text)
    return text


def architecture_family(source: str, destination: str) -> str:
    src = owner(source)
    dst = owner(destination)
    dest_lower = destination.lower()

    if src == "execute" and dst in {"predictor", "frontend", "fetch_queue"}:
        return "Branch resolution/redirect"
    if src == "csr" or dst == "csr":
        return "CSR path"
    if (src, dst) in {
        ("execute", "exception"), ("exception", "ctrl"),
        ("ctrl", "exception"), ("exception", "rs"),
        ("exception", "fetch_queue"), ("other", "exception"),
    }:
        return "Exception/recovery control"
    if src == "reset" or dest_lower.endswith(("/r", "/s", "/clr", "/set")):
        return "Reset/control distribution"
    if src == "frontend" and dst == "itcm":
        return "Frontend -> ITCM request"
    if dst == "issue" and any(marker in dest_lower for marker in (
        "select_fast_wakeup_", "select_wakeup_", "_release_credit_q",
        "select_head_lane_a_valid_q", "select_head_lane_b_valid_q",
        "lsu_select_reserved_q", "dtcm_launch_wakeup_",
    )):
        return "RS -> Select wakeup token"
    if dst == "ctrl" and "producer_done_q" in dest_lower:
        return "Execute/Completion -> ROB done"
    if src == "ctrl" and dst == "issue" and (
        "/gen_regs[" in dest_lower or ".registers_reg[" in dest_lower
    ):
        return "Retire -> Register File"
    if dst == "predictor" and any(marker in dest_lower for marker in (
        "clear", "invalidate", "maintenance",
    )):
        return "Predictor maintenance"
    if (src == "issue" and dst == "lsu") or (src == "lsu" and dst == "dtcm"):
        return "AGU/LSU request path"
    if src == "dtcm" and dst in {"issue", "value_file"}:
        return "DTCM response -> Operand/FU"
    if src == "itcm" and dst in {"frontend", "fetch_queue"}:
        return "ITCM -> FetchQ/Frontend"
    if src in {"predictor", "itcm"} and dst == "predictor":
        return "Predictor feedback/index"
    if src == "predictor" and dst in {"frontend", "fetch_queue"}:
        return "Predictor -> Fetch/Redirect"
    if src in {"frontend", "fetch_queue"} and dst in {"frontend", "fetch_queue", "mems"}:
        return "Frontend control"
    if src in {"frontend", "fetch_queue", "itcm"} and dst in {"issue", "rs"}:
        return "Dispatch/Decode -> RS"
    if dst == "rs" and ("src0_ready" in dest_lower or "src1_ready" in dest_lower):
        return "Wakeup -> RS ready"
    if src == "ctrl" and dst == "rs":
        return "Rename/ROB -> RS metadata"
    if "select_head_uop" in dest_lower:
        return "RS/Select -> Select head"
    if dst in {"issue", "value_file"} and any(
        marker in dest_lower for marker in (
            "operand", "payload", "agu_in_req", "agu_in_dtcm_addr",
        )
    ):
        return "Operand/Value -> FU input"
    if dst == "rs" or "g_rs_entry" in dest_lower:
        return "Dispatch/Decode -> RS"
    if src in {"ctrl", "frontend", "fetch_queue"} and dst == "ctrl":
        return "ROB/Rename/Retire"
    if dst == "ctrl" and src in {"issue", "lsu"}:
        return "ROB/Rename/Retire"
    if src == "ctrl" and dst == "issue":
        return "ROB/Rename/Retire"
    if src in {"ctrl", "exception"} and dst == "lsu":
        return "Recovery/ROB -> LSU"
    if src in {"ctrl", "exception"} and dst in {"execute", "divider", "multiplier"}:
        return "Recovery/ROB -> Execute"
    if src == "lsu" and dst == "lsu":
        return "LSU queue/store internal"
    if src == "lsu" and dst in {"issue", "rs", "value_file"}:
        return "Wakeup -> RS ready" if dst == "rs" else "Operand/Value -> FU input"
    if src == "completion" or dst == "completion":
        return "Completion network"
    if src in {"issue", "value_file"} and dst in {"execute", "divider", "multiplier"}:
        return "MDU/Execute internal" if dst in {"divider", "multiplier"} else "Operand/Value -> FU input"
    if src in {"execute", "divider", "multiplier"} or dst in {"execute", "divider", "multiplier"}:
        return "MDU/Execute internal"
    if src == "issue" and dst == "issue" and "csr_" in dest_lower:
        return "CSR path"
    if src == "exception" or dst == "exception":
        return "Reset/control distribution"
    return "Miscellaneous"


def locate_csv(report_dir: Path, suffix: str) -> Path:
    matches = sorted(report_dir.glob(f"cpu*_timing_{suffix}.csv"))
    if len(matches) != 1:
        raise FileNotFoundError(
            f"expected one cpu*_timing_{suffix}.csv in {report_dir}, found {len(matches)}"
        )
    return matches[0]


def dataset_frequency(group_csv: Path) -> float:
    match = FREQUENCY_RE.search(group_csv.name)
    if not match:
        raise ValueError(f"cannot determine frequency from {group_csv.name}")
    return float(match.group("frequency").replace("p", "."))


def read_timing_summary(report_dir: Path) -> TimingSummary:
    path = report_dir / "post_route_timing_summary.rpt"
    if not path.is_file():
        return TimingSummary()
    text = path.read_text(encoding="utf-8", errors="replace")
    marker = text.find("Design Timing Summary")
    match = SUMMARY_ROW_RE.search(text, marker if marker >= 0 else 0)
    if not match:
        return TimingSummary()
    return TimingSummary(
        wns_ns=float(match.group("wns")),
        tns_ns=float(match.group("tns")),
        failing_endpoints=int(match.group("failing")),
        total_endpoints=int(match.group("total")),
    )


def read_route_health(report_dir: Path) -> RouteHealth:
    health = RouteHealth(max_congestion_pct={}, effective_congestion_level={})
    status_path = report_dir / "post_route_status.rpt"
    if status_path.is_file():
        status_text = status_path.read_text(encoding="utf-8", errors="replace")
        values: dict[str, int | None] = {}
        for name, pattern in ROUTE_STATUS_RE.items():
            match = pattern.search(status_text)
            values[name] = int(match.group(1)) if match else None
        health.routable_nets = values["routable"]
        health.fully_routed_nets = values["fully_routed"]
        health.routing_errors = values["routing_errors"]

    log_path = report_dir.parent / "log" / "vivado.log"
    if log_path.is_file():
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        for direction, percentage in MAX_CONGESTION_RE.findall(log_text):
            health.max_congestion_pct[direction] = float(percentage)
        for direction, level in EFFECTIVE_CONGESTION_RE.findall(log_text):
            health.effective_congestion_level[direction] = int(level)

    congestion_path = report_dir.parent / "project" / "FPGA" / "congestion.rpt"
    if congestion_path.is_file():
        congestion_text = congestion_path.read_text(encoding="utf-8", errors="replace")
        health.no_high_level_windows = (
            "No congestion windows are found above level 5" in congestion_text
            and "No initial estimated congestion windows are found above level 5"
            in congestion_text
        )
    return health


def slack_bucket(slack: float) -> str:
    if slack <= -1.0:
        return "<= -1.0"
    if slack <= -0.9:
        return "-1.0 .. -0.9"
    if slack <= -0.8:
        return "-0.9 .. -0.8"
    if slack <= -0.6:
        return "-0.8 .. -0.6"
    return "> -0.6"


def load_dataset(report_dir: Path) -> Dataset:
    report_dir = report_dir.resolve()
    group_csv = locate_csv(report_dir, "groups")
    representative_csv = locate_csv(report_dir, "violations")
    families: dict[str, FamilyStats] = {}
    endpoint_families: dict[str, dict[str, EndpointStats]] = {}

    for row in read_csv(group_csv):
        family = architecture_family(
            row.get("worst_start", row.get("start_pattern", "")),
            row.get("worst_end", row.get("end_pattern", "")),
        )
        families.setdefault(family, FamilyStats()).observe_group(row)
        endpoint = signal_family(row.get("worst_end", row.get("end_pattern", "")))
        endpoint_families.setdefault(family, {}).setdefault(
            endpoint, EndpointStats()
        ).observe_group(row)

    buckets: dict[str, int] = {}
    for row in read_csv(representative_csv):
        family = architecture_family(row.get("source", ""), row.get("destination", ""))
        families.setdefault(family, FamilyStats()).observe_representative(row)
        endpoint = signal_family(row.get("destination", ""))
        endpoint_families.setdefault(family, {}).setdefault(
            endpoint, EndpointStats()
        ).observe_representative(row)
        slack = parse_float(row.get("slack_ns"))
        if slack is not None:
            bucket = slack_bucket(slack)
            buckets[bucket] = buckets.get(bucket, 0) + 1

    return Dataset(
        name=report_dir.parent.name,
        frequency_mhz=dataset_frequency(group_csv),
        report_dir=report_dir,
        summary=read_timing_summary(report_dir),
        route_health=read_route_health(report_dir),
        families=families,
        endpoint_families=endpoint_families,
        representative_buckets=buckets,
    )


def format_number(value: float | None, digits: int = 3) -> str:
    return "N/A" if value is None else f"{value:.{digits}f}"


def ordered_families(dataset: Dataset) -> list[tuple[str, FamilyStats]]:
    return sorted(
        dataset.families.items(),
        key=lambda item: (-item[1].raw_paths, item[1].worst_slack_ns or 0.0, item[0]),
    )


def write_csv_report(datasets: Iterable[Dataset], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "dataset", "frequency_mhz", "family", "raw_paths", "fine_groups",
        "representatives", "worst_slack_ns", "weighted_avg_slack_ns",
        "average_route_pct", "route_pct_ge_80", "route_pct_count",
        "worst_source", "worst_destination", "worst_structure", "guidance",
    ]
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        for dataset in datasets:
            for family, stats in ordered_families(dataset):
                writer.writerow({
                    "dataset": dataset.name,
                    "frequency_mhz": dataset.frequency_mhz,
                    "family": family,
                    "raw_paths": stats.raw_paths,
                    "fine_groups": stats.fine_groups,
                    "representatives": stats.representatives,
                    "worst_slack_ns": stats.worst_slack_ns,
                    "weighted_avg_slack_ns": stats.weighted_average_slack_ns,
                    "average_route_pct": stats.average_route_pct,
                    "route_pct_ge_80": stats.route_pct_ge_80,
                    "route_pct_count": stats.route_pct_count,
                    "worst_source": stats.worst_source,
                    "worst_destination": stats.worst_destination,
                    "worst_structure": stats.worst_structure,
                    "guidance": FAMILY_GUIDANCE[family],
                })


def ordered_endpoints(
    dataset: Dataset, family: str
) -> list[tuple[str, EndpointStats]]:
    return sorted(
        dataset.endpoint_families.get(family, {}).items(),
        key=lambda item: (
            -item[1].raw_paths,
            item[1].worst_slack_ns if item[1].worst_slack_ns is not None else 0.0,
            item[0],
        ),
    )


def write_endpoint_csv_report(datasets: Iterable[Dataset], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "dataset", "frequency_mhz", "family", "endpoint_family",
        "raw_paths", "representatives", "worst_slack_ns",
    ]
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        for dataset in datasets:
            for family, _ in ordered_families(dataset):
                for endpoint, stats in ordered_endpoints(dataset, family):
                    writer.writerow({
                        "dataset": dataset.name,
                        "frequency_mhz": dataset.frequency_mhz,
                        "family": family,
                        "endpoint_family": endpoint,
                        "raw_paths": stats.raw_paths,
                        "representatives": stats.representatives,
                        "worst_slack_ns": stats.worst_slack_ns,
                    })


def clipped(value: str, width: int = 150) -> str:
    return value if len(value) <= width else value[: width - 3] + "..."


def write_markdown(
    datasets: list[Dataset], output: Path, top: int, endpoint_top: int
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as stream:
        stream.write("# Routed Timing Architecture Families\n\n")
        stream.write("Raw paths are reconstructed from group counts; representatives are unique-pin worst paths.\n\n")
        stream.write("| Dataset | MHz | WNS ns | TNS ns | Failing endpoints | Captured raw paths | Representatives | Route >=80% reps |\n")
        stream.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for dataset in datasets:
            stream.write(
                f"| `{dataset.name}` | {dataset.frequency_mhz:g} | "
                f"{format_number(dataset.summary.wns_ns)} | {format_number(dataset.summary.tns_ns)} | "
                f"{dataset.summary.failing_endpoints or 'N/A'} | "
                f"{sum(item.raw_paths for item in dataset.families.values())} | "
                f"{sum(item.representatives for item in dataset.families.values())} | "
                f"{dataset.route_pct_ge_80}/{dataset.route_pct_count} |\n"
            )

        stream.write("\n## Routing Health\n\n")
        stream.write("Final congestion values come from the latest `vivado.log`; route status comes from the routed checkpoint report.\n\n")
        stream.write("| Dataset | Fully routed | Routing errors | N max/level | S max/level | E max/level | W max/level | No level >5 windows |\n")
        stream.write("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n")
        for dataset in datasets:
            health = dataset.route_health
            direction_cells = []
            for direction in ("North", "South", "East", "West"):
                percentage = (health.max_congestion_pct or {}).get(direction)
                level = (health.effective_congestion_level or {}).get(direction)
                direction_cells.append(
                    f"{format_number(percentage, 1)}%/{level if level is not None else 'N/A'}"
                )
            fully_routed = (
                "N/A" if health.fully_routed_nets is None
                else f"{health.fully_routed_nets}/{health.routable_nets}"
            )
            no_high_level = (
                "N/A" if health.no_high_level_windows is None
                else "yes" if health.no_high_level_windows else "no"
            )
            stream.write(
                f"| `{dataset.name}` | {fully_routed} | "
                f"{health.routing_errors if health.routing_errors is not None else 'N/A'} | "
                + " | ".join(direction_cells)
                + f" | {no_high_level} |\n"
            )

        for dataset in datasets:
            stream.write(f"\n## {dataset.name} ({dataset.frequency_mhz:g} MHz)\n\n")
            stream.write("| Rank | Architecture family | Raw paths | Unique reps | Worst ns | Weighted avg ns | Avg route % | Route >=80% reps | Guidance |\n")
            stream.write("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n")
            ranked = ordered_families(dataset)
            for rank, (family, stats) in enumerate(ranked[:top], start=1):
                stream.write(
                    f"| {rank} | {family} | {stats.raw_paths} | {stats.representatives} | "
                    f"{format_number(stats.worst_slack_ns)} | "
                    f"{format_number(stats.weighted_average_slack_ns)} | "
                    f"{format_number(stats.average_route_pct, 1)} | "
                    f"{stats.route_pct_ge_80}/{stats.route_pct_count} | "
                    f"{FAMILY_GUIDANCE[family]} |\n"
                )

            stream.write("\n### Representative Slack Distribution\n\n")
            for bucket in ("<= -1.0", "-1.0 .. -0.9", "-0.9 .. -0.8", "-0.8 .. -0.6", "> -0.6"):
                stream.write(f"- `{bucket} ns`: {dataset.representative_buckets.get(bucket, 0)}\n")

            stream.write("\n### Worst Representative Per Family\n\n")
            for family, stats in sorted(
                dataset.families.items(), key=lambda item: item[1].worst_slack_ns or 0.0
            )[:top]:
                stream.write(
                    f"- **{family}** `{format_number(stats.worst_slack_ns)} ns`: "
                    f"`{clipped(stats.worst_source)}` -> `{clipped(stats.worst_destination)}`\n"
                )
                if stats.worst_structure:
                    stream.write(f"  Structure: `{clipped(stats.worst_structure, 220)}`\n")

            stream.write("\n### Main Endpoint Register Families\n\n")
            stream.write("| Architecture family | Endpoint register family | Raw paths | Unique reps | Worst ns |\n")
            stream.write("| --- | --- | ---: | ---: | ---: |\n")
            for family, _ in ranked[:top]:
                for endpoint, stats in ordered_endpoints(dataset, family)[:endpoint_top]:
                    stream.write(
                        f"| {family} | `{endpoint}` | {stats.raw_paths} | "
                        f"{stats.representatives} | {format_number(stats.worst_slack_ns)} |\n"
                    )

        if len(datasets) > 1:
            all_families = sorted({family for dataset in datasets for family in dataset.families})
            stream.write("\n## Frequency Trend\n\n")
            stream.write("| Architecture family | " + " | ".join(
                f"{dataset.frequency_mhz:g} MHz raw / worst ns" for dataset in datasets
            ) + " |\n")
            stream.write("| --- | " + " | ".join("---:" for _ in datasets) + " |\n")
            for family in all_families:
                cells = []
                for dataset in datasets:
                    stats = dataset.families.get(family)
                    cells.append("-" if stats is None else f"{stats.raw_paths} / {format_number(stats.worst_slack_ns)}")
                stream.write(f"| {family} | " + " | ".join(cells) + " |\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_dirs", nargs="+", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--endpoint-top", type=int, default=3)
    args = parser.parse_args()

    datasets = sorted(
        (load_dataset(path) for path in args.report_dirs),
        key=lambda item: item.frequency_mhz,
    )
    csv_path = args.out_dir / "timing_families.csv"
    endpoint_csv_path = args.out_dir / "timing_endpoint_families.csv"
    markdown_path = args.out_dir / "timing_families.md"
    write_csv_report(datasets, csv_path)
    write_endpoint_csv_report(datasets, endpoint_csv_path)
    write_markdown(
        datasets, markdown_path, max(1, args.top), max(1, args.endpoint_top)
    )
    print(f"wrote {csv_path}")
    print(f"wrote {endpoint_csv_path}")
    print(f"wrote {markdown_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
