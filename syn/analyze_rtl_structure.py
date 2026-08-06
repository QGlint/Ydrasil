#!/usr/bin/env python3
"""Analyze a Verilator final tree for RTL structure hazards.

The report is deliberately structural rather than a synthesis estimate.  It
tracks registers, unpacked arrays, assignment dependencies, cell connections,
combinational strongly connected components, path depth, and fanout.  The
input is Verilator's stable ``--dump-tree-json`` format.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any, Iterable

from rtl_timing_families import family_key, load_archive_training, normalize_owner


ASSIGN_TYPES = {"ASSIGN", "ASSIGNW", "ASSIGNDLY"}
PSEUDO_PREFIX = "@cell:"

# These are expression nodes rather than declarations/references.  Verilator
# emits a few internal helper nodes as well; counting only operators keeps the
# metric stable across tree-json versions.
OPERATOR_TYPES = {
    "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "NEG", "NOT", "AND", "OR",
    "XOR", "XNOR", "EQ", "NEQ", "CASEEQ", "CASENEQ", "LT", "LTE", "GT",
    "GTE", "SHL", "SHR", "ASHL", "ASHR", "ROL", "ROR", "REDAND", "REDOR",
    "REDXOR", "REDXNOR", "REDNOR", "REDNAND", "COND", "MUX", "PMUX",
    "CASE", "CASEZ", "CASEX", "IF", "UNIQUE", "PRIORITY",
    # Verilator emits signed/operator-specialized spellings after width and
    # signedness lowering.  Keep them in the structural model instead of
    # silently treating the operation as a wire.
    "ARRAYSEL", "GTS", "LTES", "GTES", "MULS", "DIVS", "MODDIVS",
    "CONCAT",
}
MUX_TYPES = {"COND", "MUX", "PMUX", "CASE", "CASEZ", "CASEX", "IF"}
ASSOCIATIVE_TYPES = {"AND", "OR", "XOR", "XNOR", "REDAND", "REDOR", "REDXOR", "REDXNOR"}

# These nodes are elaboration/typing aliases, not different hardware.  The
# aliases are normalized for depth accounting while their original spelling
# remains visible in operator statistics.
OPERATOR_ALIASES = {
    "GTS": "GT", "GTES": "GTE", "LTES": "LTE", "MULS": "MUL",
    "DIVS": "DIV", "MODDIVS": "MOD",
}


def operator_depth_cost(node: dict[str, Any], index: dict[str, dict[str, Any]]) -> int:
    """Return a conservative FPGA-structure cost for one AST operator.

    Constant packed selects and concatenations are wiring and should not
    inflate timing depth.  Dynamic unpacked-array selects (the common LUTRAM
    read-address form) do have a mux/decode cost.  Specialized signed
    operators are charged like their ordinary counterparts.
    """
    kind = str(node.get("type", "")).upper()
    if kind == "CONCAT":
        return 0
    if kind == "SEL":
        # SEL is intentionally outside OPERATOR_TYPES.  A fixed packed slice
        # is a wire; a variable part-select is represented by a different
        # Verilator node and is handled below.
        return 0
    if kind == "ARRAYSEL":
        bit_nodes = node.get("bitp", [])
        dynamic = any(item.get("type") != "CONST" for item in walk(bit_nodes))
        if not dynamic:
            return 0
        source = (node.get("fromp") or [{}])[0]
        dtype = index.get(source.get("dtypep", "")) if source else None
        shape = dtype_shape(dtype, index) if dtype else {"array_elements": None}
        elements = shape.get("array_elements") or 2
        return max(1, math.ceil(math.log2(max(2, elements))))
    return 1


def walk(node: Any) -> Iterable[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def node_name(node: dict[str, Any] | None) -> str | None:
    if not node:
        return None
    return node.get("origName") or node.get("verilogName") or node.get("name")


def literal_int(node: dict[str, Any] | None) -> int | None:
    """Read the constant spellings emitted by Verilator (32'h3, 4'sh-1, ...)."""
    if not node or node.get("type") != "CONST":
        return None
    text = str(node.get("name", "")).replace("_", "")
    match = re.search(r"(?:\d+)?'s?[hH]([0-9a-fA-F]+)$", text)
    if match:
        return int(match.group(1), 16)
    match = re.search(r"(?:\d+)?'s?[dD](-?\d+)$", text)
    if match:
        return int(match.group(1), 10)
    match = re.fullmatch(r"-?\d+", text)
    return int(text, 10) if match else None


def range_extent(range_node: dict[str, Any] | None) -> int | None:
    if not range_node:
        return None
    left = (range_node.get("leftp") or [{}])[0]
    right = (range_node.get("rightp") or [{}])[0]
    left_value = literal_int(left)
    right_value = literal_int(right)
    if left_value is None or right_value is None:
        return None
    return abs(left_value - right_value) + 1


def dtype_width(dtype: dict[str, Any] | None, index: dict[str, dict[str, Any]], seen: set[str] | None = None) -> int | None:
    if not dtype:
        return None
    seen = set() if seen is None else seen
    addr = dtype.get("addr")
    if addr and addr in seen:
        return None
    if addr:
        seen.add(addr)
    kind = dtype.get("type", "")

    if kind == "BASICDTYPE":
        extents = [range_extent(item) for item in dtype.get("rangep", [])]
        if extents and all(item is not None for item in extents):
            return product(item for item in extents if item is not None)
        raw_range = str(dtype.get("range", ""))
        match = re.fullmatch(r"\s*(-?\d+)\s*:\s*(-?\d+)\s*", raw_range)
        if match:
            return abs(int(match.group(1)) - int(match.group(2))) + 1
        if str(dtype.get("keyword", "")).lower() in {"integer", "time"}:
            return 32
        return int(dtype.get("widthConst", 1) or 1)

    if kind in {"REFDTYPE", "MEMBERDTYPE"}:
        target = index.get(dtype.get("refDTypep", ""))
        return dtype_width(target, index, seen)

    if kind == "ENUMDTYPE":
        target = index.get(dtype.get("refDTypep", ""))
        width = dtype_width(target, index, seen)
        if width:
            return width
        values = []
        for item in dtype.get("itemsp", []):
            for value in item.get("valuep", []):
                value_text = str(value.get("name", ""))
                match = re.match(r"(\d+)'", value_text)
                if match:
                    values.append(int(match.group(1)))
        return max(values, default=1)

    if kind == "STRUCTDTYPE":
        widths = []
        for member in dtype.get("membersp", []):
            member_type = index.get(member.get("refDTypep", ""))
            width = dtype_width(member_type, index, seen.copy())
            if width is None:
                return None
            widths.append(width)
        return sum(widths) if widths else 0

    if kind in {"PACKARRAYDTYPE", "UNPACKARRAYDTYPE"}:
        extent = 1
        for item in dtype.get("rangep", []):
            item_extent = range_extent(item)
            if item_extent is None:
                extent = None
                break
            extent *= item_extent
        target_width = dtype_width(index.get(dtype.get("refDTypep", "")), index, seen)
        if extent is None or target_width is None:
            return None
        return extent * target_width

    if dtype.get("widthConst") is not None:
        return int(dtype["widthConst"])
    target = index.get(dtype.get("refDTypep", "") or dtype.get("dtypep", ""))
    return dtype_width(target, index, seen) if target and target is not dtype else None


def product(values: Iterable[int]) -> int:
    result = 1
    for value in values:
        result *= value
    return result


def dtype_shape(dtype: dict[str, Any] | None, index: dict[str, dict[str, Any]]) -> dict[str, Any]:
    if not dtype:
        return {"kind": "unknown", "width_bits": None, "array_extents": []}
    extents = []
    current = dtype
    seen: set[str] = set()
    while current and current.get("addr") not in seen:
        addr = current.get("addr")
        if addr:
            seen.add(addr)
        kind = current.get("type", "")
        if kind in {"PACKARRAYDTYPE", "UNPACKARRAYDTYPE"}:
            for item in current.get("rangep", []):
                extents.append(range_extent(item))
            current = index.get(current.get("refDTypep", ""))
        elif kind in {"REFDTYPE", "MEMBERDTYPE"}:
            current = index.get(current.get("refDTypep", ""))
        else:
            break
    return {
        "kind": dtype.get("type", "unknown"),
        "type_name": dtype.get("name") or dtype.get("keyword"),
        "width_bits": dtype_width(dtype, index),
        "array_extents": extents,
        "array_elements": product(item for item in extents if item is not None) if extents and all(item is not None for item in extents) else None,
        "packed": bool(dtype.get("packed", False)),
    }


def var_refs(node: Any, index: dict[str, dict[str, Any]], access: str | None = None) -> list[dict[str, Any]]:
    refs = []
    for item in walk(node):
        if item.get("type") != "VARREF":
            continue
        if access and item.get("access") != access:
            continue
        ref = index.get(item.get("varp", ""), item)
        refs.append({
            "addr": item.get("varp", ""),
            "name": node_name(ref) or item.get("name"),
            "access": item.get("access"),
            "loc": item.get("loc"),
        })
    return refs


def refs_from_nodes(nodes: Iterable[dict[str, Any]], index: dict[str, dict[str, Any]], access: str | None = None) -> list[dict[str, Any]]:
    """Extract references from an already flattened node list."""
    # Statement fields such as IF.condp/CASE.exprp are emitted as one dict,
    # while module/always scans pass an already flattened list.  Accept both
    # forms without recursively walking the flattened list (which would count
    # every child reference multiple times).
    iterable: Iterable[dict[str, Any]] = walk(nodes) if isinstance(nodes, dict) else nodes
    refs = []
    for item in iterable:
        if item.get("type") != "VARREF" or (access and item.get("access") != access):
            continue
        ref = index.get(item.get("varp", ""), item)
        refs.append({
            "addr": item.get("varp", ""),
            "name": node_name(ref) or item.get("name"),
            "access": item.get("access"),
            "loc": item.get("loc"),
        })
    return refs


def unique_refs(refs: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    result = {}
    for ref in refs:
        if ref.get("addr"):
            result[ref["addr"]] = ref
    return list(result.values())


def node_width(node: dict[str, Any] | None, index: dict[str, dict[str, Any]]) -> int | None:
    """Return the elaborated width attached to an expression node."""
    if not node:
        return None
    width = node.get("widthConst")
    if width is not None:
        try:
            return max(1, int(width))
        except (TypeError, ValueError):
            pass
    dtype = index.get(node.get("dtypep", ""))
    return dtype_width(dtype, index) if dtype else None


def expression_children(node: dict[str, Any]) -> list[dict[str, Any]]:
    children = []
    for key, value in node.items():
        if key in {"dtypep", "addr", "loc", "name", "varp", "varScopep", "classOrPackagep"}:
            continue
        if isinstance(value, dict):
            children.append(value)
        elif isinstance(value, list):
            children.extend(item for item in value if isinstance(item, dict))
    return children


def associative_operands(node: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    operands = []
    for child in expression_children(node):
        if str(child.get("type", "")).upper() == kind:
            operands.extend(associative_operands(child, kind))
        else:
            operands.append(child)
    return operands


def expression_depth(node: Any, index: dict[str, dict[str, Any]]) -> int:
    """Estimate implementation depth, balancing associative reductions.

    Verilator preserves source associativity.  FPGA synthesis normally builds
    balanced trees for long OR/AND/XOR reductions, so raw AST nesting would
    greatly overstate their depth (notably opcode decode and bitmanip logic).
    """
    if isinstance(node, list):
        return max((expression_depth(item, index) for item in node), default=0)
    if not isinstance(node, dict):
        return 0
    kind = str(node.get("type", "")).upper()
    children = expression_children(node)
    if kind not in OPERATOR_TYPES:
        return max((expression_depth(child, index) for child in children), default=0)
    if kind in ASSOCIATIVE_TYPES:
        operands = associative_operands(node, kind)
        reduction_depth = max(1, math.ceil(math.log2(max(2, len(operands)))))
        return reduction_depth + max((expression_depth(child, index) for child in operands), default=0)
    return operator_depth_cost(node, index) + max((expression_depth(child, index) for child in children), default=0)


def expression_metrics(node: Any, index: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Summarize an elaborated expression without pretending it is a netlist."""
    operators = 0
    conditionals = 0
    max_width = 0
    max_depth = 0
    weighted_work = 0

    def visit(item: Any, depth: int = 0) -> None:
        nonlocal operators, conditionals, max_width, max_depth, weighted_work
        if not isinstance(item, dict):
            if isinstance(item, list):
                for child in item:
                    visit(child, depth)
            return
        kind = str(item.get("type", "")).upper()
        width = node_width(item, index) or 1
        if kind in OPERATOR_TYPES:
            cost = operator_depth_cost(item, index)
            operators += 1
            max_width = max(max_width, width)
            max_depth = max(max_depth, depth + cost)
            weighted_work += width * cost
            if kind in MUX_TYPES:
                conditionals += 1
        for key, value in item.items():
            if key in {"dtypep", "addr", "loc", "name", "varp", "varScopep", "classOrPackagep"}:
                continue
            visit(value, depth + (operator_depth_cost(item, index) if kind in OPERATOR_TYPES else 0))

    visit(node)
    max_depth = expression_depth(node, index)
    return {
        "operator_count": operators,
        "operator_depth": max_depth,
        "conditional_count": conditionals,
        "max_expression_width": max_width or None,
        "weighted_combination_work": weighted_work,
    }


def guarded_assignment_context(
    always: dict[str, Any],
    index: dict[str, dict[str, Any]],
) -> tuple[dict[str, set[str]], dict[str, int], dict[str, dict[str, int]]]:
    """Map each sequential assignment to enclosing if/case control signals.

    The tree JSON keeps an ``IF.condp`` or ``CASE.exprp`` outside the
    ASSIGNDLY RHS, so a plain RHS scan misses CE/enable paths.  Preserve the
    guard context while walking statement branches.  This is an intentional
    structural approximation; reset and generated unique-case checks remain
    visible and can be filtered by the caller if needed.
    """
    result: dict[str, set[str]] = defaultdict(set)
    depths: dict[str, int] = defaultdict(int)
    control_depths: dict[str, dict[str, int]] = defaultdict(dict)

    def visit(
        node: Any,
        guards: set[str],
        guard_depth: int,
        inherited_costs: dict[str, int],
    ) -> None:
        if isinstance(node, list):
            for item in node:
                visit(item, guards, guard_depth, inherited_costs)
            return
        if not isinstance(node, dict):
            return
        kind = str(node.get("type", "")).upper()
        if kind in ASSIGN_TYPES:
            addr = node.get("addr")
            if addr:
                result[addr].update(guards)
                depths[addr] = max(depths[addr], guard_depth)
                for source in guards:
                    control_depths[addr][source] = max(
                        control_depths[addr].get(source, 0),
                        inherited_costs.get(source, 1),
                    )
            return
        if kind == "IF":
            conds = {
                ref["addr"]
                for ref in refs_from_nodes(walk(node.get("condp", [])), index, "RD")
                if ref.get("addr")
            }
            branch_guards = guards | conds
            condition_cost = max(1, expression_depth(node.get("condp", []), index))
            branch_costs = dict(inherited_costs)
            for source in conds:
                branch_costs[source] = max(branch_costs.get(source, 0), condition_cost)
            branch_depth = guard_depth + condition_cost
            visit(node.get("thensp", []), branch_guards, branch_depth, branch_costs)
            visit(node.get("elsesp", []), branch_guards, branch_depth, branch_costs)
            return
        if kind == "CASE":
            conds = {
                ref["addr"]
                for ref in refs_from_nodes(walk(node.get("exprp", [])), index, "RD")
                if ref.get("addr")
            }
            condition_cost = max(1, expression_depth(node.get("exprp", []), index))
            case_costs = dict(inherited_costs)
            for source in conds:
                case_costs[source] = max(case_costs.get(source, 0), condition_cost)
            case_depth = guard_depth + condition_cost
            visit(node.get("itemsp", []), guards | conds, case_depth, case_costs)
            return
        if kind == "CASEITEM":
            visit(node.get("stmtsp", []), guards, guard_depth, inherited_costs)
            return
        # Avoid Verilator's generated unique-case assertion tree, which is a
        # second copy of the same assignment context.
        for key, value in node.items():
            if key in {"dtypep", "addr", "loc", "name", "varp", "varScopep", "classOrPackagep", "notParallelp"}:
                continue
            visit(value, guards, guard_depth, inherited_costs)

    visit(always, set(), 0, {})
    return result, depths, control_depths


