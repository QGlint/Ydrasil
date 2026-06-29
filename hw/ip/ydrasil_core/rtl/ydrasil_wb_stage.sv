
// 写回单元 - 仲裁 LSU、普通 EX 和流水线乘法结果的单写口写回。
module ydrasil_wb_stage
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [REGS_DATA_WIDTH-1:0]   alu_wdata_rd_i,
    input  wire                         alu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   alu_rf_waddr_rd_i,

    input  wire [REGS_DATA_WIDTH-1:0]   lsu_wb_result_i,
    input  wire                         lsu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   lsu_rf_waddr_rd_i,

    input  wire [REGS_DATA_WIDTH-1:0]   mul_wdata_rd_i,
    input  wire                         mul_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   mul_rf_waddr_rd_i,

    output wire                         wb_mul_complete_o,
    output wire [REGS_ADDR_WIDTH-1:0]   wb_mul_complete_waddr_o,
    output wire                         wb_backpressure_o,

    output wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_o,
    output wire                         rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_o
);

    localparam int MUL_FIFO_DEPTH = 16;
    localparam int MUL_FIFO_PTR_WIDTH = 4;
    localparam int MUL_FIFO_COUNT_WIDTH = 5;
    localparam int MUL_FIFO_BACKPRESSURE_LEVEL = 10;

    reg [REGS_DATA_WIDTH-1:0] mul_fifo_data_q [0:MUL_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] mul_fifo_addr_q [0:MUL_FIFO_DEPTH-1];
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_rptr_q;
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_wptr_q;
    reg [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_q;

    reg [REGS_DATA_WIDTH-1:0] alu_pending_data_q;
    reg [REGS_ADDR_WIDTH-1:0] alu_pending_addr_q;
    reg                       alu_pending_valid_q;

    wire mul_fifo_empty = (mul_fifo_count_q == '0);
    wire mul_fifo_full = (mul_fifo_count_q == MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] mul_fifo_head_data = mul_fifo_data_q[mul_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] mul_fifo_head_addr = mul_fifo_addr_q[mul_fifo_rptr_q];

    wire sel_lsu = lsu_rf_wen_rd_i;
    wire sel_alu_pending = !sel_lsu & alu_pending_valid_q;
    wire sel_alu_current = !sel_lsu & !alu_pending_valid_q & alu_rf_wen_rd_i;
    wire sel_mul_fifo = !sel_lsu & !alu_pending_valid_q & !alu_rf_wen_rd_i & !mul_fifo_empty;
    wire sel_mul_current =
        !sel_lsu & !alu_pending_valid_q & !alu_rf_wen_rd_i & mul_fifo_empty & mul_rf_wen_rd_i;

    wire mul_dequeue = sel_mul_fifo;
    wire mul_direct_write = sel_mul_current;
    wire mul_enqueue = mul_rf_wen_rd_i & !mul_direct_write;
    wire mul_enqueue_accept = mul_enqueue & !mul_fifo_full;

    wire alu_pending_next_valid =
        sel_alu_pending ? alu_rf_wen_rd_i :
        (!sel_alu_current & alu_rf_wen_rd_i);
    wire [REGS_DATA_WIDTH-1:0] alu_pending_next_data = alu_wdata_rd_i;
    wire [REGS_ADDR_WIDTH-1:0] alu_pending_next_addr = alu_rf_waddr_rd_i;

    wire [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_next =
        mul_fifo_count_q +
        (mul_enqueue_accept ? MUL_FIFO_COUNT_WIDTH'(1) : '0) -
        (mul_dequeue ? MUL_FIFO_COUNT_WIDTH'(1) : '0);

    assign wb_mul_complete_o = (sel_mul_fifo | sel_mul_current);
    assign wb_mul_complete_waddr_o = sel_mul_current ? mul_rf_waddr_rd_i : mul_fifo_head_addr;
    assign wb_backpressure_o =
        (mul_fifo_count_q >= MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_BACKPRESSURE_LEVEL));

    assign rf_wen_rd_o =
        sel_lsu | sel_alu_pending | sel_alu_current | sel_mul_fifo | sel_mul_current;
    assign rf_waddr_rd_o =
        ({REGS_ADDR_WIDTH{sel_lsu}}         & lsu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{sel_alu_pending}} & alu_pending_addr_q) |
        ({REGS_ADDR_WIDTH{sel_alu_current}} & alu_rf_waddr_rd_i) |
        ({REGS_ADDR_WIDTH{sel_mul_fifo}}    & mul_fifo_head_addr) |
        ({REGS_ADDR_WIDTH{sel_mul_current}} & mul_rf_waddr_rd_i);
    assign rf_wdata_rd_o =
        ({REGS_DATA_WIDTH{sel_lsu}}         & lsu_wb_result_i) |
        ({REGS_DATA_WIDTH{sel_alu_pending}} & alu_pending_data_q) |
        ({REGS_DATA_WIDTH{sel_alu_current}} & alu_wdata_rd_i) |
        ({REGS_DATA_WIDTH{sel_mul_fifo}}    & mul_fifo_head_data) |
        ({REGS_DATA_WIDTH{sel_mul_current}} & mul_wdata_rd_i);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_pending_data_q  <= '0;
            alu_pending_addr_q  <= '0;
            alu_pending_valid_q <= 1'b0;
            mul_fifo_rptr_q     <= '0;
            mul_fifo_wptr_q     <= '0;
            mul_fifo_count_q    <= '0;
        end else begin
            alu_pending_valid_q <= alu_pending_next_valid;
            if (alu_pending_next_valid) begin
                alu_pending_data_q <= alu_pending_next_data;
                alu_pending_addr_q <= alu_pending_next_addr;
            end

            if (mul_enqueue_accept) begin
                mul_fifo_data_q[mul_fifo_wptr_q] <= mul_wdata_rd_i;
                mul_fifo_addr_q[mul_fifo_wptr_q] <= mul_rf_waddr_rd_i;
                mul_fifo_wptr_q <= mul_fifo_wptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            if (mul_dequeue) begin
                mul_fifo_rptr_q <= mul_fifo_rptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            mul_fifo_count_q <= mul_fifo_count_next;
        end
    end

endmodule
