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

    localparam int BP_ENTRIES = 4;
    localparam logic [31:0] PC_A = 32'h8000_0000;
    localparam logic [31:0] PC_B = PC_A + (BP_ENTRIES * 32'd4);
    localparam logic [31:0] TARGET_A0 = 32'h8000_0040;
    localparam logic [31:0] TARGET_B0 = 32'h8000_0080;
    localparam logic [31:0] TARGET_B1 = 32'h8000_00c0;

    logic        predict_hit;
    logic        predict_taken;
    logic [31:0] predict_target;

    logic [31:0] predict_pc;
    logic        train_valid;
    logic [31:0] train_pc;
    logic        train_taken;
    logic [31:0] train_target;
    logic        invalidate;
    int          step;

    ydrasil_branch_predictor #(
        .BP_ENTRIES(BP_ENTRIES)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .predict_pc_i     (predict_pc),
        .predict_hit_o    (predict_hit),
        .predict_taken_o  (predict_taken),
        .predict_target_o (predict_target),
        .train_valid_i    (train_valid),
        .train_pc_i       (train_pc),
        .train_taken_i    (train_taken),
        .train_target_i   (train_target),
        .invalidate_i     (invalidate)
    );

    task automatic drive_idle(input logic [31:0] pc);
        begin
            predict_pc   <= pc;
            train_valid  <= 1'b0;
            train_pc     <= '0;
            train_taken  <= 1'b0;
            train_target <= '0;
            invalidate   <= 1'b0;
        end
    endtask

    task automatic drive_train(
        input logic [31:0] pc,
        input logic        taken,
        input logic [31:0] target
    );
        begin
            predict_pc   <= pc;
            train_valid  <= 1'b1;
            train_pc     <= pc;
            train_taken  <= taken;
            train_target <= target;
            invalidate   <= 1'b0;
        end
    endtask

    task automatic check_predict(
        input logic        exp_hit,
        input logic        exp_taken,
        input logic [31:0] exp_target
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
            if (exp_hit && (predict_target !== exp_target)) begin
                $fatal(1, "predict_target mismatch: got 0x%08h expected 0x%08h at step %0d",
                       predict_target, exp_target, step);
            end
        end
    endtask

    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step         <= 0;
            predict_pc   <= PC_A;
            train_valid  <= 1'b0;
            train_pc     <= '0;
            train_taken  <= 1'b0;
            train_target <= '0;
            invalidate   <= 1'b0;
        end else begin
            case (step)
                0: begin
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                1: begin
                    check_predict(1'b0, 1'b0, '0);
                    drive_train(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                2: begin
                    check_predict(1'b1, 1'b1, TARGET_A0);
                    drive_train(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                3: begin
                    check_predict(1'b1, 1'b1, TARGET_A0);
                    drive_train(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                4: begin
                    check_predict(1'b1, 1'b1, TARGET_A0);
                    drive_train(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                5: begin
                    check_predict(1'b1, 1'b0, TARGET_A0);
                    drive_train(PC_A, 1'b0, TARGET_A0);
                    step <= step + 1;
                end
                6: begin
                    check_predict(1'b1, 1'b0, TARGET_A0);
                    drive_train(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                7: begin
                    check_predict(1'b1, 1'b0, TARGET_A0);
                    drive_train(PC_A, 1'b1, TARGET_A0);
                    step <= step + 1;
                end
                8: begin
                    check_predict(1'b1, 1'b1, TARGET_A0);
                    drive_train(PC_B, 1'b1, TARGET_B0);
                    step <= step + 1;
                end
                9: begin
                    predict_pc  <= PC_B;
                    train_valid <= 1'b0;
                    step <= step + 1;
                end
                10: begin
                    check_predict(1'b1, 1'b1, TARGET_B0);
                    drive_idle(PC_A);
                    step <= step + 1;
                end
                11: begin
                    check_predict(1'b0, 1'b0, '0);
                    drive_train(PC_B, 1'b1, TARGET_B1);
                    step <= step + 1;
                end
                12: begin
                    check_predict(1'b1, 1'b1, TARGET_B1);
                    predict_pc   <= PC_B;
                    train_valid  <= 1'b1;
                    train_pc     <= PC_B;
                    train_taken  <= 1'b1;
                    train_target <= TARGET_B0;
                    invalidate   <= 1'b1;
                    step <= step + 1;
                end
                13: begin
                    check_predict(1'b0, 1'b0, '0);
                    drive_idle(PC_B);
                    step <= step + 1;
                end
                14: begin
                    check_predict(1'b0, 1'b0, '0);
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
