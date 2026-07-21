
"""
Copyright 2020 Google LLC
Copyright 2020 PerfectVIPs Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
"""

import sys
import random
import logging
import vsc
from enum import IntEnum, auto
from importlib import import_module
from pygen_src.riscv_instr_gen_config import cfg
from pygen_src.isa.riscv_instr import riscv_instr
from pygen_src.riscv_directed_instr_lib import riscv_mem_access_stream
from pygen_src.riscv_instr_pkg import riscv_reg_t, riscv_instr_name_t, riscv_instr_group_t
rcs = import_module("pygen_src.target." + cfg.argv.target + ".riscv_core_setting")


class locality_e(IntEnum):
    NARROW = 0
    HIGH = auto()
    MEDIUM = auto()
    SPARSE = auto()


# Base class for all load/store instruction stream
@vsc.randobj
class riscv_load_store_base_instr_stream(riscv_mem_access_stream):
    def __init__(self):
        super().__init__()
        self.num_load_store = vsc.rand_uint32_t()
        self.num_mixed_instr = vsc.rand_uint32_t()
        self.base = vsc.rand_int32_t()
        self.offset = []
        self.addr = []
        self.load_store_instr = []
        self.data_page_id = vsc.rand_uint32_t()
        self.rs1_reg = vsc.rand_enum_t(riscv_reg_t)
        self.locality = vsc.rand_enum_t(locality_e)
        self.max_load_store_offset = vsc.rand_int32_t()
        self.use_sp_as_rs1 = vsc.rand_bit_t()

    @vsc.constraint
    def sp_rnd_order_c(self):
        vsc.solve_order(self.use_sp_as_rs1, self.rs1_reg)

    @vsc.constraint
    def sp_c(self):
        vsc.dist(self.use_sp_as_rs1, [vsc.weight(1, 1), vsc.weight(0, 2)])
        with vsc.if_then(self.use_sp_as_rs1 == 1):
            self.rs1_reg == riscv_reg_t.SP

    # TODO Getting pyvsc error -- > rs1 has not been build yet
    '''@vsc.constraint
    def rs1_c(self):
        self.rs1_reg.not_inside(vsc.rangelist(cfg.reserved_regs,
                                              self.reserved_rd, riscv_reg_t.ZERO))'''

    @vsc.constraint
    def addr_c(self):
        # TODO solve_order
        # vsc.solve_order(self.data_page_id, self.max_load_store_offset)
        # vsc.solve_order(self.max_load_store_offset, self.base)
        self.data_page_id < self.max_data_page_id
        with vsc.foreach(self.data_page, idx = True) as i:
            with vsc.if_then(i == self.data_page_id):
                self.max_load_store_offset == self.data_page[i].size_in_bytes
        self.base in vsc.rangelist(vsc.rng(0, self.max_load_store_offset - 1))

    def randomize_offset(self):
        count = int(self.num_load_store)
        base = int(self.base)
        region_size = int(self.max_load_store_offset)
        locality = locality_e(int(self.locality))
        limits = {
            locality_e.NARROW: 16,
            locality_e.HIGH: 64,
            locality_e.MEDIUM: 256,
            locality_e.SPARSE: 2048,
        }
        limit = limits[locality]
        low = max(-limit, -base)
        high = min(limit, region_size - base)
        if low >= high:
            raise RuntimeError("No in-range load/store offset is available")
        self.offset = [0] * count
        self.addr = [0] * count
        for i in range(count):
            self.offset[i] = random.randrange(low, high)
            self.addr[i] = base + self.offset[i]

    def pre_randomize(self):
        super().pre_randomize()
        if(riscv_reg_t.SP in [cfg.reserved_regs, self.reserved_rd]):
            self.use_sp_as_rs1 = 0
            with vsc.raw_mode():
                self.use_sp_as_rs1.rand_mode = False
            self.sp_rnd_order_c.constraint_mode(False)

    def post_randomize(self):
        self.randomize_offset()
        if self.rs1_reg == riscv_reg_t.ZERO:
            candidates = [
                reg for reg in riscv_reg_t
                if reg != riscv_reg_t.ZERO
                and reg not in cfg.reserved_regs
                and reg not in self.reserved_rd
            ]
            if not candidates:
                raise RuntimeError("No legal GPR is available for load/store base")
            self.rs1_reg = random.choice(candidates)
        rs1_reg = riscv_reg_t(int(self.rs1_reg))
        # rs1 cannot be modified by other instructions
        if rs1_reg not in self.reserved_rd:
            self.reserved_rd.append(rs1_reg)
        self.gen_load_store_instr(rs1_reg)
        self.add_mixed_instr(self.num_mixed_instr)
        self.add_rs1_init_la_instr(rs1_reg, int(self.data_page_id), int(self.base))
        super().post_randomize()

    # Generate each load/store instruction
    def gen_load_store_instr(self, rs1_reg):
        enable_compressed_load_store = 0
        region_size = int(self.max_load_store_offset)
        self.randomize_avail_regs()
        if ((rs1_reg in [riscv_reg_t.S0, riscv_reg_t.S1, riscv_reg_t.A0, riscv_reg_t.A1,
                              riscv_reg_t.A2, riscv_reg_t.A3, riscv_reg_t.A4, riscv_reg_t.A5,
                              riscv_reg_t.SP]) and not(cfg.disable_compressed_instr)):
            enable_compressed_load_store = 1
        for i in range(len(self.addr)):
            allowed_instr = []
            # Assign the allowed load/store instructions based on address alignment
            # This is done separately rather than a constraint to improve the randomization
            # performance
            allowed_instr.extend(
                [riscv_instr_name_t.LB, riscv_instr_name_t.LBU, riscv_instr_name_t.SB])
            if not cfg.enable_unaligned_load_store:
                if (self.addr[i] & 1) == 0 and self.addr[i] + 2 <= region_size:
                    allowed_instr.extend(
                        [riscv_instr_name_t.LH, riscv_instr_name_t.LHU, riscv_instr_name_t.SH])
                if self.addr[i] % 4 == 0 and self.addr[i] + 4 <= region_size:
                    allowed_instr.extend([riscv_instr_name_t.LW, riscv_instr_name_t.SW])
                    if cfg.enable_floating_point:
                        allowed_instr.extend([riscv_instr_name_t.FLW,
                                              riscv_instr_name_t.FSW])
                    if ((self.offset[i] in range(128)) and (self.offset[i] % 4 == 0) and
                        (riscv_instr_group_t.RV32C in rcs.supported_isa) and
                            (enable_compressed_load_store)):
                        if rs1_reg == riscv_reg_t.SP:
                            logging.info("Add LWSP/SWSP to allowed instr")
                            allowed_instr.extend(
                                [riscv_instr_name_t.C_LWSP, riscv_instr_name_t.C_SWSP])
                        else:
                            allowed_instr.extend(
                                [riscv_instr_name_t.C_LW, riscv_instr_name_t.C_SW])
                            if (cfg.enable_floating_point and
                                    riscv_instr_group_t.RV32FC in rcs.supported_isa):
                                allowed_instr.extend(
                                    [riscv_instr_name_t.C_FLW, riscv_instr_name_t.C_FSW])
                if ((rcs.XLEN >= 64) and (self.addr[i] % 8 == 0)
                        and self.addr[i] + 8 <= region_size):
                    allowed_instr.extend([riscv_instr_name_t.LWU,
                                          riscv_instr_name_t.LD,
                                          riscv_instr_name_t.SD])
                    if (cfg.enable_floating_point and
                            (riscv_instr_group_t.RV32D in rcs.supported_isa)):
                        allowed_instr.extend([riscv_instr_name_t.FLD,
                                              riscv_instr_name_t.FSD])
                    if (self.offset[i] in range(256) and (self.offset[i] % 8 == 0) and
                        (riscv_instr_group_t.RV64C in rcs.supported_isa) and
                            enable_compressed_load_store):
                        if rs1_reg == riscv_reg_t.SP:
                            allowed_instr.extend(
                                [riscv_instr_name_t.C_LDSP, riscv_instr_name_t.C_SDSP])
                        else:
                            allowed_instr.extend(
                                [riscv_instr_name_t.C_LD, riscv_instr_name_t.C_SD])
                            if (cfg.enable_floating_point and
                                    (riscv_instr_group_t.RV32DC in rcs.supported_isa)):
                                allowed_instr.extend(
                                    [riscv_instr_name_t.C_FLD, riscv_instr_name_t.C_FSD])
            else:
                if self.addr[i] + 2 <= region_size:
                    allowed_instr.extend([riscv_instr_name_t.LH, riscv_instr_name_t.LHU,
                                          riscv_instr_name_t.SH])
                if self.addr[i] + 4 <= region_size:
                    allowed_instr.extend([riscv_instr_name_t.LW, riscv_instr_name_t.SW])
                if rcs.XLEN >= 64 and self.addr[i] + 8 <= region_size:
                    allowed_instr.extend(
                        [riscv_instr_name_t.LWU, riscv_instr_name_t.LD, riscv_instr_name_t.SD])
            instr = riscv_instr.get_load_store_instr(allowed_instr)
            instr.has_rs1 = 0
            instr.has_imm = 0
            self.randomize_gpr(instr)
            instr.rs1 = rs1_reg
            instr.imm_str = str(instr.uintToInt(self.offset[i]))
            instr.process_load_store = 0
            self.instr_list.append(instr)
            self.load_store_instr.append(instr)


