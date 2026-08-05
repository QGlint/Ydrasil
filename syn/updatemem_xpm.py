#!/usr/bin/env python3
"""Update one Ydrasil XPM memory image in an implemented bitstream."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


PROCESSORS = {
    "itcm": "u_soc_core/u_core/u_ydrasil_mems/u_itcm/u_impl/u_xpm_memory_sdpram",
    "dtcm": "u_soc_core/u_core/u_ydrasil_mems/u_dtcm/u_impl/u_xpm_memory_sdpram",
}


def existing_file(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"file not found: {path}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--memory", choices=sorted(PROCESSORS), required=True)
    parser.add_argument("--mmi", type=existing_file, required=True)
    parser.add_argument("--mem", type=existing_file, required=True)
    parser.add_argument("--bit", type=existing_file, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--updatemem", default="updatemem")
    parser.add_argument("--proc", dest="processor", default=None)
    args = parser.parse_args()

    output = args.out.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        args.updatemem,
        "-force",
        "-meminfo", str(args.mmi),
        "-data", str(args.mem),
        "-bit", str(args.bit),
        "-proc", args.processor or PROCESSORS[args.memory],
        "-out", str(output),
    ]
    subprocess.run(command, check=True)
    print(f"updated {args.memory}: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
