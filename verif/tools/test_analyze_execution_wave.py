#!/usr/bin/env python3
"""Unit tests for the lightweight execution waveform analyzer."""

from __future__ import annotations

import csv
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from verif.tools.analyze_execution_wave import (
    AnalysisError,
    REQUIRED_COLUMNS,
    WaveRow,
    analyze,
    diagnose_cycle,
    load_provenance,
    load_rows,
    main,
)


BOOL_DEFAULTS = {
    "if_valid0": 1,
    "if_valid1": 1,
    "decode_valid0": 1,
    "decode_valid1": 1,
    "dispatch_accept0": 1,
    "dispatch_accept1": 1,
    "select_valid0": 0,
    "select_valid1": 0,
    "select_push": 0,
    "select_head_valid": 0,
    "select_head_pair": 0,
    "select_skid_valid": 0,
    "operand_accept0": 0,
    "operand_accept1": 0,
    "ex_valid0": 0,
    "ex_valid1": 0,
    "ex_accept0": 1,
    "ex_accept1": 1,
    "retire0": 0,
    "retire1": 0,
    "producer_full": 0,
    "lsu_idle": 1,
    "lsu_struct_stall": 0,
    "serialize_stall": 0,
    "mdu_available": 1,
    "flush": 0,
    "redirect": 0,
    "recovery_pending": 0,
    "fetch_req_valid": 1,
    "fetch_resp_valid": 1,
    "pending_redirect": 0,
    "dtcm_wakeup": 0,
    "mdu_wakeup": 0,
}


def base_row(cycle: int) -> dict[str, int | str]:
    row: dict[str, int | str] = {name: 0 for name in REQUIRED_COLUMNS}
    row.update(BOOL_DEFAULTS)
    row.update({
        "cycle": cycle,
        "instret": cycle,
        "fetch_pc": f"0x{0x80000000 + cycle * 4:x}",
        "issue_pc0": f"0x{0x80000000 + cycle * 4:x}",
        "issue_pc1": f"0x{0x80000004 + cycle * 4:x}",
        "ex_pc0": f"0x{0x80000000 + cycle * 4:x}",
        "ex_pc1": f"0x{0x80000004 + cycle * 4:x}",
        "retire_pc0": f"0x{0x80000000 + cycle * 4:x}",
        "retire_pc1": f"0x{0x80000004 + cycle * 4:x}",
        "issue_tag0": cycle % 12,
        "issue_tag1": (cycle + 1) % 12,
        "ex_tag0": cycle % 12,
        "ex_tag1": (cycle + 1) % 12,
        "selected_pc0": f"0x{0x80000000 + cycle * 4:x}",
        "selected_pc1": f"0x{0x80000004 + cycle * 4:x}",
        "selected_tag0": cycle % 12,
        "selected_tag1": (cycle + 1) % 12,
        "head0_b_only": 0,
        "pipeline_flush": 0,
        "fence_issue": 0,
        "trap_redirect": 0,
        "rs_valid_mask": "000f",
        "rs_ready_mask": "0000",
        "rob_count": 4,
        "lsu_credit": 2,
        "lsu_reserved": 2,
        "frontend_queue_count": 2,
        "alu_credit": 1,
        "p0_credit": 1,
        "p1_credit": 1,
        "reset": 0,
        "sample_valid": 1,
        "halted": 0,
    })
    return row


class Fixture:
    def __init__(self, root: Path, rows: list[dict[str, int | str]]):
        self.csv_path = root / "execution.csv"
        self.metadata_path = root / "execution.metadata.json"
        self.probe_sha = "2" * 64
        self.rtl_sha = "1" * 64
        columns = list(REQUIRED_COLUMNS)
        with self.csv_path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)
        csv_sha = hashlib.sha256(self.csv_path.read_bytes()).hexdigest()
        self.metadata = {
            "schema": "ydrasil.execution_wave.v2",
            "design": "Ydrasil",
            "rtl_sha256": self.rtl_sha,
            "probe_sha256": self.probe_sha,
            "csv_sha256": csv_sha,
            "test_name": "unit/raw_dependency",
            "simulator": "unit-sim",
            "probe_instance": "tb.dut",
            "generated_utc": "2026-08-10T00:00:00Z",
            "issue_width": 2,
            "rob_depth": 12,
            "clock_period_ns": 10,
            "benchmark_start_pc": "0x80000000",
            "benchmark_stop_pc": "0x80001000",
        }
        self.metadata_path.write_text(json.dumps(self.metadata), encoding="utf-8")


