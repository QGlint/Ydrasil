#!/usr/bin/env python3
"""Tests for the standalone RTL structure gate."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from analyze_rtl_structure import (
    apply_weighted_timing_path_policy,
    timing_path_weighted_violation,
)


class StructureGateTest(unittest.TestCase):
    def test_weight_starts_at_possible_depth_and_grows_with_depth(self) -> None:
        self.assertEqual(timing_path_weighted_violation(8, 9), 0)
        self.assertEqual(timing_path_weighted_violation(9, 9), 1)
        self.assertEqual(timing_path_weighted_violation(12, 9), 4)

    def test_long_paths_accumulate_to_the_limit(self) -> None:
        hierarchy = {
            "timing_path_risks": [
                {"structural_depth": 10},
                {"structural_depth": 11},
                {"structural_depth": 8},
            ]
        }

        total = apply_weighted_timing_path_policy(hierarchy, 9, 5)

        self.assertEqual(total, 5)
        self.assertEqual(
            [item["weighted_violation"] for item in hierarchy["timing_path_risks"]],
            [2, 3, 0],
        )
        self.assertTrue(hierarchy["timing_path_weighted_violation_exceeded"])

    def test_bram_launch_penalty_contributes_to_the_total(self) -> None:
        hierarchy = {
            "timing_path_risks": [
                {"structural_depth": 5, "launch_kind": "bram_output"},
                {"structural_depth": 10, "launch_kind": "register_q"},
            ]
        }

        total = apply_weighted_timing_path_policy(hierarchy, 9, 5, 6)

        self.assertEqual(total, 5)
        self.assertEqual(
            [
                item["weighted_structural_depth"]
                for item in hierarchy["timing_path_risks"]
            ],
            [11, 10],
        )
        self.assertTrue(hierarchy["timing_path_weighted_violation_exceeded"])

    def test_check_output_recomputes_and_fails_aggregate_violation(self) -> None:
        report = {
            "summary": {"timing_possible_depth_threshold": 9},
            "hierarchical": {
                "timing_path_risks": [
                    {
                        "key": "shorter",
                        "severity": "WARNING",
                        "structural_depth": 10,
                    },
                    {
                        "key": "deeper",
                        "severity": "WARNING",
                        "structural_depth": 11,
                    },
                ],
                "meaningful_cycles": [],
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "structure.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).with_name("analyze_rtl_structure.py")),
                    "--check-output",
                    str(path),
                    "--timing-path-weighted-violation-limit",
                    "5",
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("ERROR aggregate_timing_path_violation", result.stdout)
        self.assertIn("CONTRIBUTOR deeper: weighted=3", result.stdout)
        self.assertIn("weighted timing-path violation total=5 limit=5", result.stderr)


if __name__ == "__main__":
    unittest.main()
