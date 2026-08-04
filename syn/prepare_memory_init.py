#!/usr/bin/env python3
"""Create fixed-width Vivado MEM and COE files from a word-oriented image."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


HEX_WORD_RE = re.compile(r"^[0-9a-fA-F]+$")


def load_words(path: Path, width: int) -> list[str]:
    digits = (width + 3) // 4
    words: list[str] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        value = raw_line.strip()
        if not value:
            continue
        if not HEX_WORD_RE.fullmatch(value) or len(value) > digits:
            raise SystemExit(
                f"error: {path}:{line_number}: expected at most {digits} hexadecimal digits")
        words.append(value.lower().zfill(digits))
    if not words:
        raise SystemExit(f"error: memory image is empty: {path}")
    return words


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="ascii")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--mem", type=Path, required=True)
    parser.add_argument("--coe", type=Path, required=True)
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--depth", type=int, required=True)
    args = parser.parse_args()

    if args.width <= 0 or args.width % 8 != 0:
        raise SystemExit("error: --width must be a positive byte multiple")
    if args.depth <= 0:
        raise SystemExit("error: --depth must be positive")

    source = args.input.resolve()
    if not source.is_file():
        raise SystemExit(f"error: memory image not found: {source}")
    words = load_words(source, args.width)
    used_words = len(words)
    if used_words > args.depth:
        raise SystemExit(
            f"error: {source} uses {used_words} words, capacity is {args.depth}")

    digits = (args.width + 3) // 4
    words.extend(["0" * digits] * (args.depth - used_words))
    write_text(args.mem.resolve(), "\n".join(words) + "\n")
    coe_body = ",\n".join(words) + ";\n"
    write_text(
        args.coe.resolve(),
        "memory_initialization_radix=16;\n"
        "memory_initialization_vector=\n" + coe_body,
    )
    print(
        f"staged {source.name}: {used_words}/{args.depth} words, "
        f"width={args.width} bits")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
