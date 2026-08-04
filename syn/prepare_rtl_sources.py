#!/usr/bin/env python3
"""Create deterministic RTL file lists from a Bender package.

The generated file list is accepted by Verilator and is also the source of
truth for the Yosys-Slang and Vivado OOC targets.  Xilinx wrappers are added
last and any generic module shadowed by a wrapper is removed first.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


MODULE_RE = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b", re.MULTILINE)
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_RE = re.compile(r"//.*?$", re.MULTILINE)


def strip_comments(text: str) -> str:
    return LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", text))


def modules_in_file(path: Path) -> set[str]:
    try:
        return set(MODULE_RE.findall(strip_comments(path.read_text(encoding="utf-8", errors="ignore"))))
    except OSError:
        return set()


def unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def source_fingerprint(files: list[str]) -> str:
    """Hash the exact source snapshot used by a generated file list."""
    digest = hashlib.sha256()
    for file_name in files:
        path = Path(file_name)
        digest.update(str(path).encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
        digest.update(b"\0")
    return digest.hexdigest()


def git_revision(repo_root: Path) -> str | None:
    try:
        return subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def run_bender(bender: str, bender_dir: Path, targets: list[str]) -> list[str]:
    command = [bender, "--no-progress", "-d", str(bender_dir), "script", "flist-plus"]
    for target in targets:
        command.extend(["-t", target])
    try:
        completed = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise SystemExit(f"error: Bender executable not found: {bender}") from None
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr)
        raise SystemExit(f"error: Bender source generation failed ({exc.returncode})") from None
    return completed.stdout.splitlines()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--bender", default="bender")
    parser.add_argument("--bender-dir", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--wrapper-dir", type=Path, default=None)
    parser.add_argument("--with-wrappers", action="store_true")
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, default=None)
    args = parser.parse_args()
    if not args.target:
        args.target = ["verilator"]

    repo_root = args.repo_root.resolve()
    bender_dir = args.bender_dir.resolve()
    wrapper_dir = (args.wrapper_dir or repo_root / "hw/ip/Xilinx_ip_wrapper/rtl").resolve()
    lines = run_bender(args.bender, bender_dir, args.target)

    incdirs = unique([line[len("+incdir+"):].strip() for line in lines if line.startswith("+incdir+")])
    defines = unique([line[len("+define+"):].strip() for line in lines if line.startswith("+define+")] + args.define)
    files = unique([str(Path(line.strip()).resolve()) for line in lines if line.strip() and not line.startswith("+")])

    skipped: list[str] = []
    wrappers: list[Path] = []
    if args.with_wrappers:
        wrappers = sorted(wrapper_dir.glob("*.sv"))
        wrapper_modules = set().union(*(modules_in_file(path) for path in wrappers))
        filtered: list[str] = []
        for file_name in files:
            # ydrmem/rtl contains simulation/inference models.  A Vivado
            # wrapper build must use only the Xilinx replacements, including
            # the integrated LUTRAM model, rather than compiling both trees.
            if "/hw/ip/ydrmem/rtl/" in file_name.replace("\\", "/"):
                skipped.append(f"{file_name}:generic-memory-model")
                continue
            overlap = modules_in_file(Path(file_name)) & wrapper_modules
            if overlap:
                skipped.append(f"{file_name}:{','.join(sorted(overlap))}")
            else:
                filtered.append(file_name)
        files = filtered
        files.extend(str(path.resolve()) for path in wrappers)

    files = unique(files)
    incdirs = unique([str(Path(path).resolve()) for path in incdirs if Path(path).is_dir()])
    missing = [path for path in files if not Path(path).is_file()]
    if missing:
        for path in missing:
            print(f"missing RTL source: {path}", file=sys.stderr)
        return 2

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as output:
        output.write("# Generated by syn/prepare_rtl_sources.py. Do not edit.\n")
        for path in incdirs:
            output.write(f"+incdir+{path}\n")
        for define in defines:
            output.write(f"+define+{define}\n")
        for path in files:
            output.write(f"{path}\n")

    metadata = {
        "bender_dir": str(bender_dir),
        "targets": args.target,
        "wrapper_dir": str(wrapper_dir),
        "with_wrappers": args.with_wrappers,
        "include_dirs": incdirs,
        "defines": defines,
        "sources": files,
        "skipped_shadowed_sources": skipped,
        "source_fingerprint": source_fingerprint(files),
        "git_revision": git_revision(repo_root),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    if args.metadata:
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"wrote {args.out} with {len(files)} RTL sources")
    for item in skipped:
        print(f"skipped wrapper-shadowed source: {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
