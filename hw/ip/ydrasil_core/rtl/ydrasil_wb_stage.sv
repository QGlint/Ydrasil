
// 写回单元 - 仲裁 LSU、普通 EX 和流水线乘法结果的单写口写回。
module ydrasil_wb_stage
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [REGS_DATA_WIDTH-1:0]   alu_wdata_rd_i,
    input  wire                         alu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   alu_rf_waddr_rd_i,
    input  producer_id_t                alu_producer_id_i,

    input  wire [REGS_DATA_WIDTH-1:0]   lsu_wb_result_i,
    input  wire                         lsu_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   lsu_rf_waddr_rd_i,
    input  producer_id_t                lsu_producer_id_i,
    input  wire                         lsu_producer_tracked_i,

    input  wire [REGS_DATA_WIDTH-1:0]   mul_wdata_rd_i,
    input  wire                         mul_rf_wen_rd_i,
    input  wire [REGS_ADDR_WIDTH-1:0]   mul_rf_waddr_rd_i,
    input  producer_id_t                mul_producer_id_i,

    output wire                         wb_mul_complete_o,
    output wire [REGS_ADDR_WIDTH-1:0]   wb_mul_complete_waddr_o,
    output wire                         wb_backpressure_o,

    output wire [REGS_DATA_WIDTH-1:0]   rf_wdata_rd_o,
    output wire                         rf_wen_rd_o,
    output wire [REGS_ADDR_WIDTH-1:0]   rf_waddr_rd_o
    ,output producer_id_t               rf_producer_id_o
    ,output wire                        rf_producer_tracked_o
);

    localparam int MUL_FIFO_DEPTH = 4;
    localparam int MUL_FIFO_PTR_WIDTH = 2;
    localparam int MUL_FIFO_COUNT_WIDTH = 3;
    localparam int MUL_FIFO_BACKPRESSURE_LEVEL = 2;
    localparam int ALU_FIFO_DEPTH = 4;
    localparam int ALU_FIFO_PTR_WIDTH = 2;
    localparam int ALU_FIFO_COUNT_WIDTH = 3;
    localparam int ALU_FIFO_BACKPRESSURE_LEVEL = 2;

    reg [REGS_DATA_WIDTH-1:0] mul_fifo_data_q [0:MUL_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] mul_fifo_addr_q [0:MUL_FIFO_DEPTH-1];
    producer_id_t mul_fifo_producer_id_q [0:MUL_FIFO_DEPTH-1];
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_rptr_q;
    reg [MUL_FIFO_PTR_WIDTH-1:0] mul_fifo_wptr_q;
    reg [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_q;

    reg [REGS_DATA_WIDTH-1:0] alu_fifo_data_q [0:ALU_FIFO_DEPTH-1];
    reg [REGS_ADDR_WIDTH-1:0] alu_fifo_addr_q [0:ALU_FIFO_DEPTH-1];
    producer_id_t alu_fifo_producer_id_q [0:ALU_FIFO_DEPTH-1];
    reg [ALU_FIFO_PTR_WIDTH-1:0] alu_fifo_rptr_q;
    reg [ALU_FIFO_PTR_WIDTH-1:0] alu_fifo_wptr_q;
    reg [ALU_FIFO_COUNT_WIDTH-1:0] alu_fifo_count_q;

    wire mul_fifo_empty = (mul_fifo_count_q == '0);
    wire mul_fifo_full = (mul_fifo_count_q == MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] mul_fifo_head_data = mul_fifo_data_q[mul_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] mul_fifo_head_addr = mul_fifo_addr_q[mul_fifo_rptr_q];
    producer_id_t mul_fifo_head_producer_id;
    assign mul_fifo_head_producer_id = mul_fifo_producer_id_q[mul_fifo_rptr_q];
    wire alu_fifo_empty = (alu_fifo_count_q == '0);
    wire alu_fifo_full = (alu_fifo_count_q == ALU_FIFO_COUNT_WIDTH'(ALU_FIFO_DEPTH));
    wire [REGS_DATA_WIDTH-1:0] alu_fifo_head_data = alu_fifo_data_q[alu_fifo_rptr_q];
    wire [REGS_ADDR_WIDTH-1:0] alu_fifo_head_addr = alu_fifo_addr_q[alu_fifo_rptr_q];
    producer_id_t alu_fifo_head_producer_id;
    assign alu_fifo_head_producer_id = alu_fifo_producer_id_q[alu_fifo_rptr_q];

    wire sel_lsu = lsu_rf_wen_rd_i;
    wire sel_alu_fifo = !sel_lsu & !alu_fifo_empty;
    wire sel_alu_current = !sel_lsu & alu_fifo_empty & alu_rf_wen_rd_i;
    wire sel_mul_fifo = !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i & !mul_fifo_empty;
    wire sel_mul_current =
        !sel_lsu & alu_fifo_empty & !alu_rf_wen_rd_i & mul_fifo_empty & mul_rf_wen_rd_i;

    wire alu_dequeue = sel_alu_fifo;
    wire alu_direct_write = sel_alu_current;
    wire alu_enqueue = alu_rf_wen_rd_i & !alu_direct_write;
    wire alu_enqueue_accept = alu_enqueue & (!alu_fifo_full | alu_dequeue);
    wire mul_dequeue = sel_mul_fifo;
    wire mul_direct_write = sel_mul_current;
    wire mul_enqueue = mul_rf_wen_rd_i & !mul_direct_write;
    wire mul_enqueue_accept = mul_enqueue & !mul_fifo_full;

    wire [ALU_FIFO_COUNT_WIDTH-1:0] alu_fifo_count_next =
        alu_fifo_count_q +
        (alu_enqueue_accept ? ALU_FIFO_COUNT_WIDTH'(1) : '0) -
        (alu_dequeue ? ALU_FIFO_COUNT_WIDTH'(1) : '0);
    wire [MUL_FIFO_COUNT_WIDTH-1:0] mul_fifo_count_next =
        mul_fifo_count_q +
        (mul_enqueue_accept ? MUL_FIFO_COUNT_WIDTH'(1) : '0) -
        (mul_dequeue ? MUL_FIFO_COUNT_WIDTH'(1) : '0);

    assign wb_mul_complete_o = (sel_mul_fifo | sel_mul_current);
    assign wb_mul_complete_waddr_o = sel_mul_current ? mul_rf_waddr_rd_i : mul_fifo_head_addr;
    assign wb_backpressure_o =
        (alu_fifo_count_q >= ALU_FIFO_COUNT_WIDTH'(ALU_FIFO_BACKPRESSURE_LEVEL)) |
        (mul_fifo_count_q >= MUL_FIFO_COUNT_WIDTH'(MUL_FIFO_BACKPRESSURE_LEVEL));

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
    assign rf_producer_id_o = sel_lsu ? lsu_producer_id_i :
        sel_alu_fifo ? alu_fifo_head_producer_id :
        sel_alu_current ? alu_producer_id_i :
        sel_mul_fifo ? mul_fifo_head_producer_id : mul_producer_id_i;
    assign rf_producer_tracked_o = sel_lsu ? lsu_producer_tracked_i :
                                           (rf_wen_rd_o && (rf_waddr_rd_o != '0));

    // FIFO payload is deliberately not asynchronously reset: valid/count and
    // pointers define ownership, while a synchronous reset keeps the inferred
    // small RAMs free of reset pins and permits LUTRAM packing.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            alu_fifo_rptr_q     <= '0;
            alu_fifo_wptr_q     <= '0;
            alu_fifo_count_q    <= '0;
            mul_fifo_rptr_q     <= '0;
            mul_fifo_wptr_q     <= '0;
            mul_fifo_count_q    <= '0;
        end else begin
            if (alu_enqueue_accept) begin
                alu_fifo_data_q[alu_fifo_wptr_q] <= alu_wdata_rd_i;
                alu_fifo_addr_q[alu_fifo_wptr_q] <= alu_rf_waddr_rd_i;
                alu_fifo_producer_id_q[alu_fifo_wptr_q] <= alu_producer_id_i;
                alu_fifo_wptr_q <= alu_fifo_wptr_q + ALU_FIFO_PTR_WIDTH'(1);
            end

            if (alu_dequeue) begin
                alu_fifo_rptr_q <= alu_fifo_rptr_q + ALU_FIFO_PTR_WIDTH'(1);
            end

            alu_fifo_count_q <= alu_fifo_count_next;

            if (mul_enqueue_accept) begin
                mul_fifo_data_q[mul_fifo_wptr_q] <= mul_wdata_rd_i;
                mul_fifo_addr_q[mul_fifo_wptr_q] <= mul_rf_waddr_rd_i;
                mul_fifo_producer_id_q[mul_fifo_wptr_q] <= mul_producer_id_i;
                mul_fifo_wptr_q <= mul_fifo_wptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            if (mul_dequeue) begin
                mul_fifo_rptr_q <= mul_fifo_rptr_q + MUL_FIFO_PTR_WIDTH'(1);
            end

            mul_fifo_count_q <= mul_fifo_count_next;
        end
    end

endmodule