def tarjan(graph: dict[str, set[str]]) -> list[list[str]]:
    index_counter = 0
    indices: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    stack: list[str] = []
    on_stack: set[str] = set()
    components: list[list[str]] = []

    def visit(node: str) -> None:
        nonlocal index_counter
        indices[node] = index_counter
        lowlink[node] = index_counter
        index_counter += 1
        stack.append(node)
        on_stack.add(node)
        for target in graph.get(node, ()):
            if target not in indices:
                visit(target)
                lowlink[node] = min(lowlink[node], lowlink[target])
            elif target in on_stack:
                lowlink[node] = min(lowlink[node], indices[target])
        if lowlink[node] == indices[node]:
            component = []
            while True:
                target = stack.pop()
                on_stack.remove(target)
                component.append(target)
                if target == node:
                    break
            components.append(component)

    for node in graph:
        if node not in indices:
            visit(node)
    return components


def loc_line(loc: str | None) -> int | None:
    match = re.search(r",(\d+):", str(loc or ""))
    return int(match.group(1)) if match else None


def loop_bound(loop: dict[str, Any], index: dict[str, dict[str, Any]]) -> dict[str, Any]:
    test = next((item for item in walk(loop) if item.get("type") == "LOOPTEST"), None)
    if not test:
        return {"static": False, "bound": None, "condition": None}
    constants = [literal_int(item) for item in walk(test) if item.get("type") == "CONST"]
    refs = unique_refs(var_refs(test, index, "RD"))
    bound = constants[-1] if constants else None
    return {
        "static": bound is not None,
        "bound": bound,
        "condition": test.get("loc"),
        "induction_vars": [item["name"] for item in refs],
        "estimated_iterations": bound if bound is not None and bound >= 0 else None,
    }


