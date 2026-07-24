// Copyright 2019 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// SPDX-License-Identifier: SHL-0.51

// Author: Stefan Mach <smach@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

// Ydrasil 集成版：在 FP32 FMA 的分类、对齐、宽加法、归一化和舍入前
// 增加可停顿流水边界，避免 DISTRIBUTED 配置重复堆叠原有寄存器。
module fpnew_fma #(
  parameter fpnew_pkg::fp_format_e   FpFormat    = fpnew_pkg::fp_format_e'(0),
  parameter int unsigned             NumPipeRegs = 0,
  parameter fpnew_pkg::pipe_config_t PipeConfig  = fpnew_pkg::BEFORE,
  parameter type                     TagType     = logic,
  parameter type                     AuxType     = logic,
  // Do not change
  localparam int unsigned WIDTH = fpnew_pkg::fp_width(FpFormat),
  localparam int unsigned ExtRegEnaWidth = NumPipeRegs == 0 ? 1 : NumPipeRegs
) (
  input logic                      clk_i,
  input logic                      rst_ni,
  // Input signals
  input logic [2:0][WIDTH-1:0]     operands_i, // 3 operands
  input logic [2:0]                is_boxed_i, // 3 operands
  input fpnew_pkg::roundmode_e     rnd_mode_i,
  input fpnew_pkg::operation_e     op_i,
  input logic                      op_mod_i,
  input TagType                    tag_i,
  input logic                      mask_i,
  input AuxType                    aux_i,
  // Input Handshake
  input  logic                     in_valid_i,
  output logic                     in_ready_o,
  input  logic                     flush_i,
  // Output signals
  output logic [WIDTH-1:0]         result_o,
  output fpnew_pkg::status_t       status_o,
  output logic                     extension_bit_o,
  output TagType                   tag_o,
  output logic                     mask_o,
  output AuxType                   aux_o,
  // Output handshake
  output logic                     out_valid_o,
  input  logic                     out_ready_i,
  // Indication of valid data in flight
  output logic                     busy_o,
  // External register enable override
  input  logic [ExtRegEnaWidth-1:0] reg_ena_i
);

  // ----------
  // Constants
  // ----------
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);
  localparam int unsigned BIAS     = fpnew_pkg::bias(FpFormat);
  // Precision bits 'p' include the implicit bit
  localparam int unsigned PRECISION_BITS = MAN_BITS + 1;
  // The lower 2p+3 bits of the internal FMA result will be needed for leading-zero detection
  localparam int unsigned LOWER_SUM_WIDTH  = 2 * PRECISION_BITS + 3;
  localparam int unsigned LZC_RESULT_WIDTH = $clog2(LOWER_SUM_WIDTH);
  // Internal exponent width of FMA must accomodate all meaningful exponent values in order to avoid
  // datapath leakage. This is either given by the exponent bits or the width of the LZC result.
  // In most reasonable FP formats the internal exponent will be wider than the LZC result.
  localparam int unsigned EXP_WIDTH = unsigned'(fpnew_pkg::maximum(EXP_BITS + 2, LZC_RESULT_WIDTH));
  // Shift amount width: maximum internal mantissa size is 3p+4 bits
  localparam int unsigned SHIFT_AMOUNT_WIDTH = $clog2(3 * PRECISION_BITS + 5);
  // Pipelines
  // DISTRIBUTED 模式下优先把寄存器放在真正的组合逻辑边界。前四级保持
  // FPnew 原有的 1/2/1 分布；第五、六级分别切开对齐器和宽加法器。
  localparam NUM_ALIGN_REGS = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 5 ? 1 : 0;
  localparam NUM_ADD_REGS   = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 6 ? 1 : 0;
  localparam NUM_NORM_REGS  = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 7 ? 1 : 0;
  localparam NUM_ROUND_REGS = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 8 ? 1 : 0;
  localparam NUM_DECODE_REGS = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 9 ? 1 : 0;
  localparam NUM_SHIFT_REGS = PipeConfig == fpnew_pkg::DISTRIBUTED && NumPipeRegs >= 10 ? 1 : 0;
  localparam NUM_INP_REGS = PipeConfig == fpnew_pkg::BEFORE
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? (NumPipeRegs > 0 ? 1 : 0)
                               : 0); // no regs here otherwise
  localparam NUM_OUT_REGS = PipeConfig == fpnew_pkg::AFTER
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? (NumPipeRegs > 1 ? 1 : 0)
                               : 0); // no regs here otherwise
  localparam NUM_MID_REGS = PipeConfig == fpnew_pkg::INSIDE
                          ? NumPipeRegs
                          : (PipeConfig == fpnew_pkg::DISTRIBUTED
                             ? (NumPipeRegs - NUM_INP_REGS - NUM_DECODE_REGS - NUM_ALIGN_REGS -
                                NUM_ADD_REGS - NUM_SHIFT_REGS - NUM_NORM_REGS - NUM_ROUND_REGS -
                                NUM_OUT_REGS)
                             : 0); // no regs here otherwise

  // ----------------
  // Type definition
  // ----------------
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;

  typedef struct packed {
    fp_t                  operand_a;
    fp_t                  operand_b;
    fp_t                  operand_c;
    fpnew_pkg::fp_info_t  info_a;
    fpnew_pkg::fp_info_t  info_b;
    fpnew_pkg::fp_info_t  info_c;
    logic                 effective_subtraction;
    logic                 tentative_sign;
    logic                 result_is_special;
    fp_t                  special_result;
    fpnew_pkg::status_t   special_status;
    fpnew_pkg::roundmode_e rnd_mode;
    TagType               tag;
    logic                 mask;
    AuxType               aux;
  } decode_payload_t;

  typedef struct packed {
    logic [3*PRECISION_BITS+3:0]   product_shifted;
    logic [PRECISION_BITS-1:0]     mantissa_c;
    logic                          effective_subtraction;
    logic                          tentative_sign;
    logic signed [EXP_WIDTH-1:0]   exponent_product;
    logic signed [EXP_WIDTH-1:0]   exponent_difference;
    logic signed [EXP_WIDTH-1:0]   tentative_exponent;
    logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt;
    fpnew_pkg::roundmode_e         rnd_mode;
    logic                          result_is_special;
    fp_t                           special_result;
    fpnew_pkg::status_t            special_status;
    TagType                        tag;
    logic                          mask;
    AuxType                        aux;
  } align_payload_t;

  typedef struct packed {
    logic [3*PRECISION_BITS+3:0]   product_shifted;
    logic [3*PRECISION_BITS+3:0]   addend_after_shift;
    logic                          sticky_before_add;
    logic                          effective_subtraction;
    logic                          tentative_sign;
    logic signed [EXP_WIDTH-1:0]   exponent_product;
    logic signed [EXP_WIDTH-1:0]   exponent_difference;
    logic signed [EXP_WIDTH-1:0]   tentative_exponent;
    logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt;
    fpnew_pkg::roundmode_e         rnd_mode;
    logic                          result_is_special;
    fp_t                           special_result;
    fpnew_pkg::status_t            special_status;
    TagType                        tag;
    logic                          mask;
    AuxType                        aux;
  } add_payload_t;

  typedef struct packed {
    logic [3*PRECISION_BITS+3:0]   sum;
    logic [SHIFT_AMOUNT_WIDTH-1:0] norm_shamt;
    logic signed [EXP_WIDTH-1:0]   normalized_exponent;
    logic                          sticky_before_add;
    logic                          final_sign;
    logic                          effective_subtraction;
    fpnew_pkg::roundmode_e         rnd_mode;
    logic                          result_is_special;
    fp_t                           special_result;
    fpnew_pkg::status_t            special_status;
    TagType                        tag;
    logic                          mask;
    AuxType                        aux;
  } shift_payload_t;

  typedef struct packed {
    logic [3*PRECISION_BITS+4:0] sum_shifted;
    logic signed [EXP_WIDTH-1:0] normalized_exponent;
    logic                        sticky_before_add;
    logic                        final_sign;
    logic                        effective_subtraction;
    fpnew_pkg::roundmode_e       rnd_mode;
    logic                        result_is_special;
    fp_t                         special_result;
    fpnew_pkg::status_t          special_status;
    TagType                      tag;
    logic                        mask;
    AuxType                      aux;
  } norm_payload_t;

  typedef struct packed {
    logic [EXP_BITS+MAN_BITS-1:0] pre_round_abs;
    logic                         pre_round_sign;
    logic [1:0]                   round_sticky_bits;
    logic                         effective_subtraction;
    logic                         of_before_round;
    logic [2*PRECISION_BITS+2:0]  sum_sticky_bits;
    fpnew_pkg::roundmode_e        rnd_mode;
    logic                         result_is_special;
    fp_t                          special_result;
    fpnew_pkg::status_t           special_status;
    TagType                       tag;
    logic                         mask;
    AuxType                       aux;
  } round_payload_t;

  // ---------------
  // Input pipeline
  // ---------------
  // Input pipeline signals, index i holds signal after i register stages
  logic                  [0:NUM_INP_REGS][2:0][WIDTH-1:0] inp_pipe_operands_q;
  logic                  [0:NUM_INP_REGS][2:0]            inp_pipe_is_boxed_q;
  fpnew_pkg::roundmode_e [0:NUM_INP_REGS]                 inp_pipe_rnd_mode_q;
  fpnew_pkg::operation_e [0:NUM_INP_REGS]                 inp_pipe_op_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_op_mod_q;
  TagType                [0:NUM_INP_REGS]                 inp_pipe_tag_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_mask_q;
  AuxType                [0:NUM_INP_REGS]                 inp_pipe_aux_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_INP_REGS] inp_pipe_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign inp_pipe_operands_q[0] = operands_i;
  assign inp_pipe_is_boxed_q[0] = is_boxed_i;
  assign inp_pipe_rnd_mode_q[0] = rnd_mode_i;
  assign inp_pipe_op_q[0]       = op_i;
  assign inp_pipe_op_mod_q[0]   = op_mod_i;
  assign inp_pipe_tag_q[0]      = tag_i;
  assign inp_pipe_mask_q[0]     = mask_i;
  assign inp_pipe_aux_q[0]      = aux_i;
  assign inp_pipe_valid_q[0]    = in_valid_i;
  // Input stage: Propagate pipeline ready signal to updtream circuitry
  assign in_ready_o = inp_pipe_ready[0];
  // Generate the register stages
  for (genvar i = 0; i < NUM_INP_REGS; i++) begin : gen_input_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign inp_pipe_ready[i] = inp_pipe_ready[i+1] | ~inp_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(inp_pipe_valid_q[i+1], inp_pipe_valid_q[i], inp_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (inp_pipe_ready[i] & inp_pipe_valid_q[i]) | reg_ena_i[i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(inp_pipe_operands_q[i+1], inp_pipe_operands_q[i], reg_ena, '0)
    `FFL(inp_pipe_is_boxed_q[i+1], inp_pipe_is_boxed_q[i], reg_ena, '0)
    `FFL(inp_pipe_rnd_mode_q[i+1], inp_pipe_rnd_mode_q[i], reg_ena, fpnew_pkg::RNE)
    `FFL(inp_pipe_op_q[i+1],       inp_pipe_op_q[i],       reg_ena, fpnew_pkg::FMADD)
    `FFL(inp_pipe_op_mod_q[i+1],   inp_pipe_op_mod_q[i],   reg_ena, '0)
    `FFL(inp_pipe_tag_q[i+1],      inp_pipe_tag_q[i],      reg_ena, TagType'('0))
    `FFL(inp_pipe_mask_q[i+1],     inp_pipe_mask_q[i],     reg_ena, '0)
    `FFL(inp_pipe_aux_q[i+1],      inp_pipe_aux_q[i],      reg_ena, AuxType'('0))
  end

  // -----------------
  // Input processing
  // -----------------
  fpnew_pkg::fp_info_t [2:0] info_q;

  // Classify input
  fpnew_classifier #(
    .FpFormat    ( FpFormat ),
    .NumOperands ( 3        )
    ) i_class_inputs (
    .operands_i ( inp_pipe_operands_q[NUM_INP_REGS] ),
    .is_boxed_i ( inp_pipe_is_boxed_q[NUM_INP_REGS] ),
    .info_o     ( info_q                            )
  );

  fp_t                 operand_a, operand_b, operand_c;
  fpnew_pkg::fp_info_t info_a,    info_b,    info_c;

  // Operation selection and operand adjustment
  // | \c op_q  | \c op_mod_q | Operation Adjustment
  // |:--------:|:-----------:|---------------------
  // | FMADD    | \c 0        | FMADD: none
  // | FMADD    | \c 1        | FMSUB: Invert sign of operand C
  // | FNMSUB   | \c 0        | FNMSUB: Invert sign of operand A
  // | FNMSUB   | \c 1        | FNMADD: Invert sign of operands A and C
  // | ADD      | \c 0        | ADD: Set operand A to +1.0
  // | ADD      | \c 1        | SUB: Set operand A to +1.0, invert sign of operand C
  // | MUL      | \c 0        | MUL: Set operand C to +0.0 or -0.0 depending on the rounding mode
  // | *others* | \c -        | *invalid*
  // \note \c op_mod_q always inverts the sign of the addend.
  always_comb begin : op_select

    // Default assignments - packing-order-agnostic
    operand_a = inp_pipe_operands_q[NUM_INP_REGS][0];
    operand_b = inp_pipe_operands_q[NUM_INP_REGS][1];
    operand_c = inp_pipe_operands_q[NUM_INP_REGS][2];
    info_a    = info_q[0];
    info_b    = info_q[1];
    info_c    = info_q[2];

    // op_mod_q inverts sign of operand C
    operand_c.sign = operand_c.sign ^ inp_pipe_op_mod_q[NUM_INP_REGS];

    unique case (inp_pipe_op_q[NUM_INP_REGS])
      fpnew_pkg::FMADD:  ; // do nothing
      fpnew_pkg::FNMSUB: operand_a.sign = ~operand_a.sign; // invert sign of product
      fpnew_pkg::ADD: begin // Set multiplicand to +1
        operand_a = '{sign: 1'b0, exponent: BIAS, mantissa: '0};
        info_a    = '{is_normal: 1'b1, is_boxed: 1'b1, default: 1'b0}; //normal, boxed value.
      end
      fpnew_pkg::MUL: begin // Set addend to +0 or -0, depending whether the rounding mode is RDN
        if (inp_pipe_rnd_mode_q[NUM_INP_REGS] == fpnew_pkg::RDN)
          operand_c = '{sign: 1'b0, exponent: '0, mantissa: '0};
        else
          operand_c = '{sign: 1'b1, exponent: '0, mantissa: '0};
        info_c    = '{is_zero: 1'b1, is_boxed: 1'b1, default: 1'b0}; //zero, boxed value.
      end
      default: begin // propagate don't cares
        operand_a  = '{default: fpnew_pkg::DONT_CARE};
        operand_b  = '{default: fpnew_pkg::DONT_CARE};
        operand_c  = '{default: fpnew_pkg::DONT_CARE};
        info_a     = '{default: fpnew_pkg::DONT_CARE};
        info_b     = '{default: fpnew_pkg::DONT_CARE};
        info_c     = '{default: fpnew_pkg::DONT_CARE};
      end
    endcase
  end

  // ---------------------
  // Input classification
  // ---------------------
  logic any_operand_inf;
  logic any_operand_nan;
  logic signalling_nan;
  logic effective_subtraction;
  logic tentative_sign;

  // Reduction for special case handling
  assign any_operand_inf = (| {info_a.is_inf,        info_b.is_inf,        info_c.is_inf});
  assign any_operand_nan = (| {info_a.is_nan,        info_b.is_nan,        info_c.is_nan});
  assign signalling_nan  = (| {info_a.is_signalling, info_b.is_signalling, info_c.is_signalling});
  // Effective subtraction in FMA occurs when product and addend signs differ
  assign effective_subtraction = operand_a.sign ^ operand_b.sign ^ operand_c.sign;
  // The tentative sign of the FMA shall be the sign of the product
  assign tentative_sign = operand_a.sign ^ operand_b.sign;

  // ----------------------
  // Special case handling
  // ----------------------
  fp_t                special_result;
  fpnew_pkg::status_t special_status;
  logic               result_is_special;

  always_comb begin : special_cases
    // Default assignments
    special_result    = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)}; // canonical qNaN
    special_status    = '0;
    result_is_special = 1'b0;

    // Handle potentially mixed nan & infinity input => important for the case where infinity and
    // zero are multiplied and added to a qnan.
    // RISC-V mandates raising the NV exception in these cases:
    // (inf * 0) + c or (0 * inf) + c INVALID, no matter c (even quiet NaNs)
    if ((info_a.is_inf && info_b.is_zero) || (info_a.is_zero && info_b.is_inf)) begin
      result_is_special = 1'b1; // bypass FMA, output is the canonical qNaN
      special_status.NV = 1'b1; // invalid operation
    // NaN Inputs cause canonical quiet NaN at the output and maybe invalid OP
    end else if (any_operand_nan) begin
      result_is_special = 1'b1;           // bypass FMA, output is the canonical qNaN
      special_status.NV = signalling_nan; // raise the invalid operation flag if signalling
    // Special cases involving infinity
    end else if (any_operand_inf) begin
      result_is_special = 1'b1; // bypass FMA
      // Effective addition of opposite infinities (±inf - ±inf) is invalid!
      if ((info_a.is_inf || info_b.is_inf) && info_c.is_inf && effective_subtraction)
        special_status.NV = 1'b1; // invalid operation
      // Handle cases where output will be inf because of inf product input
      else if (info_a.is_inf || info_b.is_inf) begin
        // Result is infinity with the sign of the product
        special_result    = '{sign: operand_a.sign ^ operand_b.sign, exponent: '1, mantissa: '0};
      // Handle cases where the addend is inf
      end else if (info_c.is_inf) begin
        // Result is inifinity with sign of the addend (= operand_c)
        special_result    = '{sign: operand_c.sign, exponent: '1, mantissa: '0};
      end
    end
  end

  // 操作数分类/特殊值判断与乘积/指数路径之间的真实流水边界。
  decode_payload_t [0:NUM_DECODE_REGS] decode_pipe_payload_q;
  logic             [0:NUM_DECODE_REGS] decode_pipe_valid_q;
  logic             [0:NUM_DECODE_REGS] decode_pipe_ready;

  always_comb begin
    decode_pipe_payload_q[0]                       = '0;
    decode_pipe_payload_q[0].operand_a             = operand_a;
    decode_pipe_payload_q[0].operand_b             = operand_b;
    decode_pipe_payload_q[0].operand_c             = operand_c;
    decode_pipe_payload_q[0].info_a                = info_a;
    decode_pipe_payload_q[0].info_b                = info_b;
    decode_pipe_payload_q[0].info_c                = info_c;
    decode_pipe_payload_q[0].effective_subtraction = effective_subtraction;
    decode_pipe_payload_q[0].tentative_sign        = tentative_sign;
    decode_pipe_payload_q[0].result_is_special     = result_is_special;
    decode_pipe_payload_q[0].special_result        = special_result;
    decode_pipe_payload_q[0].special_status        = special_status;
    decode_pipe_payload_q[0].rnd_mode              = inp_pipe_rnd_mode_q[NUM_INP_REGS];
    decode_pipe_payload_q[0].tag                   = inp_pipe_tag_q[NUM_INP_REGS];
    decode_pipe_payload_q[0].mask                  = inp_pipe_mask_q[NUM_INP_REGS];
    decode_pipe_payload_q[0].aux                   = inp_pipe_aux_q[NUM_INP_REGS];
  end
  assign decode_pipe_valid_q[0] = inp_pipe_valid_q[NUM_INP_REGS];
  assign inp_pipe_ready[NUM_INP_REGS] = decode_pipe_ready[0];

  for (genvar i = 0; i < NUM_DECODE_REGS; i++) begin : gen_decode_pipeline
    logic reg_ena;
    assign decode_pipe_ready[i] = decode_pipe_ready[i+1] | ~decode_pipe_valid_q[i+1];
    `FFLARNC(decode_pipe_valid_q[i+1], decode_pipe_valid_q[i], decode_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (decode_pipe_ready[i] & decode_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + i];
    `FFL(decode_pipe_payload_q[i+1], decode_pipe_payload_q[i], reg_ena, '0)
  end

  // ---------------------------
  // Initial exponent data path
  // ---------------------------
  logic signed [EXP_WIDTH-1:0] exponent_a, exponent_b, exponent_c;
  logic signed [EXP_WIDTH-1:0] exponent_addend, exponent_product, exponent_difference;
  logic signed [EXP_WIDTH-1:0] tentative_exponent;

  // Zero-extend exponents into signed container - implicit width extension
  assign exponent_a = signed'({1'b0, decode_pipe_payload_q[NUM_DECODE_REGS].operand_a.exponent});
  assign exponent_b = signed'({1'b0, decode_pipe_payload_q[NUM_DECODE_REGS].operand_b.exponent});
  assign exponent_c = signed'({1'b0, decode_pipe_payload_q[NUM_DECODE_REGS].operand_c.exponent});

  // Calculate internal exponents from encoded values. Real exponents are (ex = Ex - bias + 1 - nx)
  // with Ex the encoded exponent and nx the implicit bit. Internal exponents stay biased.
  assign exponent_addend = signed'(exponent_c +
      $signed({1'b0, ~decode_pipe_payload_q[NUM_DECODE_REGS].info_c.is_normal}));
  // Biased product exponent is the sum of encoded exponents minus the bias.
  assign exponent_product = (decode_pipe_payload_q[NUM_DECODE_REGS].info_a.is_zero ||
                             decode_pipe_payload_q[NUM_DECODE_REGS].info_b.is_zero)
                            ? 2 - signed'(BIAS) // in case the product is zero, set minimum exp.
                            : signed'(exponent_a +
                                      decode_pipe_payload_q[NUM_DECODE_REGS].info_a.is_subnormal +
                                      exponent_b +
                                      decode_pipe_payload_q[NUM_DECODE_REGS].info_b.is_subnormal
                                      - signed'(BIAS));
  // Exponent difference is the addend exponent minus the product exponent
  assign exponent_difference = exponent_addend - exponent_product;
  // The tentative exponent will be the larger of the product or addend exponent
  assign tentative_exponent = (exponent_difference > 0) ? exponent_addend : exponent_product;

  // Shift amount for addend based on exponents (unsigned as only right shifts)
  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt;

  always_comb begin : addend_shift_amount
    // Product-anchored case, saturated shift (addend is only in the sticky bit)
    if (exponent_difference <= signed'(-2 * PRECISION_BITS - 1))
      addend_shamt = 3 * PRECISION_BITS + 4;
    // Addend and product will have mutual bits to add
    else if (exponent_difference <= signed'(PRECISION_BITS + 2))
      addend_shamt = unsigned'(signed'(PRECISION_BITS) + 3 - exponent_difference);
    // Addend-anchored case, saturated shift (product is only in the sticky bit)
    else
      addend_shamt = 0;
  end

  // ------------------
  // Product data path
  // ------------------
  logic [PRECISION_BITS-1:0]   mantissa_a, mantissa_b, mantissa_c;
  logic [2*PRECISION_BITS-1:0] product;             // the p*p product is 2p bits wide
  logic [3*PRECISION_BITS+3:0] product_shifted;     // addends are 3p+4 bit wide (including G/R)

  // Add implicit bits to mantissae
  assign mantissa_a = {decode_pipe_payload_q[NUM_DECODE_REGS].info_a.is_normal,
                       decode_pipe_payload_q[NUM_DECODE_REGS].operand_a.mantissa};
  assign mantissa_b = {decode_pipe_payload_q[NUM_DECODE_REGS].info_b.is_normal,
                       decode_pipe_payload_q[NUM_DECODE_REGS].operand_b.mantissa};
  assign mantissa_c = {decode_pipe_payload_q[NUM_DECODE_REGS].info_c.is_normal,
                       decode_pipe_payload_q[NUM_DECODE_REGS].operand_c.mantissa};

  // Mantissa multiplier (a*b)
  assign product = mantissa_a * mantissa_b;

  // Product is placed into a 3p+4 bit wide vector, padded with 2 bits for round and sticky:
  // | 000...000 | product | RS |
  //  <-  p+2  -> <-  2p -> < 2>
  assign product_shifted = product << 2; // constant shift

  // ---------------------------------
  // Product/exponent alignment pipeline
  // ---------------------------------
  align_payload_t [0:NUM_ALIGN_REGS] align_pipe_payload_q;
  logic           [0:NUM_ALIGN_REGS] align_pipe_valid_q;
  logic           [0:NUM_ALIGN_REGS] align_pipe_ready;

  always_comb begin
    align_pipe_payload_q[0]                       = '0;
    align_pipe_payload_q[0].product_shifted       = product_shifted;
    align_pipe_payload_q[0].mantissa_c            = mantissa_c;
    align_pipe_payload_q[0].effective_subtraction =
        decode_pipe_payload_q[NUM_DECODE_REGS].effective_subtraction;
    align_pipe_payload_q[0].tentative_sign        =
        decode_pipe_payload_q[NUM_DECODE_REGS].tentative_sign;
    align_pipe_payload_q[0].exponent_product      = exponent_product;
    align_pipe_payload_q[0].exponent_difference   = exponent_difference;
    align_pipe_payload_q[0].tentative_exponent    = tentative_exponent;
    align_pipe_payload_q[0].addend_shamt          = addend_shamt;
    align_pipe_payload_q[0].rnd_mode              = decode_pipe_payload_q[NUM_DECODE_REGS].rnd_mode;
    align_pipe_payload_q[0].result_is_special     =
        decode_pipe_payload_q[NUM_DECODE_REGS].result_is_special;
    align_pipe_payload_q[0].special_result        =
        decode_pipe_payload_q[NUM_DECODE_REGS].special_result;
    align_pipe_payload_q[0].special_status        =
        decode_pipe_payload_q[NUM_DECODE_REGS].special_status;
    align_pipe_payload_q[0].tag                   = decode_pipe_payload_q[NUM_DECODE_REGS].tag;
    align_pipe_payload_q[0].mask                  = decode_pipe_payload_q[NUM_DECODE_REGS].mask;
    align_pipe_payload_q[0].aux                   = decode_pipe_payload_q[NUM_DECODE_REGS].aux;
  end
  assign align_pipe_valid_q[0] = decode_pipe_valid_q[NUM_DECODE_REGS];
  assign decode_pipe_ready[NUM_DECODE_REGS] = align_pipe_ready[0];

  for (genvar i = 0; i < NUM_ALIGN_REGS; i++) begin : gen_align_pipeline
    logic reg_ena;
    assign align_pipe_ready[i] = align_pipe_ready[i+1] | ~align_pipe_valid_q[i+1];
    `FFLARNC(align_pipe_valid_q[i+1], align_pipe_valid_q[i], align_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (align_pipe_ready[i] & align_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + i];
    `FFL(align_pipe_payload_q[i+1], align_pipe_payload_q[i], reg_ena, '0)
  end

  // -----------------
  // Addend data path
  // -----------------
  logic [3*PRECISION_BITS+3:0] addend_after_shift;  // upper 3p+4 bits are needed to go on
  logic [PRECISION_BITS-1:0]   addend_sticky_bits;  // up to p bit of shifted addend are sticky
  logic                        sticky_before_add;   // they are compressed into a single sticky bit
  logic [3*PRECISION_BITS+3:0] addend_shifted;      // addends are 3p+4 bit wide (including G/R)
  logic                        inject_carry_in;     // inject carry for subtractions if needed

  // In parallel, the addend is right-shifted according to the exponent difference. Up to p bits
  // are shifted out and compressed into a sticky bit.
  // BEFORE THE SHIFT:
  // | mantissa_c | 000..000 |
  //  <-    p   -> <- 3p+4 ->
  // AFTER THE SHIFT:
  // | 000..........000 | mantissa_c | 000...............0GR |  sticky bits  |
  //  <- addend_shamt -> <-    p   -> <- 2p+4-addend_shamt -> <-  up to p  ->
  assign {addend_after_shift, addend_sticky_bits} =
      (align_pipe_payload_q[NUM_ALIGN_REGS].mantissa_c << (3 * PRECISION_BITS + 4)) >>
      align_pipe_payload_q[NUM_ALIGN_REGS].addend_shamt;

  assign sticky_before_add     = (| addend_sticky_bits);
  // assign addend_after_shift[0] = sticky_before_add;

  // -------------------------
  // Addend alignment pipeline
  // -------------------------
  add_payload_t [0:NUM_ADD_REGS] add_pipe_payload_q;
  logic         [0:NUM_ADD_REGS] add_pipe_valid_q;
  logic         [0:NUM_ADD_REGS] add_pipe_ready;

  always_comb begin
    add_pipe_payload_q[0]                       = '0;
    add_pipe_payload_q[0].product_shifted       = align_pipe_payload_q[NUM_ALIGN_REGS].product_shifted;
    add_pipe_payload_q[0].addend_after_shift    = addend_after_shift;
    add_pipe_payload_q[0].sticky_before_add     = sticky_before_add;
    add_pipe_payload_q[0].effective_subtraction = align_pipe_payload_q[NUM_ALIGN_REGS].effective_subtraction;
    add_pipe_payload_q[0].tentative_sign        = align_pipe_payload_q[NUM_ALIGN_REGS].tentative_sign;
    add_pipe_payload_q[0].exponent_product      = align_pipe_payload_q[NUM_ALIGN_REGS].exponent_product;
    add_pipe_payload_q[0].exponent_difference   = align_pipe_payload_q[NUM_ALIGN_REGS].exponent_difference;
    add_pipe_payload_q[0].tentative_exponent    = align_pipe_payload_q[NUM_ALIGN_REGS].tentative_exponent;
    add_pipe_payload_q[0].addend_shamt          = align_pipe_payload_q[NUM_ALIGN_REGS].addend_shamt;
    add_pipe_payload_q[0].rnd_mode              = align_pipe_payload_q[NUM_ALIGN_REGS].rnd_mode;
    add_pipe_payload_q[0].result_is_special     = align_pipe_payload_q[NUM_ALIGN_REGS].result_is_special;
    add_pipe_payload_q[0].special_result        = align_pipe_payload_q[NUM_ALIGN_REGS].special_result;
    add_pipe_payload_q[0].special_status        = align_pipe_payload_q[NUM_ALIGN_REGS].special_status;
    add_pipe_payload_q[0].tag                   = align_pipe_payload_q[NUM_ALIGN_REGS].tag;
    add_pipe_payload_q[0].mask                  = align_pipe_payload_q[NUM_ALIGN_REGS].mask;
    add_pipe_payload_q[0].aux                   = align_pipe_payload_q[NUM_ALIGN_REGS].aux;
  end
  assign add_pipe_valid_q[0] = align_pipe_valid_q[NUM_ALIGN_REGS];
  assign align_pipe_ready[NUM_ALIGN_REGS] = add_pipe_ready[0];

  for (genvar i = 0; i < NUM_ADD_REGS; i++) begin : gen_add_pipeline
    logic reg_ena;
    assign add_pipe_ready[i] = add_pipe_ready[i+1] | ~add_pipe_valid_q[i+1];
    `FFLARNC(add_pipe_valid_q[i+1], add_pipe_valid_q[i], add_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (add_pipe_ready[i] & add_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS + i];
    `FFL(add_pipe_payload_q[i+1], add_pipe_payload_q[i], reg_ena, '0)
  end

  // In case of a subtraction, the addend is inverted
  assign addend_shifted  = add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction
                            ? ~add_pipe_payload_q[NUM_ADD_REGS].addend_after_shift
                            : add_pipe_payload_q[NUM_ADD_REGS].addend_after_shift;
  assign inject_carry_in = add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction &
                           ~add_pipe_payload_q[NUM_ADD_REGS].sticky_before_add;

  // ------
  // Adder
  // ------
  logic [3*PRECISION_BITS+4:0] sum_raw;   // added one bit for the carry
  logic                        sum_carry; // observe carry bit from sum for sign fixing
  logic [3*PRECISION_BITS+3:0] sum;       // discard carry as sum won't overflow
  logic                        final_sign;

  //Mantissa adder (ab+c). In normal addition, it cannot overflow.
  assign sum_raw = add_pipe_payload_q[NUM_ADD_REGS].product_shifted +
                   addend_shifted + inject_carry_in;
  assign sum_carry = sum_raw[3*PRECISION_BITS+4];

  // Complement negative sum (can only happen in subtraction -> overflows for positive results)
  assign sum        = (add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction && ~sum_carry)
                      ? -sum_raw : sum_raw;

  // In case of a mispredicted subtraction result, do a sign flip
  assign final_sign = (add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction &&
                       (sum_carry == add_pipe_payload_q[NUM_ADD_REGS].tentative_sign))
                      ? 1'b1
                      : (add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction
                         ? 1'b0 : add_pipe_payload_q[NUM_ADD_REGS].tentative_sign);

  // ---------------
  // Internal pipeline
  // ---------------
  // Pipeline output signals as non-arrays
  logic                          effective_subtraction_q;
  logic signed [EXP_WIDTH-1:0]   exponent_product_q;
  logic signed [EXP_WIDTH-1:0]   exponent_difference_q;
  logic signed [EXP_WIDTH-1:0]   tentative_exponent_q;
  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt_q;
  logic                          sticky_before_add_q;
  logic [3*PRECISION_BITS+3:0]   sum_q;
  logic                          final_sign_q;
  fpnew_pkg::roundmode_e         rnd_mode_q;
  logic                          result_is_special_q;
  fp_t                           special_result_q;
  fpnew_pkg::status_t            special_status_q;
  // Internal pipeline signals, index i holds signal after i register stages
  logic                  [0:NUM_MID_REGS]                         mid_pipe_eff_sub_q;
  logic signed           [0:NUM_MID_REGS][EXP_WIDTH-1:0]          mid_pipe_exp_prod_q;
  logic signed           [0:NUM_MID_REGS][EXP_WIDTH-1:0]          mid_pipe_exp_diff_q;
  logic signed           [0:NUM_MID_REGS][EXP_WIDTH-1:0]          mid_pipe_tent_exp_q;
  logic                  [0:NUM_MID_REGS][SHIFT_AMOUNT_WIDTH-1:0] mid_pipe_add_shamt_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_sticky_q;
  logic                  [0:NUM_MID_REGS][3*PRECISION_BITS+3:0]   mid_pipe_sum_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_final_sign_q;
  fpnew_pkg::roundmode_e [0:NUM_MID_REGS]                         mid_pipe_rnd_mode_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_res_is_spec_q;
  fp_t                   [0:NUM_MID_REGS]                         mid_pipe_spec_res_q;
  fpnew_pkg::status_t    [0:NUM_MID_REGS]                         mid_pipe_spec_stat_q;
  TagType                [0:NUM_MID_REGS]                         mid_pipe_tag_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_mask_q;
  AuxType                [0:NUM_MID_REGS]                         mid_pipe_aux_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_MID_REGS] mid_pipe_ready;

  // Input stage: First element of pipeline is taken from upstream logic
  assign mid_pipe_eff_sub_q[0]     = add_pipe_payload_q[NUM_ADD_REGS].effective_subtraction;
  assign mid_pipe_exp_prod_q[0]    = add_pipe_payload_q[NUM_ADD_REGS].exponent_product;
  assign mid_pipe_exp_diff_q[0]    = add_pipe_payload_q[NUM_ADD_REGS].exponent_difference;
  assign mid_pipe_tent_exp_q[0]    = add_pipe_payload_q[NUM_ADD_REGS].tentative_exponent;
  assign mid_pipe_add_shamt_q[0]   = add_pipe_payload_q[NUM_ADD_REGS].addend_shamt;
  assign mid_pipe_sticky_q[0]      = add_pipe_payload_q[NUM_ADD_REGS].sticky_before_add;
  assign mid_pipe_sum_q[0]         = sum;
  assign mid_pipe_final_sign_q[0]  = final_sign;
  assign mid_pipe_rnd_mode_q[0]    = add_pipe_payload_q[NUM_ADD_REGS].rnd_mode;
  assign mid_pipe_res_is_spec_q[0] = add_pipe_payload_q[NUM_ADD_REGS].result_is_special;
  assign mid_pipe_spec_res_q[0]    = add_pipe_payload_q[NUM_ADD_REGS].special_result;
  assign mid_pipe_spec_stat_q[0]   = add_pipe_payload_q[NUM_ADD_REGS].special_status;
  assign mid_pipe_tag_q[0]         = add_pipe_payload_q[NUM_ADD_REGS].tag;
  assign mid_pipe_mask_q[0]        = add_pipe_payload_q[NUM_ADD_REGS].mask;
  assign mid_pipe_aux_q[0]         = add_pipe_payload_q[NUM_ADD_REGS].aux;
  assign mid_pipe_valid_q[0]       = add_pipe_valid_q[NUM_ADD_REGS];
  // Input stage: Propagate pipeline ready signal to addend pipe
  assign add_pipe_ready[NUM_ADD_REGS] = mid_pipe_ready[0];

  // Generate the register stages
  for (genvar i = 0; i < NUM_MID_REGS; i++) begin : gen_inside_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign mid_pipe_ready[i] = mid_pipe_ready[i+1] | ~mid_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(mid_pipe_valid_q[i+1], mid_pipe_valid_q[i], mid_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (mid_pipe_ready[i] & mid_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS +
                               NUM_ADD_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(mid_pipe_eff_sub_q[i+1],     mid_pipe_eff_sub_q[i],     reg_ena, '0)
    `FFL(mid_pipe_exp_prod_q[i+1],    mid_pipe_exp_prod_q[i],    reg_ena, '0)
    `FFL(mid_pipe_exp_diff_q[i+1],    mid_pipe_exp_diff_q[i],    reg_ena, '0)
    `FFL(mid_pipe_tent_exp_q[i+1],    mid_pipe_tent_exp_q[i],    reg_ena, '0)
    `FFL(mid_pipe_add_shamt_q[i+1],   mid_pipe_add_shamt_q[i],   reg_ena, '0)
    `FFL(mid_pipe_sticky_q[i+1],      mid_pipe_sticky_q[i],      reg_ena, '0)
    `FFL(mid_pipe_sum_q[i+1],         mid_pipe_sum_q[i],         reg_ena, '0)
    `FFL(mid_pipe_final_sign_q[i+1],  mid_pipe_final_sign_q[i],  reg_ena, '0)
    `FFL(mid_pipe_rnd_mode_q[i+1],    mid_pipe_rnd_mode_q[i],    reg_ena, fpnew_pkg::RNE)
    `FFL(mid_pipe_res_is_spec_q[i+1], mid_pipe_res_is_spec_q[i], reg_ena, '0)
    `FFL(mid_pipe_spec_res_q[i+1],    mid_pipe_spec_res_q[i],    reg_ena, '0)
    `FFL(mid_pipe_spec_stat_q[i+1],   mid_pipe_spec_stat_q[i],   reg_ena, '0)
    `FFL(mid_pipe_tag_q[i+1],         mid_pipe_tag_q[i],         reg_ena, TagType'('0))
    `FFL(mid_pipe_mask_q[i+1],        mid_pipe_mask_q[i],        reg_ena, '0)
    `FFL(mid_pipe_aux_q[i+1],         mid_pipe_aux_q[i],         reg_ena, AuxType'('0))
  end
  // Output stage: assign selected pipe outputs to signals for later use
  assign effective_subtraction_q = mid_pipe_eff_sub_q[NUM_MID_REGS];
  assign exponent_product_q      = mid_pipe_exp_prod_q[NUM_MID_REGS];
  assign exponent_difference_q   = mid_pipe_exp_diff_q[NUM_MID_REGS];
  assign tentative_exponent_q    = mid_pipe_tent_exp_q[NUM_MID_REGS];
  assign addend_shamt_q          = mid_pipe_add_shamt_q[NUM_MID_REGS];
  assign sticky_before_add_q     = mid_pipe_sticky_q[NUM_MID_REGS];
  assign sum_q                   = mid_pipe_sum_q[NUM_MID_REGS];
  assign final_sign_q            = mid_pipe_final_sign_q[NUM_MID_REGS];
  assign rnd_mode_q              = mid_pipe_rnd_mode_q[NUM_MID_REGS];
  assign result_is_special_q     = mid_pipe_res_is_spec_q[NUM_MID_REGS];
  assign special_result_q        = mid_pipe_spec_res_q[NUM_MID_REGS];
  assign special_status_q        = mid_pipe_spec_stat_q[NUM_MID_REGS];

  // --------------
  // Normalization
  // --------------
  logic        [LOWER_SUM_WIDTH-1:0]  sum_lower;              // lower 2p+3 bits of sum are searched
  logic        [LZC_RESULT_WIDTH-1:0] leading_zero_count;     // the number of leading zeroes
  logic signed [LZC_RESULT_WIDTH:0]   leading_zero_count_sgn; // signed leading-zero count
  logic                               lzc_zeroes;             // in case only zeroes found

  logic        [SHIFT_AMOUNT_WIDTH-1:0] norm_shamt; // Normalization shift amount
  logic signed [EXP_WIDTH-1:0]          normalized_exponent;

  logic [3*PRECISION_BITS+4:0] sum_shifted;       // result after first normalization shift
  logic [PRECISION_BITS:0]     final_mantissa;    // final mantissa before rounding with round bit
  logic [2*PRECISION_BITS+2:0] sum_sticky_bits;   // remaining 2p+3 sticky bits after normalization
  logic                        sticky_after_norm; // sticky bit after normalization

  logic signed [EXP_WIDTH-1:0] final_exponent;

  assign sum_lower = sum_q[LOWER_SUM_WIDTH-1:0];

  // Leading zero counter for cancellations
  lzc #(
    .WIDTH ( LOWER_SUM_WIDTH ),
    .MODE  ( 1               ) // MODE = 1 counts leading zeroes
  ) i_lzc (
    .in_i    ( sum_lower          ),
    .cnt_o   ( leading_zero_count ),
    .empty_o ( lzc_zeroes         )
  );

  assign leading_zero_count_sgn = signed'({1'b0, leading_zero_count});

  // Normalization shift amount based on exponents and LZC (unsigned as only left shifts)
  always_comb begin : norm_shift_amount
    // Product-anchored case or cancellations require LZC
    if ((exponent_difference_q <= 0) || (effective_subtraction_q && (exponent_difference_q <= 2))) begin
      // Normal result (biased exponent > 0 and not a zero)
      if ((exponent_product_q - leading_zero_count_sgn + 1 >= 0) && !lzc_zeroes) begin
        // Undo initial product shift, remove the counted zeroes
        norm_shamt          = PRECISION_BITS + 2 + leading_zero_count;
        normalized_exponent = exponent_product_q - leading_zero_count_sgn + 1; // account for shift
      // Subnormal result
      end else begin
        // Cap the shift distance to align mantissa with minimum exponent
        norm_shamt          = unsigned'(signed'(PRECISION_BITS) + 2 + exponent_product_q);
        normalized_exponent = 0; // subnormals encoded as 0
      end
    // Addend-anchored case
    end else begin
      norm_shamt          = addend_shamt_q; // Undo the initial shift
      normalized_exponent = tentative_exponent_q;
    end
  end

  // LZC/移位量计算与宽移位器之间的真实流水边界。
  shift_payload_t [0:NUM_SHIFT_REGS] shift_pipe_payload_q;
  logic              [0:NUM_SHIFT_REGS] shift_pipe_valid_q;
  logic              [0:NUM_SHIFT_REGS] shift_pipe_ready;

  always_comb begin
    shift_pipe_payload_q[0]                       = '0;
    shift_pipe_payload_q[0].sum                   = sum_q;
    shift_pipe_payload_q[0].norm_shamt            = norm_shamt;
    shift_pipe_payload_q[0].normalized_exponent   = normalized_exponent;
    shift_pipe_payload_q[0].sticky_before_add     = sticky_before_add_q;
    shift_pipe_payload_q[0].final_sign            = final_sign_q;
    shift_pipe_payload_q[0].effective_subtraction = effective_subtraction_q;
    shift_pipe_payload_q[0].rnd_mode              = rnd_mode_q;
    shift_pipe_payload_q[0].result_is_special     = result_is_special_q;
    shift_pipe_payload_q[0].special_result        = special_result_q;
    shift_pipe_payload_q[0].special_status        = special_status_q;
    shift_pipe_payload_q[0].tag                   = mid_pipe_tag_q[NUM_MID_REGS];
    shift_pipe_payload_q[0].mask                  = mid_pipe_mask_q[NUM_MID_REGS];
    shift_pipe_payload_q[0].aux                   = mid_pipe_aux_q[NUM_MID_REGS];
  end
  assign shift_pipe_valid_q[0] = mid_pipe_valid_q[NUM_MID_REGS];
  assign mid_pipe_ready[NUM_MID_REGS] = shift_pipe_ready[0];

  for (genvar i = 0; i < NUM_SHIFT_REGS; i++) begin : gen_shift_pipeline
    logic reg_ena;
    assign shift_pipe_ready[i] = shift_pipe_ready[i+1] | ~shift_pipe_valid_q[i+1];
    `FFLARNC(shift_pipe_valid_q[i+1], shift_pipe_valid_q[i], shift_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (shift_pipe_ready[i] & shift_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS + NUM_ADD_REGS +
                               NUM_MID_REGS + i];
    `FFL(shift_pipe_payload_q[i+1], shift_pipe_payload_q[i], reg_ena, '0)
  end

  // Do the large normalization shift
  assign sum_shifted = shift_pipe_payload_q[NUM_SHIFT_REGS].sum <<
                       shift_pipe_payload_q[NUM_SHIFT_REGS].norm_shamt;

  // ----------------------------------
  // Normalization/rounding boundary pipe
  // ----------------------------------
  norm_payload_t [0:NUM_NORM_REGS] norm_pipe_payload_q;
  logic           [0:NUM_NORM_REGS] norm_pipe_valid_q;
  logic           [0:NUM_NORM_REGS] norm_pipe_ready;

  always_comb begin
    norm_pipe_payload_q[0]                       = '0;
    norm_pipe_payload_q[0].sum_shifted           = sum_shifted;
    norm_pipe_payload_q[0].normalized_exponent   =
        shift_pipe_payload_q[NUM_SHIFT_REGS].normalized_exponent;
    norm_pipe_payload_q[0].sticky_before_add     =
        shift_pipe_payload_q[NUM_SHIFT_REGS].sticky_before_add;
    norm_pipe_payload_q[0].final_sign            =
        shift_pipe_payload_q[NUM_SHIFT_REGS].final_sign;
    norm_pipe_payload_q[0].effective_subtraction =
        shift_pipe_payload_q[NUM_SHIFT_REGS].effective_subtraction;
    norm_pipe_payload_q[0].rnd_mode              = shift_pipe_payload_q[NUM_SHIFT_REGS].rnd_mode;
    norm_pipe_payload_q[0].result_is_special     =
        shift_pipe_payload_q[NUM_SHIFT_REGS].result_is_special;
    norm_pipe_payload_q[0].special_result        =
        shift_pipe_payload_q[NUM_SHIFT_REGS].special_result;
    norm_pipe_payload_q[0].special_status        =
        shift_pipe_payload_q[NUM_SHIFT_REGS].special_status;
    norm_pipe_payload_q[0].tag                   = shift_pipe_payload_q[NUM_SHIFT_REGS].tag;
    norm_pipe_payload_q[0].mask                  = shift_pipe_payload_q[NUM_SHIFT_REGS].mask;
    norm_pipe_payload_q[0].aux                   = shift_pipe_payload_q[NUM_SHIFT_REGS].aux;
  end
  assign norm_pipe_valid_q[0] = shift_pipe_valid_q[NUM_SHIFT_REGS];
  assign shift_pipe_ready[NUM_SHIFT_REGS] = norm_pipe_ready[0];

  for (genvar i = 0; i < NUM_NORM_REGS; i++) begin : gen_norm_pipeline
    logic reg_ena;
    assign norm_pipe_ready[i] = norm_pipe_ready[i+1] | ~norm_pipe_valid_q[i+1];
    `FFLARNC(norm_pipe_valid_q[i+1], norm_pipe_valid_q[i], norm_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (norm_pipe_ready[i] & norm_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS + NUM_ADD_REGS +
                               NUM_MID_REGS + NUM_SHIFT_REGS + i];
    `FFL(norm_pipe_payload_q[i+1], norm_pipe_payload_q[i], reg_ena, '0)
  end

  // The addend-anchored case needs a 1-bit normalization since the leading-one can be to the left
  // or right of the (non-carry) MSB of the sum.
  always_comb begin : small_norm
    // Default assignment, discarding carry bit
    {final_mantissa, sum_sticky_bits} = norm_pipe_payload_q[NUM_NORM_REGS].sum_shifted;
    final_exponent = norm_pipe_payload_q[NUM_NORM_REGS].normalized_exponent;

    // The normalized sum has overflown, align right and fix exponent
    if (norm_pipe_payload_q[NUM_NORM_REGS].sum_shifted[3*PRECISION_BITS+4]) begin
      {final_mantissa, sum_sticky_bits} =
          norm_pipe_payload_q[NUM_NORM_REGS].sum_shifted >> 1;
      final_exponent = norm_pipe_payload_q[NUM_NORM_REGS].normalized_exponent + 1;
    // The normalized sum is normal, nothing to do
    end else if (norm_pipe_payload_q[NUM_NORM_REGS].sum_shifted[3*PRECISION_BITS+3]) begin
      // do nothing
    // The normalized sum is still denormal, align left - unless the result is not already subnormal
    end else if (norm_pipe_payload_q[NUM_NORM_REGS].normalized_exponent > 1) begin
      {final_mantissa, sum_sticky_bits} =
          norm_pipe_payload_q[NUM_NORM_REGS].sum_shifted << 1;
      final_exponent = norm_pipe_payload_q[NUM_NORM_REGS].normalized_exponent - 1;
    // Otherwise we're denormal
    end else begin
      final_exponent = '0;
    end
  end

  // Update the sticky bit with the shifted-out bits
  assign sticky_after_norm = (| {sum_sticky_bits}) |
                             norm_pipe_payload_q[NUM_NORM_REGS].sticky_before_add;

  // ----------------------------
  // Rounding and classification
  // ----------------------------
  logic                         pre_round_sign;
  logic [EXP_BITS-1:0]          pre_round_exponent;
  logic [MAN_BITS-1:0]          pre_round_mantissa;
  logic [EXP_BITS+MAN_BITS-1:0] pre_round_abs; // absolute value of result before rounding
  logic [1:0]                   round_sticky_bits;

  logic of_before_round, of_after_round; // overflow
  logic uf_before_round, uf_after_round; // underflow
  logic result_zero;

  logic                         rounded_sign;
  logic [EXP_BITS+MAN_BITS-1:0] rounded_abs; // absolute value of result after rounding

  // Classification before round. RISC-V mandates checking underflow AFTER rounding!
  assign of_before_round = final_exponent >= 2**(EXP_BITS)-1; // infinity exponent is all ones
  assign uf_before_round = final_exponent == 0;               // exponent for subnormals capped to 0

  // Assemble result before rounding. In case of overflow, the largest normal value is set.
  assign pre_round_sign     = norm_pipe_payload_q[NUM_NORM_REGS].final_sign;
  assign pre_round_exponent = (of_before_round) ? 2**EXP_BITS-2 : unsigned'(final_exponent[EXP_BITS-1:0]);
  assign pre_round_mantissa = (of_before_round) ? '1 : final_mantissa[MAN_BITS:1]; // bit 0 is R bit
  assign pre_round_abs      = {pre_round_exponent, pre_round_mantissa};

  // In case of overflow, the round and sticky bits are set for proper rounding
  assign round_sticky_bits  = (of_before_round) ? 2'b11 : {final_mantissa[0], sticky_after_norm};

  // 小归一化与舍入/异常分类之间的真实流水边界。
  round_payload_t [0:NUM_ROUND_REGS] round_pipe_payload_q;
  logic            [0:NUM_ROUND_REGS] round_pipe_valid_q;
  logic            [0:NUM_ROUND_REGS] round_pipe_ready;

  always_comb begin
    round_pipe_payload_q[0]                       = '0;
    round_pipe_payload_q[0].pre_round_abs         = pre_round_abs;
    round_pipe_payload_q[0].pre_round_sign        = pre_round_sign;
    round_pipe_payload_q[0].round_sticky_bits     = round_sticky_bits;
    round_pipe_payload_q[0].effective_subtraction =
        norm_pipe_payload_q[NUM_NORM_REGS].effective_subtraction;
    round_pipe_payload_q[0].of_before_round       = of_before_round;
    round_pipe_payload_q[0].sum_sticky_bits       = sum_sticky_bits;
    round_pipe_payload_q[0].rnd_mode              = norm_pipe_payload_q[NUM_NORM_REGS].rnd_mode;
    round_pipe_payload_q[0].result_is_special     =
        norm_pipe_payload_q[NUM_NORM_REGS].result_is_special;
    round_pipe_payload_q[0].special_result        =
        norm_pipe_payload_q[NUM_NORM_REGS].special_result;
    round_pipe_payload_q[0].special_status        =
        norm_pipe_payload_q[NUM_NORM_REGS].special_status;
    round_pipe_payload_q[0].tag                   = norm_pipe_payload_q[NUM_NORM_REGS].tag;
    round_pipe_payload_q[0].mask                  = norm_pipe_payload_q[NUM_NORM_REGS].mask;
    round_pipe_payload_q[0].aux                   = norm_pipe_payload_q[NUM_NORM_REGS].aux;
  end
  assign round_pipe_valid_q[0] = norm_pipe_valid_q[NUM_NORM_REGS];
  assign norm_pipe_ready[NUM_NORM_REGS] = round_pipe_ready[0];

  for (genvar i = 0; i < NUM_ROUND_REGS; i++) begin : gen_round_pipeline
    logic reg_ena;
    assign round_pipe_ready[i] = round_pipe_ready[i+1] | ~round_pipe_valid_q[i+1];
    `FFLARNC(round_pipe_valid_q[i+1], round_pipe_valid_q[i], round_pipe_ready[i],
             flush_i, 1'b0, clk_i, rst_ni)
    assign reg_ena = (round_pipe_ready[i] & round_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS + NUM_ADD_REGS +
                               NUM_MID_REGS + NUM_SHIFT_REGS + NUM_NORM_REGS + i];
    `FFL(round_pipe_payload_q[i+1], round_pipe_payload_q[i], reg_ena, '0)
  end

  // Perform the rounding
  fpnew_rounding #(
    .AbsWidth ( EXP_BITS + MAN_BITS )
  ) i_fpnew_rounding (
    .abs_value_i             ( round_pipe_payload_q[NUM_ROUND_REGS].pre_round_abs         ),
    .sign_i                  ( round_pipe_payload_q[NUM_ROUND_REGS].pre_round_sign        ),
    .round_sticky_bits_i     ( round_pipe_payload_q[NUM_ROUND_REGS].round_sticky_bits     ),
    .rnd_mode_i              ( round_pipe_payload_q[NUM_ROUND_REGS].rnd_mode              ),
    .effective_subtraction_i ( round_pipe_payload_q[NUM_ROUND_REGS].effective_subtraction ),
    .abs_rounded_o           ( rounded_abs             ),
    .sign_o                  ( rounded_sign            ),
    .exact_zero_o            ( result_zero             )
  );

  // Classification after rounding
  assign uf_after_round = (rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '0) // denormal
        || ((round_pipe_payload_q[NUM_ROUND_REGS].pre_round_abs[
                 EXP_BITS+MAN_BITS-1:MAN_BITS] == '0) &&
            (rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == 1) &&
           ((round_pipe_payload_q[NUM_ROUND_REGS].round_sticky_bits != 2'b11) ||
            (!round_pipe_payload_q[NUM_ROUND_REGS].sum_sticky_bits[MAN_BITS*2 + 4] &&
             ((round_pipe_payload_q[NUM_ROUND_REGS].rnd_mode == fpnew_pkg::RNE) ||
              (round_pipe_payload_q[NUM_ROUND_REGS].rnd_mode == fpnew_pkg::RMM)))));
  assign of_after_round = rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '1; // exponent all ones

  // -----------------
  // Result selection
  // -----------------
  logic [WIDTH-1:0]     regular_result;
  fpnew_pkg::status_t   regular_status;

  // Assemble regular result
  assign regular_result    = {rounded_sign, rounded_abs};
  assign regular_status.NV = 1'b0; // only valid cases are handled in regular path
  assign regular_status.DZ = 1'b0; // no divisions
  assign regular_status.OF = round_pipe_payload_q[NUM_ROUND_REGS].of_before_round |
                             of_after_round;   // rounding can introduce overflow
  assign regular_status.UF = uf_after_round & regular_status.NX; // only inexact results raise UF
  assign regular_status.NX = (| round_pipe_payload_q[NUM_ROUND_REGS].round_sticky_bits) |
                             round_pipe_payload_q[NUM_ROUND_REGS].of_before_round |
                             of_after_round;

  // Final results for output pipeline
  fp_t                result_d;
  fpnew_pkg::status_t status_d;

  // Select output depending on special case detection
  assign result_d = round_pipe_payload_q[NUM_ROUND_REGS].result_is_special
                    ? round_pipe_payload_q[NUM_ROUND_REGS].special_result : regular_result;
  assign status_d = round_pipe_payload_q[NUM_ROUND_REGS].result_is_special
                    ? round_pipe_payload_q[NUM_ROUND_REGS].special_status : regular_status;

  // ----------------
  // Output Pipeline
  // ----------------
  // Output pipeline signals, index i holds signal after i register stages
  fp_t                [0:NUM_OUT_REGS] out_pipe_result_q;
  fpnew_pkg::status_t [0:NUM_OUT_REGS] out_pipe_status_q;
  TagType             [0:NUM_OUT_REGS] out_pipe_tag_q;
  logic               [0:NUM_OUT_REGS] out_pipe_mask_q;
  AuxType             [0:NUM_OUT_REGS] out_pipe_aux_q;
  logic               [0:NUM_OUT_REGS] out_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_OUT_REGS] out_pipe_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign out_pipe_result_q[0] = result_d;
  assign out_pipe_status_q[0] = status_d;
  assign out_pipe_tag_q[0]    = round_pipe_payload_q[NUM_ROUND_REGS].tag;
  assign out_pipe_mask_q[0]   = round_pipe_payload_q[NUM_ROUND_REGS].mask;
  assign out_pipe_aux_q[0]    = round_pipe_payload_q[NUM_ROUND_REGS].aux;
  assign out_pipe_valid_q[0]  = round_pipe_valid_q[NUM_ROUND_REGS];
  assign round_pipe_ready[NUM_ROUND_REGS] = out_pipe_ready[0];
  // Generate the register stages
  for (genvar i = 0; i < NUM_OUT_REGS; i++) begin : gen_output_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign out_pipe_ready[i] = out_pipe_ready[i+1] | ~out_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(out_pipe_valid_q[i+1], out_pipe_valid_q[i], out_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (out_pipe_ready[i] & out_pipe_valid_q[i]) |
                     reg_ena_i[NUM_INP_REGS + NUM_DECODE_REGS + NUM_ALIGN_REGS + NUM_ADD_REGS +
                               NUM_MID_REGS + NUM_SHIFT_REGS + NUM_NORM_REGS +
                               NUM_ROUND_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(out_pipe_result_q[i+1], out_pipe_result_q[i], reg_ena, '0)
    `FFL(out_pipe_status_q[i+1], out_pipe_status_q[i], reg_ena, '0)
    `FFL(out_pipe_tag_q[i+1],    out_pipe_tag_q[i],    reg_ena, TagType'('0))
    `FFL(out_pipe_mask_q[i+1],   out_pipe_mask_q[i],   reg_ena, '0)
    `FFL(out_pipe_aux_q[i+1],    out_pipe_aux_q[i],    reg_ena, AuxType'('0))
  end
  // Output stage: Ready travels backwards from output side, driven by downstream circuitry
  assign out_pipe_ready[NUM_OUT_REGS] = out_ready_i;
  // Output stage: assign module outputs
  assign result_o        = out_pipe_result_q[NUM_OUT_REGS];
  assign status_o        = out_pipe_status_q[NUM_OUT_REGS];
  assign extension_bit_o = 1'b1; // always NaN-Box result
  assign tag_o           = out_pipe_tag_q[NUM_OUT_REGS];
  assign mask_o          = out_pipe_mask_q[NUM_OUT_REGS];
  assign aux_o           = out_pipe_aux_q[NUM_OUT_REGS];
  assign out_valid_o     = out_pipe_valid_q[NUM_OUT_REGS];
  assign busy_o          = (| {inp_pipe_valid_q, decode_pipe_valid_q, align_pipe_valid_q,
                               add_pipe_valid_q,
                               mid_pipe_valid_q, shift_pipe_valid_q, norm_pipe_valid_q,
                               round_pipe_valid_q,
                               out_pipe_valid_q});
endmodule
