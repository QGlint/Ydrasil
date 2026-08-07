#!/usr/bin/env python3
"""Tests for leave-one-out RTL timing validation."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cross_validate_rtl_timing import (
    independent_structure_predictions,
    is_over_target,
)


class CrossValidationTest(unittest.TestCase):
    def test_margin_target_marks_met_5ns_path_for_scoring(self) -> None:
        record = {
            "data_delay_ns": 4.72,
            "slack_ns": 0.05,
            "status": "MET",
        }

        self.assertTrue(is_over_target(record, 4.5))
        self.assertFalse(is_over_target(record, 5.0))

    def test_only_independent_structure_reason_is_eligible(self) -> None:
        structure = {
            "hierarchical": {
                "timing_path_risks": [
                    {
                        "key": "ctrl->lsu|register_q->register_d",
                        "reasons": ["independent_structural_path_upper_bound"],
                    },
                    {
                        "key": "issue->ctrl|register_q->register_d",
                        "reasons": ["reachable_path_family_failed_in_archived_vivado"],
                    },
                ]
            }
        }

        self.assertEqual(
            independent_structure_predictions(structure),
            {"ctrl->lsu|register_q->register_d"},
        )


if __name__ == "__main__":
    unittest.main()