def module_report(module: dict[str, Any], index: dict[str, dict[str, Any]], module_status: dict[str, dict[str, Any]]) -> dict[str, Any]:
    module_name = node_name(module) or "<unknown>"
    elaborated_name = str(module.get("name") or module_name)
    module_nodes = list(walk(module))
    # A Verilator MODULE owns declarations in its statement tree.  De-duplicate
    # by address because declarations can be reached through pin metadata too.
    variables_by_addr = {}
    for item in module_nodes:
        if item.get("type") == "VAR" and item.get("addr"):
            variables_by_addr[item["addr"]] = item
    variables = list(variables_by_addr.values())
    var_names = {addr: node_name(item) or addr for addr, item in variables_by_addr.items()}
    # In Verilator 5.x ordinary SV module ports are commonly represented as
    # ``direction=OUTPUT,varType=WIRE``.  Restricting this to varType=PORT
    # silently dropped the outputs of most RTL modules and made Q-to-output
    # paths look like unconnected internal sinks.
    outputs = {
        addr: var_names[addr]
        for addr, item in variables_by_addr.items()
        if item.get("direction") == "OUTPUT" and item.get("varType") in {"PORT", "WIRE"}
    }
    inputs = {addr for addr, item in variables_by_addr.items() if item.get("direction") == "INPUT"}

    graph: dict[str, set[str]] = defaultdict(set)
    reverse: dict[str, set[str]] = defaultdict(set)
    edge_weight: dict[tuple[str, str], int] = {}
    reads: Counter[str] = Counter()
    consumers: dict[str, set[str]] = defaultdict(set)
    seq_lhs: set[str] = set()
    sequential_control_registers: dict[str, set[str]] = defaultdict(set)
    writes: Counter[str] = Counter()
    assignment_count = Counter()
    always_summary = []
    expression_summary = []
    sequential_assignments = []
    self_feedback = []
    partial_feedback = []
    procedural_reassignments = []
    latch_like = []
    block_dependency_edges: list[tuple[str, str, str]] = []
    sensitivity_edges: set[tuple[str, str]] = set()

    def add_edge(source: str, target: str, consumer: str | None = None, weight: int = 0) -> None:
        graph[source].add(target)
        reverse[target].add(source)
        edge_weight[(source, target)] = max(edge_weight.get((source, target), 0), max(0, weight))
        if consumer:
            consumers[source].add(consumer)

    # Capture reset context at the always block level and all assignment edges.
    for always in [item for item in module_nodes if item.get("type") == "ALWAYS"]:
        keyword = always.get("keyword", "always")
        always_nodes = list(walk(always))
        assignments = [item for item in always_nodes if item.get("type") in ASSIGN_TYPES]
        guard_controls, guard_depths, guard_costs = guarded_assignment_context(always, index)
        reset_like = any(re.search(r"(?:^|_)(?:rst|reset)(?:_|$)", ref["name"], re.I) for ref in refs_from_nodes(always_nodes, index) if ref.get("name"))
        always_lhs = set()
        assigned_before: set[str] = set()
        for assignment in assignments:
            assignment_count[assignment.get("type", "ASSIGN")] += 1
            assignment_metrics = expression_metrics(assignment.get("rhsp", []), index)
            lhs = unique_refs(var_refs(assignment.get("lhsp", []), index, "WR"))
            rhs = unique_refs(var_refs(assignment.get("rhsp", []), index, "RD"))
            lhs_addrs = {item["addr"] for item in lhs if item.get("addr") in variables_by_addr}
            rhs_addrs = {item["addr"] for item in rhs if item.get("addr") in variables_by_addr}
            guard_addrs = {
                addr
                for addr in guard_controls.get(assignment.get("addr"), ())
                if addr in variables_by_addr
            }
            for target in lhs_addrs:
                writes[target] += 1
                always_lhs.add(target)
                if assignment.get("type") == "ASSIGNDLY":
                    seq_lhs.add(target)
                if target in rhs_addrs and assignment.get("type") != "ASSIGNDLY":
                    lhs_root = (assignment.get("lhsp") or [{}])[0]
                    item = {
                        "signal": var_names.get(target, target),
                        "loc": assignment.get("loc"),
                        "assignment_type": assignment.get("type"),
                    }
                    if (
                        keyword in {"always_comb", "always_latch", "always"}
                        and lhs_root.get("type") == "VARREF"
                        and target in assigned_before
                    ):
                        # A procedural temporary is commonly initialized and
                        # then conditionally overwritten.  Collapsing all
                        # versions to one signal would manufacture a false
                        # SCC (selected_idx/selected_valid in issue logic).
                        procedural_reassignments.append(item)
                    elif lhs_root.get("type") == "VARREF":
                        self_feedback.append(item)
                    else:
                        partial_feedback.append(item)
                    latch_like.append(item)
                for source in rhs_addrs:
                    if assignment.get("type") != "ASSIGNDLY":
                        # A packed-field assignment has VARREFs below a SEL;
                        # treating it as whole-variable feedback creates a
                        # false SCC when different fields are initialized.
                        lhs_root = (assignment.get("lhsp") or [{}])[0]
                        if source == target and lhs_root.get("type") != "VARREF":
                            continue
                        if (
                            source == target
                            and keyword in {"always_comb", "always_latch", "always"}
                            and lhs_root.get("type") == "VARREF"
                            and target in assigned_before
                        ):
                            continue
                        add_edge(
                            source,
                            target,
                            f"assign:{assignment.get('loc', '')}",
                            assignment_metrics["operator_depth"],
                        )
                # An enclosing if/case is part of the combinational cone even
                # though the condition is outside the assignment RHS in the
                # Verilator tree.  This is essential for paths such as
                # head_accept_ready -> eligible -> selected_idx -> ctx_raddr.
                if assignment.get("type") != "ASSIGNDLY":
                    for source in guard_addrs:
                        if (
                            source == target
                            and keyword in {"always_comb", "always_latch", "always"}
                            and target in assigned_before
                        ):
                            continue
                        add_edge(
                            source,
                            target,
                            f"guard:{assignment.get('loc', '')}",
                            # Guard evaluation plus the mux/priority select
                            # introduced by the conditional assignment.
                            max(1, guard_costs.get(assignment.get("addr"), {}).get(source, 1)) + 2,
                        )
            for source in rhs_addrs:
                consumers[source].add(f"assign:{assignment.get('loc', '')}")
            for source in guard_addrs:
                consumers[source].add(f"guard:{assignment.get('loc', '')}")
            assigned_before.update(lhs_addrs)
            if assignment.get("type") != "ASSIGNDLY":
                metrics = assignment_metrics
                if metrics["operator_count"]:
                    lhs_names = [item["name"] for item in lhs if item.get("name")]
                    expression_summary.append({
                        "lhs": lhs_names,
                        "loc": assignment.get("loc"),
                        **metrics,
                    })
            else:
                sequential_assignments.append({
                    "addr": assignment.get("addr"),
                    "lhs": [item["addr"] for item in lhs if item.get("addr") in variables_by_addr],
                    "rhs": [item["addr"] for item in rhs if item.get("addr") in variables_by_addr],
                    "control_addrs": sorted(
                        control
                        for control in guard_controls.get(assignment.get("addr"), ())
                        if control in variables_by_addr
                    ),
                    "controls": sorted(
                        var_names.get(control, control)
                        for control in guard_controls.get(assignment.get("addr"), ())
                        if control in variables_by_addr
                    ),
                    "loc": assignment.get("loc"),
                    **assignment_metrics,
                })
            if assignment.get("type") == "ASSIGNDLY":
                for control in guard_controls.get(assignment.get("addr"), ()):
                    if control in variables_by_addr:
                        for target in lhs_addrs:
                            sequential_control_registers[control].add(var_names.get(target, target))
        # Verilator's UNOPTFLAT check also models a combinational process as a
        # sensitivity dependency.  A continuous wire read inside an
        # always_comb can therefore close a loop through a signal assigned in
        # that process even when no single assignment has the reverse edge
        # (for example: selected_valid -> issue_fire -> selected_valid).
        # Preserve that structural dependency for loop detection, but do not
        # add reads of signals assigned by the same process: those are already
        # represented by their assignment-level edges and connecting every
        # procedural temporary to every LHS would create false SCCs.
        if keyword in {"always_comb", "always_latch", "always"} and not any(
            item.get("type") == "ASSIGNDLY" for item in assignments
        ):
            block_reads = {
                ref.get("addr")
                for ref in refs_from_nodes(always_nodes, index, "RD")
                if ref.get("addr") in variables_by_addr and ref.get("addr") not in always_lhs
            }
            for source in block_reads:
                for target in always_lhs:
                    if source != target:
                        block_dependency_edges.append((
                            source,
                            target,
                            f"always:{always.get('loc', '')}",
                        ))
        if assignments:
            always_summary.append({
                "keyword": keyword,
                "loc": always.get("loc"),
                "assignment_count": len(assignments),
                "lhs_count": len(always_lhs),
                "reset_like": reset_like,
                "registered_lhs": sorted(var_names.get(item, item) for item in always_lhs if item in seq_lhs),
            })

    # Cell pins expose module-to-module connections.  Pseudo nodes keep those
    # edges visible without pretending a child instance is a combinational gate.
    cell_outputs: dict[str, dict[str, Any]] = {}
    cell_inputs: set[str] = set()
    cell_connections = []
    cell_bindings = []
    for cell in [item for item in module_nodes if item.get("type") == "CELL" and item.get("pinsp")]:
        instance_name = cell.get("origName") or cell.get("name") or "<cell>"
        child_module = index.get(cell.get("modp", ""), {})
        child_name = node_name(child_module) or instance_name
        child_elaborated_name = str(child_module.get("name") or child_name)
        for pin in cell.get("pinsp", []):
            child_var = index.get(pin.get("modVarp", ""), {})
            direction = child_var.get("direction")
            pin_name = pin.get("name") or "<pin>"
            pseudo = f"{PSEUDO_PREFIX}{instance_name}.{pin_name}"
            refs = unique_refs(var_refs(pin.get("exprp", []), index))
            cell_bindings.append({
                "instance": instance_name,
                "child": child_name,
                "child_elaborated_name": child_elaborated_name,
                "pin": pin_name,
                "direction": direction or "unknown",
                "child_var_addr": pin.get("modVarp", ""),
                "signal_addrs": sorted(
                    ref["addr"] for ref in refs
                    if ref.get("addr") in variables_by_addr
                ),
            })
            cell_connections.append({
                "instance": instance_name,
                "module": child_name,
                "pin": pin_name,
                "direction": direction or "unknown",
                "signals": sorted(ref["name"] for ref in refs if ref.get("name")),
            })
            if direction == "OUTPUT":
                cell_outputs[pseudo] = {
                    "child": child_name,
                    "child_elaborated_name": child_elaborated_name,
                    "pin": pin_name,
                    "signals": sorted(ref["name"] for ref in refs if ref.get("name")),
                }
                for ref in refs:
                    if ref.get("addr") in variables_by_addr:
                        add_edge(pseudo, ref["addr"], f"cell:{instance_name}.{pin_name}")
            elif direction == "INPUT":
                cell_inputs.add(pseudo)
                for ref in refs:
                    if ref.get("addr") in variables_by_addr:
                        add_edge(ref["addr"], pseudo, f"cell:{instance_name}.{pin_name}")
                        consumers[ref["addr"]].add(f"cell:{instance_name}.{pin_name}")

    # A process-level sensitivity edge is needed only when assignment-level
    # edges already provide the return path.  Adding every read-to-LHS pair
    # would connect unrelated outputs in a large always_comb and distort the
    # reported depth.  This bounded reachability check adds exactly the edge
    # that closes an existing path, while every node is still visited at most
    # once per candidate pair.
    def reaches(start: str, goal: str) -> bool:
        pending = [start]
        seen: set[str] = set()
        while pending:
            current = pending.pop()
            if current == goal:
                return True
            if current in seen:
                continue
            seen.add(current)
            pending.extend(graph.get(current, ()))
        return False

    for source, target, consumer in block_dependency_edges:
        if source != target and reaches(target, source):
            add_edge(source, target, consumer, 0)
            sensitivity_edges.add((source, target))

    # Count elaborated read references.  The AST is already expanded, so this
    # is the useful first-order fanout estimate; ``unique_consumers`` keeps the
    # assignment/cell-site view for triage.
    for ref in refs_from_nodes(module_nodes, index, "RD"):
        addr = ref.get("addr")
        if addr in variables_by_addr:
            reads[addr] += 1

    loops = [loop_bound(item, index) | {"loc": item.get("loc")} for item in module_nodes if item.get("type") == "LOOP"]
    loop_var_names = {name for item in loops for name in item.get("induction_vars", [])}
    loop_var_addrs = {addr for addr, name in var_names.items() if name in loop_var_names}
    # Loop counters are elaboration temporaries, not hardware signals.  Remove
    # their graph nodes before SCC and depth analysis.
    for addr in loop_var_addrs:
        graph.pop(addr, None)
        reverse.pop(addr, None)
    for targets in graph.values():
        targets.difference_update(loop_var_addrs)
    for sources in reverse.values():
        sources.difference_update(loop_var_addrs)

    nodes = set(graph)
    nodes.update(target for targets in graph.values() for target in targets)
    components = tarjan({node: set(graph.get(node, ())) for node in nodes})
    cycles = []
    true_cycles = []
    cycle_components: list[tuple[int, dict[str, Any]]] = []
    component_of = {}
    for number, component in enumerate(components):
        for item in component:
            component_of[item] = number
        if len(component) > 1 or any(item in graph.get(item, set()) for item in component):
            names = [var_names.get(item, item) for item in component]
            members = set(component)
            value_graph = {
                source: {
                    target
                    for target in graph.get(source, set())
                    if target in members and (source, target) not in sensitivity_edges
                }
                for source in members
            }
            value_components = tarjan(value_graph)
            value_cycle = any(
                len(part) > 1 or any(item in value_graph.get(item, set()) for item in part)
                for part in value_components
            )
            internal_sensitivity_edges = sorted(
                (
                    var_names.get(source, source),
                    var_names.get(target, target),
                )
                for source, target in sensitivity_edges
                if source in members and target in members
            )
            sensitivity_witness = []
            for source in sorted({item[0] for item in internal_sensitivity_edges}):
                candidates = {
                    target
                    for left, target in internal_sensitivity_edges
                    if left == source
                }
                frontier = {
                    target
                    for target in candidates
                    if not any(
                        target != other and reaches(target, other)
                        for other in candidates
                    )
                }
                sensitivity_witness.extend(
                    (var_names.get(source, source), var_names.get(target, target))
                    for target in sorted(frontier)
                )
            cycle = {
                "signals": sorted(names),
                "size": len(component),
                "kind": (
                    "mixed"
                    if value_cycle and internal_sensitivity_edges
                    else ("value" if value_cycle else "sensitivity")
                ),
                "sensitivity_edges": [
                    {"source": source, "target": target}
                    for source, target in internal_sensitivity_edges
                ],
                "sensitivity_witness": [
                    {"source": source, "target": target}
                    for source, target in sensitivity_witness
                ],
                "sensitivity_witness_path": [
                    [target, source]
                    for source, target in sensitivity_witness
                ],
            }
            cycles.append(cycle)
            cycle_components.append((number, cycle))
            if len(component) > 1:
                true_cycles.append(cycle)

    # Longest combinational path on the SCC condensation graph.  Sequential
    # destinations are sources for the next cycle and do not add logic depth.
    dag: dict[int, set[int]] = defaultdict(set)
    indegree: Counter[int] = Counter()
    for source, targets in graph.items():
        for target in targets:
            left, right = component_of[source], component_of[target]
            if left != right and right not in dag[left]:
                dag[left].add(right)
                indegree[right] += 1

    def component_edge_cost(left: int, right: int) -> int:
        if any(item in seq_lhs for item in components[left]):
            return 0
        weights = [
            edge_weight[(source, target)]
            for source in components[left]
            for target in components[right]
            if (source, target) in edge_weight
        ]
        return max(weights, default=1)

    queue = deque(number for number in range(len(components)) if indegree[number] == 0)
    depth = {number: 0 for number in range(len(components))}
    depth_parent: dict[int, int] = {}
    topo_order = []
    while queue:
        current = queue.popleft()
        topo_order.append(current)
        for target in dag.get(current, ()):
            edge_cost = component_edge_cost(current, target)
            candidate = depth[current] + edge_cost
            if candidate > depth[target]:
                depth[target] = candidate
                depth_parent[target] = current
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)

    # A signal on the RHS of a non-blocking assignment is a timing endpoint at
    # the destination flop's D pin.  Keep the reverse map so a Q-to-boundary
    # walk can distinguish a real register cut from an unconsumed temporary.
    sequential_rhs_registers: dict[str, set[str]] = defaultdict(set)
    for assignment in sequential_assignments:
        for source in assignment["rhs"]:
            for target in assignment["lhs"]:
                sequential_rhs_registers[source].add(var_names.get(target, target))

    # Reverse longest paths answer a different question from input-to-output
    # depth: how much combinational logic can a register Q drive before the
    # next register D, module boundary, child input, or dead internal sink?
    # A path can have more than one terminal; retain the longest terminal and
    # its endpoint kind for triage.
    forward_depth = {number: 0 for number in range(len(components))}
    forward_next: dict[int, int] = {}
    forward_endpoint: dict[int, str] = {}
    forward_endpoint_registers: dict[int, list[str]] = {}
    endpoint_priority = {
        "register_d": 5,
        "register_control": 4,
        "module_output": 3,
        "child_input": 2,
        "combinational_sink": 1,
    }

    def choose_forward_candidate(
        candidate: tuple[int, str, int | None, list[str] | None],
        best: tuple[int, str, int | None, list[str] | None] | None,
    ) -> tuple[int, str, int | None, list[str] | None]:
        if best is None or candidate[0] > best[0]:
            return candidate
        if candidate[0] == best[0] and endpoint_priority[candidate[1]] > endpoint_priority[best[1]]:
            return candidate
        return best

    for current in reversed(topo_order):
        candidates: list[tuple[int, str, int | None, list[str] | None]] = []
        members = set(components[current])
        if members & set(outputs):
            candidates.append((0, "module_output", None, None))
        if members & cell_inputs:
            candidates.append((0, "child_input", None, None))
        register_targets = sorted({
            target
            for source in members
            for target in sequential_rhs_registers.get(source, ())
        })
        if register_targets:
            candidates.append((0, "register_d", None, register_targets))
        control_targets = sorted({
            target
            for source in members
            for target in sequential_control_registers.get(source, ())
        })
        if control_targets:
            candidates.append((0, "register_control", None, control_targets))
        if not dag.get(current):
            candidates.append((0, "combinational_sink", None, None))
        for target in dag.get(current, ()):
            candidates.append((
                component_edge_cost(current, target) + forward_depth[target],
                forward_endpoint.get(target, "combinational_sink"),
                target,
                forward_endpoint_registers.get(target),
            ))
        selected = None
        for candidate in candidates:
            selected = choose_forward_candidate(candidate, selected)
        if selected is not None:
            forward_depth[current] = selected[0]
            forward_endpoint[current] = selected[1]
            if selected[2] is not None:
                forward_next[current] = selected[2]
            if selected[3]:
                forward_endpoint_registers[current] = selected[3]

    # Keep an independent longest path for every endpoint kind.  A register Q
    # can feed both a long internal D cone and a shorter module-output cone;
    # choosing only the globally longest terminal incorrectly reports the
    # output branch as absent.
    endpoint_kinds = tuple(endpoint_priority)
    endpoint_forward_depth: dict[str, dict[int, int]] = {
        endpoint: {number: -1 for number in range(len(components))}
        for endpoint in endpoint_kinds
    }
    endpoint_forward_next: dict[str, dict[int, int]] = {
        endpoint: {} for endpoint in endpoint_kinds
    }
    output_nodes = set(outputs)
    for current in reversed(topo_order):
        members = set(components[current])
        terminal_kinds = set()
        if members & output_nodes:
            terminal_kinds.add("module_output")
        if members & cell_inputs:
            terminal_kinds.add("child_input")
        if any(source in sequential_rhs_registers for source in members):
            terminal_kinds.add("register_d")
        if any(source in sequential_control_registers for source in members):
            terminal_kinds.add("register_control")
        if not dag.get(current):
            terminal_kinds.add("combinational_sink")
        for endpoint in endpoint_kinds:
            best = 0 if endpoint in terminal_kinds else -1
            best_target = None
            for target in dag.get(current, ()):
                target_depth = endpoint_forward_depth[endpoint][target]
                if target_depth < 0:
                    continue
                candidate = component_edge_cost(current, target) + target_depth
                if candidate > best:
                    best = candidate
                    best_target = target
            endpoint_forward_depth[endpoint][current] = best
            if best_target is not None:
                endpoint_forward_next[endpoint][current] = best_target

    def bounded_internal_depth(component: int) -> int:
        """Estimate one simple lap around an SCC, never revisiting a node.

        Repeated relaxation on a cyclic graph keeps adding positive edge
        weights and reports an invented depth (or loops forever).  A bounded
        simple-path walk is finite and matches the useful question here:
        how much distinct combinational logic is in one feedback lap?
        """
        members = set(components[component])
        if not members:
            return 0
        value_edges = {
            source: {
                target
                for target in graph.get(source, set())
                if target in members and (source, target) not in sensitivity_edges
            }
            for source in members
        }
        best = 0
        stack: list[tuple[str, frozenset[str], int]] = [
            (source, frozenset({source}), 0) for source in sorted(members)
        ]
        seen_states: set[tuple[str, frozenset[str]]] = set()
        state_limit = max(10000, len(members) * 4096)
        while stack and len(seen_states) < state_limit:
            source, visited, score = stack.pop()
            state = (source, visited)
            if state in seen_states:
                continue
            seen_states.add(state)
            best = max(best, score)
            for target in sorted(value_edges.get(source, ())):
                if target in visited:
                    continue
                stack.append((
                    target,
                    visited | {target},
                    score + edge_weight.get((source, target), 1),
                ))
        return best

    for component, cycle in cycle_components:
        cycle["entry_depth"] = depth.get(component, 0)
        cycle["internal_operator_depth"] = bounded_internal_depth(component)
        cycle["exit_depth"] = forward_depth.get(component, 0)
        cycle["timing_path_depth"] = cycle["entry_depth"] + cycle["exit_depth"]
        cycle["bounded_path_depth"] = (
            cycle["entry_depth"]
            + cycle["internal_operator_depth"]
            + cycle["exit_depth"]
        )
    variable_depth = {}
    for addr in nodes:
        component = component_of.get(addr)
        if component is not None:
            variable_depth[addr] = depth.get(component, 0)

    # Sequential assignment RHS edges are timing-path terminals.  They are
    # intentionally absent from the combinational SCC graph, but their
    # expression depth still belongs in the path ending at the destination D
    # pin.
    def reconstruct_upstream_path(addr: str) -> tuple[list[str], list[list[str]]]:
        component = component_of.get(addr)
        if component is None:
            return [var_names.get(addr, addr)], [[var_names.get(addr, addr)]]
        path = [component]
        while path[-1] in depth_parent:
            path.append(depth_parent[path[-1]])
        path.reverse()
        signals = []
        component_signals = []
        for item in path:
            names = sorted(var_names.get(node, node) for node in components[item])
            signals.append(names[0] if names else f"<scc:{item}>")
            component_signals.append(names[:16])
        return signals, component_signals

    def source_kind(source: str) -> str:
        if source in seq_lhs:
            return "register_q"
        if source in inputs:
            return "module_input"
        if source in cell_outputs:
            return "child_output"
        return "unknown"

    register_path_details = []
    for assignment in sequential_assignments:
        for target in assignment["lhs"]:
            sources = assignment["rhs"]
            source_depth = max((variable_depth.get(source, 0) for source in sources), default=0)
            critical_source = max(sources, key=lambda source: variable_depth.get(source, 0), default=None)
            path_signals, component_signals = reconstruct_upstream_path(critical_source) if critical_source else ([], [])
            kinds = {source_kind(source) for source in sources}
            if any(name in {var_names[item] for item in inputs} for name in path_signals):
                kinds.add("module_input")
            if any(name.startswith(PSEUDO_PREFIX) for name in path_signals):
                kinds.add("child_output")
            register_path_details.append({
                "register": var_names.get(target, target),
                "source_signals": sorted(var_names.get(source, source) for source in sources),
                "source_kind": sorted(kinds),
                "path_signals": path_signals + [var_names.get(target, target)],
                "path_component_signals": component_signals,
                "control_signals": assignment.get("controls", []),
                "depth": source_depth + assignment["operator_depth"],
                "operator_depth": assignment["operator_depth"],
                "loc": assignment.get("loc"),
            })

    # Vivado frequently reports a path ending at a flop CE pin rather than D.
    # Keep input/child-output paths to those controls separate from Q-to-D
    # paths.  Otherwise a long internal recovery cone can hide the actual
    # input-to-enable path when a module's ``max_depth`` is used as a timing
    # proxy.
    def path_source_kinds(path_signals: list[str], source_addrs: list[str] | None = None) -> set[str]:
        kinds: set[str] = set()
        source_names = set(path_signals[:1])
        if source_addrs:
            for addr in source_addrs:
                if addr in seq_lhs:
                    kinds.add("register_q")
                elif addr in inputs:
                    kinds.add("module_input")
                elif addr in cell_outputs:
                    kinds.add("child_output")
        if any(var_names.get(addr, addr) in source_names for addr in inputs):
            kinds.add("module_input")
        if any(var_names.get(addr, addr) in source_names for addr in seq_lhs):
            kinds.add("register_q")
        if any(name.startswith(PSEUDO_PREFIX) for name in source_names):
            kinds.add("child_output")
        return kinds or {"unknown"}

    control_path_details = []
    for control in sorted(sequential_control_registers, key=lambda item: var_names.get(item, item)):
        control_name = var_names.get(control, control)
        control_depth = variable_depth.get(control, 0)
        path_signals, component_signals = reconstruct_upstream_path(control)
        control_path_details.append({
            "control": control_name,
            "control_addr": control,
            "registers": sorted(sequential_control_registers[control]),
            "source_kind": sorted(path_source_kinds(path_signals, [control])),
            "depth": control_depth,
            "path_signals": path_signals,
            "path_component_signals": component_signals,
            "loc": var_names.get(control, control),
        })

    def max_path_depth(items: list[dict[str, Any]], *kinds: str) -> int:
        if not kinds:
            return max((item.get("depth", 0) for item in items), default=0)
        return max(
            (
                item.get("depth", 0)
                for item in items
                if any(kind in item.get("source_kind", []) for kind in kinds)
            ),
            default=0,
        )

    loop_product = 1
    static_loops = 0
    for item in loops:
        if item.get("estimated_iterations") is not None:
            static_loops += 1
            loop_product *= max(1, item["estimated_iterations"])

    def child_output_is_cut(pseudo: str) -> bool:
        child = cell_outputs.get(pseudo, {})
        child_report = resolve_child_report(
            child.get("child", ""), child.get("child_elaborated_name")
        )
        return child.get("pin") in set(child_report.get("registered_outputs", []))

    def resolve_child_report(
        child_name: str,
        child_elaborated_name: str | None = None,
    ) -> dict[str, Any]:
        report = module_status.get(child_elaborated_name or "") or module_status.get(child_name)
        if report:
            return report
        # Parameterized Verilator module names commonly have ``__`` suffixes.
        base = child_name.split("__", 1)[0]
        return module_status.get(base, {})

    # Module boundaries are not timing cuts by themselves.  Seed each child
    # output with the child's own output path depth, then propagate that depth
    # through the parent's condensation graph.  Registered child outputs seed
    # zero because the destination flop is the cut.
    boundary_paths = []
    boundary_depths: dict[str, int] = {}
    boundary_output_info: dict[str, dict[str, Any]] = {}
    for pseudo, child in cell_outputs.items():
        child_report = resolve_child_report(
            child.get("child", ""), child.get("child_elaborated_name")
        )
        child_output = next(
            (item for item in child_report.get("outputs", []) if item.get("name") == child.get("pin")),
            None,
        )
        if child_output is None:
            continue
        boundary_output_info[pseudo] = child_output
        cut = child_output.get("status") == "registered"
        path_depth = 0 if cut else int(child_output.get("path_depth") or 0)
        boundary_depths[pseudo] = path_depth
        boundary_paths.append({
            "instance": pseudo.split(".", 1)[0].removeprefix(PSEUDO_PREFIX),
            "child_module": child.get("child"),
            "pin": child.get("pin"),
            "parent_signals": child.get("signals", []),
            "cut": cut,
            "child_output_status": child_output.get("status", "unknown"),
            "child_path_depth": child_output.get("path_depth", 0),
            "seed_depth": path_depth,
        })

    cross_component_depth = {number: 0 for number in range(len(components))}
    for pseudo, seed in boundary_depths.items():
        component = component_of.get(pseudo)
        if component is not None:
            cross_component_depth[component] = max(cross_component_depth[component], seed)
    cross_indegree = Counter()
    for source, targets in dag.items():
        for target in targets:
            cross_indegree[target] += 1
    cross_queue = deque(number for number in range(len(components)) if cross_indegree[number] == 0)
    cross_parent: dict[int, int] = {}
    while cross_queue:
        current = cross_queue.popleft()
        for target in dag.get(current, ()):
            edge_cost = component_edge_cost(current, target)
            candidate = cross_component_depth[current] + edge_cost
            if candidate > cross_component_depth[target]:
                cross_component_depth[target] = candidate
                cross_parent[target] = current
            cross_indegree[target] -= 1
            if cross_indegree[target] == 0:
                cross_queue.append(target)
    cross_module_max_depth = max(cross_component_depth.values(), default=0)

    def reconstruct_component_path(
        depths: dict[int, int],
        parents: dict[int, int],
    ) -> dict[str, Any]:
        if not depths:
            return {"depth": 0, "signals": []}
        end = max(depths, key=lambda item: depths[item])
        components_path = [end]
        while components_path[-1] in parents:
            components_path.append(parents[components_path[-1]])
        components_path.reverse()
        signals = []
        for component in components_path:
            names = sorted(var_names.get(item, item) for item in components[component])
            signals.append(names[0] if names else f"<scc:{component}>")
        return {
            "depth": depths[end],
            "signals": signals,
            "component_count": len(components_path),
        }

    critical_local_path = reconstruct_component_path(depth, depth_parent)
    critical_cross_path = reconstruct_component_path(cross_component_depth, cross_parent)

    def reconstruct_parent_path(addr: str, parents: dict[int, int]) -> tuple[list[str], list[list[str]]]:
        component = component_of.get(addr)
        if component is None:
            name = var_names.get(addr, addr)
            return [name], [[name]]
        path = [component]
        while path[-1] in parents:
            path.append(parents[path[-1]])
        path.reverse()
        signals = []
        component_signals = []
        for item in path:
            names = sorted(var_names.get(node, node) for node in components[item])
            signals.append(names[0] if names else f"<scc:{item}>")
            component_signals.append(names[:16])
        return signals, component_signals

    def reconstruct_forward_path(addr: str) -> dict[str, Any]:
        component = component_of.get(addr)
        if component is None:
            return {"register": var_names.get(addr, addr), "depth": 0, "signals": []}
        components_path = [component]
        while components_path[-1] in forward_next:
            components_path.append(forward_next[components_path[-1]])
        signals = []
        component_signals = []
        for item in components_path:
            names = sorted(var_names.get(node, node) for node in components[item])
            signals.append(names[0] if names else f"<scc:{item}>")
            component_signals.append(names[:16])
        endpoint = forward_endpoint.get(component, "combinational_sink")
        return {
            "register": var_names.get(addr, addr),
            "depth": forward_depth.get(component, 0),
            "signals": signals,
            "component_signals": component_signals,
            "endpoint": endpoint,
            "endpoint_registers": forward_endpoint_registers.get(component, []),
        }

    def reconstruct_endpoint_path(addr: str, endpoint: str) -> dict[str, Any] | None:
        component = component_of.get(addr)
        if component is None or endpoint_forward_depth[endpoint].get(component, -1) < 0:
            return None
        components_path = [component]
        next_map = endpoint_forward_next[endpoint]
        while components_path[-1] in next_map:
            components_path.append(next_map[components_path[-1]])
        return {
            "register": var_names.get(addr, addr),
            "depth": endpoint_forward_depth[endpoint][component],
            "signals": [
                sorted(var_names.get(node, node) for node in components[item])[0]
                for item in components_path
                if components[item]
            ],
            "endpoint": endpoint,
        }

    register_to_boundary_paths = [reconstruct_forward_path(addr) for addr in seq_lhs]
    register_to_boundary_paths.sort(key=lambda item: (-item["depth"], item["register"]))
    register_to_endpoint_paths = {
        endpoint: sorted(
            (
                path
                for addr in seq_lhs
                if (path := reconstruct_endpoint_path(addr, endpoint)) is not None
            ),
            key=lambda item: (-item["depth"], item["register"]),
        )
        for endpoint in endpoint_kinds
    }
    register_to_boundary_by_endpoint = {
        endpoint: max((item["depth"] for item in paths), default=0)
        for endpoint, paths in register_to_endpoint_paths.items()
    }

    # Output status used to walk every reverse-graph path independently.  That
    # is quadratic on ordinary fan-in and can become effectively unbounded for
    # a real combinational loop.  Work on the SCC condensation DAG instead:
    # each SCC is visited once, cycles are atomic, and terminal reachability is
    # unioned independently from the single longest path retained for detail.
    reverse_dag: dict[int, set[int]] = defaultdict(set)
    for source, targets in dag.items():
        for target in targets:
            reverse_dag[target].add(source)

    component_terminal: dict[int, set[str]] = {}
    component_best_depth: dict[int, int] = {}
    component_best_path: dict[int, list[str]] = {}

    def component_rep(component: int) -> str:
        members = sorted(var_names.get(item, item) for item in components[component])
        return members[0] if members else f"<scc:{component}>"

    # topo_order is the source-to-sink order of the condensation DAG, so all
    # predecessor component summaries are available when processing a node.
    for component in topo_order:
        members = set(components[component])
        terminals: set[str] = set()
        candidates: list[tuple[int, int, list[str]]] = []
        representative = component_rep(component)

        register_members = sorted(members & seq_lhs)
        if register_members:
            terminals.add("register")
            candidates.append((0, 0, [var_names.get(register_members[0], register_members[0])]))

        input_members = sorted(members & inputs)
        if input_members:
            terminals.add("input")
            candidates.append((0, 1, [var_names.get(input_members[0], input_members[0])]))

        # Child outputs are leaves from the parent graph.  Their child-local
        # depth is already known from the second module-report pass.
        for pseudo in sorted(members & set(boundary_output_info)):
            child_output = boundary_output_info[pseudo]
            child_terminals = set(child_output.get("terminals", [])) or {"unknown"}
            terminals.update(child_terminals)
            candidates.append((
                int(child_output.get("path_depth") or 0),
                2,
                [var_names.get(pseudo, pseudo)],
            ))

        predecessor_components = reverse_dag.get(component, set())
        if not predecessor_components and not terminals:
            terminals.add("unknown")
        for predecessor in predecessor_components:
            predecessor_terminals = component_terminal.get(predecessor, {"unknown"})
            terminals.update(predecessor_terminals)
            edge_cost = component_edge_cost(predecessor, component)
            if any(item in seq_lhs for item in components[predecessor]):
                edge_cost = 0
            candidates.append((
                component_best_depth.get(predecessor, 0) + edge_cost,
                3,
                [representative] + component_best_path.get(predecessor, [component_rep(predecessor)]),
            ))

        if candidates:
            # Prefer greater depth, then a stable path tie-break.  Terminal
            # priority only breaks equal-depth alternatives deterministically.
            best_depth, _, best_path = max(
                candidates,
                key=lambda item: (item[0], -item[1], tuple(item[2])),
            )
        else:
            best_depth, best_path = 0, [representative]
        component_terminal[component] = terminals
        component_best_depth[component] = best_depth
        component_best_path[component] = best_path

    def output_path_status(output: str) -> tuple[str, int, set[str], list[str]]:
        component = component_of.get(output)
        output_name = var_names.get(output, output)
        if component is None:
            terminals = {"input"} if output in inputs else {"unknown"}
            status = "combinational" if terminals == {"input"} else "unknown"
            return status, 0, terminals, [output_name]
        terminals = set(component_terminal.get(component, {"unknown"}))
        path_depth = component_best_depth.get(component, 0)
        component_path = component_best_path.get(component, [component_rep(component)])
        # component_best_path is current-component to terminal.  Replace its
        # representative with the actual module output for a useful report.
        path_signals = [output_name]
        if component_path and component_path[0] != output_name:
            path_signals.extend(component_path[1:])
        elif len(component_path) > 1:
            path_signals.extend(component_path[1:])
        if terminals and terminals <= {"register"}:
            status = "registered"
        elif "input" in terminals:
            status = "combinational"
        else:
            status = "unknown"
        return status, path_depth, terminals, list(reversed(path_signals))

    output_reports = []
    for addr, name in sorted(outputs.items(), key=lambda item: item[1]):
        status, path_depth, terminals, path_signals = output_path_status(addr)
        output_reports.append({
            "name": name,
            "addr": addr,
            "status": status,
            "path_depth": path_depth,
            "terminals": sorted(terminals),
            "critical_path": path_signals,
            "width_bits": dtype_width(index.get(variables_by_addr[addr].get("dtypep", "")), index),
        })

    cross_register_path_details = []
    for assignment in sequential_assignments:
        for target in assignment["lhs"]:
            sources = assignment["rhs"]
            source_depth = max(
                (
                    cross_component_depth.get(component_of.get(source, -1), 0)
                    for source in sources
                ),
                default=0,
            )
            critical_source = max(
                sources,
                key=lambda source: cross_component_depth.get(component_of.get(source, -1), 0),
                default=None,
            )
            path_signals, component_signals = reconstruct_parent_path(critical_source, cross_parent) if critical_source else ([], [])
            kinds = {source_kind(source) for source in sources}
            if any(name in {var_names[item] for item in inputs} for name in path_signals):
                kinds.add("module_input")
            if any(name.startswith(PSEUDO_PREFIX) for name in path_signals):
                kinds.add("child_output")
            cross_register_path_details.append({
                "register": var_names.get(target, target),
                "source_signals": sorted(var_names.get(source, source) for source in sources),
                "source_kind": sorted(kinds),
                "path_signals": path_signals + [var_names.get(target, target)],
                "path_component_signals": component_signals,
                "control_signals": assignment.get("controls", []),
                "depth": source_depth + assignment["operator_depth"],
                "operator_depth": assignment["operator_depth"],
                "loc": assignment.get("loc"),
            })
    cross_graph_max_depth = max(cross_component_depth.values(), default=0)
    cross_output_path_max_depth = max((item["path_depth"] for item in output_reports), default=0)
    cross_register_path_max_depth = max((item["depth"] for item in cross_register_path_details), default=0)
    cross_endpoint_depths = [cross_output_path_max_depth, cross_register_path_max_depth]
    cross_module_max_depth = max(cross_endpoint_depths) if any(cross_endpoint_depths) else cross_graph_max_depth
    if cross_register_path_details:
        cross_register_critical = max(cross_register_path_details, key=lambda item: item["depth"])
        cross_signals = cross_register_critical.get("path_signals") or (cross_register_critical["source_signals"] + [cross_register_critical["register"]])
        critical_cross_path = {
            "depth": cross_register_critical["depth"],
            "signals": cross_signals,
            "component_count": len(cross_signals),
            "endpoint": "register_d",
        }
    elif output_reports:
        critical_output = max(output_reports, key=lambda item: item["path_depth"])
        critical_cross_path = {
            "depth": critical_output["path_depth"],
            "signals": [critical_output["name"]],
            "component_count": 1,
            "endpoint": "module_output",
        }
    if register_path_details:
        register_critical = max(register_path_details, key=lambda item: item["depth"])
        local_signals = register_critical.get("path_signals") or (register_critical["source_signals"] + [register_critical["register"]])
        critical_local_path = {
            "depth": register_critical["depth"],
            "signals": local_signals,
            "component_count": len(local_signals),
            "endpoint": "register_d",
        }
    elif output_reports:
        critical_output = max(output_reports, key=lambda item: item["path_depth"])
        critical_local_path = {
            "depth": critical_output["path_depth"],
            "signals": [critical_output["name"]],
            "component_count": 1,
            "endpoint": "module_output",
        }

    register_reports = []
    reset_lhs = set()
    for item in always_summary:
        if item["reset_like"]:
            reset_lhs.update(item["registered_lhs"])
    for addr in sorted(seq_lhs, key=lambda item: var_names.get(item, item)):
        var = variables_by_addr.get(addr)
        dtype = index.get(var.get("dtypep", "")) if var else None
        shape = dtype_shape(dtype, index)
        name = var_names.get(addr, addr)
        register_reports.append({
            "name": name,
            "addr": addr,
            **shape,
            "writes": writes[addr],
            "reset_like": name in reset_lhs,
        })
    multiwrite_register_arrays = [
        item for item in register_reports
        if (item.get("array_elements") or 0) >= 2
        and int(item.get("writes", 0)) >= 2
        and (item.get("width_bits") or 0) >= 64
    ]

    signal_reports = []
    for addr, var in sorted(variables_by_addr.items(), key=lambda item: var_names[item[0]]):
        dtype = index.get(var.get("dtypep", ""))
        signal_reports.append({
            "name": var_names[addr],
            "addr": addr,
            "direction": var.get("direction", "NONE"),
            "var_type": var.get("varType"),
            **dtype_shape(dtype, index),
            "register": addr in seq_lhs,
        })

    def signal_width(*names: str) -> int | None:
        wanted = set(names)
        return next(
            (int(item["width_bits"]) for item in signal_reports
             if item.get("name") in wanted and item.get("width_bits") is not None),
            None,
        )

    memory_geometry = None
    geometry_ports: tuple[tuple[str, ...], tuple[str, ...]] | None = None
    if module_name == "ydrasil_itcm":
        geometry_ports = (("itcm_addr",), ("itcm_data_o",))
    elif module_name == "ydrasil_dtcm":
        geometry_ports = (("dtcm_raddr", "dtcm_waddr"), ("dtcm_data_o", "dtcm_data_i"))
    elif module_name in {"ydrasil_1r1w_bram", "ydrasil_1r1w_ram", "ydrasil_1r1w_masked_ram"}:
        geometry_ports = (("raddr_i", "waddr_i"), ("rdata_o", "wdata_i"))
    if geometry_ports:
        address_width = signal_width(*geometry_ports[0])
        data_width = signal_width(*geometry_ports[1])
        if address_width is not None and data_width is not None:
            depth_words = 1 << address_width
            capacity_bits = depth_words * data_width
            memory_geometry = {
                "instance_model": elaborated_name,
                "address_width_bits": address_width,
                "data_width_bits": data_width,
                "depth_words": depth_words,
                "capacity_bits": capacity_bits,
                "capacity_bytes": capacity_bits // 8,
                "capacity_kib": capacity_bits / (8 * 1024),
                "derivation": "per_elaborated_instance_port_widths",
            }

    fanout_reports = []
    def transitive_read_estimate(addr: str) -> int:
        """Estimate downstream load work through combinational assignments."""
        pending = list(graph.get(addr, ()))
        visited: set[str] = set()
        estimate = 0
        while pending:
            current = pending.pop()
            if current in visited:
                continue
            visited.add(current)
            estimate += max(1, reads[current], len(consumers[current]))
            pending.extend(graph.get(current, ()))
        return estimate

    for addr, var in variables_by_addr.items():
        if reads[addr] == 0 and not consumers[addr]:
            continue
        width = dtype_width(index.get(var.get("dtypep", "")), index)
        # This is intentionally named an estimate.  It accounts for packed
        # width and elaborated read sites, but cannot model Vivado replication
        # and clock-enable promotion.
        estimated_bit_fanout = reads[addr] * max(1, width or 1)
        fanout_score = estimated_bit_fanout + len(consumers[addr])
        fanout_reports.append({
            "name": var_names[addr],
            "addr": addr,
            "width_bits": width,
            "read_references": reads[addr],
            "fanout": reads[addr],
            "estimated_bit_fanout": estimated_bit_fanout,
            "transitive_read_estimate": transitive_read_estimate(addr),
            "fanout_risk_score": fanout_score,
            "unique_consumers": len(consumers[addr]),
            "depth": variable_depth.get(addr, 0),
            "register": addr in seq_lhs,
        })
    fanout_reports.sort(key=lambda item: (-item["fanout_risk_score"], -item["fanout"], item["name"]))

    output_statuses = {item["status"] for item in output_reports}
    all_registered = bool(output_reports) and output_statuses == {"registered"}
    registration_status = "yes" if all_registered else ("no" if "combinational" in output_statuses else "unknown")
    signal_graph_max_depth = max(variable_depth.values(), default=0)
    output_path_max_depth = max((item["path_depth"] for item in output_reports), default=0)
    register_path_max_depth = max((item["depth"] for item in register_path_details), default=0)
    input_to_register_max_depth = max_path_depth(register_path_details, "module_input")
    child_output_to_register_max_depth = max_path_depth(register_path_details, "child_output")
    input_to_control_max_depth = max_path_depth(control_path_details, "module_input")
    child_output_to_control_max_depth = max_path_depth(control_path_details, "child_output")
    q_to_control_path_max_depth = max_path_depth(control_path_details, "register_q")
    endpoint_depths = [output_path_max_depth, register_path_max_depth]
    max_depth = max(endpoint_depths) if any(endpoint_depths) else signal_graph_max_depth
    critical_register_paths = sorted(
        register_path_details,
        key=lambda item: (-item["depth"], item["register"], str(item.get("loc", ""))),
    )[:20]
    cycle_depths = [item for item in cycles if item.get("size", 0) > 1]
    expression_summary.sort(
        key=lambda item: (-item["weighted_combination_work"], -item["operator_depth"], str(item.get("loc", "")))
    )
    combination = {
        "node_count": len(nodes),
        "edge_count": sum(len(targets) for targets in graph.values()),
        "max_depth": max_depth,
        "signal_graph_max_depth": signal_graph_max_depth,
        "output_path_max_depth": output_path_max_depth,
        "register_path_max_depth": register_path_max_depth,
        "input_to_register_max_depth": input_to_register_max_depth,
        "child_output_to_register_max_depth": child_output_to_register_max_depth,
        "input_to_control_max_depth": input_to_control_max_depth,
        "child_output_to_control_max_depth": child_output_to_control_max_depth,
        "q_to_control_path_max_depth": q_to_control_path_max_depth,
        "register_q_to_d_max_depth": register_to_boundary_by_endpoint["register_d"],
        "register_q_to_control_max_depth": register_to_boundary_by_endpoint["register_control"],
        "register_q_to_output_max_depth": register_to_boundary_by_endpoint["module_output"],
        "register_q_to_child_input_max_depth": register_to_boundary_by_endpoint["child_input"],
        "register_q_to_combination_sink_max_depth": register_to_boundary_by_endpoint["combinational_sink"],
        "register_q_to_any_boundary_max_depth": max(
            register_to_boundary_by_endpoint["module_output"],
            register_to_boundary_by_endpoint["child_input"],
        ),
        "critical_register_paths": critical_register_paths,
        "critical_output_paths": sorted(
            output_reports,
            key=lambda item: (-item["path_depth"], item["name"]),
        )[:20],
        "register_to_boundary_max_depth": max((item["depth"] for item in register_to_boundary_paths), default=0),
        "critical_register_to_boundary_paths": register_to_boundary_paths[:20],
        "critical_register_to_endpoint_paths": {
            endpoint: paths[:20]
            for endpoint, paths in register_to_endpoint_paths.items()
        },
        "critical_control_paths": sorted(
            control_path_details,
            key=lambda item: (-item["depth"], item["control"]),
        )[:20],
        "cross_register_path_max_depth": cross_register_path_max_depth,
        "critical_cross_register_paths": sorted(
            cross_register_path_details,
            key=lambda item: (-item["depth"], item["register"], str(item.get("loc", ""))),
        )[:20],
        "depth_model": "operator_tree_weighted",
        "critical_path": critical_local_path,
        "cross_module_max_depth": cross_module_max_depth,
        "cross_module_depth_delta": max(0, cross_module_max_depth - max_depth),
        "critical_cross_module_path": critical_cross_path,
        "cycle_count": len(true_cycles),
        "cycles": true_cycles,
        "scc_count_including_self": len(cycles),
        "cycle_kind_counts": dict(Counter(item.get("kind", "unknown") for item in cycle_depths)),
        "cycle_max_entry_depth": max((item.get("entry_depth", 0) for item in cycle_depths), default=0),
        "cycle_max_internal_operator_depth": max((item.get("internal_operator_depth", 0) for item in cycle_depths), default=0),
        "cycle_max_exit_depth": max((item.get("exit_depth", 0) for item in cycle_depths), default=0),
        "cycle_max_timing_path_depth": max((item.get("timing_path_depth", 0) for item in cycle_depths), default=0),
        "cycle_max_bounded_path_depth": max((item.get("bounded_path_depth", 0) for item in cycle_depths), default=0),
        "self_feedback_assignments": self_feedback,
        "partial_field_feedback": partial_feedback,
        "procedural_reassignments": procedural_reassignments,
        "latch_like_combination": latch_like,
        "operator_count": sum(item["operator_count"] for item in expression_summary),
        "conditional_count": sum(item["conditional_count"] for item in expression_summary),
        "max_operator_depth": max((item["operator_depth"] for item in expression_summary), default=0),
        "max_expression_width": max((item["max_expression_width"] or 0 for item in expression_summary), default=0),
        "weighted_combination_work": sum(item["weighted_combination_work"] for item in expression_summary),
        "packed_read_work": sum(item["estimated_bit_fanout"] for item in fanout_reports),
        "packed_consumer_work": sum((item.get("width_bits") or 1) * item["unique_consumers"] for item in fanout_reports),
        "expression_hotspots": expression_summary[:20],
        "cross_module_paths": boundary_paths,
        "cross_module_uncut_count": sum(1 for item in boundary_paths if item["child_output_status"] == "combinational"),
        "cross_module_unknown_count": sum(1 for item in boundary_paths if item["child_output_status"] == "unknown"),
        "cross_module_cut_count": sum(1 for item in boundary_paths if item["cut"]),
    }
    return {
        # Kept for the hierarchical pass and removed before JSON emission.
        # The local report intentionally remains compact, while this graph
        # snapshot lets the top-level analysis reconnect CELL pins without
        # reparsing every assignment a second time.
        "_analysis": {
            "nodes": sorted(nodes),
            "edges": [
                [source, target]
                for source in sorted(graph)
                for target in sorted(graph[source])
                if source in nodes and target in nodes
            ],
            "edge_weights": {
                f"{source}\x00{target}": edge_weight.get((source, target), 1)
                for source in graph
                for target in graph[source]
                if source in nodes and target in nodes
            },
            "sensitivity_edges": [
                [source, target]
                for source, target in sorted(sensitivity_edges)
                if source in nodes and target in nodes
            ],
            "seq_lhs": sorted(seq_lhs & nodes),
            "inputs": sorted(inputs & nodes),
            "outputs": sorted(outputs),
            "var_names": var_names,
            "sequential_rhs": [
                {
                    "source": source,
                    "targets": sorted(
                        target
                        for target in assignment["lhs"]
                    ),
                }
                for assignment in sequential_assignments
                for source in assignment["rhs"]
                if source in nodes
            ],
            "sequential_endpoints": [
                {
                    "targets": sorted(assignment["lhs"]),
                    "sources": sorted(assignment["rhs"]),
                    "controls": sorted(assignment.get("control_addrs", [])),
                    "operator_depth": int(assignment.get("operator_depth", 0)),
                    "loc": assignment.get("loc"),
                }
                for assignment in sequential_assignments
            ],
            "sequential_controls": sorted(sequential_control_registers),
            "cell_bindings": cell_bindings,
        },
        "name": module_name,
        "elaborated_name": elaborated_name,
        "loc": module.get("loc"),
        "output_count": len(output_reports),
        "outputs": output_reports,
        "registered_outputs": [item["name"] for item in output_reports if item["status"] == "registered"],
        "combinational_outputs": [item["name"] for item in output_reports if item["status"] == "combinational"],
        "unknown_outputs": [item["name"] for item in output_reports if item["status"] == "unknown"],
        "all_outputs_registered": all_registered,
        "registration_status": registration_status,
        "register_count": len(register_reports),
        "register_bits": sum(item["width_bits"] or 0 for item in register_reports),
        "registers": register_reports,
        "multiwrite_register_arrays": multiwrite_register_arrays,
        "signal_count": len(signal_reports),
        "signals": signal_reports,
        "memory_geometry": memory_geometry,
        "cell_connections": cell_connections,
        "always_blocks": dict(Counter(item["keyword"] for item in always_summary)),
        "always_details": always_summary,
        "assignment_count": dict(assignment_count),
        "loop_count": len(loops),
        "static_loop_count": static_loops,
        "static_loop_product": loop_product if static_loops else 0,
        "loops": loops,
        "combination": combination,
        "fanout_hotspots": fanout_reports[:20],
        "fanout_signals": fanout_reports,
        "risk_flags": {
            "combinational_loop": bool(true_cycles),
            "self_feedback": bool(self_feedback),
            "partial_field_feedback": bool(partial_feedback),
            "procedural_reassignment": bool(procedural_reassignments),
            # Raw references and distinct consumers are the useful structural
            # fanout signals.  Width-weighted work is reported separately;
            # otherwise every 450-bit packet would look like a 450-way net.
            "high_fanout_over_32": any(item["fanout"] > 32 or item["unique_consumers"] > 32 for item in fanout_reports),
            "wide_physical_load": any(
                item["estimated_bit_fanout"] >= 2048
                and item["unique_consumers"] >= 4
                for item in fanout_reports
            ),
            "deep_combination_over_8": max_depth > 8,
            "long_register_to_boundary_over_8": combination["register_to_boundary_max_depth"] > 8,
            "long_register_to_output_over_8": combination["register_q_to_any_boundary_max_depth"] > 8,
            "long_register_to_d_over_8": combination["register_q_to_d_max_depth"] > 8,
            "long_input_to_control_over_8": combination["input_to_control_max_depth"] > 8,
            "cross_module_combination_not_cut": any(item["child_output_status"] == "combinational" for item in boundary_paths),
            "wide_mux_or_work": combination["weighted_combination_work"] > 4096 or combination["packed_consumer_work"] > 8192 or combination["conditional_count"] > 64,
            "large_register_array": any((item.get("array_elements") or 0) >= 16 and (item.get("width_bits") or 0) >= 256 for item in register_reports),
            "multiwrite_register_array": bool(multiwrite_register_arrays),
        },
    }


