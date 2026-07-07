
// 写回单元 - 仲裁 LSU、普通 EX 和流水线乘法结果的单写口写回。
module ydrasil_wb_stage
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         flush_i,

    input  wire [REGS_DATA_WIDTH-1:0]   alu_wdata_rd_i,
    input  wire                         alu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   alu_rf_waddr_rd_i,

    input  wire [REGS_DATA_WIDTH-1:0]   pipe1_alu_wdata_rd_i,
    input  wire                         pipe1_alu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   pipe1_alu_rf_waddr_rd_i,
    input  wire [5:0]                   pipe1_alu_rn_pdst_i,

    input  wire [REGS_DATA_WIDTH-1:0]   lsu_wb_result_i,
    input  wire                         lsu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   lsu_rf_waddr_rd_i,

    input  wire [REGS_DATA_WIDTH-1:0]   mul_wdata_rd_i,
    input  wire                         mul_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   mul_rf_waddr_rd_i,
    input  wire [5:0]                   mul_rn_pdst_i,

    output wire                         wb_mul_complete_o,
    output wire [REGS_ADDR_WIDTH-1:0]   wb_mul_complete_waddr_o,
    output wire [5:0]                   wb_mul_complete_pdst_o,
    output wire                         wb_backpressure_o,
    output wire                         pipe1_resbuf_full_o,
    output wire                         pipe1_wb_dequeue_o,
    output wire                         pipe1_wb_enqueue_o,
    output wire                         pipe1_wb_pdst_valid_o,
    output wire [5:0]                   pipe1_wb_pdst_o,
    output wire [REGS_DATA_WIDTH-1:0]   pipe1_wb_data_o,
    output wire                         pipe1_fwd_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]   pipe1_fwd_addr_o,
    output wire [5:0]                   pipe1_fwd_pdst_o,
    output wire [REGS_DATA_WIDTH-1:0]   pipe1_fwd_data_o,
    output wire                         wb_buf_fwd_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0]   wb_buf_fwd_addr_o,
    output wire [REGS_DATA_WIDTH-1:0]   wb_buf_fwd_data_o,

    output wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_o,
    output wire                         rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_o
);

    localparam int MUL_FIFO_DEPTH = 16;
    localparam int MUL_FIFO_PTR_WIDTH = 4;
    localparam int MUL_FIFO_COUNT_WIDTH = 5;
    localparam int MUL_FIFO_BACKPRESSURE_LEVEL = 10;
    localparam int ALU_FIFO_DEPTH = 16;
    localparam int ALU_FIFO_PTR_WIDTH = 4;
    localparam int ALU_FIFO_COUNT_WIDTH = 5;
    localparam int ALU_FIFO_BACKPRESSURE_LEVEL = 10;
    localparam int P1_FIFO_DEPTH = 8;
    localparam int P1_FIFO_PTR_WIDTH = 3;
    localparam int P1_FIFO_COUNT_WIDTH = 4;
    localparam int P1_FIFO_BACKPRESSURE_LEVEL = 6;

    reg [REGS_DATA_WIDTH-1:0] mul_fifo_data_q [0:MUL_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] mul_fifo_addr_q [0:MUL_FIFO_DEPTH-1];
    reg [5:0] mul_fifo_pdst_q [0:MUL_FIFO_DEPTH-1];
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_rptr_q;
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_wptr_q;
    reg [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_q;

    reg [REGS_DATA_WIDTH-1:0] alu_fifo_data_q [0:ALU_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] alu_fifo_addr_q [0:ALU_FIFO_DEPTH-1];
    reg [ALU_FIFO_PTR_WIDTH-1:0] alu_fifo_rptr_q;
    reg [ALU_FIFO_PTR_WIDTH-1:0] alu_fifo_wptr_q;
    reg [ALU_FIFO_COUNT_WIDTH-1:0] alu_fifo_count_q;
    reg [31:0] perf_p1_wb_enqueue;
    reg [31:0] perf_p1_wb_dequeue;
    reg [31:0] perf_p1_wb_direct;
    reg [31:0] perf_p1_wb_wait_cycles;
    reg [31:0] perf_p1_wb_max_occ;
    reg [31:0] perf_p1_wb_order_fix;
`ifndef SYNTHESIS
    reg wb_buf_fwd_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] wb_buf_fwd_addr_q;
    reg [REGS_DATA_WIDTH-1:0] wb_buf_fwd_data_q;
`endif
    reg [REGS_DATA_WIDTH-1:0] p1_fifo_data_q [0:P1_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] p1_fifo_addr_q [0:P1_FIFO_DEPTH-1];
    reg [5:0] p1_fifo_pdst_q [0:P1_FIFO_DEPTH-1];
    reg p1_fifo_ready_q [0:P1_FIFO_DEPTH-1];
    reg [P1_FIFO_PTR_WIDTH-1:0] p1_fifo_rptr_q;
    reg [P1_FIFO_PTR_WIDTH-1:0] p1_fifo_wptr_q;
    reg [P1_FIFO_COUNT_WIDTH-1:0] p1_fifo_count_q;

    wire mul_fifo_empty = (mul_fifo_count_q == '0);
    wire mul_fifo_full = (mul_fifo_count_q == MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] mul_fifo_head_data = mul_fifo_data_q[mul_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] mul_fifo_head_addr = mul_fifo_addr_q[mul_fifo_rptr_q];
    wire [5:0] mul_fifo_head_pdst = mul_fifo_pdst_q[mul_fifo_rptr_q];
    wire alu_fifo_empty = (alu_fifo_count_q == '0);
    wire alu_fifo_full = (alu_fifo_count_q == ALU_FIFO_COUNT_WIDTH'(ALU_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] alu_fifo_head_data = alu_fifo_data_q[alu_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] alu_fifo_head_addr = alu_fifo_addr_q[alu_fifo_rptr_q];
    wire p1_fifo_empty = (p1_fifo_count_q == '0);
    wire p1_fifo_full = (p1_fifo_count_q == P1_FIFO_COUNT_WIDTH'(P1_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] p1_fifo_head_data = p1_fifo_data_q[p1_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] p1_fifo_head_addr = p1_fifo_addr_q[p1_fifo_rptr_q];
    wire [5:0] p1_fifo_head_pdst = p1_fifo_pdst_q[p1_fifo_rptr_q];
    wire p1_fifo_head_ready = p1_fifo_ready_q[p1_fifo_rptr_q];

    wire sel_lsu = lsu_rf_wen_rd_i;
    wire sel_alu_fifo = !sel_lsu & !alu_fifo_empty;
    wire sel_alu_current = !sel_lsu & alu_fifo_empty & alu_rf_wen_rd_i;
    wire pipe1_alu_rf_wen_eff = pipe1_alu_rf_wen_rd_i;
    wire sel_p1_fifo = !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i & !p1_fifo_empty;
    wire sel_p1_current =
        !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i & p1_fifo_empty & pipe1_alu_rf_wen_eff;
    wire p1_write_clear = p1_fifo_empty & !pipe1_alu_rf_wen_eff;
    wire sel_mul_fifo =
        !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i &
        p1_write_clear & !mul_fifo_empty;
    wire sel_mul_current =
        !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i &
        p1_write_clear & mul_fifo_empty & mul_rf_wen_rd_i;

    wire alu_dequeue = sel_alu_fifo;
    wire alu_direct_write = sel_alu_current;
    wire alu_enqueue = alu_rf_wen_rd_i & !alu_direct_write;
    wire alu_enqueue_accept = alu_enqueue & (!alu_fifo_full | alu_dequeue);
    wire p1_dequeue = sel_p1_fifo;
    wire p1_direct_write = sel_p1_current;
    wire p1_enqueue = pipe1_alu_rf_wen_eff & !p1_direct_write;
    wire p1_enqueue_accept = p1_enqueue & (!p1_fifo_full | p1_dequeue);
    wire p1_fifo_ready_event = p1_dequeue & !p1_fifo_head_ready;
    wire p1_current_ready_event =
        pipe1_alu_rf_wen_eff & !p1_fifo_ready_event &
        !(alu_rf_wen_rd_i & lsu_rf_wen_rd_i);
    wire mul_dequeue = sel_mul_fifo;
    wire mul_direct_write = sel_mul_current;
    wire mul_enqueue = mul_rf_wen_rd_i & !mul_direct_write;
    wire mul_enqueue_accept = mul_enqueue & !mul_fifo_full;
`ifndef SYNTHESIS
    wire wb_buf_capture_alu = alu_enqueue_accept & (alu_rf_waddr_rd_i != '0);
    wire wb_buf_capture_p1 = !wb_buf_capture_alu & p1_enqueue_accept & (pipe1_alu_rf_waddr_rd_i != '0);
    wire wb_buf_capture_mul =
        !wb_buf_capture_p1 & !wb_buf_capture_alu & mul_enqueue_accept & (mul_rf_waddr_rd_i != '0);
    wire wb_buf_capture_valid = wb_buf_capture_p1 | wb_buf_capture_alu | wb_buf_capture_mul;
    wire [REGS_ADDR_WIDTH-1:0] wb_buf_capture_addr =
        ({REGS_ADDR_WIDTH{wb_buf_capture_p1}} & pipe1_alu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{wb_buf_capture_alu}} & alu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{wb_buf_capture_mul}} & mul_rf_waddr_rd_i);
    wire [REGS_DATA_WIDTH-1:0] wb_buf_capture_data =
        ({REGS_DATA_WIDTH{wb_buf_capture_p1}} & pipe1_alu_wdata_rd_i) |
        ({REGS_DATA_WIDTH{wb_buf_capture_alu}} & alu_wdata_rd_i) |
        ({REGS_DATA_WIDTH{wb_buf_capture_mul}} & mul_wdata_rd_i);
    wire wb_buf_entry_writes =
        rf_wen_rd_o && wb_buf_fwd_valid_q && (rf_waddr_rd_o == wb_buf_fwd_addr_q);
`endif

    wire [ALU_FIFO_COUNT_WIDTH-1:0] alu_fifo_count_next =
        alu_fifo_count_q +
        (alu_enqueue_accept ? ALU_FIFO_COUNT_WIDTH'(1) : '0) -
        (alu_dequeue ? ALU_FIFO_COUNT_WIDTH'(1) : '0);
    wire [P1_FIFO_COUNT_WIDTH-1:0] p1_fifo_count_next =
        p1_fifo_count_q +
        (p1_enqueue_accept ? P1_FIFO_COUNT_WIDTH'(1) : '0) -
        (p1_dequeue ? P1_FIFO_COUNT_WIDTH'(1) : '0);
    wire [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_next =
        mul_fifo_count_q +
        (mul_enqueue_accept ? MUL_FIFO_COUNT_WIDTH'(1) : '0) -
        (mul_dequeue ? MUL_FIFO_COUNT_WIDTH'(1) : '0);

    wire p1_wb_backpressure =
        p1_fifo_count_q >= P1_FIFO_COUNT_WIDTH'(P1_FIFO_BACKPRESSURE_LEVEL);

    assign wb_mul_complete_o = (sel_mul_fifo | sel_mul_current);
    assign wb_mul_complete_waddr_o = sel_mul_current ? mul_rf_waddr_rd_i : mul_fifo_head_addr;
    assign wb_mul_complete_pdst_o = sel_mul_current ? mul_rn_pdst_i : mul_fifo_head_pdst;
    assign wb_backpressure_o =
        (alu_fifo_count_q >= ALU_FIFO_COUNT_WIDTH'(ALU_FIFO_BACKPRESSURE_LEVEL)) |
        p1_wb_backpressure |
        (mul_fifo_count_q >= MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_BACKPRESSURE_LEVEL));
    assign pipe1_resbuf_full_o = p1_fifo_full;
    assign pipe1_wb_dequeue_o = sel_p1_fifo | sel_p1_current;
    assign pipe1_wb_enqueue_o = p1_enqueue_accept | p1_direct_write;
    assign pipe1_wb_pdst_valid_o = p1_fifo_ready_event | p1_current_ready_event;
    assign pipe1_wb_pdst_o = p1_fifo_ready_event ? p1_fifo_head_pdst : pipe1_alu_rn_pdst_i;
    assign pipe1_wb_data_o = p1_fifo_ready_event ? p1_fifo_head_data : pipe1_alu_wdata_rd_i;
    assign pipe1_fwd_valid_o = !p1_fifo_empty;
    assign pipe1_fwd_addr_o = p1_fifo_head_addr;
    assign pipe1_fwd_pdst_o = p1_fifo_head_pdst;
    assign pipe1_fwd_data_o = p1_fifo_head_data;
`ifndef SYNTHESIS
    assign wb_buf_fwd_valid_o = wb_buf_fwd_valid_q;
    assign wb_buf_fwd_addr_o = wb_buf_fwd_addr_q;
    assign wb_buf_fwd_data_o = wb_buf_fwd_data_q;
`else
    assign wb_buf_fwd_valid_o = 1'b0;
    assign wb_buf_fwd_addr_o = '0;
    assign wb_buf_fwd_data_o = '0;
`endif

    assign rf_wen_rd_o =
        sel_lsu | sel_alu_fifo | sel_alu_current | sel_mul_fifo | sel_mul_current;
    assign rf_waddr_rd_o =
        ({REGS_ADDR_WIDTH{sel_lsu}}         & lsu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{sel_alu_fifo}}    & alu_fifo_head_addr) |
        ({REGS_ADDR_WIDTH{sel_alu_current}} & alu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{sel_mul_fifo}}    & mul_fifo_head_addr) |
        ({REGS_ADDR_WIDTH{sel_mul_current}} & mul_rf_waddr_rd_i);
    assign rf_wdata_rd_o =
        ({REGS_DATA_WIDTH{sel_lsu}}         & lsu_wb_result_i) |
        ({REGS_DATA_WIDTH{sel_alu_fifo}}    & alu_fifo_head_data) |
        ({REGS_DATA_WIDTH{sel_alu_current}} & alu_wdata_rd_i) |
        ({REGS_DATA_WIDTH{sel_mul_fifo}}    & mul_fifo_head_data) |
        ({REGS_DATA_WIDTH{sel_mul_current}} & mul_wdata_rd_i);

    always_ff @(posedge clk or negedge rst_n) begin
        integer p1_i;
        if (!rst_n) begin
            alu_fifo_rptr_q     <= '0;
            alu_fifo_wptr_q     <= '0;
            alu_fifo_count_q    <= '0;
            p1_fifo_rptr_q      <= '0;
            p1_fifo_wptr_q      <= '0;
            p1_fifo_count_q     <= '0;
            for (p1_i = 0; p1_i < P1_FIFO_DEPTH; p1_i = p1_i + 1) begin
                p1_fifo_ready_q[p1_i] <= 1'b0;
            end
            perf_p1_wb_enqueue  <= '0;
            perf_p1_wb_dequeue  <= '0;
            perf_p1_wb_direct   <= '0;
            perf_p1_wb_wait_cycles <= '0;
            perf_p1_wb_max_occ  <= '0;
            perf_p1_wb_order_fix <= '0;
`ifndef SYNTHESIS
            wb_buf_fwd_valid_q <= 1'b0;
            wb_buf_fwd_addr_q <= '0;
            wb_buf_fwd_data_q <= '0;
`endif
            mul_fifo_rptr_q     <= '0;
            mul_fifo_wptr_q     <= '0;
            mul_fifo_count_q    <= '0;
        end else begin
`ifndef SYNTHESIS
            if (flush_i) begin
                wb_buf_fwd_valid_q <= 1'b0;
            end
            if (wb_buf_entry_writes) begin
                wb_buf_fwd_valid_q <= 1'b0;
            end
            if (wb_buf_capture_valid && (!wb_buf_fwd_valid_q || wb_buf_entry_writes)) begin
                wb_buf_fwd_valid_q <= 1'b1;
                wb_buf_fwd_addr_q <= wb_buf_capture_addr;
                wb_buf_fwd_data_q <= wb_buf_capture_data;
            end

`endif
            if (alu_enqueue_accept) begin
                alu_fifo_data_q[alu_fifo_wptr_q] <= alu_wdata_rd_i;
                alu_fifo_addr_q[alu_fifo_wptr_q] <= alu_rf_waddr_rd_i;
                alu_fifo_wptr_q <= alu_fifo_wptr_q + ALU_FIFO_PTR_WIDTH'(1);
            end

            if (alu_dequeue) begin
                alu_fifo_rptr_q <= alu_fifo_rptr_q + ALU_FIFO_PTR_WIDTH'(1);
            end

            alu_fifo_count_q <= alu_fifo_count_next;

            if (p1_enqueue_accept) begin
                p1_fifo_data_q[p1_fifo_wptr_q] <= pipe1_alu_wdata_rd_i;
                p1_fifo_addr_q[p1_fifo_wptr_q] <= pipe1_alu_rf_waddr_rd_i;
                p1_fifo_pdst_q[p1_fifo_wptr_q] <= pipe1_alu_rn_pdst_i;
                p1_fifo_ready_q[p1_fifo_wptr_q] <= p1_current_ready_event;
                p1_fifo_wptr_q <= p1_fifo_wptr_q + P1_FIFO_PTR_WIDTH'(1);
            end

            if (p1_dequeue) begin
                if (!p1_enqueue_accept || (p1_fifo_wptr_q != p1_fifo_rptr_q)) begin
                    p1_fifo_ready_q[p1_fifo_rptr_q] <= 1'b0;
                end
                p1_fifo_rptr_q <= p1_fifo_rptr_q + P1_FIFO_PTR_WIDTH'(1);
            end

            p1_fifo_count_q <= p1_fifo_count_next;
            perf_p1_wb_enqueue <= perf_p1_wb_enqueue +
                (pipe1_alu_rf_wen_rd_i ? 32'd1 : 32'd0);
            perf_p1_wb_dequeue <= perf_p1_wb_dequeue +
                ((sel_p1_fifo | sel_p1_current) ? 32'd1 : 32'd0);
            perf_p1_wb_direct <= perf_p1_wb_direct +
                (sel_p1_current ? 32'd1 : 32'd0);
            perf_p1_wb_wait_cycles <= perf_p1_wb_wait_cycles +
                (!p1_fifo_empty ? 32'd1 : 32'd0);
            if ({28'b0, p1_fifo_count_q} > perf_p1_wb_max_occ) begin
                perf_p1_wb_max_occ <= {28'b0, p1_fifo_count_q};
            end
            perf_p1_wb_order_fix <= perf_p1_wb_order_fix +
                ((pipe1_alu_rf_wen_rd_i && (sel_lsu | sel_alu_fifo | sel_alu_current)) ? 32'd1 : 32'd0);

            if (mul_enqueue_accept) begin
                mul_fifo_data_q[mul_fifo_wptr_q] <= mul_wdata_rd_i;
                mul_fifo_addr_q[mul_fifo_wptr_q] <= mul_rf_waddr_rd_i;
                mul_fifo_pdst_q[mul_fifo_wptr_q] <= mul_rn_pdst_i;
                mul_fifo_wptr_q <= mul_fifo_wptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            if (mul_dequeue) begin
                mul_fifo_rptr_q <= mul_fifo_rptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            mul_fifo_count_q <= mul_fifo_count_next;
        end
    end

endmodule
