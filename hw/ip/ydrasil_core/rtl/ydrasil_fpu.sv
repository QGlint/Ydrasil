module ydrasil_fpu
    import ydrasil_pkg::*;
    import ydrasil_fpu_math_pkg::*;
(
    input  wire                        clk,
    input  wire                        rst_n,
    input  ydrasil_fpu_req_pkt_t       req_i,
    output wire                        req_ready_o,
    input  wire [2:0]                  frm_i,
    input  wire                        result_ready_i,
    output wire                        busy_o,
    output wire                        result_valid_o,
    output wire [FPU_DATA_WIDTH-1:0]   result_o,
    output wire [REGS_ADDR_WIDTH-1:0]  result_addr_o,
    output wire                        result_fpr_o,
    output wire                        result_gpr_o,
    output producer_id_t               result_producer_id_o,
    output wire                        result_producer_tracked_o,
    output wire [4:0]                  result_fflags_o,
    output wire [INST_ADDR_WIDTH-1:0]  result_pc_o,
    output wire [INST_DATA_WIDTH-1:0]  result_instr_o
);
    ydrasil_fpu_req_pkt_t request_q;
    reg [2:0] round_mode_q;
    reg execute_q;
    reg div_wait_q;
    reg fma_wait_q;
    reg int_wait_q;
    reg result_valid_q;
    reg [63:0] result_data_q;
    reg [4:0] result_flags_q;
`ifdef YDRASIL_FPU_DOUBLE
    localparam integer BASIC_LATENCY = 9;
`else
    localparam integer BASIC_LATENCY = 6;
`endif
    (* retiming_backward = 1 *)
    reg [63:0] basic_data_pipe [0:BASIC_LATENCY-1];
    (* retiming_backward = 1 *)
    reg [4:0] basic_flags_pipe [0:BASIC_LATENCY-1];
    reg [BASIC_LATENCY-1:0] basic_valid_pipe;
    integer control_stage;
    integer data_stage;

    wire accepted = req_i.valid && req_ready_o;
    wire output_consumed = result_valid_q && result_ready_i;
    wire iterative_op = (request_q.op == FPU_OP_DIV) ||
        (request_q.op == FPU_OP_SQRT);
    wire arithmetic_op = (request_q.op == FPU_OP_ADD) ||
        (request_q.op == FPU_OP_SUB) ||
        (request_q.op == FPU_OP_MUL) ||
        (request_q.op == FPU_OP_FMADD) ||
        (request_q.op == FPU_OP_FMSUB) ||
        (request_q.op == FPU_OP_FNMSUB) ||
        (request_q.op == FPU_OP_FNMADD);
    wire pack_conversion_op =
        (request_q.op == FPU_OP_CVT_S_W) ||
        (request_q.op == FPU_OP_CVT_S_WU) ||
        (request_q.op == FPU_OP_CVT_D_W) ||
        (request_q.op == FPU_OP_CVT_D_WU) ||
        (request_q.op == FPU_OP_CVT_S_D) ||
        (request_q.op == FPU_OP_CVT_D_S);
    wire int_conversion_op =
        (request_q.op == FPU_OP_CVT_W_S) ||
        (request_q.op == FPU_OP_CVT_WU_S) ||
        (request_q.op == FPU_OP_CVT_W_D) ||
        (request_q.op == FPU_OP_CVT_WU_D);
    wire fma_pipeline_op = arithmetic_op || pack_conversion_op;
    wire div_start = execute_q && iterative_op;
    wire fma_start = execute_q && fma_pipeline_op;
    wire int_start = execute_q && int_conversion_op;
    wire div_done;
    wire [63:0] div_result;
    wire [4:0] div_flags;
    wire fma_done;
    wire [63:0] fma_result;
    wire [4:0] fma_flags;
    wire int_done;
    wire [63:0] int_result;
    wire [4:0] int_flags;
    wire basic_busy = |basic_valid_pipe;
    wire [63:0] operand_a64 =
        {{(64-FPU_DATA_WIDTH){1'b1}}, request_q.operand_a};
    wire [63:0] operand_b64 =
        {{(64-FPU_DATA_WIDTH){1'b1}}, request_q.operand_b};
    wire [63:0] operand_c64 =
        {{(64-FPU_DATA_WIDTH){1'b1}}, request_q.operand_c};
`ifdef YDRASIL_FPU_DOUBLE
    wire effective_fmt = request_q.fmt;
    wire effective_dst_fmt = request_q.dst_fmt;
