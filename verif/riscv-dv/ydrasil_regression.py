#!/usr/bin/env python3
"""Cached, bounded-parallel riscv-dv regression driver for Ydrasil."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import gzip
import hashlib
import json
import os
import re
import secrets
import signal
import shutil
import sqlite3
import statistics
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

MAX_JOBS = 20
ITCM_WORDS = 16 * 1024 // 4
DTCM_WORDS = 256 * 1024 // 4
DIRECTED_REGION_BYTES = 4096


@dataclass(frozen=True)
class Profile:
    target: str
    arch: str
    abi: str
    instr_count: int
    subprograms: int
    version: int = 6


def _json_dump(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def _tree_hash(paths: list[Path], extra: dict[str, Any]) -> str:
    digest = hashlib.sha256(json.dumps(extra, sort_keys=True).encode())
    for root in paths:
        if root.is_file():
            files = [root]
        else:
            files = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix in {".py", ".h", ".s", ".ld"})
        for path in files:
            digest.update(str(path).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()[:12]


def _profile_id(args: argparse.Namespace) -> tuple[Profile, str]:
    profile = Profile(
        target=args.target,
        arch=args.arch,
        abi=args.abi,
        instr_count=args.instr_count,
        subprograms=args.subprograms,
    )
    source_hash = _tree_hash(
        [args.dv_root / "pygen/pygen_src", args.dv_root / "user_extension", args.linker],
        asdict(profile),
    )
    return profile, f"{profile.target}_i{profile.instr_count}_s{profile.subprograms}_{source_hash}"


def _suite_id(profile_id: str, start_seed: int, count: int) -> str:
    return f"{profile_id}_seed{start_seed}_n{count}"


def _run_logged(
    cmd: list[str],
    log: Path,
    cwd: Path,
    timeout: int | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as stream:
        return subprocess.run(
            cmd,
            cwd=cwd,
            stdout=stream,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
            env=env,
            start_new_session=True,
        )


def _binary_to_mem(binary: Path, mem: Path) -> int:
    data = binary.read_bytes()
    if len(data) % 4:
        data += b"\0" * (4 - len(data) % 4)
    with mem.open("w", encoding="ascii") as stream:
        for offset in range(0, len(data), 4):
            stream.write(f"{int.from_bytes(data[offset:offset + 4], 'little'):08x}\n")
    return len(data) // 4


def _symbol_address(gcc: Path, elf: Path, symbol: str) -> int:
    nm = gcc.with_name(gcc.name.removesuffix("gcc") + "nm")
    output = subprocess.check_output([str(nm), "-n", str(elf)], text=True)
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-1] == symbol:
            return int(fields[0], 16)
    raise RuntimeError(f"ELF symbol not found: {symbol}")


def _case_dir(args: argparse.Namespace, profile_id: str, seed: int) -> Path:
    return args.work_root / "cache" / profile_id / f"seed_{seed}"


def _case_ready(case_dir: Path) -> bool:
    return all((case_dir / name).is_file() for name in ("ready.json", "program.elf", "program.itcm", "program.dtcm"))


def _validate_directed_load_store(asm: Path) -> None:
    start_re = re.compile(
        r"\bla\s+(?P<reg>[a-z0-9]+)\s*,\s*"
        r"(?:h\d+_)?(?:s_)?region_\d+\+(?P<base>-?\d+).*"
        r"#start riscv_load_store_(?:hazard|rand|stress|base)_instr_stream"
    )
    access_re = re.compile(
        r"^\s*(?:[A-Za-z0-9_]+:\s*)?"
        r"(?P<op>lb|lbu|lh|lhu|lw|sb|sh|sw)\s+"
        r"[^,]+,\s*(?P<offset>-?\d+)\s*\(\s*(?P<reg>[a-z0-9]+)\s*\)"
    )
    widths = {"lb": 1, "lbu": 1, "sb": 1, "lh": 2, "lhu": 2, "sh": 2,
              "lw": 4, "sw": 4}
    active: tuple[str, int, int] | None = None
    checked = 0
    for line_number, line in enumerate(asm.read_text(encoding="utf-8").splitlines(), 1):
        start = start_re.search(line)
        if start:
            if active is not None:
                raise RuntimeError(f"ASM validator: nested load/store stream at line {line_number}")
            active = (start.group("reg"), int(start.group("base")), line_number)
        if active is None:
            continue
        access = access_re.search(line)
        if access:
            base_reg, base, start_line = active
            op = access.group("op")
            access_reg = access.group("reg")
            offset = int(access.group("offset"))
            address = base + offset
            width = widths[op]
            if access_reg != base_reg:
                raise RuntimeError(
                    f"ASM validator: stream at line {start_line} initializes {base_reg}, "
                    f"but line {line_number} uses {access_reg}"
                )
            if address % width:
                raise RuntimeError(
                    f"ASM validator: misaligned {op} at line {line_number}: "
                    f"base={base} offset={offset} address={address}"
                )
            if address < 0 or address + width > DIRECTED_REGION_BYTES:
                raise RuntimeError(
                    f"ASM validator: out-of-range {op} at line {line_number}: "
                    f"address={address} width={width}"
                )
            checked += 1
        if "#end riscv_load_store_" in line:
            active = None
    if active is not None:
        raise RuntimeError(f"ASM validator: unterminated load/store stream at line {active[2]}")
    if checked == 0:
        raise RuntimeError("ASM validator: generated test contains no directed load/store accesses")


def _prepare_one(args: argparse.Namespace, profile: Profile, profile_id: str, seed: int) -> dict[str, Any]:
    started = time.monotonic()
    case_dir = _case_dir(args, profile_id, seed)
    if _case_ready(case_dir):
        os.utime(case_dir / "ready.json", None)
        return {"seed": seed, "status": "cached", "elapsed": time.monotonic() - started}

    case_dir.mkdir(parents=True, exist_ok=True)
    lock = case_dir / ".prepare.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        return {"seed": seed, "status": "busy", "elapsed": time.monotonic() - started}

    tmp = case_dir / f".tmp_{os.getpid()}_{time.time_ns()}"
    tmp.mkdir()
    try:
        generator_log = tmp / "generator.log"
        asm_prefix = tmp / "program"
        gen_cmd = [
            str(args.python),
            str(args.dv_root / "pygen/pygen_src/test/riscv_instr_base_test.py"),
            f"--target={profile.target}",
            "--gen_test=riscv_instr_base_test",
            "--num_of_tests=1",
            f"--seed={seed}",
            f"--asm_file_name={asm_prefix}",
            f"--log_file_name={generator_log}",
            f"--instr_cnt={profile.instr_count}",
            f"--num_of_sub_program={profile.subprograms}",
            "--bare_program_mode=1",
            "--disable_compressed_instr=1",
            "--fix_sp=1",
            "--no_csr_instr=1",
            "--no_ebreak=1",
            "--no_dret=1",
            "--no_wfi=1",
            "--enable_interrupt=0",
            "--enable_unaligned_load_store=0",
            "--illegal_instr_ratio=0",
            "--hint_instr_ratio=0",
            "--directed_instr_0=riscv_load_store_hazard_instr_stream,12",
            "--directed_instr_1=riscv_jal_instr,8",
            "--directed_instr_2=riscv_int_numeric_corner_stream,8",
        ]
        result = _run_logged(gen_cmd, tmp / "prepare.log", args.dv_root, args.prepare_timeout)
        asm = tmp / "program_0.S"
        if result.returncode or not asm.is_file():
            raise RuntimeError(f"generator failed with exit code {result.returncode}")
        _validate_directed_load_store(asm)

        elf = tmp / "program.elf"
        gcc_cmd = [
            str(args.gcc),
            f"-march={profile.arch}",
            f"-mabi={profile.abi}",
            "-nostdlib",
            "-nostartfiles",
            "-static",
            "-mcmodel=medany",
            f"-I{args.dv_root / 'user_extension'}",
            "-T",
            str(args.linker),
            str(asm),
            "-o",
            str(elf),
        ]
        result = _run_logged(gcc_cmd, tmp / "compile.log", args.project_root, args.prepare_timeout)
        if result.returncode or not elf.is_file():
            raise RuntimeError(f"GCC failed with exit code {result.returncode}")

        itcm_bin = tmp / "program.itcm.bin"
        dtcm_bin = tmp / "program.dtcm.bin"
        objcopy_common = [str(args.objcopy), "-O", "binary", "--gap-fill=0x00"]
        subprocess.run(objcopy_common + ["--only-section=.text", str(elf), str(itcm_bin)], check=True)
        dtcm_sections = [
            ".data",
            ".region_*",
            ".amo_*",
            ".s_region_*",
            ".user_stack",
            ".kernel_data",
            ".kernel_stack",
            ".page_table",
            ".bss",
        ]
        subprocess.run(
            objcopy_common + [item for section in dtcm_sections for item in (f"--only-section={section}",)] + [str(elf), str(dtcm_bin)],
            check=True,
        )
        itcm_words = _binary_to_mem(itcm_bin, tmp / "program.itcm")
        dtcm_words = _binary_to_mem(dtcm_bin, tmp / "program.dtcm")
        if itcm_words > ITCM_WORDS or dtcm_words > DTCM_WORDS:
            raise RuntimeError(f"memory overflow: ITCM={itcm_words}/{ITCM_WORDS}, DTCM={dtcm_words}/{DTCM_WORDS} words")

        with asm.open("rb") as source, gzip.open(tmp / "program.S.gz", "wb", compresslevel=6) as target:
            shutil.copyfileobj(source, target)
        ready = {
            "seed": seed,
            "profile": asdict(profile),
            "profile_id": profile_id,
            "itcm_words": itcm_words,
            "dtcm_words": dtcm_words,
            "elf_bytes": elf.stat().st_size,
            "write_tohost": _symbol_address(args.gcc, elf, "write_tohost"),
            "prepared_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        }
        for name in ("program.elf", "program.itcm", "program.dtcm", "program.S.gz"):
            (tmp / name).replace(case_dir / name)
        _json_dump(case_dir / "ready.json", ready)
        shutil.rmtree(case_dir / "prepare_failure", ignore_errors=True)
        shutil.rmtree(tmp)
        return {"seed": seed, "status": "prepared", "elapsed": time.monotonic() - started, **ready}
    except Exception as error:
        error_dir = case_dir / "prepare_failure"
        if error_dir.exists():
            shutil.rmtree(error_dir)
        tmp.replace(error_dir)
        _json_dump(error_dir / "error.json", {"seed": seed, "error": str(error)})
        return {"seed": seed, "status": "failed", "elapsed": time.monotonic() - started, "error": str(error)}
    finally:
        lock.unlink(missing_ok=True)


def _db_open(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute(
        """CREATE TABLE IF NOT EXISTS results (
        seed INTEGER PRIMARY KEY, status TEXT NOT NULL, elapsed REAL NOT NULL,
        reason TEXT NOT NULL, returncode INTEGER NOT NULL, metrics TEXT NOT NULL,
        artifact_dir TEXT NOT NULL, updated_at TEXT NOT NULL)"""
    )
    db.commit()
    return db


def _seed_history_open(args: argparse.Namespace, profile_id: str) -> sqlite3.Connection:
    path = args.work_root / "history" / f"{profile_id}.sqlite3"
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute(
        "CREATE TABLE IF NOT EXISTS seeds ("
        "seed INTEGER PRIMARY KEY, allocated_at TEXT NOT NULL)"
    )
    db.execute(
        "CREATE TABLE IF NOT EXISTS failures ("
        "seed INTEGER PRIMARY KEY, first_seen TEXT NOT NULL, "
        "last_seen TEXT NOT NULL, last_status TEXT NOT NULL)"
    )

    known_seeds: set[int] = set()
    known_failures: dict[int, str] = {}
    profile_dir = args.work_root / "cache" / profile_id
    for case_dir in profile_dir.glob("seed_*"):
        try:
            known_seeds.add(int(case_dir.name.removeprefix("seed_")))
        except ValueError:
            continue
    for result_root in (args.work_root / "runs", args.work_root / "repro"):
        for result_db in result_root.glob(f"*{profile_id}*/results.sqlite3"):
            try:
                source = sqlite3.connect(result_db)
                for seed, status in source.execute("SELECT seed, status FROM results"):
                    known_seeds.add(seed)
                    if status in {"FAIL", "TIMEOUT", "ERROR"}:
                        known_failures[seed] = status
                source.close()
            except sqlite3.Error:
                continue
    now = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    db.executemany(
        "INSERT OR IGNORE INTO seeds VALUES (?, ?)",
        ((seed, now) for seed in known_seeds),
    )
    db.executemany(
        "INSERT OR IGNORE INTO failures VALUES (?, ?, ?, ?)",
        ((seed, now, now, status) for seed, status in known_failures.items()),
    )
    db.commit()
    return db


def _reserve_random_seed(db: sqlite3.Connection) -> int:
    while True:
        seed = secrets.randbelow(0x7fff_ffff) + 1
        try:
            db.execute(
                "INSERT INTO seeds VALUES (?, ?)",
                (seed, time.strftime("%Y-%m-%dT%H:%M:%S%z")),
            )
            db.commit()
            return seed
        except sqlite3.IntegrityError:
            continue


def _record_permanent_result(db: sqlite3.Connection, seed: int, status: str) -> None:
    now = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    db.execute(
        "INSERT INTO failures VALUES (?, ?, ?, ?) "
        "ON CONFLICT(seed) DO UPDATE SET last_seen=excluded.last_seen, "
        "last_status=excluded.last_status",
        (seed, now, now, status),
    )
    db.commit()


def _active_runner_pid(runner_file: Path) -> int | None:
    if not runner_file.is_file():
        return None
    try:
        pid = int(json.loads(runner_file.read_text(encoding="utf-8"))["pid"])
    except (KeyError, ValueError, json.JSONDecodeError):
        runner_file.unlink(missing_ok=True)
        return None
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        runner_file.unlink(missing_ok=True)
        return None
    except PermissionError:
        pass
    return pid


def _tail(path: Path, lines: int = 80) -> str:
    if not path.is_file():
        return ""
    return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])


def _metrics(hw_log: Path) -> list[str]:
    if not hw_log.is_file():
        return []
    prefixes = ("PERF_METRIC:", "PERF_STALL:", "PERF_BRANCH:", "PERF_BP_ACC:")
    return [line for line in hw_log.read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith(prefixes)]


def _spike_tail_is_terminal(hw_csv: Path, spike_csv: Path, finish_pc: int) -> bool:
    if not hw_csv.is_file() or not spike_csv.is_file():
        return False
    with hw_csv.open(newline="", encoding="utf-8", errors="replace") as stream:
        hw_rows = list(csv.DictReader(stream))
    with spike_csv.open(newline="", encoding="utf-8", errors="replace") as stream:
        spike_rows = list(csv.DictReader(stream))
    if len(spike_rows) < len(hw_rows):
        return False
    for row in spike_rows[len(hw_rows):]:
        try:
            if int(row.get("pc", "0"), 16) != finish_pc:
                return False
        except ValueError:
            return False
    return True


def _run_one(args: argparse.Namespace, profile: Profile, profile_id: str, suite_dir: Path, seed: int) -> dict[str, Any]:
    started = time.monotonic()
    case_dir = _case_dir(args, profile_id, seed)
    if not _case_ready(case_dir):
        return {"seed": seed, "status": "ERROR", "reason": "prepared artifacts missing", "returncode": 2, "elapsed": 0.0, "work": "", "metrics": []}
    ready = json.loads((case_dir / "ready.json").read_text(encoding="utf-8"))
    finish_pc = int(ready["write_tohost"])

    work = suite_dir / "tmp" / f"seed_{seed}"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    hw_log = work / "hw.log"
    compare_log = work / "compare.log"
    driver_log = work / "driver.log"
    coverage_file = suite_dir / "coverage" / "pending" / f"seed_{seed}.dat"
    coverage_file.parent.mkdir(parents=True, exist_ok=True)
    coverage_file.unlink(missing_ok=True)
    cmd = [
        str(args.make),
        "--no-print-directory",
        "sim_compare",
        "SIM_COMPARE=csv",
        "VERILATOR_COVERAGE=1",
        "VERILATOR_TRACE=0",
        f"OBJ_DIR={args.model_dir}",
        f"ARCH={profile.arch}",
        f"ABI={profile.abi}",
        "PRIV=m",
        f"SPIKE={args.spike}",
        f"SPIKE_MAXSTEPS={args.spike_maxsteps}",
        f"COMPARE_NAME=riscv-dv/{profile_id}/seed_{seed}",
        f"COMPARE_ELF={case_dir / 'program.elf'}",
        f"COMPARE_ITCM={case_dir / 'program.itcm'}",
        f"COMPARE_DTCM={case_dir / 'program.dtcm'}",
        f"COMPARE_OUT_DIR={work / 'compare'}",
        f"COMPARE_HW_OUT_DIR={work / 'hw'}",
        f"COMPARE_HW_LOG={hw_log}",
        f"COMPARE_SPIKE_LOG={work / 'spike.log'}",
        f"COMPARE_HW_CSV={work / 'hw.csv'}",
        f"COMPARE_SPIKE_CSV={work / 'spike.csv'}",
        f"COMPARE_LOG={compare_log}",
        f"COVERAGE_DATA_DIR={coverage_file.parent}",
        f"COMPARE_COVERAGE_FILE={coverage_file}",
        "COMPARE_COMPLETE_PROGRAM=1",
        "COMPARE_ALLOW_SPIKE_TAIL=1",
        "COMPARE_MAX_SPIKE_TAIL=0",
        "COMPARE_GPR_IGNORE_MASK=0x1800",
        f"SIM_COMPARE_MAX_MISMATCHES={args.max_mismatches}",
        f"COMPARE_SIM_EXTRA_DEFINES=+cpp_timeout={args.sim_timeout} +sv_timeout={args.sim_timeout} +finish_pc={finish_pc:08x}",
    ]
    env = os.environ.copy()
    env.pop("MAKEFLAGS", None)
    env.pop("MFLAGS", None)
    try:
        result = _run_logged(cmd, driver_log, args.project_root, args.case_timeout, env)
        hw_text = hw_log.read_text(encoding="utf-8", errors="replace") if hw_log.is_file() else ""
        compare_text = compare_log.read_text(encoding="utf-8", errors="replace") if compare_log.is_file() else ""
        terminal_tail = _spike_tail_is_terminal(work / "hw.csv", work / "spike.csv", finish_pc)
        passed = result.returncode == 0 and "MATCH: YES" in compare_text and "TEST_PASS" in hw_text and terminal_tail
        if passed:
            status, reason = "PASS", "Spike commit trace matched and test reached write_tohost"
        elif "TEST_PASS" not in hw_text:
            status, reason = "TIMEOUT", "RTL did not reach TEST_PASS before timeout"
        elif "MATCH: YES" not in compare_text:
            status, reason = "FAIL", "Spike/RTL commit trace mismatch"
        elif not terminal_tail:
            status, reason = "FAIL", "Spike tail escaped the write_tohost terminal loop"
        else:
            status, reason = "ERROR", f"comparison command exited {result.returncode}"
        return {
            "seed": seed,
            "status": status,
            "reason": reason,
            "returncode": result.returncode,
            "elapsed": time.monotonic() - started,
            "work": str(work),
            "metrics": _metrics(hw_log),
            "tail": _tail(compare_log) or _tail(driver_log),
            "coverage": str(coverage_file) if coverage_file.is_file() else "",
        }
    except subprocess.TimeoutExpired:
        return {"seed": seed, "status": "TIMEOUT", "reason": "host-side case timeout", "returncode": 124, "elapsed": time.monotonic() - started, "work": str(work), "metrics": [], "tail": _tail(driver_log), "coverage": str(coverage_file) if coverage_file.is_file() else ""}


def _gzip_failure_files(directory: Path) -> None:
    for path in directory.rglob("*"):
        if path.is_file() and path.suffix in {".csv", ".log"} and path.stat().st_size > 4096:
            with path.open("rb") as source, gzip.open(str(path) + ".gz", "wb", compresslevel=6) as target:
                shutil.copyfileobj(source, target)
            path.unlink()


def _disk_usage(path: Path) -> tuple[int, int]:
    total = 0
    files = 0
    if not path.exists():
        return total, files
    for item in path.rglob("*"):
        if item.is_file():
            files += 1
            total += item.stat().st_size
    return total, files


def _prepared_seed_sizes(profile_dir: Path) -> list[int]:
    return [
        sum(path.stat().st_size for path in ready.parent.iterdir() if path.is_file())
        for ready in profile_dir.glob("seed_*/ready.json")
    ] if profile_dir.exists() else []


def _merge_coverage(args: argparse.Namespace, suite_dir: Path) -> int:
    coverage_dir = suite_dir / "coverage"
    pending_dir = coverage_dir / "pending"
    inputs = sorted(p for p in pending_dir.glob("*.dat") if p.stat().st_size) if pending_dir.exists() else []
    if not inputs:
        return 0
    merged = coverage_dir / "merged.dat"
    output = coverage_dir / "merged.next.dat"
    cmd = [str(args.verilator_coverage), "--write", str(output)]
    if merged.is_file():
        cmd.append(str(merged))
    cmd.extend(str(path) for path in inputs)
    result = subprocess.run(cmd, cwd=args.project_root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    if result.returncode or not output.is_file():
        (coverage_dir / "merge-error.log").write_text(result.stdout, encoding="utf-8")
        return 1
    output.replace(merged)
    for path in inputs:
        path.unlink(missing_ok=True)
    info = coverage_dir / "coverage.info"
    subprocess.run(
        [str(args.verilator_coverage), "--write-info", str(info), str(merged)],
        cwd=args.project_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return 0


def _write_summary(
    suite_dir: Path,
    suite_id: str,
    rows: list[dict[str, Any]],
    prepared: int,
    cached: int,
    planned: int,
    stopped: bool,
) -> dict[str, Any]:
    counts: dict[str, int] = {}
    elapsed = []
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
        elapsed.append(float(row["elapsed"]))
    bytes_used, files = _disk_usage(suite_dir)
    summary = {
        "suite_id": suite_id,
        "counts": counts,
        "total": len(rows),
        "planned": planned,
        "stopped": stopped,
        "prepared": prepared,
        "cache_hits": cached,
        "elapsed_case_seconds": sum(elapsed),
        "median_case_seconds": statistics.median(elapsed) if elapsed else 0.0,
        "suite_bytes": bytes_used,
        "suite_files": files,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    _json_dump(suite_dir / "summary.json", summary)
    with (suite_dir / "summary.log").open("w", encoding="utf-8") as stream:
        stream.write(f"[RISCV-DV] SUITE={suite_id}\n")
        stream.write("[RISCV-DV] " + " ".join(f"{key}={value}" for key, value in sorted(counts.items())) + f" COMPLETED={len(rows)} PLANNED={planned} STOPPED={int(stopped)}\n")
        stream.write(f"[RISCV-DV] CASE_SECONDS_SUM={sum(elapsed):.1f} MEDIAN={summary['median_case_seconds']:.3f}\n")
        stream.write(f"[RISCV-DV] DISK_BYTES={bytes_used} FILES={files}\n")
    return summary


def command_prepare(args: argparse.Namespace) -> int:
    profile, profile_id = _profile_id(args)
    seeds = list(range(args.start_seed, args.start_seed + args.count))
    args.work_root.mkdir(parents=True, exist_ok=True)
    profile_dir = args.work_root / "cache" / profile_id
    missing_count = sum(not _case_ready(_case_dir(args, profile_id, seed)) for seed in seeds)
    profile_bytes, _ = _disk_usage(profile_dir)
    sizes = _prepared_seed_sizes(profile_dir)
    per_seed = int(statistics.median(sizes)) if sizes else 128 * 1024
    projected_bytes = profile_bytes + missing_count * per_seed
    cache_limit = int(args.max_cache_gb * 1024 * 1024 * 1024)
    if missing_count and projected_bytes > cache_limit:
        print(
            f"[PREPARE] ERROR: projected current-profile cache is {projected_bytes} bytes, "
            f"above the {cache_limit} byte limit; reduce --count or raise --max-cache-gb",
            file=sys.stderr,
        )
        return 2
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(_prepare_one, args, profile, profile_id, seed): seed for seed in seeds}
        for future in concurrent.futures.as_completed(futures):
            row = future.result()
            results.append(row)
            print(f"[PREPARE] seed={row['seed']} status={row['status']} elapsed={row['elapsed']:.2f}s", flush=True)
    failed = [row for row in results if row["status"] not in {"prepared", "cached"}]
    cache_bytes, cache_files = _disk_usage(args.work_root / "cache" / profile_id)
    print(f"[PREPARE] profile={profile_id} prepared={sum(r['status'] == 'prepared' for r in results)} cached={sum(r['status'] == 'cached' for r in results)} failed={len(failed)} bytes={cache_bytes} files={cache_files}")
    return 1 if failed else 0


def command_run(args: argparse.Namespace, only_seed: int | None = None) -> int:
    profile, profile_id = _profile_id(args)
    seeds = [only_seed] if only_seed is not None else list(range(args.start_seed, args.start_seed + args.count))
    suite_id = _suite_id(profile_id, seeds[0], len(seeds)) if only_seed is None else f"repro_{profile_id}_seed{only_seed}_{time.strftime('%Y%m%d_%H%M%S')}"
    suite_dir = args.work_root / ("repro" if only_seed is not None else "runs") / suite_id
    db = _db_open(suite_dir / "results.sqlite3")
    completed = {} if args.rerun or only_seed is not None else {row[0]: row[1] for row in db.execute("SELECT seed, status FROM results")}
    pending = [seed for seed in seeds if seed not in completed]
    missing = [seed for seed in pending if not _case_ready(_case_dir(args, profile_id, seed))]
    if missing:
        print(f"[RISCV-DV] ERROR: {len(missing)} seeds are not prepared; first missing seed={missing[0]}", file=sys.stderr)
        return 2

    rows: list[dict[str, Any]] = []
    retained_failures = len(list((suite_dir / "failures").glob("seed_*"))) if (suite_dir / "failures").exists() else 0
    stop_file = args.work_root / "STOP"
    runner_file = args.work_root / "runner.json"
    stop_event = threading.Event()
    if only_seed is None:
        stop_file.unlink(missing_ok=True)
        _json_dump(runner_file, {"pid": os.getpid(), "suite_id": suite_id, "suite_dir": str(suite_dir)})

    def request_stop(signum: int, _frame: Any) -> None:
        print(f"\n[RISCV-DV] signal {signum}: graceful stop requested; waiting for active cases", flush=True)
        stop_event.set()
        stop_file.touch()

    old_handlers = {}
    if only_seed is None:
        for signum in (signal.SIGINT, signal.SIGTERM):
            old_handlers[signum] = signal.signal(signum, request_stop)

    def record(row: dict[str, Any]) -> None:
        nonlocal retained_failures
        work = Path(row["work"]) if row.get("work") else None
        artifact = ""
        if row["status"] == "PASS":
            if work and work.exists():
                shutil.rmtree(work)
            shutil.rmtree(suite_dir / "failures" / f"seed_{row['seed']}", ignore_errors=True)
        elif work and work.exists() and retained_failures < args.keep_failures:
            failure_dir = suite_dir / "failures" / f"seed_{row['seed']}"
            failure_dir.parent.mkdir(parents=True, exist_ok=True)
            if failure_dir.exists():
                shutil.rmtree(failure_dir)
            work.replace(failure_dir)
            _gzip_failure_files(failure_dir)
            artifact = str(failure_dir)
            retained_failures += 1
        elif work and work.exists():
            shutil.rmtree(work)
        db.execute(
            "INSERT OR REPLACE INTO results VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (row["seed"], row["status"], row["elapsed"], row["reason"] + ("\n" + row.get("tail", "")[-4000:] if row.get("tail") else ""), row["returncode"], json.dumps(row.get("metrics", [])), artifact, time.strftime("%Y-%m-%dT%H:%M:%S%z")),
        )
        db.commit()
        rows.append(row)
        print(f"[RUN] seed={row['seed']} status={row['status']} elapsed={row['elapsed']:.2f}s reason={row['reason']}", flush=True)

    iterator = iter(pending)
    futures: dict[concurrent.futures.Future[dict[str, Any]], int] = {}
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            while len(futures) < args.jobs:
                try:
                    seed = next(iterator)
                except StopIteration:
                    break
                futures[pool.submit(_run_one, args, profile, profile_id, suite_dir, seed)] = seed
            completed_since_merge = 0
            while futures:
                done, _ = concurrent.futures.wait(futures, timeout=1, return_when=concurrent.futures.FIRST_COMPLETED)
                if not done:
                    if stop_file.exists():
                        stop_event.set()
                    continue
                for future in done:
                    futures.pop(future)
                    record(future.result())
                    completed_since_merge += 1
                if completed_since_merge >= args.coverage_batch:
                    if _merge_coverage(args, suite_dir):
                        stop_event.set()
                    completed_since_merge = 0
                if stop_file.exists():
                    stop_event.set()
                while not stop_event.is_set() and len(futures) < args.jobs:
                    try:
                        seed = next(iterator)
                    except StopIteration:
                        break
                    futures[pool.submit(_run_one, args, profile, profile_id, suite_dir, seed)] = seed
    finally:
        coverage_error = _merge_coverage(args, suite_dir)
        if only_seed is None:
            runner_file.unlink(missing_ok=True)
            for signum, handler in old_handlers.items():
                signal.signal(signum, handler)

    all_rows = [
        {"seed": seed, "status": status, "elapsed": elapsed}
        for seed, status, elapsed in db.execute("SELECT seed, status, elapsed FROM results ORDER BY seed")
    ]
    summary = _write_summary(suite_dir, suite_id, all_rows, 0, len(completed), len(seeds), stop_event.is_set())
    db.close()
    shutil.rmtree(suite_dir / "tmp", ignore_errors=True)
    print((suite_dir / "summary.log").read_text(encoding="utf-8"), end="")
    failures = sum(summary["counts"].get(key, 0) for key in ("FAIL", "TIMEOUT", "ERROR")) + coverage_error
    return 1 if failures else 0


def command_continuous(args: argparse.Namespace) -> int:
    profile, profile_id = _profile_id(args)
    suite_id = f"{profile_id}_random"
    suite_dir = args.work_root / "runs" / suite_id
    runner_file = args.work_root / "runner.json"
    active_pid = _active_runner_pid(runner_file)
    if active_pid is not None:
        print(f"[RISCV-DV] ERROR: runner PID {active_pid} is already active", file=sys.stderr)
        return 2
    db = _db_open(suite_dir / "results.sqlite3")
    history_db = _seed_history_open(args, profile_id)
    permanent_seeds = [
        row[0] for row in history_db.execute(
            "SELECT seed FROM failures ORDER BY first_seen, seed"
        )
    ]
    permanent_iter = iter(permanent_seeds)
    retained_failures = (
        len(list((suite_dir / "failures").glob("seed_*")))
        if (suite_dir / "failures").exists() else 0
    )
    stop_file = args.work_root / "STOP"
    stop_event = threading.Event()
    stop_file.unlink(missing_ok=True)
    _json_dump(
        runner_file,
        {"pid": os.getpid(), "mode": "random", "suite_id": suite_id,
         "suite_dir": str(suite_dir)},
    )

    def request_stop(signum: int, _frame: Any) -> None:
        print(
            f"\n[RISCV-DV] signal {signum}: graceful stop requested; "
            "waiting for active cases",
            flush=True,
        )
        stop_event.set()
        stop_file.touch()

    old_handlers = {}
    for signum in (signal.SIGINT, signal.SIGTERM):
        old_handlers[signum] = signal.signal(signum, request_stop)

    def prepare_and_run(seed: int) -> dict[str, Any]:
        started = time.monotonic()
        prepared = _prepare_one(args, profile, profile_id, seed)
        if prepared["status"] not in {"prepared", "cached"}:
            return {
                "seed": seed,
                "status": "ERROR",
                "reason": f"program preparation failed: {prepared.get('error', prepared['status'])}",
                "returncode": 2,
                "elapsed": time.monotonic() - started,
                "work": "",
                "metrics": [],
                "coverage": "",
            }
        row = _run_one(args, profile, profile_id, suite_dir, seed)
        row["elapsed"] = time.monotonic() - started
        return row

    def record(row: dict[str, Any]) -> None:
        nonlocal retained_failures
        seed = row["seed"]
        work = Path(row["work"]) if row.get("work") else None
        case_dir = _case_dir(args, profile_id, seed)
        artifact = ""
        if row["status"] == "PASS":
            if work and work.exists():
                shutil.rmtree(work)
            shutil.rmtree(suite_dir / "failures" / f"seed_{seed}", ignore_errors=True)
            shutil.rmtree(case_dir, ignore_errors=True)
        elif work and work.exists() and retained_failures < args.keep_failures:
            failure_dir = suite_dir / "failures" / f"seed_{seed}"
            failure_dir.parent.mkdir(parents=True, exist_ok=True)
            if failure_dir.exists():
                shutil.rmtree(failure_dir)
            work.replace(failure_dir)
            _gzip_failure_files(failure_dir)
            artifact = str(failure_dir)
            retained_failures += 1
        elif (case_dir / "prepare_failure").exists() and retained_failures < args.keep_failures:
            artifact = str(case_dir / "prepare_failure")
            retained_failures += 1
        else:
            if work and work.exists():
                shutil.rmtree(work)
            shutil.rmtree(case_dir, ignore_errors=True)
        db.execute(
            "INSERT OR REPLACE INTO results VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (seed, row["status"], row["elapsed"],
             row["reason"] + ("\n" + row.get("tail", "")[-4000:] if row.get("tail") else ""),
             row["returncode"], json.dumps(row.get("metrics", [])), artifact,
             time.strftime("%Y-%m-%dT%H:%M:%S%z")),
        )
        db.commit()
        if (row["status"] in {"FAIL", "TIMEOUT", "ERROR"} or
                row.get("permanent_replay")):
            _record_permanent_result(history_db, seed, row["status"])
        label = "REGRESSION" if row.get("permanent_replay") else "RANDOM"
        print(
            f"[{label}] seed={seed} status={row['status']} "
            f"elapsed={row['elapsed']:.2f}s reason={row['reason']}",
            flush=True,
        )

    futures: dict[concurrent.futures.Future[dict[str, Any]], tuple[int, bool]] = {}
    completed_since_merge = 0
    coverage_error = 0
    print(
        f"[RISCV-DV] RANDOM START profile={profile_id} jobs={args.jobs} "
        f"history={history_db.execute('SELECT COUNT(*) FROM seeds').fetchone()[0]} "
        f"permanent={len(permanent_seeds)}",
        flush=True,
    )

    def submit_next(pool: concurrent.futures.ThreadPoolExecutor) -> None:
        try:
            seed = next(permanent_iter)
            permanent_replay = True
        except StopIteration:
            seed = _reserve_random_seed(history_db)
            permanent_replay = False
        future = pool.submit(prepare_and_run, seed)
        futures[future] = (seed, permanent_replay)

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            while len(futures) < args.jobs:
                submit_next(pool)
            while futures:
                done, _ = concurrent.futures.wait(
                    futures, timeout=1,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                if not done:
                    if stop_file.exists():
                        stop_event.set()
                    continue
                for future in done:
                    _, permanent_replay = futures.pop(future)
                    row = future.result()
                    row["permanent_replay"] = permanent_replay
                    record(row)
                    completed_since_merge += 1
                if completed_since_merge >= args.coverage_batch:
                    if _merge_coverage(args, suite_dir):
                        coverage_error = 1
                        stop_event.set()
                    completed_since_merge = 0
                if stop_file.exists():
                    stop_event.set()
                while not stop_event.is_set() and len(futures) < args.jobs:
                    submit_next(pool)
    finally:
        coverage_error |= _merge_coverage(args, suite_dir)
        runner_file.unlink(missing_ok=True)
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)

    all_rows = [
        {"seed": seed, "status": status, "elapsed": elapsed}
        for seed, status, elapsed in db.execute(
            "SELECT seed, status, elapsed FROM results ORDER BY updated_at"
        )
    ]
    summary = _write_summary(
        suite_dir, suite_id, all_rows, 0, 0, len(all_rows), stop_event.is_set()
    )
    history_count = history_db.execute("SELECT COUNT(*) FROM seeds").fetchone()[0]
    permanent_count = history_db.execute("SELECT COUNT(*) FROM failures").fetchone()[0]
    history_db.close()
    db.close()
    shutil.rmtree(suite_dir / "tmp", ignore_errors=True)
    print((suite_dir / "summary.log").read_text(encoding="utf-8"), end="")
    print(
        f"[RISCV-DV] RANDOM HISTORY={history_count} "
        f"PERMANENT_REGRESSIONS={permanent_count}"
    )
    failures = sum(
        summary["counts"].get(key, 0) for key in ("FAIL", "TIMEOUT", "ERROR")
    ) + coverage_error
    return 1 if failures else 0


def command_estimate(args: argparse.Namespace) -> int:
    _, profile_id = _profile_id(args)
    profile_dir = args.work_root / "cache" / profile_id
    sizes = _prepared_seed_sizes(profile_dir)
    per_seed = int(statistics.median(sizes)) if sizes else 128 * 1024
    fixed_bytes, fixed_files = _disk_usage(args.work_root / "venv")
    model_bytes, model_files = _disk_usage(args.model_dir)
    projected_cache = per_seed * args.count
    cache_limit = int(args.max_cache_gb * 1024 * 1024 * 1024)
    print(f"[ESTIMATE] profile={profile_id} seeds={args.count} prepared_bytes_per_seed={per_seed} prepared_total_bytes={projected_cache} prepared_files~={args.count * 5}")
    print(f"[ESTIMATE] fixed_venv_bytes={fixed_bytes} fixed_venv_files={fixed_files} model_bytes={model_bytes} model_files={model_files}")
    print(f"[ESTIMATE] projected_total_bytes={fixed_bytes + model_bytes + projected_cache} cache_limit_bytes={cache_limit} fits_cache_limit={int(projected_cache <= cache_limit)}")
    print(f"[ESTIMATE] transient_concurrency={args.jobs} transient space is bounded by active jobs; successful trace/log/CSV files are deleted immediately")
    return 0


def command_status(args: argparse.Namespace) -> int:
    _, profile_id = _profile_id(args)
    history_db = _seed_history_open(args, profile_id)
    history_count = history_db.execute("SELECT COUNT(*) FROM seeds").fetchone()[0]
    failures = list(
        history_db.execute(
            "SELECT seed, first_seen, last_seen, last_status "
            "FROM failures ORDER BY first_seen, seed"
        )
    )
    history_db.close()
    print(
        f"[RISCV-DV] RANDOM STATUS profile={profile_id} "
        f"history={history_count} permanent={len(failures)}"
    )
    for seed, first_seen, last_seen, status in failures:
        print(
            f"[PERMANENT] seed={seed} status={status} "
            f"first_seen={first_seen} last_seen={last_seen}"
        )
    return 0


def command_cleanup(args: argparse.Namespace) -> int:
    shutil.rmtree(args.work_root / "runs" / ".tmp", ignore_errors=True)
    for tmp in args.work_root.glob("runs/*/tmp"):
        shutil.rmtree(tmp, ignore_errors=True)
    runs = sorted(
        (p for p in (args.work_root / "runs").glob("*")
         if p.is_dir() and not p.name.endswith("_random")),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for old in runs[args.keep_runs:]:
        shutil.rmtree(old)
    repros = sorted((p for p in (args.work_root / "repro").glob("*") if p.is_dir()), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in repros[args.keep_runs:]:
        shutil.rmtree(old)
    cache_root = args.work_root / "cache"
    for case_dir in cache_root.glob("*/seed_*"):
        for tmp in case_dir.glob(".tmp_*"):
            shutil.rmtree(tmp, ignore_errors=True)
        if _case_ready(case_dir):
            shutil.rmtree(case_dir / "prepare_failure", ignore_errors=True)
    if args.all:
        shutil.rmtree(cache_root, ignore_errors=True)
        shutil.rmtree(args.work_root / "repro", ignore_errors=True)
    else:
        _, current_profile = _profile_id(args)
        limit = int(args.max_cache_gb * 1024 * 1024 * 1024)
        old_profiles = sorted(
            (p for p in cache_root.glob("*") if p.is_dir() and p.name != current_profile),
            key=lambda p: p.stat().st_mtime,
        )
        cache_bytes, _ = _disk_usage(cache_root)
        for old in old_profiles:
            if cache_bytes <= limit:
                break
            old_bytes, _ = _disk_usage(old)
            shutil.rmtree(old)
            cache_bytes -= old_bytes
    total, files = _disk_usage(args.work_root)
    print(f"[CLEANUP] bytes={total} files={files} keep_runs={args.keep_runs} cache_removed={args.all}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=("prepare", "run", "continuous", "reproduce", "estimate", "status", "cleanup"),
    )
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--dv-root", type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--python", type=Path, default=Path(sys.executable))
    parser.add_argument("--gcc", type=Path, required=True)
    parser.add_argument("--objcopy", type=Path, required=True)
    parser.add_argument("--make", type=Path, default=Path("make"))
    parser.add_argument("--spike", type=Path, required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--linker", type=Path, required=True)
    parser.add_argument("--target", default="rv32im_ydrasil")
    parser.add_argument("--arch", default="rv32im_zicsr_zifencei")
    parser.add_argument("--abi", default="ilp32")
    parser.add_argument("--start-seed", type=int, default=1)
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--seed", type=int)
    parser.add_argument("--instr-count", type=int, default=400)
    parser.add_argument("--subprograms", type=int, default=0)
    parser.add_argument("--jobs", type=int, default=12)
    parser.add_argument("--prepare-timeout", type=int, default=1200)
    parser.add_argument("--case-timeout", type=int, default=600)
    parser.add_argument("--sim-timeout", type=int, default=500000)
    parser.add_argument("--spike-maxsteps", type=int, default=200000)
    parser.add_argument("--max-mismatches", type=int, default=5)
    parser.add_argument("--keep-failures", type=int, default=20)
    parser.add_argument("--keep-runs", type=int, default=5)
    parser.add_argument("--coverage-batch", type=int, default=20)
    parser.add_argument("--max-cache-gb", type=float, default=4.0)
    parser.add_argument("--verilator-coverage", type=Path, default=Path("verilator_coverage"))
    parser.add_argument("--rerun", action="store_true")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    args.project_root = args.project_root.resolve()
    args.dv_root = args.dv_root.resolve()
    args.work_root = args.work_root.resolve()
    args.model_dir = args.model_dir.resolve()
    args.linker = args.linker.resolve()
    args.gcc = args.gcc.resolve()
    args.objcopy = args.objcopy.resolve()
    args.spike = args.spike.resolve()
    # Keep the venv launcher path. resolve() follows it to the system interpreter.
    args.python = Path(os.path.abspath(args.python))
    coverage_tool = shutil.which(str(args.verilator_coverage))
    if not coverage_tool:
        parser.error(f"verilator coverage tool not found: {args.verilator_coverage}")
    args.verilator_coverage = Path(coverage_tool)
    if not 1 <= args.jobs <= MAX_JOBS:
        parser.error(f"--jobs must be between 1 and {MAX_JOBS}")
    if args.count < 1 or args.instr_count < 10 or args.subprograms < 0:
        parser.error("count/instr-count must be positive and subprograms must be non-negative")
    if args.command == "reproduce" and args.seed is None:
        parser.error("reproduce requires --seed")
    return args


def main() -> int:
    args = parse_args()
    if args.command == "prepare":
        return command_prepare(args)
    if args.command == "run":
        return command_run(args)
    if args.command == "continuous":
        return command_continuous(args)
    if args.command == "reproduce":
        return command_run(args, args.seed)
    if args.command == "estimate":
        return command_estimate(args)
    if args.command == "status":
        return command_status(args)
    return command_cleanup(args)


if __name__ == "__main__":
    raise SystemExit(main())
