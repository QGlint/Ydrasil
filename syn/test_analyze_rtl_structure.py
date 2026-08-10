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

from analyze_rtl_structure import join_cone_segments, tarjan


class StructureGateTest(unittest.TestCase):
    def test_required_waypoint_cannot_be_bypassed(self) -> None:
        first = {
            "source": "issue.dtcm_q",
            "target": "main_ex.completion_data_o",
            "source_signal": "dtcm_q",
            "destination_signal": "completion_data_o",
            "depth": 7,
            "signals": ["issue.dtcm_q", "main_ex.completion_data_o"],
            "owner_crossings": 1,
        }
        second = {
            "source": "main_ex.completion_data_o",
            "target": "value_file.value_q/D",
            "source_signal": "completion_data_o",
            "destination_signal": "value_q",
            "depth": 5,
            "signals": ["main_ex.completion_data_o", "value_file.value_q/D"],
            "owner_crossings": 2,
        }

        joined = join_cone_segments(first, second)

        self.assertIsNotNone(joined)
        self.assertEqual(joined["depth"], 12)
        self.assertEqual(joined["owner_crossings"], 3)
        self.assertEqual(joined["signals"], [
            "issue.dtcm_q",
            "main_ex.completion_data_o",
            "value_file.value_q/D",
        ])
        self.assertIsNone(join_cone_segments(first, None))

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
