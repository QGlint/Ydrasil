#!/usr/bin/env python3
"""Archive one RTL-structure/Vivado calibration sample below build/."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(repo_root: Path, *args: str) -> str | None:
    try:
        return subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--build-root", type=Path, required=True)
    parser.add_argument("--archive-dir", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--structure", type=Path, required=True)
    parser.add_argument("--source-metadata", type=Path, required=True)
    parser.add_argument("--filelist", type=Path, required=True)
    parser.add_argument("--comparison", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    build_root = args.build_root.resolve()
    archive_dir = args.archive_dir.resolve()
    try:
        archive_dir.relative_to(build_root)
    except ValueError:
        print(f"error: archive directory must be below {build_root}: {archive_dir}", file=sys.stderr)
        return 2
    inputs = {
        "reports": args.reports,
        "structure.json": args.structure,
        "sources.json": args.source_metadata,
        "rtl.f": args.filelist,
        "vivado-compare.json": args.comparison,
        "reliability-summary.txt": args.summary,
    }
    missing = [str(path) for path in inputs.values() if not path.exists()]
    if missing:
        print(f"error: archive inputs missing: {', '.join(missing)}", file=sys.stderr)
        return 2
    if archive_dir.exists():
        print(f"error: refusing to overwrite calibration archive: {archive_dir}", file=sys.stderr)
        return 2

    comparison = json.loads(args.comparison.read_text(encoding="utf-8"))
    comparison_provenance = comparison.get("provenance", {})
    freshness = comparison_provenance.get("status")
    compatibility = comparison_provenance.get("calibration_compatibility")
    if (
        freshness != "current_rtl_snapshot_and_reports_not_older_than_sources"
        and compatibility != "structurally_equivalent_to_archived_report_snapshot"
    ):
        print(
            "error: refusing to archive mismatched RTL and Vivado reports: "
            f"status={freshness} compatibility={compatibility}",
            file=sys.stderr,
        )
        return 2

    archive_dir.mkdir(parents=True)
    shutil.copytree(args.reports, archive_dir / "reports", copy_function=shutil.copy2)
    for destination, source in inputs.items():
        if destination == "reports":
            continue
        shutil.copy2(source, archive_dir / destination)

    structure = json.loads(args.structure.read_text(encoding="utf-8"))
    provenance = structure.get("provenance", {})
    copied_files = sorted(path for path in archive_dir.rglob("*") if path.is_file())
    manifest = {
        "schema_version": 1,
        "archived_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_commit": git_output(repo_root, "rev-parse", "HEAD"),
        "git_describe": git_output(repo_root, "describe", "--always", "--dirty"),
        "rtl_git_status": (git_output(repo_root, "status", "--porcelain", "--", "hw/ip") or "").splitlines(),
        "source_fingerprint": provenance.get("source_fingerprint"),
        "source_count": provenance.get("source_count"),
        "top": structure.get("top"),
        "target_period_ns": structure.get("summary", {}).get("target_period_ns"),
        "reports_source": str(args.reports.resolve()),
        "comparison_freshness_status": freshness,
        "calibration_compatibility": compatibility,
        "files": {
            str(path.relative_to(archive_dir)): {
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in copied_files
        },
    }
    (archive_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (archive_dir / "git-commit.txt").write_text(
        f"{manifest['git_commit'] or 'unknown'}\n",
        encoding="utf-8",
    )
    print(f"archived calibration sample: {archive_dir}")
    print(f"git commit: {manifest['git_commit']}")
    print(f"source fingerprint: {manifest['source_fingerprint']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
