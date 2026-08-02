#!/usr/bin/env python3
"""Compare Yosys stat JSON using relative resource thresholds."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


def normalize_cell_name(name: object) -> str:
    return str(name).lstrip("\\").upper()


def cell_counts(stats: dict[str, object]) -> dict[str, int]:
    counts = stats.get("num_cells_by_type")
    if isinstance(counts, dict):
        return {str(name): int(value) for name, value in counts.items()}
    counts = stats.get("cells")
    if isinstance(counts, dict):
        return {str(name): int(value) for name, value in counts.items()}
    return {}


def choose_stats(data: dict[str, object], top: str | None) -> dict[str, object]:
    design = data.get("design")
    if isinstance(design, dict):
        return design

    modules = data.get("modules")
    if not isinstance(modules, dict):
        raise ValueError("stat JSON does not contain a design or module map")

    if top:
        want = normalize_cell_name(top)
        for name, module in modules.items():
            if normalize_cell_name(name) == want and isinstance(module, dict):
                return module

    for key in ("top", f"\\{top}" if top else ""):
        module = modules.get(key)
        if isinstance(module, dict):
            return module

    for module in modules.values():
        if isinstance(module, dict):
            return module

    raise ValueError("stat JSON does not contain a usable module entry")


def count_where(counts: dict[str, int], predicate) -> int:
    return sum(value for name, value in counts.items() if predicate(normalize_cell_name(name)))


def is_actual_lut(name: str) -> bool:
    return name.startswith("LUT")


def is_ff(name: str) -> bool:
    return name.startswith(("FD", "DFF", "$_DFF", "$_SDFF", "$_ADFF"))


def is_latch(name: str) -> bool:
    return name.startswith(("LD", "$_DLATCH"))


def is_ram(name: str) -> bool:
    return name.startswith("$MEM") or name.startswith("RAM") or "RAMB" in name or "URAM" in name


def is_dsp(name: str) -> bool:
    return "DSP" in name or "MACC" in name or name.startswith(("$MUL", "MULT"))


def is_mux(name: str) -> bool:
    return "MUX" in name


def is_cmp(name: str) -> bool:
    return name.startswith(("$EQ", "$NE", "$LT", "$LE", "$GT", "$GE", "CMP"))


def is_carry(name: str) -> bool:
    return "CARRY" in name or "XORCY" in name or "MUXCY" in name or name.startswith("LCU")


def is_comb_proxy(name: str) -> bool:
    return name.startswith(
        (
            "$AND",
            "$OR",
            "$XOR",
            "$XNOR",
            "$NOT",
            "$REDUCE",
            "$ALU",
            "$LCU",
            "$DEMUX",
            "$PMUX",
            "$BMUX",
            "$BWMUX",
            "$SHIFT",
            "$SHL",
            "$SHR",
            "$EQ",
            "$NE",
            "$LT",
            "$LE",
            "$GT",
            "$GE",
            "AND",
            "OR",
            "XOR",
            "XNOR",
            "NOT",
            "DEMUX",
            "PMUX",
            "BMUX",
            "BWMUX",
            "SHIFT",
            "SHL",
            "SHR",
            "ALU",
            "LCU",
            "MUX",
        )
    )


def resource_metrics(data: dict[str, object], top: str | None) -> dict[str, object]:
    stats = choose_stats(data, top)
    counts = cell_counts(stats)
    total = int(stats.get("num_cells", sum(counts.values())))

    lut_cells = count_where(counts, is_actual_lut)
    ff = count_where(counts, is_ff)
    latch = count_where(counts, is_latch)
    ram = count_where(counts, is_ram)
    dsp = count_where(counts, is_dsp)
    mux = count_where(counts, is_mux)
    cmp = count_where(counts, is_cmp)
    carry = count_where(counts, is_carry)
    comb = total - ff - latch - ram - dsp
    logic = count_where(counts, is_comb_proxy)

    analysis = data.get("analysis")
    if not isinstance(analysis, dict):
        analysis = stats.get("analysis")
    if not isinstance(analysis, dict):
        analysis = {}
    ltp_length = analysis.get("ltp_length")
    if ltp_length is not None:
        ltp_length = int(ltp_length)

    lut_source = "lut_cells" if lut_cells else "comb_proxy"
    lut = lut_cells if lut_cells else comb

    return {
        "lut": lut,
        "lut_source": lut_source,
        "ff": ff,
        "latch": latch,
        "ram": ram,
        "dsp": dsp,
        "mux": mux,
        "cmp": cmp,
        "carry": carry,
        "logic": logic,
        "comb": comb,
        "cells": total,
        "ltp": ltp_length,
    }


def percent_delta(before: float, after: float) -> float:
    if before == 0:
        return 0.0 if after == 0 else math.inf
    return (after - before) * 100.0 / before


def format_delta(delta: float) -> str:
    if math.isinf(delta):
        return "inf"
    return f"{delta:.2f}"


def emit_row(metric: str, before: float, after: float, limit: float | None, source: str = "") -> float:
    delta = percent_delta(before, after)
    limit_text = "" if limit is None else f"{limit:g}"
    print(f"{metric},{before:g},{after:g},{format_delta(delta)},{limit_text},{source}")
    return delta


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--top", default=None)
    parser.add_argument("--lut-limit", type=float, default=15)
    parser.add_argument("--ltp-limit", type=float, default=20)
    args = parser.parse_args()

    base = resource_metrics(json.loads(args.baseline.read_text(encoding="utf-8")), args.top)
    candidate = resource_metrics(json.loads(args.candidate.read_text(encoding="utf-8")), args.top)

    failed = False
    print("metric,baseline,candidate,delta_percent,limit_percent,source")

    if base["lut_source"] != candidate["lut_source"]:
        print(
            f"error: LUT metric source mismatch: baseline={base['lut_source']} candidate={candidate['lut_source']}",
            file=sys.stderr,
        )
        failed = True

    delta = emit_row("lut", base["lut"], candidate["lut"], args.lut_limit, str(candidate["lut_source"]))
    if math.isinf(delta) or delta > args.lut_limit:
        failed = True

    for metric in ("ff", "latch", "ram", "dsp", "mux", "cmp", "carry", "logic", "comb", "cells"):
        emit_row(metric, base[metric], candidate[metric], None)

    if base["ltp"] is None or candidate["ltp"] is None:
        print("error: missing ltp_length in Yosys analysis JSON", file=sys.stderr)
        failed = True
    else:
        delta = emit_row("ltp", base["ltp"], candidate["ltp"], args.ltp_limit, "analysis.ltp_length")
        if math.isinf(delta) or delta > args.ltp_limit:
            failed = True

    if failed:
        print("Yosys relative resource gate: FAIL", file=sys.stderr)
        return 1
    print("Yosys relative resource gate: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
