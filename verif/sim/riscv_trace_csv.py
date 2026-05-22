"""Trace CSV utilities and log parsers for Spike and Verilator."""

import argparse
import csv
import logging
import os
import re
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from verif.sim.lib import convert_pseudo_instr, gpr_to_abi, setup_logging, sint_to_hex


class RiscvInstructionTraceEntry(object):
    """RISC-V instruction trace entry"""

    def __init__(self):
        self.gpr = []
        self.csr = []
        self.instr = ""
        self.operand = ""
        self.pc = ""
        self.binary = ""
        self.instr_str = ""
        self.mode = ""

    def get_trace_string(self):
        """Return a short string of the trace entry"""
        return ("pc[{}] {}: {} {}".format(
            self.pc, self.instr_str, " ".join(self.gpr), " ".join(self.csr)))


class RiscvInstructionTraceCsv(object):
    """RISC-V instruction trace CSV class

    This class provides functions to read/write trace CSV
    """

    def __init__(self, csv_fd):
        self.csv_fd = csv_fd

    def start_new_trace(self):
        """Create a CSV file handle for a new trace"""
        fields = ["pc", "instr", "gpr", "csr", "binary", "mode", "instr_str",
                  "operand", "pad"]
        self.csv_writer = csv.DictWriter(self.csv_fd, fieldnames=fields)
        self.csv_writer.writeheader()

    def read_trace(self, trace):
        """Read instruction trace from CSV file"""
        csv_reader = csv.DictReader(self.csv_fd)
        for row in csv_reader:
            new_trace = RiscvInstructionTraceEntry()
            new_trace.gpr = row['gpr'].split(';')
            new_trace.csr = row['csr'].split(';')
            new_trace.pc = row['pc']
            new_trace.operand = row['operand']
            new_trace.binary = row['binary']
            new_trace.instr_str = row['instr_str']
            new_trace.instr = row['instr']
            new_trace.mode = row['mode']
            trace.append(new_trace)

    # TODO: Convert pseudo instruction to regular instruction

    def write_trace_entry(self, entry):
        """Write a new trace entry to CSV"""
        self.csv_writer.writerow({'instr_str': entry.instr_str,
                                  'gpr'      : ";".join(entry.gpr),
                                  'csr'      : ";".join(entry.csr),
                                  'operand'  : entry.operand,
                                  'pc'       : entry.pc,
                                  'binary'   : entry.binary,
                                  'instr'    : entry.instr,
                                  'mode'     : entry.mode})


def get_imm_hex_val(imm):
    """Get the hex representation of the imm value"""
    if imm[0] == '-':
        is_negative = 1
        imm = imm[1:]
    else:
        is_negative = 0
    imm_val = int(imm, 0)
    if is_negative:
        imm_val = -imm_val
    hexstr = sint_to_hex(imm_val)
    return hexstr[2:]


SPIKE_INSTR_RE = re.compile(
    r"core\s+\d+:\s+0x(?P<addr>[a-f0-9]+)\s+\(0x(?P<bin>[a-f0-9]+)\)\s+(?P<instr>.+)$"
)
SPIKE_COMMIT_RE = re.compile(
    r"(core\s+\d+:\s+)?(?P<pri>\d)\s+0x(?P<addr>[a-f0-9]+)\s+"
    r"\(0x(?P<bin>[a-f0-9]+)\)(?:\s+c\S*\s+0x[a-f0-9]+)*\s+"
    r"(?P<reg>[xf]\s*\d+)\s+0x(?P<val>[a-f0-9]+)"
)
VERILATOR_INSTR_RE = re.compile(
    r"core.*0x(?P<addr>[a-f0-9]+)\s+\(0x(?P<bin>[a-f0-9]+)\)\s+(?P<instr>.+)$"
)
VERILATOR_COMMIT_RE = re.compile(
    r"(?P<pri>\d)\s+0x(?P<addr>[a-f0-9]+)\s+\(0x(?P<bin>[a-f0-9]+)\)\s+"
    r"(?P<reg>[xf]\s*\d+)\s+0x(?P<val>[a-f0-9]+)"
)
ADDR_RE = re.compile(r"(?P<rd>[a-z0-9]+?),(?P<imm>[\-0-9]+?)\((?P<rs1>[a-z0-9]+)\)")
ILLEGAL_RE = re.compile(r"trap_illegal_instruction")


def _normalize_disasm(disasm):
    return disasm.replace("pc + ", "").replace("pc - ", "-")


