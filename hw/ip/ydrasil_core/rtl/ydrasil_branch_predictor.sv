module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES = 256
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,

    input  wire                            train_valid_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_pc_i,
    input  wire                            train_taken_i,
    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] train_target_i,

    input  wire                            invalidate_i
);

    localparam int BP_INDEX_WIDTH = ydrasil_pkg::idx_width(BP_ENTRIES);
    localparam int BP_TAG_WIDTH = ydrasil_pkg::INST_ADDR_WIDTH - BP_INDEX_WIDTH - 2;

    if ((BP_ENTRIES < 2) || ((BP_ENTRIES & (BP_ENTRIES - 1)) != 0)) begin : g_bad_bp_entries
        initial begin
            $fatal(1, "BP_ENTRIES must be a power of two and at least 2");
        end
    end

    logic [1:0]              bht_q       [0:BP_ENTRIES-1];
    logic                    btb_valid_q [0:BP_ENTRIES-1];
    logic [BP_TAG_WIDTH-1:0] btb_tag_q   [0:BP_ENTRIES-1];
    logic [ydrasil_pkg::INST_ADDR_WIDTH-1:0] btb_target_q [0:BP_ENTRIES-1];

    wire [BP_INDEX_WIDTH-1:0] predict_index;
    wire [BP_TAG_WIDTH-1:0]   predict_tag;
    wire [BP_INDEX_WIDTH-1:0] train_index;
    wire [BP_TAG_WIDTH-1:0]   train_tag;
    wire                      btb_hit;

    assign predict_index = predict_pc_i[BP_INDEX_WIDTH+1:2];
    assign predict_tag   = predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign train_index   = train_pc_i[BP_INDEX_WIDTH+1:2];
    assign train_tag     = train_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:BP_INDEX_WIDTH+2];

    assign btb_hit          = btb_valid_q[predict_index] && (btb_tag_q[predict_index] == predict_tag);
    assign predict_hit_o    = !invalidate_i && btb_hit;
    assign predict_taken_o  = predict_hit_o && bht_q[predict_index][1];
    assign predict_target_o = predict_hit_o ? btb_target_q[predict_index] : '0;

    function automatic logic [1:0] next_counter(
        input logic [1:0] counter_i,
        input logic       taken_i
    );
        if (taken_i) begin
            next_counter = (counter_i == 2'b11) ? counter_i : (counter_i + 2'b01);
        end else begin
            next_counter = (counter_i == 2'b00) ? counter_i : (counter_i - 2'b01);
        end
    endfunction

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BP_ENTRIES; i = i + 1) begin
                bht_q[i]        <= 2'b01;
                btb_valid_q[i]  <= 1'b0;
                btb_tag_q[i]    <= '0;
                btb_target_q[i] <= '0;
            end
        end else if (invalidate_i) begin
            for (i = 0; i < BP_ENTRIES; i = i + 1) begin
                bht_q[i]        <= 2'b01;
                btb_valid_q[i]  <= 1'b0;
                btb_tag_q[i]    <= '0;
                btb_target_q[i] <= '0;
            end
        end else if (train_valid_i) begin
            bht_q[train_index]        <= next_counter(bht_q[train_index], train_taken_i);
            btb_valid_q[train_index]  <= 1'b1;
            btb_tag_q[train_index]    <= train_tag;
            btb_target_q[train_index] <= train_target_i;
        end
    end

endmodule
