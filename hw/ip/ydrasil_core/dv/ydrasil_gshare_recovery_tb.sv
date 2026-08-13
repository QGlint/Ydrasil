`timescale 1ns/1ns

module ydrasil_gshare_recovery_tb;
    import ydrasil_pkg::*;

    localparam int BTB_ENTRIES = 16;
    localparam int BHT_ENTRIES = 4096;
    localparam int BHT_INDEX_WIDTH = $clog2(BHT_ENTRIES);
    localparam int BHT_ROW_WIDTH = $clog2(BHT_ENTRIES / 2);
    localparam logic [31:0] TARGET = 32'h8000_1040;

    localparam logic [31:0] LANE0_PC = 32'h8000_0100;
    localparam logic [31:0] LANE1_AFTER_NONCOND_PC = 32'h8000_0204;
    localparam logic [31:0] LANE1_AFTER_COND_PC = 32'h8000_0304;
    localparam logic [31:0] ODD_SINGLE_PC = 32'h8000_0404;
    localparam logic [31:0] LANE1_JUMP_AFTER_COND_PC = 32'h8000_0504;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [31:0] predict_pc;
    logic [31:0] predict_pc1;
    logic predict_hit;
    logic predict_taken;
    logic [31:0] predict_target;
    logic [1:0] predict_counter;
    bp_bht_index_t predict_bht_index;
    logic predict1_hit;
    logic predict1_taken;
    logic [31:0] predict1_target;
    logic [1:0] predict1_counter;
    bp_bht_index_t predict1_bht_index;
    logic spec0_valid;
    logic spec0_conditional;
    logic spec1_valid;
    logic spec1_conditional;
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
        .predict_target_token_o(),
        .predict_counter_o(predict_counter),
        .predict_global_counter_o(),
        .predict_local_counter_o(),
        .predict_bht_index_o(predict_bht_index),
        .predict0_spec_valid_i(spec0_valid),
        .predict0_spec_conditional_i(spec0_conditional),
        .predict_pc1_i(predict_pc1),
        .predict1_hit_o(predict1_hit),
        .predict1_taken_o(predict1_taken),
        .predict1_target_o(predict1_target),
        .predict1_target_token_o(),
        .predict1_counter_o(predict1_counter),
        .predict1_global_counter_o(),
        .predict1_local_counter_o(),
        .predict1_bht_index_o(predict1_bht_index),
        .predict1_spec_valid_i(spec1_valid),
        .predict1_spec_conditional_i(spec1_conditional),
        .train_i(train), .invalidate_i(invalidate)
    );

    always #5 clk = ~clk;

    function automatic bp_bht_index_t make_carried_index(
        input logic [31:0] branch_pc,
        input logic [BHT_ROW_WIDTH-1:0] lookup_history,
        input logic marker
    );
        bp_bht_index_t result;
        begin
            result = '0;
            result[BHT_INDEX_WIDTH-1:1] =
                BHT_ROW_WIDTH'(branch_pc >> 3) ^ lookup_history;
            result[0] = marker;
            make_carried_index = result;
        end
    endfunction

    task automatic idle_speculation;
        begin
            spec0_valid = 1'b0;
            spec0_conditional = 1'b0;
            spec1_valid = 1'b0;
            spec1_conditional = 1'b0;
        end
    endtask

    task automatic recover_case(
        input logic [31:0] branch_pc,
        input logic [BHT_ROW_WIDTH-1:0] lookup_history,
        input logic marker,
        input logic actual_taken,
        input logic conditional,
        input string phase
    );
        logic [BHT_ROW_WIDTH-1:0] expected_checkpoint;
        logic [BHT_ROW_WIDTH-1:0] expected_ghr;
        begin
            expected_checkpoint = marker ? (lookup_history << 1) :
                lookup_history;
            expected_ghr = conditional ?
                ((expected_checkpoint << 1) | BHT_ROW_WIDTH'(actual_taken)) :
                expected_checkpoint;

            @(negedge clk);
            idle_speculation();
            train = '0;
            train.valid = 1'b1;
            train.conditional = conditional;
            train.taken = actual_taken;
            train.recover = 1'b1;
            train.pc = branch_pc;
            train.target = TARGET;
            train.counter = 2'b01;
            train.global_counter = 2'b01;
            train.local_counter = 2'b01;
            train.bht_index = make_carried_index(branch_pc, lookup_history,
                                                  marker);
            #1;
            if (train.bht_index[0] !== marker)
                $fatal(1, "%s: carried marker got %b expected %b", phase,
                       train.bht_index[0], marker);
            if (dut.recovered_lookup_history !== lookup_history)
                $fatal(1, "%s: recovered lookup history got %b expected %b",
                       phase, dut.recovered_lookup_history, lookup_history);
            if (dut.recovered_branch_checkpoint !== expected_checkpoint)
                $fatal(1, "%s: recovered checkpoint got %b expected %b",
                       phase, dut.recovered_branch_checkpoint,
                       expected_checkpoint);
            @(posedge clk); #1;
            if (dut.ghr_q !== expected_ghr)
                $fatal(1, "%s: redirect GHR got %b expected %b", phase,
                       dut.ghr_q, expected_ghr);
        end
    endtask

    initial begin
        predict_pc = LANE0_PC;
        predict_pc1 = LANE0_PC + 32'd4;
        train = '0;
        invalidate = 1'b0;
        idle_speculation();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // (1) A lane-0 conditional carries the direct lookup history.
        recover_case(LANE0_PC, 11'b101_0011_0101, 1'b0, 1'b0, 1'b1,
                     "lane0 conditional");

        // (2) Lane 1 after a non-conditional lane 0 also carries direct history.
        recover_case(LANE1_AFTER_NONCOND_PC, 11'b011_1010_0101, 1'b0,
                     1'b1, 1'b1, "lane1 after nonconditional");

        // (3) A surviving lane 1 after lane-0 conditional predicted NT restores
        // the extra zero history bit before inserting its architectural result.
        recover_case(LANE1_AFTER_COND_PC, 11'b110_0101_1010, 1'b1, 1'b1,
                     1'b1, "lane1 after conditional NT");

        // (4) An odd-half single-lane branch is not a lane-1 pair and has no
        // preceding lane-0 conditional marker despite PC[2] being one.
        recover_case(ODD_SINGLE_PC, 11'b001_1110_0101, 1'b0, 1'b0, 1'b1,
                     "odd-half single lane");

        // A lane-1 direct jump after a lane-0 conditional restores the same
        // marker-adjusted checkpoint, but does not insert its own taken bit.
        recover_case(LANE1_JUMP_AFTER_COND_PC, 11'b010_1101_1001, 1'b1,
                     1'b1, 1'b0, "lane1 direct jump after conditional NT");

        $display("TEST_PASS");
        $finish;
    end
endmodule