def hierarchical_report(
    top_name: str,
    reports: list[dict[str, Any]],
    training: dict[str, Any] | None = None,
    target_period_ns: float = 5.0,
    bram_clock_to_out_ns: float = 2.45,
) -> dict[str, Any]:
    """Flatten combinational CELL connections for top-level feedback analysis.

    Local reports deliberately stop at module boundaries.  That is useful for
    ownership, but it hides a zero-delay path which leaves Rename/ROB, enters
    LSU, returns through Issue, and crosses an asynchronous LUTRAM read.  This
    pass reconnects each instantiated child port to its parent signal, while
    retaining the local operator weights and register cuts.  It never unfolds
    an SCC as a path list; all depth work is done on the global condensation
    DAG and bounded walks.
    """
    by_name: dict[str, dict[str, Any]] = {}
    for report in reports:
        if report.get("elaborated_name"):
            by_name[str(report["elaborated_name"])] = report
        if report.get("name"):
            by_name.setdefault(str(report["name"]), report)

    def resolve(name: str) -> dict[str, Any] | None:
        report = by_name.get(name)
        if report:
            return report
        return by_name.get(str(name).split("__", 1)[0])

    graph: dict[str, set[str]] = defaultdict(set)
    edge_weight: dict[tuple[str, str], int] = {}
    sensitivity_edges: set[tuple[str, str]] = set()
    node_info: dict[str, tuple[str, str, str]] = {}
    terminal_nodes: set[str] = set()
    launch_nodes: dict[str, dict[str, Any]] = {}
    endpoint_nodes: dict[str, dict[str, Any]] = {}
    visited_instances = 0
    max_instances = 20000

    def node_id(path: str, address: str) -> str:
        return f"{path}:{address}"

    def ensure_node(path: str, module_name: str, address: str, display_name: str | None = None) -> str:
        identifier = node_id(path, address)
        if identifier not in node_info:
            node_info[identifier] = (path, module_name, display_name or address)
        return identifier

    def add_edge(source: str, target: str, weight: int = 1, sensitivity: bool = False) -> None:
        graph[source].add(target)
        graph.setdefault(target, set())
        edge_weight[(source, target)] = max(edge_weight.get((source, target), 0), max(0, weight))
        if sensitivity:
            sensitivity_edges.add((source, target))

    def is_timing_cut_pin(binding: dict[str, Any]) -> bool:
        pin = str(binding.get("pin", ""))
        return bool(re.search(r"(?:^|_)(?:clk|clock|rst|reset)(?:_|$)", pin, re.I))

    def display(identifier: str) -> str:
        path, module_name, local_name = node_info.get(identifier, ("?", "?", identifier))
        return f"{path}.{local_name}"

    def owner_for(path: str, module_name: str) -> str:
        return normalize_owner(f"{path}/{module_name}")

    def memory_role_for(owner: str) -> str:
        if owner == "branch_predictor":
            return "predictor_bram"
        if owner in {"itcm", "dtcm"}:
            return owner
        return "other_bram"

    def memory_endpoint_kind(name: str) -> str | None:
        lowered = name.lower()
        if re.search(r"(?:^|_)(?:raddr|waddr|addr)(?:_|$)", lowered):
            return "ram_address"
        if re.search(r"(?:^|_)(?:wen|we|wstrb|mask)(?:_|$)", lowered):
            return "ram_write_enable"
        if re.search(r"(?:^|_)(?:wdata|din|data_i)(?:_|$)", lowered):
            return "ram_write_data"
        return None

    def visit(report: dict[str, Any], path: str, stack: tuple[str, ...]) -> None:
        nonlocal visited_instances
        if visited_instances >= max_instances:
            return
        visited_instances += 1
        module_name = str(report.get("name", "<unknown>"))
        module_id = str(report.get("elaborated_name") or module_name)
        active_stack = stack + (module_id,)
        analysis = report.get("_analysis", {})
        local_names = analysis.get("var_names", {})
        for address in analysis.get("nodes", []):
            ensure_node(path, module_name, address, local_names.get(address, address))
        for source, target in analysis.get("edges", []):
            if str(source).startswith(PSEUDO_PREFIX) or str(target).startswith(PSEUDO_PREFIX):
                continue
            source_node = ensure_node(path, module_name, source, local_names.get(source, source))
            target_node = ensure_node(path, module_name, target, local_names.get(target, target))
            weight = analysis.get("edge_weights", {}).get(f"{source}\x00{target}", 1)
            add_edge(source_node, target_node, int(weight or 0))
        for source, target in analysis.get("sensitivity_edges", []):
            if str(source).startswith(PSEUDO_PREFIX) or str(target).startswith(PSEUDO_PREFIX):
                continue
            source_node = node_id(path, source)
            target_node = node_id(path, target)
            if target_node in graph.get(source_node, set()):
                sensitivity_edges.add((source_node, target_node))
        owner = owner_for(path, module_name)
        multiwrite_names = {
            str(item.get("name")) for item in report.get("multiwrite_register_arrays", [])
        }
        for address in analysis.get("seq_lhs", []):
            if address in local_names:
                identifier = ensure_node(path, module_name, address, local_names[address])
                launch_nodes[identifier] = {
                    "kind": "register_q",
                    "owner": owner,
                    "signal": local_names[address],
                }
        for number, item in enumerate(analysis.get("sequential_endpoints", [])):
            for target in item.get("targets", []):
                target_name = local_names.get(target, target)
                endpoint = ensure_node(
                    path,
                    module_name,
                    f"@endpoint:{number}:{target}:D",
                    f"{target_name}/D",
                )
                terminal_nodes.add(endpoint)
                endpoint_nodes[endpoint] = {
                    "kind": "register_d",
                    "owner": owner,
                    "signal": target_name,
                    "multiwrite_array": target_name in multiwrite_names,
                    "loc": item.get("loc"),
                }
                for source in item.get("sources", []):
                    if source in local_names:
                        source_node = ensure_node(
                            path, module_name, source, local_names[source]
                        )
                        add_edge(
                            source_node,
                            endpoint,
                            max(0, int(item.get("operator_depth", 0))),
                        )
                for control in item.get("controls", []):
                    if control not in local_names:
                        continue
                    control_name = local_names[control]
                    control_kind = (
                        "register_control"
                        if re.search(r"(?:^|_)(?:rst|reset|flush)(?:_|$)", control_name, re.I)
                        else "register_ce"
                    )
                    control_endpoint = ensure_node(
                        path,
                        module_name,
                        f"@endpoint:{number}:{target}:{control_kind}",
                        f"{target_name}/{'S/R' if control_kind == 'register_control' else 'CE'}",
                    )
                    terminal_nodes.add(control_endpoint)
                    endpoint_nodes[control_endpoint] = {
                        "kind": control_kind,
                        "owner": owner,
                        "signal": target_name,
                        "multiwrite_array": target_name in multiwrite_names,
                        "loc": item.get("loc"),
                    }
                    control_node = ensure_node(
                        path, module_name, control, control_name
                    )
                    add_edge(control_node, control_endpoint, 1)

        if module_name in {"ydrasil_1r1w_bram", "ydrasil_dtcm", "ydrasil_itcm", "dtcm", "itcm"}:
            for output in analysis.get("outputs", []):
                if output in local_names:
                    identifier = ensure_node(path, module_name, output, local_names[output])
                    launch_nodes[identifier] = {
                        "kind": "bram_output",
                        "owner": owner,
                        "memory_role": memory_role_for(owner),
                        "signal": local_names[output],
                    }
        if module_name in {
            "ydrasil_1r1w_bram",
            "ydrasil_1r1w_ram",
            "ydrasil_1r1w_masked_ram",
            "ydrasil_dtcm",
            "ydrasil_itcm",
            "dtcm",
            "itcm",
        }:
            for address in analysis.get("inputs", []):
                name = local_names.get(address, address)
                kind = memory_endpoint_kind(name)
                if kind is None:
                    continue
                identifier = ensure_node(path, module_name, address, name)
                terminal_nodes.add(identifier)
                endpoint_nodes[identifier] = {
                    "kind": kind,
                    "owner": owner,
                    "signal": name,
                    "multiwrite_array": False,
                }
        if path == top_name:
            for output in analysis.get("outputs", []):
                terminal_nodes.add(node_id(path, output))

        child_instances: dict[tuple[str, str], dict[str, Any]] = {}
        for binding in analysis.get("cell_bindings", []):
            child = resolve(str(
                binding.get("child_elaborated_name") or binding.get("child", "")
            ))
            if not child or is_timing_cut_pin(binding):
                continue
            child_name = str(child.get("name", "<unknown>"))
            child_id = str(child.get("elaborated_name") or child_name)
            child_path = f"{path}/{binding.get('instance', '<cell>')}"
            child_instances[(child_path, child_id)] = child
            child_address = str(binding.get("child_var_addr", ""))
            if not child_address:
                continue
            child_analysis = child.get("_analysis", {})
            child_names = child_analysis.get("var_names", {})
            child_node = ensure_node(child_path, child_name, child_address, child_names.get(child_address, child_address))
            parent_signals = binding.get("signal_addrs", [])
            if binding.get("direction") == "INPUT":
                for source in parent_signals:
                    if source not in local_names:
                        continue
                    parent_node = ensure_node(path, module_name, source, local_names.get(source, source))
                    add_edge(parent_node, child_node, 0)
            elif binding.get("direction") == "OUTPUT":
                for target in parent_signals:
                    if target not in local_names:
                        continue
                    parent_node = ensure_node(path, module_name, target, local_names.get(target, target))
                    add_edge(child_node, parent_node, 0)

        for (child_path, child_id), child in child_instances.items():
            if child_id not in active_stack:
                visit(child, child_path, active_stack)

    top_report = resolve(top_name)
    if not top_report:
        return {
            "available": False,
            "top": top_name,
            "reason": "top module report not found",
        }
    # The recursive Tarjan implementation is safe for the local reports, but
    # an elaborated top can contain several thousand flattened signals.
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 2 * len(reports) * 1000 + 10000))
    visit(top_report, top_name, ())
    nodes = set(graph)
    nodes.update(target for targets in graph.values() for target in targets)
    if not nodes:
        return {"available": True, "top": top_name, "node_count": 0, "edge_count": 0, "cycle_count": 0, "cycles": []}

    components = tarjan({node: set(graph.get(node, ())) for node in nodes})
    component_of: dict[str, int] = {}
    for number, component in enumerate(components):
        for item in component:
            component_of[item] = number

    dag: dict[int, set[int]] = defaultdict(set)
    indegree: Counter[int] = Counter()
    for source, targets in graph.items():
        for target in targets:
            left, right = component_of[source], component_of[target]
            if left != right and right not in dag[left]:
                dag[left].add(right)
                indegree[right] += 1

    def component_cost(left: int, right: int) -> int:
        weights = [
            edge_weight.get((source, target), 1)
            for source in components[left]
            for target in components[right]
            if (source, target) in edge_weight
        ]
        return max(weights, default=1)

    queue = deque(number for number in range(len(components)) if indegree[number] == 0)
    topo_order: list[int] = []
    depth = {number: 0 for number in range(len(components))}
    depth_parent: dict[int, int] = {}
    while queue:
        current = queue.popleft()
        topo_order.append(current)
        for target in dag.get(current, ()):
            candidate = depth[current] + component_cost(current, target)
            if candidate > depth[target]:
                depth[target] = candidate
                depth_parent[target] = current
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)

    terminal_components = {component_of[node] for node in terminal_nodes if node in component_of}
    forward_depth = {number: 0 for number in range(len(components))}
    forward_endpoint: dict[int, str] = {}
    for current in reversed(topo_order):
        candidates = []
        if current in terminal_components:
            candidates.append((0, "register_or_output"))
        if not dag.get(current):
            candidates.append((0, "combinational_sink"))
        for target in dag.get(current, ()):
            candidates.append((component_cost(current, target) + forward_depth[target], forward_endpoint.get(target, "combinational_sink")))
        if candidates:
            selected = max(candidates, key=lambda item: (item[0], item[1]))
            forward_depth[current], forward_endpoint[current] = selected

    def cycle_internal_depth(component: int) -> int:
        members = set(components[component])
        value_edges = {
            source: {
                target
                for target in graph.get(source, ())
                if target in members and (source, target) not in sensitivity_edges
            }
            for source in members
        }
        best = 0
        stack: list[tuple[str, frozenset[str], int]] = [
            (source, frozenset({source}), 0) for source in sorted(members)
        ]
        seen_states: set[tuple[str, frozenset[str]]] = set()
        state_limit = max(10000, len(members) * 4096)
        while stack and len(seen_states) < state_limit:
            source, visited, score = stack.pop()
            state = (source, visited)
            if state in seen_states:
                continue
            seen_states.add(state)
            best = max(best, score)
            for target in sorted(value_edges.get(source, ())):
                if target in visited:
                    continue
                stack.append((
                    target,
                    visited | {target},
                    score + edge_weight.get((source, target), 1),
                ))
        return best

    def _bounded_reaches(local_graph: dict[str, set[str]], start: str, goal: str) -> bool:
        pending = [start]
        visited: set[str] = set()
        while pending:
            current = pending.pop()
            if current == goal:
                return True
            if current in visited:
                continue
            visited.add(current)
            pending.extend(local_graph.get(current, ()))
        return False

    cycles = []
    for number, component in enumerate(components):
        has_cycle = len(component) > 1 or any(item in graph.get(item, set()) for item in component)
        if not has_cycle:
            continue
        members = set(component)
        value_graph = {
            source: {
                target for target in graph.get(source, ())
                if target in members and (source, target) not in sensitivity_edges
            }
            for source in members
        }
        value_parts = tarjan(value_graph)
        value_cycle = any(
            len(part) > 1 or any(item in value_graph.get(item, set()) for item in part)
            for part in value_parts
        )
        internal_sensitivity_nodes = sorted(
            {
                (source, target)
                for source, target in sensitivity_edges
                if source in members and target in members
            }
        )
        internal_sensitivity = [
            (display(source), display(target))
            for source, target in internal_sensitivity_nodes
        ]
        sensitivity_witness_nodes = []
        for source in sorted({item[0] for item in internal_sensitivity_nodes}):
            candidates = {
                target for left, target in internal_sensitivity_nodes if left == source
            }
            frontier = {
                target
                for target in candidates
                if not any(
                    target != other and _bounded_reaches(value_graph, target, other)
                    for other in candidates
                )
            }
            sensitivity_witness_nodes.extend((source, target) for target in sorted(frontier))
        sensitivity_witness = [
            {"source": display(source), "target": display(target)}
            for source, target in sensitivity_witness_nodes
        ]
        entry_depth = depth.get(number, 0)
        exit_depth = forward_depth.get(number, 0)
        internal_depth = cycle_internal_depth(number)
        cycles.append({
            "signals": sorted(display(item) for item in component)[:128],
            "size": len(component),
            "kind": (
                "mixed"
                if value_cycle and internal_sensitivity
                else ("value" if value_cycle else "sensitivity")
            ),
            "sensitivity_edges": [
                {"source": source, "target": target}
                for source, target in internal_sensitivity
            ],
            "sensitivity_witness": sensitivity_witness,
            "sensitivity_witness_path": [
                [display(target), display(source)]
                for source, target in sensitivity_witness_nodes
            ],
            "entry_depth": entry_depth,
            "internal_operator_depth": internal_depth,
            "exit_depth": exit_depth,
            "timing_path_depth": entry_depth + exit_depth,
            "bounded_path_depth": entry_depth + internal_depth + exit_depth,
        })

    # ``max(depth)`` includes combinational sinks that never feed a flop D/CE
    # or a top-level output.  Keep it as a structural upper bound, but expose
    # a timing-endpoint depth separately for correlation with Vivado paths.
    endpoint_depths = {
        component: depth.get(component, 0)
        for component in terminal_components
    }
    max_component = max(depth, key=depth.get, default=0)
    max_endpoint_component = max(endpoint_depths, key=endpoint_depths.get, default=max_component)
    critical_components = [max_endpoint_component]
    while critical_components[-1] in depth_parent:
        critical_components.append(depth_parent[critical_components[-1]])
    critical_components.reverse()
    critical_path = [display(sorted(components[item])[0]) for item in critical_components]

    def named_path(source_pattern: str, target_pattern: str) -> dict[str, Any] | None:
        source_nodes = [node for node in nodes if re.search(source_pattern, display(node), re.I)]
        target_nodes = [node for node in nodes if re.search(target_pattern, display(node), re.I)]
        if not source_nodes or not target_nodes:
            return None
        target_components = {component_of[node] for node in target_nodes}
        best_depth: dict[int, int] = {}
        parents: dict[int, int] = {}
        source_for: dict[int, str] = {}
        for source in source_nodes:
            component = component_of[source]
            if component not in best_depth or best_depth[component] < 0:
                best_depth[component] = 0
                source_for[component] = source
        for current in topo_order:
            if current not in best_depth:
                continue
            for target in dag.get(current, ()):
                candidate = best_depth[current] + component_cost(current, target)
                if candidate > best_depth.get(target, -1):
                    best_depth[target] = candidate
                    parents[target] = current
                    source_for[target] = source_for[current]
        reachable = [component for component in target_components if component in best_depth]
        if not reachable:
            return None
        end = max(reachable, key=lambda item: best_depth[item])
        path_components = [end]
        while path_components[-1] in parents:
            path_components.append(parents[path_components[-1]])
        path_components.reverse()
        return {
            "source": display(source_for[path_components[0]]),
            "target": display(next(node for node in target_nodes if component_of[node] == end)),
            "depth": best_depth[end],
            "signals": [display(sorted(components[item])[0]) for item in path_components],
        }

    named_paths = {
        name: path
        for name, source_pattern, target_pattern in (
            ("producer_tag_to_issue_ex_d", r"u_rename_rob\.producer_tag_q", r"u_issue_window\.issue_ex_d"),
            ("producer_tag_to_lsu_head_accept", r"u_rename_rob\.producer_tag_q", r"u_ydrasil_load_store_unit\.head_accept_ready"),
            ("lsu_head_accept_to_issue_ex_d", r"u_ydrasil_load_store_unit\.head_accept_ready", r"u_issue_window\.issue_ex_d"),
            ("rob_head_to_issue_ex_d", r"\.rob_head_tag_q$|\.rob_head_tag$", r"u_issue_window\.issue_ex_d"),
        )
        if (path := named_path(source_pattern, target_pattern)) is not None
    }

    def best_endpoint_path(
        source_owner: str,
        launch_kind: str,
        destination_owner: str,
        endpoint_kind: str,
        launch_memory_role: str = "none",
        require_multiwrite: bool = False,
    ) -> dict[str, Any] | None:
        source_nodes = [
            node for node, info in launch_nodes.items()
            if node in component_of
            and info.get("owner") == source_owner
            and info.get("kind") == launch_kind
            and (
                launch_kind != "bram_output"
                or info.get("memory_role") == launch_memory_role
            )
        ]
        target_nodes = [
            node for node, info in endpoint_nodes.items()
            if node in component_of
            and info.get("owner") == destination_owner
            and info.get("kind") == endpoint_kind
            and (not require_multiwrite or info.get("multiwrite_array"))
        ]
        if not source_nodes or not target_nodes:
            return None
        target_components = {component_of[node] for node in target_nodes}
        best_depth: dict[int, int] = {}
        parents: dict[int, int] = {}
        source_for: dict[int, str] = {}
        for source in source_nodes:
            component = component_of[source]
            if best_depth.get(component, -1) < 0:
                best_depth[component] = 0
                source_for[component] = source
        for current in topo_order:
            if current not in best_depth:
                continue
            for target in dag.get(current, ()):
                candidate = best_depth[current] + component_cost(current, target)
                if candidate > best_depth.get(target, -1):
                    best_depth[target] = candidate
                    parents[target] = current
                    source_for[target] = source_for[current]
        reachable = [component for component in target_components if component in best_depth]
        if not reachable:
            return None
        end = max(reachable, key=lambda component: best_depth[component])
        path_components = [end]
        while path_components[-1] in parents:
            path_components.append(parents[path_components[-1]])
        path_components.reverse()
        target = next(node for node in target_nodes if component_of[node] == end)
        source = source_for[path_components[0]]
        signals = [display(sorted(components[item])[0]) for item in path_components]
        path_owners = [
            owner_for(node_info.get(sorted(components[item])[0], ("", "", ""))[0],
                      node_info.get(sorted(components[item])[0], ("", "", ""))[1])
            for item in path_components
        ]
        owner_crossings = sum(
            left != right for left, right in zip(path_owners, path_owners[1:])
        )
        return {
            "source": display(source),
            "destination": display(target),
            "source_signal": launch_nodes[source].get("signal"),
            "destination_signal": endpoint_nodes[target].get("signal"),
            "depth": best_depth[end],
            "signals": signals,
            "owner_crossings": owner_crossings,
            "multiwrite_array": bool(endpoint_nodes[target].get("multiwrite_array")),
        }

    timing_path_risks: dict[str, dict[str, Any]] = {}

    def structural_upper_delay(
        path: dict[str, Any],
        launch_kind: str,
        endpoint_kind: str,
    ) -> float:
        launch_ns = bram_clock_to_out_ns if launch_kind == "bram_output" else 0.35
        logic_ns = 0.18 * float(path.get("depth", 0))
        route_upper_ns = (
            0.65
            + 0.30 * float(path.get("owner_crossings", 0))
            + 0.08 * max(0.0, float(path.get("depth", 0)) - 2.0)
        )
        endpoint_ns = 0.25 if endpoint_kind.startswith("ram_") else 0.15
        return launch_ns + logic_ns + route_upper_ns + endpoint_ns

    def record_path_risk(
        key: str,
        path: dict[str, Any],
        source_owner: str,
        destination_owner: str,
        launch_kind: str,
        endpoint_kind: str,
        launch_memory_role: str,
        reasons: list[str],
        trained: dict[str, Any] | None = None,
        force_fail: bool = False,
    ) -> None:
        structural_upper_ns = structural_upper_delay(path, launch_kind, endpoint_kind)
        trained_p95_ns = float(trained.get("delay_ns_p95", 0.0)) if trained else 0.0
        estimated_upper_ns = max(structural_upper_ns, trained_p95_ns)
        if force_fail or estimated_upper_ns >= target_period_ns:
            severity = "FAIL"
        elif estimated_upper_ns >= max(0.0, target_period_ns - 0.7):
            severity = "HIGH"
        else:
            severity = "WARN"
        candidate = {
            "key": key,
            "severity": severity,
            "source_owner": source_owner,
            "destination_owner": destination_owner,
            "launch_kind": launch_kind,
            "launch_memory_role": launch_memory_role,
            "endpoint_kind": endpoint_kind,
            "source": path.get("source"),
            "destination": path.get("destination"),
            "source_signal": path.get("source_signal"),
            "destination_signal": path.get("destination_signal"),
            "structural_depth": path.get("depth", 0),
            "owner_crossings": path.get("owner_crossings", 0),
            "structural_upper_delay_ns": round(structural_upper_ns, 3),
            "trained_p95_delay_ns": round(trained_p95_ns, 3) if trained else None,
            "estimated_upper_delay_ns": round(estimated_upper_ns, 3),
            "estimated_slack_ns": round(target_period_ns - estimated_upper_ns, 3),
            "training_sample_count": int(trained.get("sample_count", 0)) if trained else 0,
            "training_design_count": int(trained.get("design_count", 0)) if trained else 0,
            "reasons": sorted(set(reasons)),
            "signals": path.get("signals", []),
        }
        previous = timing_path_risks.get(key)
        severity_rank = {"WARN": 0, "HIGH": 1, "FAIL": 2}
        if previous is None or (
            severity_rank[candidate["severity"]], candidate["estimated_upper_delay_ns"]
        ) > (
            severity_rank[previous["severity"]], previous["estimated_upper_delay_ns"]
        ):
            timing_path_risks[key] = candidate
        elif previous is not None:
            previous["reasons"] = sorted(set(previous["reasons"]) | set(reasons))

    trained_families = (training or {}).get("families", [])
    for trained in trained_families:
        if "other" in {
            trained.get("source_owner"), trained.get("destination_owner"),
            trained.get("endpoint_kind"),
        }:
            continue
        requested_endpoint_kind = str(trained.get("endpoint_kind"))
        path = best_endpoint_path(
            str(trained.get("source_owner")),
            str(trained.get("launch_kind")),
            str(trained.get("destination_owner")),
            requested_endpoint_kind,
            str(trained.get("launch_memory_role", "none")),
        )
        fallback_endpoint_kind = None
        if path is None and requested_endpoint_kind in {
            "register_d", "register_ce", "register_control",
        }:
            for candidate_kind in ("register_d", "register_ce", "register_control"):
                if candidate_kind == requested_endpoint_kind:
                    continue
                path = best_endpoint_path(
                    str(trained.get("source_owner")),
                    str(trained.get("launch_kind")),
                    str(trained.get("destination_owner")),
                    candidate_kind,
                    str(trained.get("launch_memory_role", "none")),
                )
                if path is not None:
                    fallback_endpoint_kind = candidate_kind
                    break
        if path is None:
            continue
        reasons = ["reachable_path_family_failed_in_archived_vivado"]
        if fallback_endpoint_kind is not None:
            reasons.append(
                f"implementation_control_pin_fallback_{fallback_endpoint_kind}"
            )
        record_path_risk(
            str(trained.get("key")), path,
            str(trained.get("source_owner")),
            str(trained.get("destination_owner")),
            str(trained.get("launch_kind")),
            requested_endpoint_kind,
            str(trained.get("launch_memory_role", "none")),
            reasons,
            trained=trained,
            force_fail=float(trained.get("worst_slack_ns", 0.0)) < 0.0,
        )
        if requested_endpoint_kind in {
            "register_d", "register_ce", "register_control",
        }:
            for sibling_kind in ("register_d", "register_ce", "register_control"):
                if sibling_kind == requested_endpoint_kind:
                    continue
                sibling_key = family_key(
                    str(trained.get("source_owner")),
                    str(trained.get("destination_owner")),
                    str(trained.get("launch_kind")),
                    sibling_kind,
                    str(trained.get("launch_memory_role", "none")),
                )
                if sibling_key in timing_path_risks:
                    continue
                sibling_path = best_endpoint_path(
                    str(trained.get("source_owner")),
                    str(trained.get("launch_kind")),
                    str(trained.get("destination_owner")),
                    sibling_kind,
                    str(trained.get("launch_memory_role", "none")),
                )
                sibling_reasons = ["trained_register_endpoint_implementation_variant"]
                if sibling_path is None:
                    sibling_path = path
                    sibling_reasons.append(
                        f"implementation_control_pin_fallback_{requested_endpoint_kind}"
                    )
                record_path_risk(
                    sibling_key,
                    sibling_path,
                    str(trained.get("source_owner")),
                    str(trained.get("destination_owner")),
                    str(trained.get("launch_kind")),
                    sibling_kind,
                    str(trained.get("launch_memory_role", "none")),
                    sibling_reasons,
                    trained=trained,
                    force_fail=float(trained.get("worst_slack_ns", 0.0)) < 0.0,
                )

    launch_groups = sorted({
        (
            str(info.get("owner")), str(info.get("kind")),
            str(info.get("memory_role", "none")),
        )
        for info in launch_nodes.values()
    })
    endpoint_groups = sorted({
        (str(info.get("owner")), str(info.get("kind")))
        for info in endpoint_nodes.values()
    })
    for source_owner, launch_kind, launch_memory_role in launch_groups:
        if source_owner == "other":
            continue
        for destination_owner, endpoint_kind in endpoint_groups:
            if destination_owner == "other":
                continue
            path = best_endpoint_path(
                source_owner,
                launch_kind,
                destination_owner,
                endpoint_kind,
                launch_memory_role,
            )
            if path is None:
                continue
            estimated = structural_upper_delay(path, launch_kind, endpoint_kind)
            warning_margin_ns = 1.5 if launch_kind == "bram_output" else 0.7
            if estimated < max(0.0, target_period_ns - warning_margin_ns):
                continue
            key = family_key(
                source_owner,
                destination_owner,
                launch_kind,
                endpoint_kind,
                launch_memory_role,
            )
            record_path_risk(
                key,
                path,
                source_owner,
                destination_owner,
                launch_kind,
                endpoint_kind,
                launch_memory_role,
                ["independent_structural_path_upper_bound"],
            )
            if endpoint_kind in {"register_d", "register_ce", "register_control"}:
                for sibling_kind in ("register_d", "register_ce", "register_control"):
                    if sibling_kind == endpoint_kind:
                        continue
                    sibling_path = best_endpoint_path(
                        source_owner,
                        launch_kind,
                        destination_owner,
                        sibling_kind,
                        launch_memory_role,
                    )
                    sibling_reasons = [
                        "independent_structural_register_endpoint_variant"
                    ]
                    if sibling_path is None:
                        sibling_path = path
                        sibling_reasons.append(
                            f"implementation_control_pin_fallback_{endpoint_kind}"
                        )
                    sibling_key = family_key(
                        source_owner,
                        destination_owner,
                        launch_kind,
                        sibling_kind,
                        launch_memory_role,
                    )
                    record_path_risk(
                        sibling_key,
                        sibling_path,
                        source_owner,
                        destination_owner,
                        launch_kind,
                        sibling_kind,
                        launch_memory_role,
                        sibling_reasons,
                    )
    for source_owner, launch_kind, launch_memory_role in launch_groups:
        if launch_kind != "bram_output":
            continue
        for destination_owner, endpoint_kind in endpoint_groups:
            if not endpoint_kind.startswith("ram_"):
                continue
            path = best_endpoint_path(
                source_owner, launch_kind, destination_owner, endpoint_kind,
                launch_memory_role
            )
            if path is None:
                continue
            key = family_key(
                source_owner, destination_owner, launch_kind, endpoint_kind,
                launch_memory_role,
            )
            record_path_risk(
                key, path, source_owner, destination_owner, launch_kind, endpoint_kind,
                launch_memory_role,
                ["bram_clock_to_out_to_unregistered_ram_pin"],
                force_fail=True,
            )

    multiwrite_owners = sorted({
        str(info.get("owner")) for info in endpoint_nodes.values()
        if info.get("multiwrite_array")
    })
    for destination_owner in multiwrite_owners:
        for source_owner, launch_kind, launch_memory_role in launch_groups:
            if launch_kind != "register_q":
                continue
            path = best_endpoint_path(
                source_owner,
                launch_kind,
                destination_owner,
                "register_d",
                launch_memory_role,
                require_multiwrite=True,
            )
            if path is None:
                continue
            key = family_key(source_owner, destination_owner, launch_kind, "register_d")
            record_path_risk(
                key, path, source_owner, destination_owner, launch_kind, "register_d",
                launch_memory_role,
                ["multiwrite_register_array_endpoint"],
                force_fail=True,
            )

    ordered_path_risks = sorted(
        timing_path_risks.values(),
        key=lambda item: (
            {"FAIL": 0, "HIGH": 1, "WARN": 2}[item["severity"]],
            item["estimated_slack_ns"],
            item["key"],
        ),
    )
    meaningful_cycles = [item for item in cycles if item.get("size", 0) > 1]
    critical_timing_path = [display(sorted(components[item])[0]) for item in critical_components]
    return {
        "available": True,
        "top": top_name,
        "instance_count": visited_instances,
        "node_count": len(nodes),
        "edge_count": sum(len(targets) for targets in graph.values()),
        "max_depth": max(depth.values(), default=0),
        "critical_path": critical_path,
        "timing_endpoint_count": len(terminal_components),
        "timing_endpoint_max_depth": max(endpoint_depths.values(), default=0),
        "critical_timing_path": critical_timing_path,
        "named_paths": named_paths,
        "timing_launch_count": len(launch_nodes),
        "timing_launch_count_by_owner_kind": dict(Counter(
            f"{item.get('owner')}|{item.get('kind')}"
            for item in launch_nodes.values()
        )),
        "timing_endpoint_count_by_kind": dict(Counter(
            str(item.get("kind")) for item in endpoint_nodes.values()
        )),
        "timing_endpoint_count_by_owner_kind": dict(Counter(
            f"{item.get('owner')}|{item.get('kind')}"
            for item in endpoint_nodes.values()
        )),
        "timing_path_risks": ordered_path_risks,
        "timing_path_fail_count": sum(
            item["severity"] == "FAIL" for item in ordered_path_risks
        ),
        "timing_path_high_count": sum(
            item["severity"] == "HIGH" for item in ordered_path_risks
        ),
        "timing_training": {
            "archive_root": (training or {}).get("archive_root"),
            "dataset_count": (training or {}).get("dataset_count", 0),
            "path_count": (training or {}).get("path_count", 0),
            "family_count": (training or {}).get("family_count", 0),
            "skipped": (training or {}).get("skipped", []),
            "bram_eligible_dataset_count": (training or {}).get(
                "bram_eligible_dataset_count", 0
            ),
            "bram_accepted_path_count": (training or {}).get(
                "bram_accepted_path_count", 0
            ),
            "bram_excluded_path_count": (training or {}).get(
                "bram_excluded_path_count", 0
            ),
            "bram_geometry_compatibility": (training or {}).get(
                "bram_geometry_compatibility", []
            ),
        },
        # A one-node SCC is useful detail (often a procedural temporary), but
        # it should not trip the architectural loop gate by itself.
        "cycle_count": len(meaningful_cycles),
        "self_cycle_count": len(cycles) - len(meaningful_cycles),
        "cycles": cycles,
        "meaningful_cycles": meaningful_cycles,
        "cycle_kind_counts": dict(Counter(item["kind"] for item in cycles)),
        "cycle_max_bounded_path_depth": max((item["bounded_path_depth"] for item in cycles), default=0),
        "cycle_max_timing_path_depth": max((item["timing_path_depth"] for item in cycles), default=0),
    }