# A single load/store instruction
@vsc.randobj
class riscv_single_load_store_instr_stream(riscv_load_store_base_instr_stream):
    def __init__(self):
        super().__init__()

    @vsc.constraint
    def legal_c(self):
        self.num_load_store == 1
        self.num_mixed_instr < 5


# Back to back load/store instructions
@vsc.randobj
class riscv_load_store_stress_instr_stream(riscv_load_store_base_instr_stream):
    def __init__(self):
        super().__init__()
        self.max_instr_cnt = 30
        self.min_instr_cnt = 10

    @vsc.constraint
    def legal_c(self):
        self.num_load_store.inside(vsc.rangelist(vsc.rng(self.min_instr_cnt, self.max_instr_cnt)))
        self.num_mixed_instr == 0


# Back to back load/store instructions
@vsc.randobj
class riscv_load_store_shared_mem_stream(riscv_load_store_stress_instr_stream):
    def __init__(self):
        super().__init__()

    def pre_randomize(self):
        self.load_store_shared_memory = 1
        super().pre_randomize()


# Random load/store sequence
# A random mix of load/store instructions and other instructions
@vsc.randobj
class riscv_load_store_rand_instr_stream(riscv_load_store_base_instr_stream):
    def __init__(self):
        super().__init__()

    @vsc.constraint
    def legal_c(self):
        self.num_load_store.inside(vsc.rangelist(vsc.rng(10, 30)))
        self.num_mixed_instr.inside(vsc.rangelist(vsc.rng(10, 30)))


