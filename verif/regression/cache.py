#!/usr/bin/env python3
"""Content-addressed completion markers for long Ydrasil regressions."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
from pathlib import Path


SOURCE_SUFFIXES = {
    ".c", ".cc", ".cpp", ".h", ".hh", ".hpp", ".ld", ".lds", ".mk",
    ".pl", ".py", ".s", ".sv", ".svh", ".v", ".vh", ".yaml", ".yml",
}
SOURCE_NAMES = {"Makefile", "config.mk", "Bender.yml", "Bender.yaml"}
SCOPE_PATHS = {
    "rtl": ("Makefile", "config.mk", "hw/ip"),
    "coverage_all": (
        "Makefile", "config.mk", "hw/ip", "sw/Makefile", "sw/bsp",
        "sw/apps/boundary", "sw/apps/coremark", "verif/tests", "verif/coverage",
    ),
    "sort": (
        "Makefile", "config.mk", "hw/ip", "sw/Makefile", "sw/bsp",
        "sw/apps/sort",
    ),
    "sort_opt": (
        "Makefile", "config.mk", "hw/ip", "sw/Makefile", "sw/bsp",
        "sw/apps/sort",
    ),
}


def _source_files(project_root: Path, scope: str) -> list[Path]:
    files: set[Path] = set()
    for relative in SCOPE_PATHS[scope]:
        path = project_root / relative
        if path.is_file():
            files.add(path)
            continue
        if not path.is_dir():
            continue
        for item in path.rglob("*"):
            if not item.is_file() or "__pycache__" in item.parts:
                continue
            relative_item = item.relative_to(project_root)
            if relative_item.parts[:2] == ("hw", "ip") and "dv" in relative_item.parts[2:]:
                continue
            if item.name in SOURCE_NAMES or item.suffix.lower() in SOURCE_SUFFIXES:
                files.add(item)
    return sorted(files)


def fingerprint(project_root: Path, scope: str) -> str:
    digest = hashlib.sha256(f"ydrasil-regression-cache-v1:{scope}\n".encode())
    for path in _source_files(project_root, scope):
        digest.update(path.relative_to(project_root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _read_state(path: Path) -> dict[str, object] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None


def command_check(args: argparse.Namespace) -> int:
    expected = fingerprint(args.project_root, args.scope)
    state = _read_state(args.state)
    artifacts = [path.resolve() for path in args.artifact]
    valid = bool(
        state
        and state.get("complete") is True
        and state.get("scope") == args.scope
        and state.get("fingerprint") == expected
        and all(path.exists() for path in artifacts)
    )
    result = "HIT" if valid else "MISS"
    print(f"[REGRESSION CACHE] {result} scope={args.scope} fingerprint={expected[:12]}")
    return 0 if valid else 1


def command_record(args: argparse.Namespace) -> int:
    artifacts = [path.resolve() for path in args.artifact]
    missing = [str(path) for path in artifacts if not path.exists()]
    if missing:
        raise SystemExit(f"cannot record completion; missing artifacts: {', '.join(missing)}")
    current_fingerprint = fingerprint(args.project_root, args.scope)
    if args.expected_fingerprint and args.expected_fingerprint != current_fingerprint:
        raise SystemExit(
            "inputs changed while the regression was running; completion was not recorded"
        )
    value = {
        "complete": True,
        "scope": args.scope,
        "fingerprint": current_fingerprint,
        "artifacts": [str(path) for path in artifacts],
        "completed_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "pid": os.getpid(),
    }
    args.state.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.state.with_suffix(args.state.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(args.state)
    print(
        f"[REGRESSION CACHE] RECORDED scope={args.scope} "
        f"fingerprint={value['fingerprint'][:12]} state={args.state}"
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("fingerprint", "check", "record"))
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--scope", choices=tuple(SCOPE_PATHS), required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    parser.add_argument("--expected-fingerprint")
    args = parser.parse_args()
    args.project_root = args.project_root.resolve()
    if args.command in {"check", "record"} and args.state is None:
        parser.error(f"{args.command} requires --state")
    return args


def main() -> int:
    args = parse_args()
    if args.command == "fingerprint":
        print(fingerprint(args.project_root, args.scope))
        return 0
    if args.command == "check":
        return command_check(args)
    return command_record(args)


if __name__ == "__main__":
    raise SystemExit(main())
