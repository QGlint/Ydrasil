`timescale 1ns/1ns

module ydrasil_branch_predictor_tb
(
`ifdef VERILATOR_CC
    input clk,
    input rst_n
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
    localparam int BHT_ENTRIES = 8;
    localparam logic [31:0] PC_A = 32'h8000_0000;
    localparam logic [31:0] PC_B = PC_A + (BTB_ENTRIES * 32'd4);
    localparam logic [31:0] PC_C = PC_A + 32'd4;
    localparam logic [31:0] TARGET_A0 = 32'h8000_0040;
    localparam logic [31:0] TARGET_B0 = 32'h8000_0080;
    localparam logic [31:0] TARGET_B1 = 32'h8000_00c0;
    localparam logic [31:0] TARGET_C0 = 32'h8000_0100;

    logic        predict_hit;
    logic        predict_taken;
    logic [31:0] predict_target;
    logic [1:0]  predict_counter;
    ydrasil_pkg::bp_bht_index_t predict_bht_index;
    logic        predict1_hit;
    logic        predict1_taken;
    logic [31:0] predict1_target;
    logic [1:0]  predict1_counter;
    ydrasil_pkg::bp_bht_index_t predict1_bht_index;

    logic [31:0] predict_pc;
    ydrasil_pkg::ydrasil_bp_train_pkt_t train_pkt;
    logic        invalidate;
    int          step;

    ydrasil_branch_predictor #(
        .BTB_ENTRIES(BTB_ENTRIES),
        .BHT_ENTRIES(BHT_ENTRIES)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .predict_pc_i     (predict_pc),
        .predict_hit_o    (predict_hit),
        .predict_taken_o  (predict_taken),
        .predict_target_o (predict_target),
        .predict_counter_o(predict_counter),
        .predict_global_counter_o(),
        .predict_local_counter_o(),
        .predict_bht_index_o(predict_bht_index),
        .predict0_spec_valid_i(1'b0),
        .predict0_spec_conditional_i(1'b1),
        .predict_pc1_i    (predict_pc + 32'd4),
        .predict1_hit_o   (predict1_hit),
        .predict1_taken_o (predict1_taken),
        .predict1_target_o(predict1_target),
        .predict1_counter_o(predict1_counter),
        .predict1_global_counter_o(),
        .predict1_local_counter_o(),
        .predict1_bht_index_o(predict1_bht_index),
        .predict1_spec_valid_i(1'b0),
        .predict1_spec_conditional_i(1'b0),
        .train_i          (train_pkt),
        .invalidate_i     (invalidate)
    );

    task automatic drive_idle(input logic [31:0] pc);
        begin
            predict_pc    <= pc;
            train_pkt     <= '0;
            invalidate    <= 1'b0;
        end
    endtask

    task automatic drive_train(
        input logic [31:0] pc,
        input logic        taken,
        input logic [31:0] target,
        input logic [1:0]  counter
    );
        begin
            predict_pc    <= pc;
            train_pkt.valid <= 1'b1;
            train_pkt.conditional <= 1'b1;
            train_pkt.pc <= pc;
            train_pkt.taken <= taken;
            train_pkt.target <= target;
            train_pkt.counter <= counter;
            // USE_GSHARE=0 in this test, so the branch's carried BHT index is
            // the word address index of the branch being trained.
            train_pkt.bht_index <= ydrasil_pkg::BP_BHT_INDEX_WIDTH'(pc >> 2);
            invalidate    <= 1'b0;
        end
    endtask

    task automatic drive_jump(
        input logic [31:0] pc,
        input logic [31:0] target
    );
        begin
            predict_pc <= pc;
            train_pkt <= '0;
            train_pkt.valid <= 1'b1;
            train_pkt.conditional <= 1'b0;
            train_pkt.pc <= pc;
            train_pkt.taken <= 1'b1;
            train_pkt.target <= target;
            train_pkt.counter <= 2'b00;
            train_pkt.bht_index <= ydrasil_pkg::BP_BHT_INDEX_WIDTH'(pc >> 2);
            invalidate <= 1'b0;
        end
    endtask

    task automatic drive_train_current(
        input logic [31:0] pc,
        input logic        taken,
        input logic [31:0] target
    );
        begin
            drive_train(pc, taken, target, predict_counter);
        end
    endtask

    task automatic check_predict(
        input logic        exp_hit,
        input logic        exp_taken,
        input logic [31:0] exp_target,
        input logic [1:0]  exp_counter
    );
        begin
            if (predict_hit !== exp_hit) begin
                $fatal(1, "predict_hit mismatch: got %0b expected %0b at step %0d",
                       predict_hit, exp_hit, step);
            end
            if (predict_taken !== exp_taken) begin
                $fatal(1, "predict_taken mismatch: got %0b expected %0b at step %0d",
                       predict_taken, exp_taken, step);
            end
            if (predict_counter !== exp_counter) begin
                $fatal(1, "predict_counter mismatch: got %0b expected %0b at step %0d",
                       predict_counter, exp_counter, step);
            end
            if (exp_hit && (predict_target !== exp_target)) begin
                $fatal(1, "predict_target mismatch: got 0x%08h expected 0x%08h at step %0d",
                       predict_target, exp_target, step);
            end
        end
    endtask

    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step          <= 0;
            predict_pc    <= PC_A;
            train_pkt     <= '0;
            invalidate    <= 1'b0;
        end else begin
            case (step)
                0: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_train_current(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                1: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                2: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b10);
                    drive_train_current(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                3: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b10);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                4: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b11);
                    drive_train_current(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                5: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b11);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                6: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b10);
                    drive_train_current(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                7: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b10);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                8: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b01);
                    drive_train_current(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                9: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b01);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                10: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b00);
                    drive_train_current(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                11: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b00);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                12: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b01);
                    drive_train_current(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                13: begin
                    check_predict(1'b1, 1'b0, TARGET_A0, 2'b01);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                14: begin
                    check_predict(1'b1, 1'b1, TARGET_A0, 2'b10);
                    drive_train(PC_B, 1'b1, TARGET_B0, 2'b01);
                    step <= step + 1;
                end
                15: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                16: begin
                    check_predict(1'b1, 1'b1, TARGET_B0, 2'b10);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                17: begin
                    // A BTB miss returns the interface default counter; stale
                    // BHT contents are not architecturally visible.
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                18: begin
                    check_predict(1'b1, 1'b1, TARGET_B0, 2'b10);
                    drive_train_current(PC_B, 1'b1, TARGET_B1);
                    step <= step + 1;
                end
                19: begin
                    check_predict(1'b1, 1'b1, TARGET_B0, 2'b10);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                20: begin
                    check_predict(1'b1, 1'b1, TARGET_B1, 2'b11);
                    predict_pc    <= PC_B;
                    train_pkt.valid <= 1'b1;
                    train_pkt.conditional <= 1'b1;
                    train_pkt.pc <= PC_B;
                    train_pkt.taken <= 1'b1;
                    train_pkt.target <= TARGET_B0;
                    train_pkt.counter <= predict_counter;
                    train_pkt.bht_index <=
                        ydrasil_pkg::BP_BHT_INDEX_WIDTH'(PC_B >> 2);
                    invalidate    <= 1'b1;
                    step <= step + 1;
                end
                21: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                22: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    predict_pc <= PC_B;
                    train_pkt <= '0;
                    invalidate <= 1'b1;
                    step <= step + 1;
                end
                23: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                24: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_jump(PC_C, TARGET_C0);
                    step <= step + 1;
                end
                25: begin
                    check_predict(1'b0, 1'b0, '0, 2'b01);
                    drive_idle(PC_C);
                    step <= step + 1;
                end
                26: begin
                    // An unconditional BTB entry is taken even though its BHT
                    // counter remains at weak-not-taken.
                    check_predict(1'b1, 1'b1, TARGET_C0, 2'b11);
                    $display("TEST_PASS");
                    $finish;
                end
                default: begin
                    $fatal(1, "unexpected predictor tb step %0d", step);
                end
            endcase
        end
    end

endmodule
