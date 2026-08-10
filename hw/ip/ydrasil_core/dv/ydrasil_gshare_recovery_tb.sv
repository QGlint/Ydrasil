`timescale 1ns/1ns

module ydrasil_gshare_recovery_tb;
    import ydrasil_pkg::*;

    localparam int BTB_ENTRIES = 16;
    localparam int BHT_ENTRIES = 16;
    localparam logic [31:0] PC = 32'h8000_0000;
    localparam logic [31:0] TARGET = 32'h8000_0040;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [31:0] predict_pc;
    logic [31:0] predict_pc1;
    logic predict_hit;
    logic predict_taken;
    logic [31:0] predict_target;
    logic [1:0] predict_counter;
    bp_bht_index_t predict_bht_index;
    bp_ghr_t predict_ghr_checkpoint;
    logic predict1_hit;
    logic predict1_taken;
    logic [31:0] predict1_target;
    logic [1:0] predict1_counter;
    bp_bht_index_t predict1_bht_index;
    bp_ghr_t predict1_ghr_checkpoint;
    logic spec0_valid;
    logic spec0_conditional;
    logic spec0_taken;
    logic spec1_valid;
    logic spec1_conditional;
    logic spec1_taken;
    ydrasil_bp_train_pkt_t train;
    logic invalidate;

    ydrasil_branch_predictor #(
        .BTB_ENTRIES(BTB_ENTRIES),
        .BHT_ENTRIES(BHT_ENTRIES),
        .USE_GSHARE(1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .predict_pc_i(predict_pc),
        .predict_hit_o(predict_hit),
        .predict_taken_o(predict_taken),
        .predict_target_o(predict_target),
        .predict_counter_o(predict_counter),
        .predict_global_counter_o(),
        .predict_local_counter_o(),
        .predict_bht_index_o(predict_bht_index),
        .predict_ghr_checkpoint_o(predict_ghr_checkpoint),
        .predict0_spec_valid_i(spec0_valid),
        .predict0_spec_conditional_i(spec0_conditional),
        .predict0_spec_taken_i(spec0_taken),
        .predict_pc1_i(predict_pc1),
        .predict1_hit_o(predict1_hit),
        .predict1_taken_o(predict1_taken),
        .predict1_target_o(predict1_target),
        .predict1_counter_o(predict1_counter),
        .predict1_global_counter_o(),
        .predict1_local_counter_o(),
        .predict1_bht_index_o(predict1_bht_index),
        .predict1_ghr_checkpoint_o(predict1_ghr_checkpoint),
        .predict1_spec_valid_i(spec1_valid),
        .predict1_spec_conditional_i(spec1_conditional),
        .predict1_spec_taken_i(spec1_taken),
        .train_i(train), .invalidate_i(invalidate)
    );

    always #5 clk = ~clk;

    task automatic expect_ghr(input logic [2:0] expected,
                              input string phase);
        begin
            if (dut.ghr_q !== expected) begin
                $fatal(1, "%s: GHR got %b expected %b", phase,
                       dut.ghr_q, expected);
            end
        end
    endtask

    task automatic idle_speculation;
        begin
            spec0_valid = 1'b0;
            spec0_conditional = 1'b0;
            spec0_taken = 1'b0;
            spec1_valid = 1'b0;
            spec1_conditional = 1'b0;
            spec1_taken = 1'b0;
        end
    endtask

    initial begin
        predict_pc = PC;
        predict_pc1 = PC + 32'd4;
        train = '0;
        invalidate = 1'b0;
        idle_speculation();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // Three conditional predictions create younger speculative history.
        // Resolving the oldest branch as not-taken must discard both younger
        // bits and recover to its pre-branch checkpoint.
        @(negedge clk);
        spec0_valid = 1'b1;
        spec0_conditional = 1'b1;
        spec0_taken = 1'b1;
        @(posedge clk); #1 expect_ghr(3'b001, "first speculative branch");

        @(negedge clk);
        spec0_taken = 1'b1;
        @(posedge clk); #1 expect_ghr(3'b011, "second speculative branch");

        @(negedge clk);
        spec0_taken = 1'b1;
        @(posedge clk); #1 expect_ghr(3'b111, "third speculative branch");

        @(negedge clk);
        idle_speculation();
        train = '0;
        train.valid = 1'b1;
        train.conditional = 1'b1;
        train.taken = 1'b0;
        train.recover = 1'b1;
        train.ghr_checkpoint = '0;
        train.pc = PC;
        train.target = TARGET;
        train.counter = 2'b01;
        train.global_counter = 2'b01;
        train.local_counter = 2'b01;
        train.bht_index = '0;
        @(posedge clk); #1 expect_ghr(3'b000, "redirect recovery");

        // A second recovery proves the actual branch direction is inserted
        // after the checkpoint, not merely restored.
        @(negedge clk);
        train.taken = 1'b1;
        train.ghr_checkpoint = 8'b0000_0010;
        @(posedge clk); #1 expect_ghr(3'b101, "recovery inserts actual direction");

        @(negedge clk);
        train = '0;
        @(posedge clk);
        @(posedge clk); #1 begin
            if (predict_bht_index[3:0] !== 4'b1010)
                $fatal(1, "GShare lookup index got %b expected 1010",
                       predict_bht_index[3:0]);
        end

        // Train exactly the carried hash index. The next lookup must hit the
        // same BHT and BTB entry, proving the train path does not recompute a
        // plain-PC BHT index.
        @(negedge clk);
        train = '0;
        train.valid = 1'b1;
        train.conditional = 1'b1;
        train.taken = 1'b1;
        train.pc = PC;
        train.target = TARGET;
        train.counter = 2'b01;
        train.global_counter = 2'b01;
        train.local_counter = 2'b01;
        train.bht_index = predict_bht_index;
        @(posedge clk);
        @(negedge clk);
        train = '0;
        @(posedge clk);
        @(posedge clk); #1 begin
            if (!predict_hit || !predict_taken)
                $fatal(1, "carried GShare index did not train prediction");
        end

        $display("TEST_PASS");
        $finish;
    end
endmodule
