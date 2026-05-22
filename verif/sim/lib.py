
"""Minimal helpers for trace parsing and formatting."""

import logging
import re


def setup_logging(verbose):
    """Configure logging for CLI tools."""
    if verbose:
        logging.basicConfig(
            format="%(asctime)s %(filename)s:%(lineno)-5s %(levelname)-8s %(message)s",
            datefmt="%a, %d %b %Y %H:%M:%S",
            level=logging.DEBUG,
        )
    else:
        logging.basicConfig(
            format="%(asctime)s %(levelname)-8s %(message)s",
            datefmt="%a, %d %b %Y %H:%M:%S",
            level=logging.INFO,
        )


GPR_TO_ABI = {
    "x0": "zero",
    "x1": "ra",
    "x2": "sp",
    "x3": "gp",
    "x4": "tp",
    "x5": "t0",
    "x6": "t1",
    "x7": "t2",
    "x8": "s0",
    "x9": "s1",
    "x10": "a0",
    "x11": "a1",
    "x12": "a2",
    "x13": "a3",
    "x14": "a4",
    "x15": "a5",
    "x16": "a6",
    "x17": "a7",
    "x18": "s2",
    "x19": "s3",
    "x20": "s4",
    "x21": "s5",
    "x22": "s6",
    "x23": "s7",
    "x24": "s8",
    "x25": "s9",
    "x26": "s10",
    "x27": "s11",
    "x28": "t3",
    "x29": "t4",
    "x30": "t5",
    "x31": "t6",
    "f0": "ft0",
    "f1": "ft1",
    "f2": "ft2",
    "f3": "ft3",
    "f4": "ft4",
    "f5": "ft5",
    "f6": "ft6",
    "f7": "ft7",
    "f8": "fs0",
    "f9": "fs1",
    "f10": "fa0",
    "f11": "fa1",
    "f12": "fa2",
    "f13": "fa3",
    "f14": "fa4",
    "f15": "fa5",
    "f16": "fa6",
    "f17": "fa7",
    "f18": "fs2",
    "f19": "fs3",
    "f20": "fs4",
    "f21": "fs5",
    "f22": "fs6",
    "f23": "fs7",
    "f24": "fs8",
    "f25": "fs9",
    "f26": "fs10",
    "f27": "fs11",
    "f28": "ft8",
    "f29": "ft9",
    "f30": "ft10",
    "f31": "ft11",
}


def gpr_to_abi(gpr):
    """Map a register name like x1 or f3 to its ABI alias."""
    return GPR_TO_ABI.get(gpr, "na")


def sint_to_hex(val):
    """Signed integer to hex conversion."""
    return str(hex((val + (1 << 32)) % (1 << 32)))


BASE_RE = re.compile(r"(?P<rd>[a-z0-9]+?),(?P<imm>[\-0-9]*?)\((?P<rs1>[a-z0-9]+?)\)")


