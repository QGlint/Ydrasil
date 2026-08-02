#!/usr/bin/env python3
"""Extract the machine-readable object emitted by ``stat -json``."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--top", required=True)
    args = parser.parse_args()
    text = args.log.read_text(encoding="utf-8", errors="replace")
    decoder = json.JSONDecoder()
    ltp_match = re.search(r"Longest topological path in\s+(.+?)\s+\(length=(\d+)\):", text)
    for offset, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[offset:])
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict) or not isinstance(value.get("modules"), dict):
            continue
        if args.top not in value["modules"] and not value["modules"]:
            continue
        analysis = value.get("analysis")
        if not isinstance(analysis, dict):
            analysis = {}
            value["analysis"] = analysis
        if ltp_match:
            analysis["ltp_module"] = ltp_match.group(1)
            analysis["ltp_length"] = int(ltp_match.group(2))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"wrote {args.output}")
        return 0
    print(f"error: stat JSON for {args.top} not found in {args.log}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