# Use a small set of GPR to create various WAW, RAW, WAR hazard scenario
@vsc.randobj
class riscv_load_store_hazard_instr_stream(riscv_load_store_base_instr_stream):
    def __init__(self):
        super().__init__()
        self.hazard_ratio = vsc.rand_int32_t()

    @vsc.constraint
    def hazard_ratio_c(self):
        self.hazard_ratio.inside(vsc.rangelist(vsc.rng(20, 100)))

    @vsc.constraint
    def legal_c(self):
        self.num_load_store.inside(vsc.rangelist(vsc.rng(10, 20)))
        self.num_mixed_instr.inside(vsc.rangelist(vsc.rng(1, 7)))

    def randomize_offset(self):
        count = int(self.num_load_store)
        base = int(self.base)
        region_size = int(self.max_load_store_offset)
        locality = locality_e(int(self.locality))
        limits = {
            locality_e.NARROW: 16,
            locality_e.HIGH: 64,
            locality_e.MEDIUM: 256,
            locality_e.SPARSE: 2048,
        }
        limit = limits[locality]
        low = max(-limit, -base)
        high = min(limit, region_size - base)
        if low >= high:
            raise RuntimeError("No in-range load/store hazard offset is available")
        self.offset = [0] * count
        self.addr = [0] * count
        for i in range(count):
            if i > 0 and random.randrange(0, 100) < int(self.hazard_ratio):
                self.offset[i] = self.offset[i - 1]
                self.addr[i] = self.addr[i - 1]
            else:
                self.offset[i] = random.randrange(low, high)
                self.addr[i] = base + self.offset[i]