def memory_timing_profile(
    report: dict[str, Any],
    bram_launch_penalty_depth: int,
    bram_clock_to_out_ns: float,
    lutram_arc_ns: float,
) -> dict[str, Any]:
    """Describe memory semantics without treating simulation arrays as FFs."""
    name = str(report.get("name", ""))
    children = {
        str(item.get("module", ""))
        for item in report.get("cell_connections", [])
        if item.get("module")
    }
    simulation_model = name.startswith("ydrmem") or name.startswith("ydrasil_sim_")
    bram_modules = {
        "dtcm",
        "itcm",
        "IROM",
        "tpdram_wrapper",
        "xpm_spram_wrapper",
        "xpm_init_bram_wrapper",
        "xpm_sdpram_wrapper",
        "xpm_tpdram_wrapper",
        "ydrasil_1r1w_bram",
        "ydrasil_dtcm",
        "ydrasil_itcm",
    }
    bram_simulation_children = {
        "ydrasil_sim_1r1w_bram",
        "ydrasil_sim_sdpram",
        "ydrasil_sim_tpdram",
    }
    lutram_modules = {"xpm_lutram_1r1w", "ydrasil_1r1w_ram"}
    contains_bram = (
        name in bram_modules
        or any(
            child.startswith("ydrmem")
            or child in bram_modules
            or child in bram_simulation_children
            for child in children
        )
    )
    contains_lutram = name in lutram_modules or bool(children & lutram_modules)
    synchronous_lutram = name == "ydrasil_1r1w_ram" or "ydrasil_1r1w_ram" in children
    asynchronous_lutram = (
        contains_lutram
        and not synchronous_lutram
        and report.get("registration_status") != "yes"
    )
    if simulation_model:
        kind = "simulation_memory_model"
    elif contains_bram and contains_lutram:
        kind = "mixed_fpga_memory_consumer"
    elif contains_bram:
        kind = "bram_wrapper_or_consumer"
    elif contains_lutram:
        kind = "lutram_wrapper_or_consumer"
    else:
        kind = "none"
    return {
        "kind": kind,
        "simulation_model_excluded_from_synthesis_risk": simulation_model,
        "contains_bram_boundary": contains_bram,
        "contains_lutram_boundary": contains_lutram,
        "synchronous_lutram_boundary": synchronous_lutram,
        "asynchronous_lutram_boundary": asynchronous_lutram,
        "storage_bits_interpretation": (
            "simulation memory capacity; do not compare with Vivado FF count"
            if simulation_model
            else (
                "LUTRAM capacity; do not compare with Vivado FF count"
                if name == "xpm_lutram_1r1w"
                else "ordinary RTL state upper bound"
            )
        ),
        "bram_launch_penalty_depth": bram_launch_penalty_depth if contains_bram and not simulation_model else 0,
        "bram_clock_to_out_reference_ns": bram_clock_to_out_ns if contains_bram else None,
        "lutram_logic_level_reference": 1 if contains_lutram else None,
        "lutram_primitive_arc_reference_ns": lutram_arc_ns if contains_lutram else None,
        "timing_trust": (
            "interface_and_register_cut_only"
            if simulation_model
            else ("macro_calibrated_structural_proxy" if contains_bram or contains_lutram else "structural_proxy")
        ),
    }


