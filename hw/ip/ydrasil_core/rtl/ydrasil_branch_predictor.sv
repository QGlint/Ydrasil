module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES  = 0,
    parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
    parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES,
    parameter int RAS_ENTRIES = 8,
    parameter bit USE_GSHARE  = 1'b1
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,
    output wire [1:0]                      predict_counter_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_bht_index_o,

    // RAS training inputs
    input  wire                            ras_push_valid_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ras_push_addr_i,
    // RAS prediction outputs (combinational read, no BRAM dep)
    output wire                            ras_pop_valid_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ras_target_o,

    input  wire                            train_valid_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_pc_i,
    input  wire                            train_taken_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_target_i,
    input  wire [1:0]                      train_counter_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_bht_index_i,

    input  wire                            invalidate_i
);

    localparam int BTB_INDEX_WIDTH = (BTB_ENTRIES > 1) ? $clog2(BTB_ENTRIES) : 1;
    localparam int BHT_INDEX_WIDTH = (BHT_ENTRIES > 1) ? $clog2(BHT_ENTRIES) : 1;
    localparam int GHR_WIDTH = (BHT_INDEX_WIDTH > 5) ? 5 : BHT_INDEX_WIDTH;
    localparam int BTB_TAG_WIDTH = ydrasil_pkg::INST_ADDR_WIDTH - BTB_INDEX_WIDTH - 2;
    localparam int BTB_DATA_WIDTH = BTB_TAG_WIDTH + ydrasil_pkg::INST_ADDR_WIDTH;
    localparam int BP_EPOCH_WIDTH = 2;
    localparam int RAS_ADDR_WIDTH = (RAS_ENTRIES > 1) ? $clog2(RAS_ENTRIES) : 1;

    logic btb_valid_q [0:BTB_ENTRIES-1];
    logic bht_valid_q [0:BHT_ENTRIES-1];
    logic [BTB_DATA_WIDTH-1:0] btb_mem [0:BTB_ENTRIES-1];
    logic [1:0] bht_mem [0:BHT_ENTRIES-1];
    logic [BP_EPOCH_WIDTH-1:0] bp_epoch_q;
    logic [GHR_WIDTH-1:0] ghr_q;
    logic [BP_EPOCH_WIDTH-1:0] btb_epoch_q [0:BTB_ENTRIES-1];
    logic [BP_EPOCH_WIDTH-1:0] bht_epoch_q [0:BHT_ENTRIES-1];

    // RAS stack
    logic [ydrasil_pkg::INST_ADDR_WIDTH-1:0] ras_stack_q [0:RAS_ENTRIES-1];
    logic [RAS_ADDR_WIDTH-1:0] ras_ptr_q;

    wire [BTB_INDEX_WIDTH-1:0] predict_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index;
    wire [BHT_INDEX_WIDTH-1:0] predict_pc_bht_index;
    wire [BTB_TAG_WIDTH-1:0]   predict_btb_tag;
    wire [BTB_INDEX_WIDTH-1:0] train_btb_index;
    wire [BHT_INDEX_WIDTH-1:0] train_bht_index;
    wire [BHT_INDEX_WIDTH-1:0] ghr_index_mask;
    wire [BTB_TAG_WIDTH-1:0]   train_btb_tag;

    logic [BTB_TAG_WIDTH-1:0]   predict_btb_tag_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index_q;
    logic                       predict_btb_valid_q;
    logic                       predict_bht_valid_q;

    wire [BTB_TAG_WIDTH-1:0] btb_rtag;
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] btb_rtarget;
    wire [1:0] bht_rdata;
    wire [1:0] bht_wdata;
    wire [1:0] bht_counter;
    wire       train_fire;
    wire       btb_hit;
    wire       predict_btb_entry_valid;
    wire       predict_bht_entry_valid;

    assign predict_btb_index = predict_pc_i[BTB_INDEX_WIDTH+1:2];
    assign predict_pc_bht_index = predict_pc_i[BHT_INDEX_WIDTH+1:2];
    assign ghr_index_mask = USE_GSHARE ? {{(BHT_INDEX_WIDTH-GHR_WIDTH){1'b0}}, ghr_q} : '0;
    assign predict_bht_index = predict_pc_bht_index ^ ghr_index_mask;
    assign predict_btb_tag   = predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign train_btb_index   = train_pc_i[BTB_INDEX_WIDTH+1:2];
    assign train_bht_index   = train_bht_index_i[BHT_INDEX_WIDTH-1:0];
    assign train_btb_tag     = train_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign predict_bht_index_o = {{(ydrasil_pkg::INST_ADDR_WIDTH-BHT_INDEX_WIDTH){1'b0}}, predict_bht_index_q};

    assign bht_wdata = train_taken_i ?
        ((train_counter_i == 2'b11) ? train_counter_i : (train_counter_i + 2'b01)) :
        ((train_counter_i == 2'b00) ? train_counter_i : (train_counter_i - 2'b01));
    assign {btb_rtag, btb_rtarget} = btb_mem[predict_btb_index];
    assign bht_rdata = bht_mem[predict_bht_index];
    assign train_fire = train_valid_i && !invalidate_i;
    assign predict_btb_entry_valid =
        btb_valid_q[predict_btb_index] &&
        (btb_epoch_q[predict_btb_index] == bp_epoch_q);
    assign predict_bht_entry_valid =
        bht_valid_q[predict_bht_index] &&
        (bht_epoch_q[predict_bht_index] == bp_epoch_q);

    // RAS prediction outputs (combinational from registers, no BRAM delay)
    assign ras_pop_valid_o = (ras_ptr_q > 0);
    assign ras_target_o = ras_pop_valid_o ?
        ras_stack_q[ras_ptr_q - {{(RAS_ADDR_WIDTH-1){1'b0}}, 1'b1}] : '0;

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_tag_q   <= '0;
            predict_bht_index_q <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            bp_epoch_q          <= '0;
            ghr_q               <= '0;
            ras_ptr_q           <= '0;
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid_q[i] <= 1'b0;
                btb_epoch_q[i] <= '0;
            end
            for (i = 0; i < BHT_ENTRIES; i = i + 1) begin
                bht_valid_q[i] <= 1'b0;
                bht_epoch_q[i] <= '0;
            end
        end else if (invalidate_i) begin
            predict_btb_tag_q   <= '0;
            predict_bht_index_q <= '0;
            predict_btb_valid_q <= 1'b0;
            predict_bht_valid_q <= 1'b0;
            bp_epoch_q          <= bp_epoch_q + {{(BP_EPOCH_WIDTH-1){1'b0}}, 1'b1};
            ghr_q               <= '0;
            ras_ptr_q           <= '0;
        end else begin
            predict_btb_tag_q   <= predict_btb_tag;
            predict_bht_index_q <= predict_bht_index;
            predict_btb_valid_q <= predict_btb_entry_valid;
            predict_bht_valid_q <= predict_bht_entry_valid;

            if (ras_push_valid_i) begin
                if (ras_ptr_q < RAS_ADDR_WIDTH'(RAS_ENTRIES)) begin
                    ras_stack_q[ras_ptr_q] <= ras_push_addr_i;
                    ras_ptr_q <= ras_ptr_q + {{(RAS_ADDR_WIDTH-1){1'b0}}, 1'b1};
                end
            end

            if (train_fire) begin
                btb_valid_q[train_btb_index] <= 1'b1;
                bht_valid_q[train_bht_index] <= 1'b1;
                btb_epoch_q[train_btb_index] <= bp_epoch_q;
                bht_epoch_q[train_bht_index] <= bp_epoch_q;
                btb_mem[train_btb_index] <= {train_btb_tag, train_target_i};
                bht_mem[train_bht_index] <= bht_wdata;
                ghr_q <= {ghr_q[GHR_WIDTH-2:0], train_taken_i};
            end
        end
    end

    assign btb_hit     = predict_btb_valid_q && (btb_rtag == predict_btb_tag_q);
    assign bht_counter = predict_bht_valid_q ? bht_rdata : 2'b01;
    assign predict_hit_o     = !invalidate_i && btb_hit;
    assign predict_counter_o = !invalidate_i ? bht_counter : 2'b01;
    assign predict_taken_o   = predict_hit_o && predict_counter_o[1];
    assign predict_target_o  = predict_hit_o ? btb_rtarget : '0;

endmodule
