#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from analyze_timing_families import architecture_family, load_dataset, signal_family


class TimingArchitectureFamilyTest(unittest.TestCase):
    def test_specific_path_families(self) -> None:
        self.assertEqual(
            architecture_family(
                "u_core/u_ydrasil_mems/u_dtcm/u_impl/mem/CLKBWRCLK",
                "u_core/u_ydrasil_issue_stage/dual_alu_payload_q_reg[0]/D",
            ),
            "DTCM response -> Operand/FU",
        )
        self.assertEqual(
            architecture_family(
                "u_core/u_ydrasil_issue_stage/g_rs_entry[6]/uop_q_reg/C",
                "u_core/u_ydrasil_issue_stage/select_head_uop1_q_reg[0]/D",
            ),
            "RS/Select -> Select head",
        )
        self.assertEqual(
            architecture_family(
                "u_core/u_ydrasil_branch_predictor/u_btb_bank1/mem/CLKARDCLK",
                "u_core/u_ydrasil_if_stage/u_fetch_queue/payload1_q_reg[0]/D",
            ),
            "Predictor -> Fetch/Redirect",
        )
        cases = (
            (
                "u_core/u_ydrasil_if_stage/pending_redirect_target_q_reg[10]/C",
                "u_core/u_ydrasil_mems/u_itcm/u_impl/mem_reg_1_2/ADDRBWRADDR[8]",
                "Frontend -> ITCM request",
            ),
            (
                "u_core/u_ydrasil_issue_stage/g_rs_entry[8].u_entry/uop_q_reg/C",
                "u_core/u_ydrasil_issue_stage/select_fast_wakeup_id_q_reg[0][1][0]/D",
                "RS -> Select wakeup token",
            ),
            (
                "u_core/u_ydrasil_issue_stage/dual_meta_q_reg[4]/C",
                "u_core/u_ctrl/producer_done_q_reg[5]/D",
                "Execute/Completion -> ROB done",
            ),
            (
                "u_core/u_ctrl/retire_data_q_reg[3]/C",
                "u_core/u_ydrasil_issue_stage/gen_regs[7].registers_reg[7][28]/CE",
                "Retire -> Register File",
            ),
            (
                "u_core/u_ydrasil_issue_stage/agu_in_operand_a_q_reg[4]/C",
                "u_core/u_ydrasil_load_store_unit/queue_q_reg[1][addr][18]/CE",
                "AGU/LSU request path",
            ),
            (
                "u_core/u_ydrasil_issue_stage/bht_clear_q_reg/C",
                "u_core/u_ydrasil_branch_predictor/btb_clear_row_q_reg[0]/CE",
                "Predictor maintenance",
            ),
            (
                "u_core/u_ydrasil_execute_stage/ex_csr_waddr_o_ff_reg[0]/C",
                "u_core/u_ydrasil_csr_stage/u_registers_csr/instret_reg[52]/CE",
                "CSR path",
            ),
            (
                "u_core/u_ydrasil_exception_stage/FSM_onehot_state_q_reg[0]/C",
                "u_core/u_ydrasil_issue_stage/g_rs_entry[1].u_entry/uop_q_reg/CE",
                "Exception/recovery control",
            ),
            (
                "u_core/u_ydrasil_execute_stage/ex2_pc_redirect_q_reg/C",
                "u_core/u_ydrasil_if_stage/u_fetch_queue/payload_q_reg/WE",
                "Branch resolution/redirect",
            ),
        )
        for source, destination, family in cases:
            with self.subTest(family=family):
                self.assertEqual(architecture_family(source, destination), family)

    def test_endpoint_signal_family_preserves_register_role(self) -> None:
        self.assertEqual(
            signal_family(
                "u_core/u_ydrasil_load_store_unit/queue_q_reg[1][store_data][26]/D"
            ),
            "queue_q[*][store_data][*]",
        )
        self.assertEqual(
            signal_family(
                "u_core/u_ydrasil_issue_stage/dual_bit_payload_q_reg[operand_b][12]/D"
            ),
            "dual_bit_payload_q[operand_b][*]",
        )

    def test_raw_and_representative_counts_are_kept_separate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory) / "pll250m" / "reports"
            reports.mkdir(parents=True)
            (reports / "cpu250_timing_groups.csv").write_text(
                "count,worst_slack_ns,avg_slack_ns,worst_start,worst_end,structure_signature\n"
                "17,-1.05,-0.7,u_core/u_ydrasil_mems/u_dtcm/u_impl/mem/CLKBWRCLK,"
                "u_core/u_ydrasil_issue_stage/dual_alu_payload_q_reg[operand_a][0]/D,LUT6>FDRE\n",
                encoding="utf-8",
            )
            (reports / "cpu250_timing_violations.csv").write_text(
                "slack_ns,source,destination,structure_signature,route_pct\n"
                "-1.05,u_core/u_ydrasil_mems/u_dtcm/u_impl/mem/CLKBWRCLK,"
                "u_core/u_ydrasil_issue_stage/dual_alu_payload_q_reg[operand_a][0]/D,LUT6>FDRE,87.5\n",
                encoding="utf-8",
            )
            (reports / "post_route_status.rpt").write_text(
                "# of routable nets..................... : 100 :\n"
                "# of fully routed nets................. : 100 :\n"
                "# of nets with routing errors.......... : 0 :\n",
                encoding="utf-8",
            )
            log_dir = reports.parent / "log"
            log_dir.mkdir()
            (log_dir / "vivado.log").write_text(
                "North Dir 1x1 Area, Max Cong = 73.5%, No Congested Regions.\n"
                "East Dir 1x1 Area, Max Cong = 95.5%, Congestion bounded by tiles\n"
                "Direction: North\nEffective congestion level: 0 Aspect Ratio: 1\n"
                "Direction: East\nEffective congestion level: 1 Aspect Ratio: 1\n",
                encoding="utf-8",
            )
            congestion_dir = reports.parent / "project" / "FPGA"
            congestion_dir.mkdir(parents=True)
            (congestion_dir / "congestion.rpt").write_text(
                "No congestion windows are found above level 5\n"
                "No initial estimated congestion windows are found above level 5\n",
                encoding="utf-8",
            )

            dataset = load_dataset(reports)

        stats = dataset.families["DTCM response -> Operand/FU"]
        self.assertEqual(stats.raw_paths, 17)
        self.assertEqual(stats.representatives, 1)
        self.assertAlmostEqual(stats.weighted_average_slack_ns, -0.7)
        self.assertAlmostEqual(stats.average_route_pct, 87.5)
        self.assertEqual(stats.route_pct_ge_80, 1)
        endpoint = dataset.endpoint_families["DTCM response -> Operand/FU"][
            "dual_alu_payload_q[operand_a][*]"
        ]
        self.assertEqual(endpoint.raw_paths, 17)
        self.assertEqual(endpoint.representatives, 1)
        self.assertAlmostEqual(endpoint.worst_slack_ns, -1.05)
        self.assertEqual(dataset.route_health.fully_routed_nets, 100)
        self.assertEqual(dataset.route_health.routing_errors, 0)
        self.assertEqual(dataset.route_health.max_congestion_pct["East"], 95.5)
        self.assertEqual(dataset.route_health.effective_congestion_level["East"], 1)
        self.assertTrue(dataset.route_health.no_high_level_windows)


if __name__ == "__main__":
    unittest.main()