def memory_geometry_profile(reports: list[dict[str, Any]]) -> dict[str, Any]:
    """Keep memory geometry per elaborated instance; never merge by maximum."""
    roles = {
        "ydrasil_itcm": "itcm",
        "ydrasil_dtcm": "dtcm",
        "ydrasil_1r1w_bram": "generic_bram",
        "ydrasil_1r1w_ram": "generic_lutram",
        "ydrasil_1r1w_masked_ram": "generic_lutram",
    }
    instances = []
    for report in reports:
        geometry = report.get("memory_geometry")
        role = roles.get(str(report.get("name")))
        if not geometry or not role:
            continue
        instances.append({
            "role": role,
            "module": report.get("name"),
            "elaborated_name": report.get("elaborated_name"),
            "address_width_bits": geometry.get("address_width_bits"),
            "data_width_bits": geometry.get("data_width_bits"),
            "depth_words": geometry.get("depth_words"),
            "capacity_bytes": geometry.get("capacity_bytes"),
        })
    instances.sort(key=lambda item: (
        str(item.get("role")), str(item.get("elaborated_name")),
        int(item.get("capacity_bytes") or 0),
    ))
    return {
        "schema_version": 1,
        "aggregation": "per_elaborated_instance_no_maximum",
        "instances": instances,
    }


