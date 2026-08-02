#!/usr/bin/env python3
"""Turn a generated Bender file list into a Yosys-Slang batch script."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flist", type=Path, required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--family", default="xc7")
    parser.add_argument("--run", default="coarse:map_luts")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--stat-json", type=Path, required=True)
    parser.add_argument("--netlist-json", type=Path, required=True)
    args = parser.parse_args()

    include_dirs: list[str] = []
    defines: list[str] = []
    sources: list[str] = []
    for raw_line in args.flist.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("+incdir+"):
            include_dirs.append(line[len("+incdir+"):])
        elif line.startswith("+define+"):
            defines.append(line[len("+define+"):])
        else:
            sources.append(line)

    # Yosys command files do not perform shell expansion.  Bender paths are
    # absolute and the repository intentionally avoids spaces in RTL paths.
    read_args = ["read_slang", "--std", "1800-2017"]
    for path in include_dirs:
        read_args.extend(["-I", path])
    for define in defines:
        read_args.extend(["-D", define])
    read_args.extend(sources)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.stat_json.parent.mkdir(parents=True, exist_ok=True)
    args.netlist_json.parent.mkdir(parents=True, exist_ok=True)
    script = " ".join(read_args) + "\n"
    script += f"hierarchy -top {args.top}\n"
    # Keep memories as $mem cells until synth_xilinx can apply the XC7 RAM
    # rules.  A plain `memory` command would eagerly expand the 64K DTCM into
    # hundreds of thousands of flip-flops before the FPGA mapper sees it.
    script += "proc\nopt\nmemory -nomap\nopt\n"
    script += f"synth_xilinx -family {args.family} -top {args.top} -run {args.run}\n"
    script += "flatten\nopt\n"
    # Yosys 0.67 prints stat JSON to stdout; Make extracts this object from the
    # build log after the run.  Redirect syntax here would be parsed as a
    # selection expression by Yosys.
    script += f"stat -json -top {args.top}\n"
    script += "ltp -noff\n"
    script += f"write_json {args.netlist_json}\n"
    args.out.write_text(script, encoding="utf-8")
    print(f"wrote {args.out} for top {args.top} ({len(sources)} sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
