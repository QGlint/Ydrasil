#!/usr/bin/env python3
"""Summarize Verilator's final tree and flag likely unregistered outputs.

Verilator 5.048 does not ship --xml-only, so the Make target uses its stable
tree JSON dump.  Newer Verilator XML can be passed as well; the JSON report is
intentionally conservative and marks unresolved cases as ``unknown``.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


def walk(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def width_of(dtype: dict[str, Any] | None, index: dict[str, dict[str, Any]]) -> int | None:
    if not dtype:
        return None
    kind = dtype.get("type", "")
    if kind == "BASICDTYPE":
        ranges = [item for item in dtype.get("rangep", []) if isinstance(item, dict)]
        if ranges:
            return int(ranges[0].get("widthConst", 1))
        return 1
    if kind == "UNPACKARRAYDTYPE":
        ranges = [item for item in dtype.get("rangep", []) if isinstance(item, dict)]
        extent = 1
        if ranges:
            range_node = ranges[0]
            left = range_node.get("leftp", [{}])[0].get("name", "")
            right = range_node.get("rightp", [{}])[0].get("name", "")
            raw_numbers = re.findall(r"32'h([0-9a-fA-F]+)$", left) + re.findall(r"32'h([0-9a-fA-F]+)$", right)
            raw_numbers += [item for item in (left, right) if item.isdigit()]
            numbers = [int(item, 16) if not item.isdigit() else int(item, 10) for item in raw_numbers]
            if len(numbers) == 2:
                extent = abs(numbers[1] - numbers[0]) + 1
        return extent * (width_of(index.get(dtype.get("refDTypep", "")), index) or 1)
    if kind in {"REFDTYPE", "LOGICDTYPE", "PACKARRAYDTYPE"}:
        return width_of(index.get(dtype.get("refDTypep", "") or dtype.get("dtypep", "")), index)
    if dtype.get("widthConst") is not None:
        return int(dtype["widthConst"])
    return None


def ref_names(node: Any, index: dict[str, dict[str, Any]]) -> set[str]:
    result: set[str] = set()
    for item in walk(node):
        if item.get("type") != "VARREF":
            continue
        var = index.get(item.get("varp", ""), item)
        name = var.get("origName") or var.get("name")
        if name:
            result.add(name)
    return result


def module_report(module: dict[str, Any], index: dict[str, dict[str, Any]]) -> dict[str, Any]:
    variables = [item for item in walk(module) if item.get("type") == "VAR"]
    # Function return values also carry direction=OUTPUT in Verilator's tree;
    # only PORT variables are module outputs.
    outputs = {
        item.get("origName") or item.get("name")
        for item in variables
        if item.get("direction") == "OUTPUT" and item.get("varType") == "PORT"
    }
    outputs.discard(None)
    delayed_lhs: set[str] = set()
    continuous: dict[str, set[str]] = {}
    always_count = Counter()
    for item in walk(module):
        if item.get("type") == "ALWAYS":
            always_count[item.get("keyword", "always")] += 1
        if item.get("type") not in {"ASSIGNDLY", "ASSIGNW", "ASSIGN"}:
            continue
        lhs = item.get("lhsp", [])
        rhs = item.get("rhsp", [])
        lhs_names = ref_names(lhs, index)
        rhs_names = ref_names(rhs, index)
        if item.get("type") == "ASSIGNDLY":
            delayed_lhs.update(lhs_names)
        else:
            for name in lhs_names:
                continuous.setdefault(name, set()).update(rhs_names)

    registered = sorted(name for name in outputs if name in delayed_lhs or continuous.get(name, set()) & delayed_lhs)
    combinational = sorted(name for name in outputs if name in continuous and name not in registered)
    unknown = sorted(outputs - set(registered) - set(combinational))
    registers = []
    for item in variables:
        name = item.get("origName") or item.get("name")
        if item.get("varType") != "VAR" or not name or name not in delayed_lhs:
            continue
        dtype = index.get(item.get("dtypep", ""))
        registers.append({"name": name, "width_bits": width_of(dtype, index), "array": dtype.get("type") == "UNPACKARRAYDTYPE" if dtype else False})
    status = "yes" if outputs and not combinational and not unknown else ("no" if combinational else "unknown")
    return {
        "name": module.get("origName") or module.get("name"),
        "output_count": len(outputs),
        "registered_outputs": registered,
        "combinational_outputs": combinational,
        "unknown_outputs": unknown,
        "all_outputs_registered": status == "yes",
        "registration_status": status,
        "register_count": len(registers),
        "register_bits": sum(item["width_bits"] or 0 for item in registers),
        "registers": registers,
        "always_blocks": dict(always_count),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--top", default=None)
    args = parser.parse_args()
    try:
        tree = json.loads(args.input.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read Verilator tree {args.input}: {exc}", file=sys.stderr)
        return 2

    index = {item["addr"]: item for item in walk(tree) if item.get("addr")}
    modules = [item for item in walk(tree) if item.get("type") == "MODULE" and item.get("name") != "@CONST-POOL@"]
    reports = [module_report(module, index) for module in modules]
    if args.top:
        reports.sort(key=lambda item: (item["name"] != args.top, item["name"]))
    result = {"input": str(args.input), "top": args.top, "modules": reports}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(reports)} modules)")
    for report in reports:
        if report["combinational_outputs"]:
            print(f"{report['name']}: combinational outputs: {', '.join(report['combinational_outputs'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