class ProvenanceTests(unittest.TestCase):
    def test_provenance_binds_design_csv_and_expected_fingerprints(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(Path(directory), [base_row(0)])
            provenance = load_provenance(
                fixture.csv_path,
                expected_rtl_sha256=fixture.rtl_sha,
                expected_probe_sha256=fixture.probe_sha,
            )
            self.assertEqual(provenance.values["design"], "Ydrasil")

            fixture.metadata["design"] = "DifferentCore"
            fixture.metadata_path.write_text(json.dumps(fixture.metadata), encoding="utf-8")
            with self.assertRaisesRegex(AnalysisError, "does not match expected design"):
                load_provenance(fixture.csv_path)

    def test_provenance_rejects_csv_tampering_and_wrong_rtl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(Path(directory), [base_row(0)])
            with fixture.csv_path.open("a", encoding="utf-8") as stream:
                stream.write("\n")
            with self.assertRaisesRegex(AnalysisError, "CSV hash mismatch"):
                load_provenance(fixture.csv_path)

            fixture = Fixture(Path(directory), [base_row(0)])
            with self.assertRaisesRegex(AnalysisError, "rtl_sha256 mismatch"):
                load_provenance(fixture.csv_path, expected_rtl_sha256="f" * 64)


class ParsingTests(unittest.TestCase):
    def test_unprefixed_masks_are_hex_and_cycles_must_be_contiguous(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = base_row(0)
            first["rs_valid_mask"] = "10"
            fixture = Fixture(Path(directory), [first, base_row(1)])
            rows, _ = load_rows(fixture.csv_path)
            self.assertEqual(rows[0]["rs_valid_mask"], 0x10)
            self.assertEqual(rows[0]["lsu_reserved"], 2)

            broken = base_row(3)
            Fixture(Path(directory), [base_row(0), broken])
            with self.assertRaisesRegex(AnalysisError, "cycle must be contiguous"):
                load_rows(fixture.csv_path)


class AnalysisTests(unittest.TestCase):
    def test_rejects_missing_or_too_short_stable_measurement(self) -> None:
        rows = [base_row(cycle) for cycle in range(7)]
        for row in rows:
            row["sample_valid"] = 0
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            with self.assertRaisesRegex(AnalysisError, "sample_valid is never 1"):
                analyze(
                    fixture.csv_path,
                    root / "missing",
                    sample_count=1,
                    window_cycles=4,
                )

        rows = [base_row(cycle) for cycle in range(7)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            with self.assertRaisesRegex(AnalysisError, "at least 8 are required"):
                analyze(
                    fixture.csv_path,
                    root / "short",
                    sample_count=2,
                    window_cycles=4,
                )

    def test_rejects_halted_cycle_inside_sample_valid_interval(self) -> None:
        rows = [base_row(cycle) for cycle in range(4)]
        rows[2]["halted"] = 1
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(Path(directory), rows)
            with self.assertRaisesRegex(AnalysisError, "sample_valid cannot be 1 while halted is 1"):
                load_rows(fixture.csv_path)

    def test_samples_only_the_explicit_stable_measurement_interval(self) -> None:
        rows = [base_row(cycle) for cycle in range(12)]
        for cycle in range(4):
            rows[cycle]["sample_valid"] = 0
        for cycle in range(4, 8):
            rows[cycle].update({"physical_exec0": 1, "physical_exec1": 1})
        for cycle in range(8, 12):
            rows[cycle]["rs_dep_mask"] = "000f"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            samples = analyze(
                fixture.csv_path,
                root / "analysis",
                sample_count=1,
                window_cycles=4,
                min_bubble_density=1.0,
            )
            self.assertEqual(samples[0].start_cycle, 8)
            self.assertTrue(all(row["sample_valid"] for row in samples[0].rows))

    def test_direct_pair_physical_lost_slots_are_quantified(self) -> None:
        rows = [base_row(cycle) for cycle in range(4)]
        for row in rows:
            row.update({
                "direct_fire": 1,
                "direct_pair": 1,
                "operand_accept0": 1,
                "operand_accept1": 1,
                "physical_exec0": 1,
                "physical_exec1": 0,
            })
        for cycle in range(1, len(rows)):
            rows[cycle].update({
                "issue_pc0": rows[cycle - 1]["selected_pc0"],
                "issue_pc1": rows[cycle - 1]["selected_pc1"],
                "issue_tag0": rows[cycle - 1]["selected_tag0"],
                "issue_tag1": rows[cycle - 1]["selected_tag1"],
            })
        for cycle in range(2, len(rows)):
            rows[cycle].update({
                "ex_pc0": rows[cycle - 2]["selected_pc0"],
                "ex_tag0": rows[cycle - 2]["selected_tag0"],
            })
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            output = root / "analysis"
            samples = analyze(
                fixture.csv_path,
                output,
                sample_count=1,
                window_cycles=4,
                min_bubble_density=0.5,
            )
            self.assertEqual(samples[0].primary_cause, "direct_pair_lost_slot")
            summary = (output / "execution_bubble_summary.csv").read_text(encoding="utf-8")
            self.assertIn("direct_pair_lost_slots", summary)
            self.assertIn("direct_pair_lost_slot", summary)

    def test_phase_matching_uses_e_minus_one_pc_and_rob_tag(self) -> None:
        source_values = base_row(10)
        source_values["operand_accept0"] = 1
        target_values = base_row(11)
        target_values.update({
            "physical_exec0": 1,
            "ex_pc0": int(str(source_values["issue_pc0"]), 16),
            "ex_tag0": source_values["issue_tag0"],
        })
        source_values["issue_pc0"] = int(str(source_values["issue_pc0"]), 16)
        matched = diagnose_cycle(WaveRow(target_values), WaveRow(source_values))
        self.assertEqual(matched.source_cycle, 10)
        self.assertEqual(matched.pc_matched_slots, 1)
        self.assertNotEqual(matched.cause, "operand_to_physical_gap")

        target_values["ex_tag0"] = (int(source_values["issue_tag0"]) + 1) % 12
        mismatched = diagnose_cycle(WaveRow(target_values), WaveRow(source_values))
        self.assertEqual(mismatched.cause, "operand_to_physical_gap")
        self.assertIn("/t", mismatched.evidence)

    def test_b_only_operand_maps_issue0_identity_to_physical_lane1(self) -> None:
        source = base_row(20)
        source.update({
            "operand_accept0": 0,
            "operand_accept1": 1,
            "head0_b_only": 1,
            "issue_pc0": 0x80001234,
            "issue_tag0": 7,
        })
        target = base_row(21)
        target.update({
            "physical_exec0": 0,
            "physical_exec1": 1,
            "ex_pc1": 0x80001234,
            "ex_tag1": 7,
        })
        matched = diagnose_cycle(WaveRow(target), WaveRow(source))
        self.assertEqual(matched.pc_matched_slots, 1)

        target.update({
            "physical_exec0": 1,
            "physical_exec1": 0,
            "ex_pc0": 0x80001234,
            "ex_tag0": 7,
        })
        wrong_lane = diagnose_cycle(WaveRow(target), WaveRow(source))
        self.assertEqual(wrong_lane.pc_matched_slots, 0)
        self.assertEqual(wrong_lane.cause, "operand_to_physical_gap")

    def test_direct_chain_requires_t1_lane_empty_and_t2_identity_match(self) -> None:
        direct = base_row(30)
        direct.update({
            "direct_fire": 1,
            "direct_pair": 1,
            "selected_pc0": 0x80002000,
            "selected_pc1": 0x80002004,
            "selected_tag0": 3,
            "selected_tag1": 4,
        })
        operand = base_row(31)
        operand.update({
            "operand_accept0": 1,
            "operand_accept1": 1,
            "issue_pc0": 0x80002000,
            "issue_pc1": 0x80002004,
            "issue_tag0": 3,
            "issue_tag1": 4,
            "physical_exec0": 0,
            "physical_exec1": 0,
        })
        physical = base_row(32)
        physical.update({
            "physical_exec0": 1,
            "physical_exec1": 1,
            "ex_pc0": 0x80002000,
            "ex_pc1": 0x80002004,
            "ex_tag0": 3,
            "ex_tag1": 4,
        })
        diagnosis = diagnose_cycle(WaveRow(physical), WaveRow(operand), WaveRow(direct))
        self.assertEqual(diagnosis.direct_selected_slots, 2)
        self.assertEqual(diagnosis.direct_operand_matched_slots, 2)
        self.assertEqual(diagnosis.direct_t1_target_lane_empty_slots, 2)
        self.assertEqual(diagnosis.direct_physical_matched_slots, 2)
        self.assertEqual(diagnosis.direct_advanceable_slots, 2)

    def test_selects_non_overlapping_windows_and_uses_raw_causes(self) -> None:
        rows = [base_row(cycle) for cycle in range(36)]
        # Three separated four-cycle regions each have two empty execute slots.
        # The asserted signals make their primary causes independently checkable.
        for cycle in range(4, 8):
            rows[cycle]["pipeline_flush"] = 1
        for cycle in range(16, 20):
            rows[cycle]["rs_dep_mask"] = "000f"
            rows[cycle]["completion_wakeup_mask"] = "0003"
        for cycle in range(28, 32):
            rows[cycle]["rs_resource_mask"] = "00f0"
            rows[cycle]["lsu_struct_stall"] = 1
            rows[cycle]["lsu_queue_count"] = 2

        # Background cycles execute both lanes, leaving the three target
        # regions as the unique maximum-weight non-overlapping selection.
        for cycle, row in enumerate(rows):
            if cycle not in {*range(4, 8), *range(16, 20), *range(28, 32)}:
                row.update({
                    "ex_valid0": 1, "ex_valid1": 1, "physical_exec0": 1,
                    "physical_exec1": 1, "retire0": 1, "retire1": 1,
                })

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            output = root / "analysis"
            samples = analyze(
                fixture.csv_path,
                output,
                sample_count=3,
                window_cycles=4,
                min_bubble_density=1.0,
                expected_rtl_sha256=fixture.rtl_sha,
                expected_probe_sha256=fixture.probe_sha,
            )
            self.assertEqual(len(samples), 3)
            ordered = sorted(samples, key=lambda item: item.start_cycle)
            self.assertEqual([sample.start_cycle for sample in ordered], [4, 16, 28])
            self.assertTrue(all(left.end_cycle < right.start_cycle for left, right in zip(ordered, ordered[1:])))
            self.assertEqual(
                {sample.primary_cause for sample in samples},
                {"recovery_redirect", "wakeup_visibility", "lsu_structural"},
            )

    def test_writes_summary_cycle_csv_markdown_and_gtkwave_vcd(self) -> None:
        rows = [base_row(cycle) for cycle in range(8)]
        for row in rows:
            row["rs_candidate_mask"] = "0001"
            row["rs_selected_mask"] = "0000"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            output = root / "analysis"
            result = main([
                str(fixture.csv_path),
                "--output-dir", str(output),
                "--samples", "2",
                "--window-cycles", "4",
                "--min-bubble-density", "1",
                "--expect-rtl-sha256", fixture.rtl_sha,
                "--expect-probe-sha256", fixture.probe_sha,
            ])
            self.assertEqual(result, 0)
            summary = (output / "execution_bubble_summary.csv").read_text(encoding="utf-8")
            report = (output / "execution_bubble_report.md").read_text(encoding="utf-8")
            sample_csv = (output / "samples/sample_01_cycles.csv").read_text(encoding="utf-8")
            vcd = (output / "execution_bubble_samples.vcd").read_text(encoding="ascii")
            self.assertIn("primary_cause", summary)
            self.assertIn("selection_arbitration", summary)
            self.assertIn("Root-cause priority", report)
            self.assertIn("cause_evidence", sample_csv)
            self.assertIn("rs_candidate_mask", sample_csv)
            self.assertIn("$enddefinitions $end", vcd)
            self.assertIn("sample_active", vcd)
            self.assertIn("primary_cause_code", vcd)
            self.assertIn("retire_pc0", vcd)

    def test_requires_enough_non_overlapping_samples_unless_allowed(self) -> None:
        rows = [base_row(cycle) for cycle in range(7)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Fixture(root, rows)
            with self.assertRaisesRegex(AnalysisError, "at least 8 are required"):
                analyze(
                    fixture.csv_path,
                    root / "strict",
                    sample_count=2,
                    window_cycles=4,
                    min_bubble_density=1.0,
                )
            samples = analyze(
                fixture.csv_path,
                root / "relaxed",
                sample_count=2,
                window_cycles=4,
                min_bubble_density=1.0,
                allow_fewer=True,
            )
            self.assertEqual(len(samples), 1)


if __name__ == "__main__":
    unittest.main()