def _parse_imm_as_int(text):
    if text.startswith("-"):
        return -_parse_imm_as_int(text[1:])
    if text.startswith("0x"):
        return int(text, 16)
    if any(ch in text.lower() for ch in "abcdef"):
        return int(text, 16)
    return int(text, 10)


def _format_operands(entry):
    if entry.instr == "jal":
        idx = entry.operand.rfind(",")
        if idx != -1:
            imm_text = entry.operand[idx + 1 :]
            entry.operand = entry.operand[: idx + 1] + str(_parse_imm_as_int(imm_text))

    m = ADDR_RE.search(entry.operand)
    if m:
        entry.operand = "{},{},{}".format(m.group("rd"), m.group("rs1"), m.group("imm"))


def _build_entry(match, full_trace):
    disasm = _normalize_disasm(match.group("instr"))
    entry = RiscvInstructionTraceEntry()
    entry.pc = match.group("addr")
    entry.binary = match.group("bin")
    entry.instr_str = disasm

    if full_trace:
        opcode = disasm.split(" ")[0]
        operand = disasm[len(opcode) :].replace(" ", "")
        entry.instr, entry.operand = convert_pseudo_instr(opcode, operand, entry.binary)
        _format_operands(entry)
    return entry


def _iter_trace_entries(lines, source, full_trace):
    if source == "spike":
        instr_re = SPIKE_INSTR_RE
        commit_re = SPIKE_COMMIT_RE
        start_trampoline_re = re.compile(r"core.*: 0x0*10000 ")
        end_trampoline_re = re.compile(r"core.*: 0x0*10010 ")
        in_trampoline = False
        in_debug = False
        start_debug_re = None
        stop_debug_re = None
    else:
        instr_re = VERILATOR_INSTR_RE
        commit_re = VERILATOR_COMMIT_RE
        end_trampoline_re = re.compile(r"core.*: 0x0000000080000000 ")
        start_trampoline_re = None
        start_debug_re = re.compile(r"core.*: 0x0000000000000800 ")
        stop_debug_re = re.compile(r"core.*: 0x0000000000000890 ")
        in_trampoline = True
        in_debug = False

    current = None

    for line in lines:
        if in_trampoline:
            if end_trampoline_re and end_trampoline_re.match(line):
                in_trampoline = False
            else:
                continue
        elif start_trampoline_re and start_trampoline_re.match(line):
            in_trampoline = True
            continue

        if start_debug_re and stop_debug_re:
            if in_debug:
                if stop_debug_re.match(line):
                    in_debug = False
                continue
            if start_debug_re.match(line):
                in_debug = True
                continue

        match = instr_re.match(line)
        if match:
            if current is not None:
                yield current, False
            current = _build_entry(match, full_trace)
            if current.instr_str == "ecall":
                break
            continue

        if current is None:
            continue

        if ILLEGAL_RE.search(line):
            yield current, True
            current = None
            continue

        commit = commit_re.match(line)
        if commit:
            reg = commit.group("reg").replace(" ", "")
            current.gpr.append("{}:{}".format(gpr_to_abi(reg), commit.group("val")))
            current.mode = commit.group("pri")

    if current is not None:
        yield current, False


def process_sim_log(log_path, csv_path, full_trace=False, source="spike"):
    logging.info("Processing %s log: %s", source, log_path)
    total = 0
    kept = 0

    with open(csv_path, "w") as csv_fd:
        writer = RiscvInstructionTraceCsv(csv_fd)
        writer.start_new_trace()

        with open(log_path, "r") as handle:
            for entry, illegal in _iter_trace_entries(handle, source, full_trace):
                total += 1
                if illegal and full_trace:
                    logging.debug("Illegal instruction: %s", entry.instr_str)

                if not (full_trace or entry.gpr or entry.instr_str in ["wfi", "ecall"]):
                    continue

                writer.write_trace_entry(entry)
                kept += 1

    logging.info("Processed instruction count: %d", total)
    logging.info("CSV saved to: %s", csv_path)
    return kept


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=str, required=True, help="Input simulation log")
    parser.add_argument("--csv", type=str, required=True, help="Output trace CSV")
    parser.add_argument(
        "--source",
        type=str,
        choices=["spike", "verilator"],
        default="spike",
        help="Log source format",
    )
    parser.add_argument("-f", "--full_trace", dest="full_trace", action="store_true")
    parser.add_argument("-v", "--verbose", dest="verbose", action="store_true")
    parser.set_defaults(full_trace=False)
    parser.set_defaults(verbose=False)
    args = parser.parse_args()

    setup_logging(args.verbose)
    process_sim_log(args.log, args.csv, args.full_trace, args.source)


if __name__ == "__main__":
    main()
