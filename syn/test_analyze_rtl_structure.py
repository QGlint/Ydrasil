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

from analyze_rtl_structure import tarjan


class StructureGateTest(unittest.TestCase):
    def test_tarjan_output_is_canonical(self) -> None:
        first = {"d": set(), "b": {"a"}, "c": set(), "a": {"b"}}
        second = {"a": {"b"}, "c": set(), "b": {"a"}, "d": set()}

        self.assertEqual(tarjan(first), [["a", "b"], ["c"], ["d"]])
        self.assertEqual(tarjan(first), tarjan(second))

    def test_reachable_failed_critical_cone_fails_gate(self) -> None:
        report = {
            "hierarchical": {
                "target_period_ns": 5.0,
                "timing_path_risks": [],
                "critical_cones": [{
                    "name": "issue_dtcm_bypass_select_to_value_file",
                    "severity": "ERROR",
                    "source": "issue.alu_in_operand_b_dtcm_q",
                    "destination": "issue/value_file.value_odd_q/D",
                    "structural_depth": 11,
                    "trained_max_delay_ns": 5.906,
                    "trained_worst_slack_ns": -0.898,
                    "reasons": ["same_signal_cone_failed_in_archived_vivado"],
                }],
                "meaningful_cycles": [],
            }
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
                ],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

        self.assertEqual(result.returncode, 1)
        self.assertTrue(result.stdout.startswith(
            "ERROR critical_cone issue_dtcm_bypass_select_to_value_file"
        ))
        self.assertIn("1 critical cones", result.stderr)


if __name__ == "__main__":
    unittest.main()