def convert_pseudo_instr(instr_name, operands, binary):
    """Convert pseudo instruction names into base ISA forms."""
    if instr_name == "nop":
        instr_name, operands = "addi", "zero,zero,0"
    elif instr_name == "mv":
        instr_name, operands = "addi", operands + ",0"
    elif instr_name == "not":
        instr_name, operands = "xori", operands + ",-1"
    elif instr_name == "neg":
        rd, rs = operands.split(",")
        instr_name, operands = "sub", "{0},zero,{1}".format(rd, rs)
    elif instr_name == "negw":
        rd, rs = operands.split(",")
        instr_name, operands = "subw", "{0},zero,{1}".format(rd, rs)
    elif instr_name == "sext.w":
        instr_name, operands = "addiw", operands + ",0"
    elif instr_name == "seqz":
        instr_name, operands = "sltiu", operands + ",1"
    elif instr_name == "snez":
        rd, rs = operands.split(",")
        instr_name, operands = "sltu", "{0},zero,{1}".format(rd, rs)
    elif instr_name == "sltz":
        instr_name, operands = "slt", operands + ",zero"
    elif instr_name == "sgtz":
        rd, rs = operands.split(",")
        instr_name, operands = "slt", "{0},zero,{1}".format(rd, rs)
    elif instr_name in ["beqz", "bnez", "bgez", "bltz"]:
        instr_name = instr_name[0:3]
        rs, imm = operands.split(",")
        operands = "{0},zero,{1}".format(rs, imm)
    elif instr_name == "blez":
        instr_name, operands = "bge", "zero," + operands
    elif instr_name == "bgtz":
        instr_name, operands = "blt", "zero," + operands
    elif instr_name == "bgt":
        rs1, rs2, imm = operands.split(",")
        instr_name, operands = "blt", "{0},{1},{2}".format(rs2, rs1, imm)
    elif instr_name == "ble":
        rs1, rs2, imm = operands.split(",")
        instr_name, operands = "bge", "{0},{1},{2}".format(rs2, rs1, imm)
    elif instr_name == "bgtu":
        rs1, rs2, imm = operands.split(",")
        instr_name, operands = "bltu", "{0},{1},{2}".format(rs2, rs1, imm)
    elif instr_name == "bleu":
        rs1, rs2, imm = operands.split(",")
        instr_name, operands = "bgeu", "{0},{1},{2}".format(rs2, rs1, imm)
    elif instr_name == "csrr":
        instr_name, operands = "csrrw", operands + ",zero"
    elif instr_name in ["csrw", "csrs", "csrc"]:
        instr_name, operands = "csrr" + instr_name[3:], "zero," + operands
    elif instr_name in ["csrwi", "csrsi", "csrci"]:
        instr_name, operands = "csrr" + instr_name[3:], "zero," + operands
    elif instr_name == "jr":
        instr_name, operands = "jalr", "zero,{0},0".format(operands)
    elif instr_name == "j":
        instr_name, operands = "jal", "zero,{0}".format(operands)
    elif instr_name == "jal" and "," not in operands:
        operands = "ra,{0}".format(operands)
    elif instr_name == "jalr":
        m = BASE_RE.search(operands)
        if m:
            operands = "{},{},{}".format(m.group("rd"), m.group("rs1"), m.group("imm"))
        elif "," not in operands:
            operands = "ra,{0},0".format(operands)
    elif instr_name == "ret":
        if binary[-1] == "2":
            instr_name = "c.jr"
            operands = "ra"
        else:
            instr_name = "jalr"
            operands = "zero,ra,0"
    # RV32B pseudo instructions
    # TODO: support "rev", "orc", and "zip/unzip" instructions for RV64
    elif instr_name == "rev.p":
        instr_name = "grevi"
        operands += ",1"
    elif instr_name == "rev2.n":
        instr_name = "grevi"
        operands += ",2"
    elif instr_name == "rev.n":
        instr_name = "grevi"
        operands += ",3"
    elif instr_name == "rev4.b":
        instr_name = "grevi"
        operands += ",4"
    elif instr_name == "rev2.b":
        instr_name = "grevi"
        operands += ",6"
    elif instr_name == "rev.b":
        instr_name = "grevi"
        operands += ",7"
    elif instr_name == "rev8.h":
        instr_name = "grevi"
        operands += ",8"
    elif instr_name == "rev4.h":
        instr_name = "grevi"
        operands += ",12"
    elif instr_name == "rev2.h":
        instr_name = "grevi"
        operands += ",14"
    elif instr_name == "rev.h":
        instr_name = "grevi"
        operands += ",15"
    elif instr_name == "rev16":
        instr_name = "grevi"
        operands += ",16"
    elif instr_name == "rev8":
        instr_name = "grevi"
        operands += ",24"
    elif instr_name == "rev4":
        instr_name = "grevi"
        operands += ",28"
    elif instr_name == "rev2":
        instr_name = "grevi"
        operands += ",30"
    elif instr_name == "rev":
        instr_name = "grevi"
        operands += ",31"
    elif instr_name == "orc.p":
        instr_name = "gorci"
        operands += ",1"
    elif instr_name == "orc2.n":
        instr_name = "gorci"
        operands += ",2"
    elif instr_name == "orc.n":
        instr_name = "gorci"
        operands += ",3"
    elif instr_name == "orc4.b":
        instr_name = "gorci"
        operands += ",4"
    elif instr_name == "orc2.b":
        instr_name = "gorci"
        operands += ",6"
    elif instr_name == "orc.b":
        instr_name = "gorci"
        operands += ",7"
    elif instr_name == "orc8.h":
        instr_name = "gorci"
        operands += ",8"
    elif instr_name == "orc4.h":
        instr_name = "gorci"
        operands += ",12"
    elif instr_name == "orc2.h":
        instr_name = "gorci"
        operands += ",14"
    elif instr_name == "orc.h":
        instr_name = "gorci"
        operands += ",15"
    elif instr_name == "orc16":
        instr_name = "gorci"
        operands += ",16"
    elif instr_name == "orc8":
        instr_name = "gorci"
        operands += ",24"
    elif instr_name == "orc4":
        instr_name = "gorci"
        operands += ",28"
    elif instr_name == "orc2":
        instr_name = "gorci"
        operands += ",30"
    elif instr_name == "orc":
        instr_name = "gorci"
        operands += ",31"
    elif instr_name == "zext.b":
        instr_name = "andi"
        operands += ",255"
    elif instr_name == "zext.h":
        # TODO: support for RV64B
        instr_name = "pack"
        operands += ",zero"
    elif instr_name == "zext.w":
        instr_name = "pack"
        operands += ",zero"
    elif instr_name == "sext.w":
        instr_name = "addiw"
        operands += ",0"
    elif instr_name == "zip.n":
        instr_name = "shfli"
        operands += ",1"
    elif instr_name == "unzip.n":
        instr_name = "unshfli"
        operands += ",1"
    elif instr_name == "zip2.b":
        instr_name = "shfli"
        operands += ",2"
    elif instr_name == "unzip2.b":
        instr_name = "unshfli"
        operands += ",2"
    elif instr_name == "zip.b":
        instr_name = "shfli"
        operands += ",3"
    elif instr_name == "unzip.b":
        instr_name = "unshfli"
        operands += ",3"
    elif instr_name == "zip4.h":
        instr_name = "shfli"
        operands += ",4"
    elif instr_name == "unzip4.h":
        instr_name = "unshfli"
        operands += ",4"
    elif instr_name == "zip2.h":
        instr_name = "shfli"
        operands += ",6"
    elif instr_name == "unzip2.h":
        instr_name = "unshfli"
        operands += ",6"
    elif instr_name == "zip.h":
        instr_name = "shfli"
        operands += ",7"
    elif instr_name == "unzip.h":
        instr_name = "unshfli"
        operands += ",7"
    elif instr_name == "zip8":
        instr_name = "shfli"
        operands += ",8"
    elif instr_name == "unzip8":
        instr_name = "unshfli"
        operands += ",8"
    elif instr_name == "zip4":
        instr_name = "shfli"
        operands += ",12"
    elif instr_name == "unzip4":
        instr_name = "unshfli"
        operands += ",12"
    elif instr_name == "zip2":
        instr_name = "shfli"
        operands += ",14"
    elif instr_name == "unzip2":
        instr_name = "unshfli"
        operands += ",14"
    elif instr_name == "zip":
        instr_name = "shfli"
        operands += ",15"
    elif instr_name == "unzip":
        instr_name = "unshfli"
        operands += ",15"
    return instr_name, operands
