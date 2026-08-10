#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rtl_timing_families import (
    archive_timing_csv,
    normalize_owner,
    read_timing_csv,
    summarize_critical_cones,
    summarize_families,
)


class TimingFamilyTest(unittest.TestCase):
    def test_archive_timing_csv_uses_manifest_frequency(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory)
            reports = archive / "reports"
            reports.mkdir()
            expected = reports / "cpu250_timing_paths.csv"
            expected.write_text("rank,data_delay_ns\n", encoding="utf-8")

            resolved = archive_timing_csv(archive, {"frequency_mhz": 250})

        self.assertEqual(resolved, expected)

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

    def test_signal_level_dtcm_value_file_cone_is_trained_separately(self) -> None:
        matching = {
            "source": (
                "u_soc/u_core/u_ydrasil_issue_stage/"
                "alu_in_operand_b_dtcm_q_reg/C"
            ),
            "destination": (
                "u_soc/u_core/u_ydrasil_issue_stage/u_value_file/"
                "value_odd_q_reg[4][7]/D"
            ),
            "data_delay_ns": 5.906,
            "slack_ns": -0.898,
            "logic_levels": 11,
            "route_fraction": 0.86487,
        }
        unrelated = {
            **matching,
            "source": "u_soc/u_core/u_ctrl/queue_head_q_reg[0]/C",
            "data_delay_ns": 6.5,
        }

        cones = summarize_critical_cones([("design-a", [matching, unrelated])])

        self.assertEqual(len(cones), 2)
        main_cone = next(
            item for item in cones
            if item["name"] == "issue_dtcm_bypass_select_to_value_file"
        )
        dual_cone = next(
            item for item in cones
            if item["name"] == "issue_dtcm_bypass_select_to_value_file_dual"
        )
        self.assertEqual(
            main_cone["name"], "issue_dtcm_bypass_select_to_value_file"
        )
        self.assertEqual(main_cone["sample_count"], 1)
        self.assertEqual(main_cone["delay_ns_max"], 5.906)
        self.assertEqual(main_cone["worst_slack_ns"], -0.898)
        self.assertEqual(
            main_cone["worst_source_rtl_signal"], "alu_in_operand_b_dtcm_q"
        )
        self.assertEqual(
            main_cone["worst_destination_rtl_signal"], "value_odd_q"
        )
        self.assertEqual(dual_cone["sample_count"], 1)

    def test_issue_queue_cone_includes_multidimensional_ce_paths(self) -> None:
        path = {
            "source": (
                "u_soc/u_core/u_ydrasil_issue_stage/"
                "issue_pipe_q0_reg[src1][producer_tag][3]/C"
            ),
            "destination": (
                "u_soc/u_core/u_ydrasil_issue_stage/"
                "dual_alu_payload_q_reg[operand_a][23]/CE"
            ),
            "data_delay_ns": 5.445,
            "slack_ns": -0.809,
            "logic_levels": 9,
            "route_fraction": 0.88797,
        }

        cones = summarize_critical_cones([("design-a", [path])])
        issue_cone = next(
            item for item in cones if item["name"] == "issue_queue_to_fu_payload"
        )
        control_cone = next(
            item for item in cones
            if item["name"] == "issue_queue_control_roundtrip_to_fu"
        )

        self.assertEqual(issue_cone["sample_count"], 1)
        self.assertEqual(issue_cone["worst_source_rtl_signal"], "issue_pipe_q0")
        self.assertEqual(
            issue_cone["worst_destination_rtl_signal"], "dual_alu_payload_q"
        )
        self.assertEqual(issue_cone["worst_destination_rtl_pin"], "CE")
        self.assertEqual(control_cone["sample_count"], 1)
        self.assertEqual(control_cone["worst_slack_ns"], -0.809)


if __name__ == "__main__":
    unittest.main()