def apply_timing_risk_policy(
    report: dict[str, Any],
    hierarchy: dict[str, Any] | None,
    period_ns: float,
    possible_depth: int,
    definite_depth: int,
    lutram_possible_depth: int,
    fanout_timing_min_depth: int,
    bram_launch_penalty_depth: int,
    bram_clock_to_out_ns: float,
    lutram_arc_ns: float,
) -> None:
    combination = report.get("combination", {})
    memory = memory_timing_profile(
        report,
        bram_launch_penalty_depth,
        bram_clock_to_out_ns,
        lutram_arc_ns,
    )
    report["memory_timing"] = memory
    base_depth = max(
        int(combination.get("max_depth", 0)),
        int(combination.get("cross_module_max_depth", 0)),
        int(combination.get("input_to_register_max_depth", 0)),
        int(combination.get("input_to_control_max_depth", 0)),
        int(combination.get("q_to_control_path_max_depth", 0)),
        int(combination.get("register_to_boundary_max_depth", 0)),
    )
    critical_path = combination.get("critical_cross_module_path") or combination.get("critical_path")
    loop = bool(report.get("risk_flags", {}).get("combinational_loop"))
    hierarchical_depth = 0
    if hierarchy:
        hierarchical_depth = int(hierarchy.get("timing_endpoint_max_depth", hierarchy.get("max_depth", 0)))
        if hierarchical_depth >= base_depth:
            base_depth = hierarchical_depth
            critical_path = {
                "depth": hierarchical_depth,
                "signals": hierarchy.get("critical_timing_path", []),
                "endpoint": "hierarchical_timing_endpoint",
            }
        loop = loop or bool(hierarchy.get("cycle_count"))
    adjusted_depth = base_depth + int(memory.get("bram_launch_penalty_depth", 0))
    excluded = bool(memory.get("simulation_model_excluded_from_synthesis_risk"))
    reasons = []
    high_fanout_timing = (
        bool(
            report.get("risk_flags", {}).get("high_fanout_over_32")
            or report.get("risk_flags", {}).get("wide_physical_load")
        )
        and base_depth >= fanout_timing_min_depth
    )
    multiwrite_array = bool(
        report.get("risk_flags", {}).get("multiwrite_register_array")
    )
    routing_sensitivity_reasons = []
    if high_fanout_timing:
        routing_sensitivity_reasons.append("rtl_fanout_estimate")
    if multiwrite_array:
        routing_sensitivity_reasons.append("multiwrite_register_array")
    if memory.get("asynchronous_lutram_boundary"):
        routing_sensitivity_reasons.append("asynchronous_lutram_boundary")
    elif memory.get("contains_lutram_boundary"):
        routing_sensitivity_reasons.append("synchronous_lutram_boundary")
    if memory.get("contains_bram_boundary"):
        routing_sensitivity_reasons.append("bram_clock_to_out_boundary")
    if (
        report.get("risk_flags", {}).get("cross_module_combination_not_cut")
        and base_depth >= fanout_timing_min_depth
    ):
        routing_sensitivity_reasons.append("uncut_cross_module_combination")
    if excluded:
        reasons.append("simulation_memory_model_excluded_from_synthesis_risk")
    else:
        if adjusted_depth >= possible_depth:
            reasons.append("endpoint_depth_at_or_above_possible_threshold")
        if high_fanout_timing:
            reasons.append("high_fanout_with_nontrivial_combination")
        if multiwrite_array:
            reasons.append("multiwrite_register_array_endpoint")
        if memory.get("asynchronous_lutram_boundary") and base_depth >= lutram_possible_depth:
            reasons.append("asynchronous_lutram_on_unregistered_path")
        elif memory.get("contains_lutram_boundary") and base_depth >= lutram_possible_depth:
            reasons.append("synchronous_lutram_with_downstream_combination")
        if memory.get("contains_bram_boundary"):
            reasons.append("bram_clock_to_out_reduces_downstream_budget")
        if loop:
            reasons.append("combinational_loop")
        if adjusted_depth >= definite_depth:
            reasons.append("endpoint_depth_at_or_above_definite_threshold")
    definite = not excluded and (loop or adjusted_depth >= definite_depth)
    possible = (
        not excluded
        and (
            definite
            or adjusted_depth >= possible_depth
            or high_fanout_timing
            or multiwrite_array
            or memory.get("contains_bram_boundary")
            or (
                memory.get("contains_lutram_boundary")
                and base_depth >= lutram_possible_depth
            )
        )
    )
    risk = {
        "target_period_ns": period_ns,
        "classification": "definite_failure" if definite else ("possible_failure" if possible else "no_structural_flag"),
        "possible_target_period_failure": possible,
        "definite_target_period_failure": definite,
        "structural_endpoint_depth": base_depth,
        "memory_adjusted_depth": adjusted_depth,
        "possible_depth_threshold": possible_depth,
        "definite_depth_threshold": definite_depth,
        "lutram_possible_depth_threshold": lutram_possible_depth,
        "fanout_timing_min_depth": fanout_timing_min_depth,
        "remaining_period_after_bram_reference_ns": (
            max(0.0, period_ns - bram_clock_to_out_ns)
            if memory.get("contains_bram_boundary") else None
        ),
        "routing_sensitivity": (
            "high" if (
                len(routing_sensitivity_reasons) >= 2
                or (high_fanout_timing and adjusted_depth >= possible_depth)
            )
            else "possible" if routing_sensitivity_reasons
            else "low"
        ),
        "routing_sensitivity_reasons": routing_sensitivity_reasons,
        "expected_failure_mode": (
            "route_or_fpga_memory_sensitive"
            if routing_sensitivity_reasons else "logic_depth_sensitive"
        ),
        "reasons": reasons,
        "critical_path": critical_path,
        "interpretation": (
            "Structural early-warning calibrated to the current xc7 post-route report; "
            "possible is conservative, while definite requires a loop or the high-depth threshold."
        ),
    }
    report["timing_risk"] = risk
    flags = report.setdefault("risk_flags", {})
    flags["possible_target_period_failure"] = possible
    flags["definite_target_period_failure"] = definite
    flags["possible_5ns_failure"] = possible if math.isclose(period_ns, 5.0) else False
    flags["definite_5ns_failure"] = definite if math.isclose(period_ns, 5.0) else False
    flags["simulation_memory_model_excluded"] = excluded


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--check-output", type=Path, default=None)
    parser.add_argument("--source-metadata", type=Path, default=None)
    parser.add_argument("--top", default=None)
    parser.add_argument("--calibration-history", type=Path, default=None)
    parser.add_argument("--fail-on-timing-path", action="store_true")
    parser.add_argument("--target-period-ns", type=float, default=5.0)
    parser.add_argument("--timing-possible-depth", type=int, default=9)
    parser.add_argument("--timing-definite-depth", type=int, default=32)
    parser.add_argument("--lutram-possible-depth", type=int, default=6)
    parser.add_argument("--fanout-timing-min-depth", type=int, default=3)
    parser.add_argument("--bram-launch-penalty-depth", type=int, default=6)
    parser.add_argument("--bram-clock-to-out-ns", type=float, default=2.45)
    parser.add_argument("--lutram-arc-ns", type=float, default=0.06)
    args = parser.parse_args()
    if args.check_output:
        try:
            checked = json.loads(args.check_output.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"error: cannot read structure report {args.check_output}: {exc}", file=sys.stderr)
            return 2
        failures = checked.get("hierarchical", {}).get("timing_path_risks", [])
        failures = [item for item in failures if item.get("severity") == "FAIL"]
        cycles = checked.get("hierarchical", {}).get("meaningful_cycles", [])
        for item in failures:
            print(
                f"FAIL {item.get('key')}: estimated={item.get('estimated_upper_delay_ns')}ns "
                f"slack={item.get('estimated_slack_ns')}ns "
                f"{item.get('source')} -> {item.get('destination')} "
                f"reasons={','.join(item.get('reasons', []))}"
            )
        for index, cycle in enumerate(cycles):
            witness = cycle.get("sensitivity_witness_path", [])
            print(
                f"FAIL combinational_loop[{index}]: kind={cycle.get('kind')} "
                f"timing-depth={cycle.get('timing_path_depth')} "
                f"bounded-depth={cycle.get('bounded_path_depth')} "
                f"witness={witness[:2]}"
            )
        if failures or cycles:
            print(
                f"error: {len(failures)} structural timing path families and "
                f"{len(cycles)} combinational loops fail the gate",
                file=sys.stderr,
            )
            return 1
        print("no structural timing path FAIL warnings")
        return 0
    if args.input is None or args.output is None:
        parser.error("--input and --output are required unless --check-output is used")
    try:
        tree = json.loads(args.input.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read Verilator tree {args.input}: {exc}", file=sys.stderr)
        return 2
    source_metadata = None
    if args.source_metadata:
        try:
            source_metadata = json.loads(args.source_metadata.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"error: cannot read RTL source metadata {args.source_metadata}: {exc}", file=sys.stderr)
            return 2

    index = {item["addr"]: item for item in walk(tree) if item.get("addr")}
    modules = [item for item in walk(tree) if item.get("type") == "MODULE" and item.get("name") not in {"$root", "@CONST-POOL@"}]
    # The first pass builds local graphs.  A second pass resolves registered
    # child outputs used by parent cell pins.
    reports = []
    status = {}
    for module in modules:
        report = module_report(module, index, status)
        reports.append(report)
        status[report["elaborated_name"]] = report
        status.setdefault(report["name"], report)
    for report, module in zip(reports, modules):
        refreshed = module_report(module, index, status)
        report.clear()
        report.update(refreshed)
        status[report["elaborated_name"]] = report
        status.setdefault(report["name"], report)

    hierarchy_top = args.top or "ydrasil_core"
    geometry_profile = memory_geometry_profile(reports)
    training = load_archive_training(
        args.calibration_history,
        args.target_period_ns,
        memory_geometry_profile=geometry_profile,
    )
    hierarchy = hierarchical_report(
        hierarchy_top,
        reports,
        training=training,
        target_period_ns=args.target_period_ns,
        bram_clock_to_out_ns=args.bram_clock_to_out_ns,
    )
    for report in reports:
        report_hierarchy = hierarchy if report.get("name") == hierarchy_top else None
        apply_timing_risk_policy(
            report,
            report_hierarchy,
            args.target_period_ns,
            args.timing_possible_depth,
            args.timing_definite_depth,
            args.lutram_possible_depth,
            args.fanout_timing_min_depth,
            args.bram_launch_penalty_depth,
            args.bram_clock_to_out_ns,
            args.lutram_arc_ns,
        )
        if report.get("name") == hierarchy_top:
            report["combination"]["hierarchical"] = hierarchy
            report["risk_flags"]["hierarchical_combinational_loop"] = bool(hierarchy.get("cycle_count"))
            report["risk_flags"]["hierarchical_deep_combination_over_32"] = hierarchy.get("max_depth", 0) > 32
        else:
            report["risk_flags"]["hierarchical_combinational_loop"] = False
            report["risk_flags"]["hierarchical_deep_combination_over_32"] = False

    if args.top:
        reports.sort(key=lambda item: (item["name"] != args.top, item["name"]))
    synthesis_reports = [
        item for item in reports
        if not item["risk_flags"].get("simulation_memory_model_excluded")
    ]
    summary = {
        "modules_with_combinational_loops": [item["name"] for item in synthesis_reports if item["risk_flags"]["combinational_loop"]],
        "modules_with_self_feedback": [item["name"] for item in synthesis_reports if item["risk_flags"]["self_feedback"]],
        "modules_with_partial_field_feedback": [item["name"] for item in synthesis_reports if item["risk_flags"]["partial_field_feedback"]],
        "modules_with_high_fanout": [item["name"] for item in synthesis_reports if item["risk_flags"]["high_fanout_over_32"]],
        "modules_with_deep_combination": [item["name"] for item in synthesis_reports if item["risk_flags"]["deep_combination_over_8"]],
        "modules_with_long_register_to_boundary": [item["name"] for item in synthesis_reports if item["risk_flags"]["long_register_to_boundary_over_8"]],
        "modules_with_long_register_to_output": [item["name"] for item in synthesis_reports if item["risk_flags"]["long_register_to_output_over_8"]],
        "modules_with_long_input_to_control": [item["name"] for item in synthesis_reports if item["risk_flags"]["long_input_to_control_over_8"]],
        "modules_with_uncut_cross_module_combination": [item["name"] for item in synthesis_reports if item["risk_flags"]["cross_module_combination_not_cut"]],
        "modules_with_wide_mux_or_work": [item["name"] for item in synthesis_reports if item["risk_flags"]["wide_mux_or_work"]],
        "modules_with_unregistered_outputs": [item["name"] for item in synthesis_reports if item["registration_status"] != "yes"],
        "modules_with_possible_target_period_failure": [item["name"] for item in synthesis_reports if item["risk_flags"]["possible_target_period_failure"]],
        "modules_with_definite_target_period_failure": [item["name"] for item in synthesis_reports if item["risk_flags"]["definite_target_period_failure"]],
        "modules_with_high_routing_sensitivity": [
            item["name"] for item in synthesis_reports
            if item.get("timing_risk", {}).get("routing_sensitivity") == "high"
        ],
        "simulation_memory_models_excluded": [item["name"] for item in reports if item["risk_flags"]["simulation_memory_model_excluded"]],
        "hierarchical_combinational_loops": (
            hierarchy.get("meaningful_cycles", hierarchy.get("cycles", []))
            if hierarchy.get("available") else []
        ),
        "hierarchical_self_cycle_count": hierarchy.get("self_cycle_count", 0) if hierarchy.get("available") else 0,
        "hierarchical_max_depth": hierarchy.get("max_depth", 0) if hierarchy.get("available") else 0,
        "hierarchical_timing_endpoint_max_depth": hierarchy.get("timing_endpoint_max_depth", 0) if hierarchy.get("available") else 0,
        "target_period_ns": args.target_period_ns,
        "timing_possible_depth_threshold": args.timing_possible_depth,
        "timing_definite_depth_threshold": args.timing_definite_depth,
        "timing_path_fail_count": hierarchy.get("timing_path_fail_count", 0),
        "timing_path_high_count": hierarchy.get("timing_path_high_count", 0),
        "timing_path_fail_families": [
            item.get("key") for item in hierarchy.get("timing_path_risks", [])
            if item.get("severity") == "FAIL"
        ],
    }
    for report in reports:
        report.pop("_analysis", None)
    result = {
        "input": str(args.input),
        "top": args.top,
        "provenance": {
            "source_metadata": str(args.source_metadata) if args.source_metadata else None,
            "source_fingerprint": source_metadata.get("source_fingerprint") if source_metadata else None,
            "git_revision": source_metadata.get("git_revision") if source_metadata else None,
            "source_generated_at_utc": source_metadata.get("generated_at_utc") if source_metadata else None,
            "source_count": len(source_metadata.get("sources", [])) if source_metadata else None,
        },
        "module_count": len(reports),
        "summary": summary,
        "hierarchical": hierarchy,
        "memory_geometry_profile": geometry_profile,
        "modules": reports,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(reports)} modules)")
    for item in hierarchy.get("timing_path_risks", []):
        print(
            f"{item.get('severity')} {item.get('key')}: "
            f"estimated={item.get('estimated_upper_delay_ns')}ns "
            f"slack={item.get('estimated_slack_ns')}ns depth={item.get('structural_depth')} "
            f"{item.get('source')} -> {item.get('destination')} "
            f"reasons={','.join(item.get('reasons', []))}"
        )
    for report in reports:
        flags = report["risk_flags"]
        if flags["combinational_loop"] or flags["hierarchical_combinational_loop"] or flags["self_feedback"] or flags["high_fanout_over_32"] or flags["deep_combination_over_8"] or flags["long_register_to_boundary_over_8"] or flags.get("long_input_to_control_over_8") or flags["wide_mux_or_work"] or flags["cross_module_combination_not_cut"]:
            cycle_depth = report["combination"].get("cycle_max_timing_path_depth", 0)
            cycle_kind = ",".join(sorted(report["combination"].get("cycle_kind_counts", {}))) or "-"
            print(f"{report['name']}: depth={report['combination']['max_depth']} cycles={report['combination']['cycle_count']} "
                  f"cycle-kind={cycle_kind} cycle-path={cycle_depth} "
                  f"cross-depth={report['combination']['cross_module_max_depth']} "
                  f"q-to-boundary={report['combination']['register_to_boundary_max_depth']} "
                  f"q-to-d={report['combination']['register_q_to_d_max_depth']} "
                  f"in-to-d={report['combination']['input_to_register_max_depth']} "
                  f"in-to-ce={report['combination']['input_to_control_max_depth']} "
                  f"q-to-output={report['combination']['register_q_to_any_boundary_max_depth']} "
                  f"ops={report['combination']['operator_count']} work={report['combination']['weighted_combination_work']} "
                  f"fanout-risk>{32}={flags['high_fanout_over_32']} self-feedback={flags['self_feedback']}")
        if flags.get("possible_target_period_failure"):
            risk = report["timing_risk"]
            print(f"{report['name']}: timing-risk={risk['classification']} target={risk['target_period_ns']}ns "
                  f"depth={risk['structural_endpoint_depth']} adjusted-depth={risk['memory_adjusted_depth']} "
                  f"routing={risk['routing_sensitivity']} "
                  f"reasons={','.join(risk['reasons'])}")
        if flags.get("hierarchical_combinational_loop"):
            print(f"{report['name']}: hierarchical-depth={report['combination']['hierarchical'].get('max_depth', 0)} "
                  f"hierarchical-cycles={report['combination']['hierarchical'].get('cycle_count', 0)} "
                  f"hierarchical-cycle-path={report['combination']['hierarchical'].get('cycle_max_timing_path_depth', 0)}")
        if report["combinational_outputs"]:
            print(f"{report['name']}: combinational outputs: {', '.join(report['combinational_outputs'])}")
    if args.fail_on_timing_path and hierarchy.get("timing_path_fail_count", 0):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
