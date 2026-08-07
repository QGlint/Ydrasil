#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rtl_timing_families import normalize_owner, summarize_families


class TimingFamilyTest(unittest.TestCase):
    def test_main_execute_instance_is_ex_block(self) -> None:
        resource = (
            "u_soc_core/u_core/u_ydrasil_execute_stage/u_main_ex/"
            "u_ydrasil_div/state_q_reg[0]/CE"
        )
        self.assertEqual(normalize_owner(resource), "ex_block")

    def test_summarize_accepts_parsed_timing_delay_field(self) -> None:
        record = {
            "source": "u_soc_core/u_core/u_ctrl/producer_valid_q_reg[9]/C",
            "destination": (
                "u_soc_core/u_core/u_ydrasil_execute_stage/u_main_ex/"
                "u_ydrasil_div/state_q_reg[0]/CE"
            ),
            "data_path_delay_ns": 5.25,
            "slack_ns": -0.25,
            "logic_levels": 9,
            "route_fraction": 0.8,
        }

        summary = summarize_families([("parsed", [record])], target_period_ns=5.0)

        self.assertEqual(summary["family_count"], 1)
        self.assertEqual(summary["families"][0]["key"], "ctrl->ex_block|register_q->register_ce")
        self.assertEqual(summary["families"][0]["delay_ns_p95"], 5.25)
        self.assertEqual(summary["families"][0]["worst_slack_ns"], -0.25)


if __name__ == "__main__":
    unittest.main()
