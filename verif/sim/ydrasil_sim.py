#!/usr/bin/env python3
"""Ydrasil simulation helper: realtime compare and log compare."""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import time
from typing import Iterable, Optional


def _open_log(path: Optional[str]):
	if not path:
		return None
	return open(path, "w", encoding="utf-8")


def _normalize_line(line: str, strip_prefix: Optional[str], drop_ansi: bool) -> str:
	if drop_ansi:
		# Simple ANSI escape sequence removal.
		cleaned = []
		esc = False
		for ch in line:
			if esc:
				if ch.isalpha():
					esc = False
				continue
			if ch == "\x1b":
				esc = True
				continue
			cleaned.append(ch)
		line = "".join(cleaned)
	if strip_prefix and line.startswith(strip_prefix):
		line = line[len(strip_prefix):]
	return line.rstrip("\n")


def _compare_realtime(args: argparse.Namespace) -> int:
	hw_cmd = shlex.split(args.hw_cmd)
	spike_cmd = shlex.split(args.spike_cmd)

	hw_log = _open_log(args.hw_log)
	spike_log = _open_log(args.spike_log)

	hw_proc = subprocess.Popen(
		hw_cmd,
		stdout=subprocess.PIPE,
		stderr=subprocess.STDOUT if args.merge_stderr else subprocess.PIPE,
		text=True,
		bufsize=1,
		universal_newlines=True,
	)
	spike_proc = subprocess.Popen(
		spike_cmd,
		stdout=subprocess.PIPE,
		stderr=subprocess.STDOUT if args.merge_stderr else subprocess.PIPE,
		text=True,
		bufsize=1,
		universal_newlines=True,
	)

	mismatches = 0
	try:
		while True:
			hw_line = hw_proc.stdout.readline() if hw_proc.stdout else ""
			spike_line = spike_proc.stdout.readline() if spike_proc.stdout else ""

			if hw_line == "" and spike_line == "":
				break

			if hw_log and hw_line:
				hw_log.write(hw_line)
			if spike_log and spike_line:
				spike_log.write(spike_line)

			if args.ignore_empty and not hw_line and not spike_line:
				continue

			hw_norm = _normalize_line(hw_line, args.strip_prefix, args.drop_ansi)
			spike_norm = _normalize_line(spike_line, args.strip_prefix, args.drop_ansi)

			if hw_norm != spike_norm:
				mismatches += 1
				print("Mismatch")
				print(f"HW:    {hw_norm}")
				print(f"SPIKE: {spike_norm}")
				if args.max_mismatches and mismatches >= args.max_mismatches:
					return 1

			if args.delay_ms:
				time.sleep(args.delay_ms / 1000.0)
	finally:
		for proc in (hw_proc, spike_proc):
			if proc.poll() is None:
				proc.terminate()
		if hw_log:
			hw_log.close()
		if spike_log:
			spike_log.close()

	return 0 if mismatches == 0 else 1


def _read_lines(path: str) -> Iterable[str]:
	with open(path, "r", encoding="utf-8", errors="replace") as f:
		for line in f:
			yield line


def _compare_logs(args: argparse.Namespace) -> int:
	if not _convert_logs_to_csv(args):
		return 2

	mismatches = 0
	for idx, (hw_line, spike_line) in enumerate(
		zip(_read_lines(args.hw_csv), _read_lines(args.spike_csv)), start=1
	):
		hw_norm = _normalize_line(hw_line, args.strip_prefix, args.drop_ansi)
		spike_norm = _normalize_line(spike_line, args.strip_prefix, args.drop_ansi)
		if hw_norm != spike_norm:
			mismatches += 1
			print(f"Mismatch at line {idx}")
			print(f"HW:    {hw_norm}")
			print(f"SPIKE: {spike_norm}")
			if args.max_mismatches and mismatches >= args.max_mismatches:
				return 1
	return 0 if mismatches == 0 else 1


def _default_trace_tool() -> str:
	return os.path.join(os.path.dirname(__file__), "riscv_trace_csv.py")


def _default_csv_path(log_path: str, suffix: str) -> str:
	base, _ = os.path.splitext(log_path)
	return base + "_" + suffix + ".csv"


def _run_convert(trace_tool: str, log_path: str, csv_path: str, source: str, full_trace: bool) -> bool:
	cmd = [
		sys.executable,
		trace_tool,
		"--log",
		log_path,
		"--csv",
		csv_path,
		"--source",
		source,
	]
	if full_trace:
		cmd.append("--full_trace")

	proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
	if proc.returncode != 0:
		print(proc.stdout)
		return False
	return True


def _convert_logs_to_csv(args: argparse.Namespace) -> bool:
	trace_tool = args.trace_tool or _default_trace_tool()
	args.hw_csv = args.hw_csv or _default_csv_path(args.hw_log, "hw")
	args.spike_csv = args.spike_csv or _default_csv_path(args.spike_log, "spike")

	if not _run_convert(trace_tool, args.hw_log, args.hw_csv, args.hw_source, args.full_trace):
		return False
	if not _run_convert(trace_tool, args.spike_log, args.spike_csv, args.spike_source, args.full_trace):
		return False
	return True


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description="Ydrasil sim compare helper")
	parser.add_argument(
		"--mode",
		choices=["realtime", "log"],
		default="realtime",
		help="Comparison mode",
	)
	parser.add_argument("--hw-cmd", type=str, default="", help="HW simulator command")
	parser.add_argument("--spike-cmd", type=str, default="", help="Spike command")
	parser.add_argument("--hw-log", type=str, default="", help="HW log file")
	parser.add_argument("--spike-log", type=str, default="", help="Spike log file")
	parser.add_argument("--hw-csv", type=str, default="", help="HW trace CSV output")
	parser.add_argument("--spike-csv", type=str, default="", help="Spike trace CSV output")
	parser.add_argument(
		"--hw-source",
		choices=["spike", "verilator"],
		default="verilator",
		help="HW log format",
	)
	parser.add_argument(
		"--spike-source",
		choices=["spike", "verilator"],
		default="spike",
		help="Spike log format",
	)
	parser.add_argument(
		"--trace-tool",
		default="",
		help="Path to riscv_trace_csv.py",
	)
	parser.add_argument("--merge-stderr", action="store_true", help="Merge stderr into stdout")
	parser.add_argument("--ignore-empty", action="store_true", help="Ignore empty line pairs")
	parser.add_argument("--strip-prefix", type=str, default="", help="Strip fixed prefix")
	parser.add_argument("--drop-ansi", action="store_true", help="Remove ANSI escape codes")
	parser.add_argument("--delay-ms", type=int, default=0, help="Delay between line reads")
	parser.add_argument("--max-mismatches", type=int, default=1, help="Stop after N mismatches")
	parser.add_argument("--full-trace", dest="full_trace", action="store_true", help="Use full trace parsing")
	parser.set_defaults(full_trace=False)
	return parser.parse_args()


def main() -> int:
	args = parse_args()
	if args.mode == "realtime":
		if not args.hw_cmd or not args.spike_cmd:
			print("--hw-cmd and --spike-cmd are required in realtime mode", file=sys.stderr)
			return 2
		return _compare_realtime(args)

	if not args.hw_log or not args.spike_log:
		print("--hw-log and --spike-log are required in log mode", file=sys.stderr)
		return 2
	return _compare_logs(args)


if __name__ == "__main__":
	sys.exit(main())
