#!/usr/bin/env python3
"""Convert one-hex-word-per-line memory data to a Xilinx COE file."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


HEX_WORD = re.compile(r"^[0-9a-fA-F]{1,8}$")


def read_words(path: Path) -> list[str]:
    words: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        word = line.strip()
        if not word:
            continue
        if not HEX_WORD.fullmatch(word):
            raise ValueError(
                f"{path}:{line_number}: invalid 32-bit hexadecimal word: {word!r}"
            )
        words.append(word.lower().zfill(8))
    if not words:
        raise ValueError(f"{path}: no memory words found")
    return words


def write_coe(path: Path, words: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as output:
        output.write("memory_initialization_radix=16;\n")
        output.write("memory_initialization_vector=\n")
        for index, word in enumerate(words):
            terminator = ";" if index == len(words) - 1 else ","
            output.write(f"{word}{terminator}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="one-hex-word-per-line input")
    parser.add_argument("output", type=Path, help="Xilinx COE output")
    args = parser.parse_args()

    words = read_words(args.input)
    write_coe(args.output, words)
    print(f"Converted {len(words)} words: {args.input} -> {args.output}")


if __name__ == "__main__":
    main()
