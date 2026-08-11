#!/usr/bin/env python3
"""Update one Ydrasil XPM memory image in an implemented bitstream."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


PROCESSORS = {
    "itcm": "u_soc_core/u_core/u_ydrasil_mems/u_itcm/u_impl/u_xpm_memory_sdpram/xpm_memory_base_inst",
    "dtcm": "u_soc_core/u_core/u_ydrasil_mems/u_dtcm/u_impl/u_xpm_memory_sdpram/xpm_memory_base_inst",
}


def existing_file(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"file not found: {path}")
    return path


def addressed_mem(source: Path) -> Path:
    lines = source.read_text(encoding="ascii").splitlines()
    first = next((line.strip() for line in lines if line.strip()), "")
    if first.startswith("@"):
        return source

    output = source.with_suffix(".addressed.mem")
    output.write_text("@00000000\n" + "\n".join(lines) + "\n", encoding="ascii")
    return output


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
    output.unlink(missing_ok=True)
    data = addressed_mem(args.mem)
    command = [
        args.updatemem,
        "-force",
        "-meminfo", str(args.mmi),
        "-data", str(data),
        "-bit", str(args.bit),
        "-proc", args.processor or PROCESSORS[args.memory],
        "-out", str(output),
    ]
    subprocess.run(command, check=True)
    if not output.is_file() or output.stat().st_size == 0:
        raise SystemExit(
            "error: updatemem reported success but did not create a bitstream: "
            f"{output}")
    print(f"updated {args.memory}: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
