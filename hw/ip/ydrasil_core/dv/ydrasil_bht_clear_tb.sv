`timescale 1ns/1ns

// Targeted regression for the serial BHT reset/FENCE.I scrub.  It deliberately
// presents a train request after that BHT address has been scrubbed, proving a
// stale or colliding write cannot reappear when the sweep completes.
module ydrasil_bht_clear_tb
import ydrasil_pkg::*;
(
`ifdef VERILATOR_CC
    input wire clk,
    input wire rst_n
`endif
);

`ifndef VERILATOR_CC
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end
`endif

    localparam int BTB_ENTRIES = 4;
    localparam int BHT_ENTRIES = 4;
    localparam logic [31:0] PC_A = 32'h8000_0000;
    localparam logic [31:0] TARGET_A = 32'h8000_0040;

    logic [31:0] predict_pc;
    logic predict_hit;
    logic predict_taken;
    logic [31:0] predict_target;
    logic [1:0] predict_counter;
    logic [31:0] predict_bht_index;
    logic predict1_hit;
    logic predict1_taken;
    logic [31:0] predict1_target;
    logic [1:0] predict1_counter;
    logic [31:0] predict1_bht_index;
    ydrasil_bp_train_pkt_t train_pkt;
    logic invalidate;
    integer step;

    ydrasil_branch_predictor #(
        .BTB_ENTRIES(BTB_ENTRIES),
        .BHT_ENTRIES(BHT_ENTRIES)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .predict_pc_i(predict_pc),
        .predict_hit_o(predict_hit),
        .predict_taken_o(predict_taken),
        .predict_target_o(predict_target),
        .predict_counter_o(predict_counter),
        .predict_bht_index_o(predict_bht_index),
        .predict0_spec_valid_i(1'b0),
        .predict0_spec_conditional_i(1'b0),
        .predict0_spec_taken_i(1'b0),
        .predict_pc1_i(predict_pc + 32'd4),
        .predict1_hit_o(predict1_hit),
        .predict1_taken_o(predict1_taken),
        .predict1_target_o(predict1_target),
        .predict1_counter_o(predict1_counter),
        .predict1_bht_index_o(predict1_bht_index),
        .train_i(train_pkt),
        .invalidate_i(invalidate)
    );

    task automatic drive(
        input logic do_train,
        input logic train_taken,
        input logic do_invalidate
    );
        begin
            predict_pc <= PC_A;
            train_pkt <= '0;
            train_pkt.valid <= do_train;
            train_pkt.conditional <= do_train;
            train_pkt.pc <= PC_A;
            train_pkt.taken <= train_taken;
            train_pkt.target <= TARGET_A;
            train_pkt.counter <= 2'b01;
            train_pkt.bht_index <= PC_A >> 2;
            invalidate <= do_invalidate;
        end
    endtask

    task automatic expect_counter(
        input logic [1:0] expected,
        input string phase
    );
        begin
            if (predict_counter !== expected) begin
                $fatal(1, "%s: counter got %b expected %b", phase,
                       predict_counter, expected);
            end
        end
    endtask

    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step <= 0;
            predict_pc <= PC_A;
            train_pkt <= '0;
            invalidate <= 1'b0;
        end else begin
            case (step)
                // Allow the reset-time BHT scrub to cover every entry.
                0, 1, 2, 3: begin
                    expect_counter(2'b01, "reset scrub");
                    drive(1'b0, 1'b0, 1'b0);
                    step <= step + 1;
                end
                4: begin
                    expect_counter(2'b01, "initial state");
                    drive(1'b1, 1'b1, 1'b0);
                    step <= step + 1;
                end
                5: begin
                    drive(1'b0, 1'b0, 1'b0);
                    step <= step + 1;
                end
                6: begin
                    expect_counter(2'b10, "trained state");
                    if (!predict_hit || !predict_taken)
                        $fatal(1, "trained branch did not predict taken");
                    drive(1'b0, 1'b0, 1'b1);
                    step <= step + 1;
                end
                7: begin
                    expect_counter(2'b01, "FENCE.I immediate state");
                    if (predict_hit || predict_taken)
                        $fatal(1, "FENCE.I did not suppress prediction");
                    drive(1'b0, 1'b0, 1'b0);
                    step <= step + 1;
                end
                8: begin
                    // Index zero was scrubbed in the preceding cycle. This
                    // request must not repopulate it while the sweep is live.
                    drive(1'b1, 1'b1, 1'b0);
                    step <= step + 1;
                end
                9, 10: begin
                    drive(1'b0, 1'b0, 1'b0);
                    step <= step + 1;
                end
                11: begin
                    expect_counter(2'b01, "post-FENCE.I scrub");
                    if (predict_taken)
                        $fatal(1, "stale BHT state survived FENCE.I");
                    drive(1'b1, 1'b1, 1'b0);
                    step <= step + 1;
                end
                12: begin
                    drive(1'b0, 1'b0, 1'b0);
                    step <= step + 1;
                end
                13: begin
                    expect_counter(2'b10, "post-scrub training");
                    if (!predict_hit || !predict_taken)
                        $fatal(1, "predictor did not recover after scrub");
                    $display("TEST_PASS");
                    $finish;
                end
                default: $fatal(1, "unexpected step %0d", step);
            endcase
        end
    end

endmodule
