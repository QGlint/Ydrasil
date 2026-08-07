#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rtl_timing_families import normalize_owner, read_timing_csv, summarize_families


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

    def test_read_timing_csv_keeps_near_critical_met_path(self) -> None:
        csv_text = (
            "rank,slack_ns,status,path_group,source,destination,logic_levels,"
            "route_pct,data_delay_ns,requirement_ns\n"
            "1,0.047,MET,cpu_clk_mmcm,u_ctrl/ready_q_reg/C,"
            "u_lsu/store_q_reg/CE,9,83.9,4.721,5.0\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "timing.csv"
            path.write_text(csv_text, encoding="utf-8")

            records = read_timing_csv(path)

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["status"], "MET")
        self.assertEqual(records[0]["slack_ns"], 0.047)


if __name__ == "__main__":
    unittest.main()