`else
    wire effective_fmt = 1'b0;
    wire effective_dst_fmt = 1'b0;
`endif
    wire fp_result_t basic_comb = execute_basic(request_q.op, effective_fmt,
        effective_dst_fmt, round_mode_q,
        operand_a64, operand_b64, operand_c64);

    ydrasil_fpu_divsqrt u_divsqrt (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(div_start),
        .sqrt_i(request_q.op == FPU_OP_SQRT),
        .fmt_i(effective_fmt),
        .rm_i(round_mode_q),
        .operand_a_i(operand_a64),
        .operand_b_i(operand_b64),
        .busy_o(),
        .done_o(div_done),
        .result_o(div_result),
        .flags_o(div_flags)
    );

    ydrasil_fpu_fma u_fma (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(fma_start),
        .op_i(request_q.op),
        .fmt_i(effective_fmt),
        .dst_fmt_i(effective_dst_fmt),
        .rm_i(round_mode_q),
        .operand_a_i(operand_a64),
        .operand_b_i(operand_b64),
        .operand_c_i(operand_c64),
        .busy_o(),
        .done_o(fma_done),
        .result_o(fma_result),
        .flags_o(fma_flags)
    );

    ydrasil_fpu_to_int u_to_int (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(int_start),
        .op_i(request_q.op),
        .fmt_i(effective_fmt),
        .rm_i(round_mode_q),
        .operand_i(operand_a64),
        .busy_o(),
        .done_o(int_done),
        .result_o(int_result),
        .flags_o(int_flags)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_q <= '0;
            round_mode_q <= '0;
            execute_q <= 1'b0;
            div_wait_q <= 1'b0;
            fma_wait_q <= 1'b0;
            int_wait_q <= 1'b0;
            result_valid_q <= 1'b0;
            result_data_q <= '0;
            result_flags_q <= '0;
            basic_valid_pipe <= '0;
        end else begin
            basic_valid_pipe[0] <= 1'b0;
            for (control_stage = 1; control_stage < BASIC_LATENCY;
                 control_stage = control_stage + 1) begin
                basic_valid_pipe[control_stage] <=
                    basic_valid_pipe[control_stage-1];
            end
            if (output_consumed)
                result_valid_q <= 1'b0;
            if (accepted) begin
                request_q <= req_i;
                round_mode_q <= req_i.rm == 3'b111 ? frm_i : req_i.rm;
                execute_q <= 1'b1;
            end
            if (execute_q) begin
                execute_q <= 1'b0;
                if (iterative_op) begin
                    div_wait_q <= 1'b1;
                end else if (fma_pipeline_op) begin
                    fma_wait_q <= 1'b1;
                end else if (int_conversion_op) begin
                    int_wait_q <= 1'b1;
                end else begin
                    basic_valid_pipe[0] <= 1'b1;
                end
            end
            if (basic_valid_pipe[BASIC_LATENCY-1]) begin
                result_data_q <= basic_data_pipe[BASIC_LATENCY-1];
                result_flags_q <= basic_flags_pipe[BASIC_LATENCY-1];
                result_valid_q <= 1'b1;
            end
            if (div_done && div_wait_q) begin
                div_wait_q <= 1'b0;
                result_data_q <= div_result;
                result_flags_q <= div_flags;
                result_valid_q <= 1'b1;
            end
            if (fma_done && fma_wait_q) begin
                fma_wait_q <= 1'b0;
                result_data_q <= fma_result;
                result_flags_q <= fma_flags;
                result_valid_q <= 1'b1;
            end
            if (int_done && int_wait_q) begin
                int_wait_q <= 1'b0;
                result_data_q <= int_result;
                result_flags_q <= int_flags;
                result_valid_q <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        basic_data_pipe[0] <= basic_comb.data;
        basic_flags_pipe[0] <= basic_comb.flags;
        for (data_stage = 1; data_stage < BASIC_LATENCY;
             data_stage = data_stage + 1) begin
            basic_data_pipe[data_stage] <= basic_data_pipe[data_stage-1];
            basic_flags_pipe[data_stage] <= basic_flags_pipe[data_stage-1];
        end
    end

    assign req_ready_o = !execute_q && !basic_busy && !div_wait_q &&
        !fma_wait_q && !int_wait_q && !result_valid_q;
    assign busy_o = execute_q || basic_busy || div_wait_q ||
        fma_wait_q || int_wait_q || result_valid_q;
    assign result_valid_o = result_valid_q;
    assign result_o = result_data_q[FPU_DATA_WIDTH-1:0];
    assign result_addr_o = request_q.rd_addr;
    assign result_fpr_o = request_q.rd_fpr;
    assign result_gpr_o = request_q.rd_gpr;
    assign result_producer_id_o = request_q.producer_id;
    assign result_producer_tracked_o = request_q.producer_tracked;
    assign result_fflags_o = result_flags_q;
    assign result_pc_o = request_q.pc;
    assign result_instr_o = request_q.instr;
endmodule
