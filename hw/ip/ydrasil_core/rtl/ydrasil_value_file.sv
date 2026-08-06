module ydrasil_value_file
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  ydrasil_completion_bus_t     completion_bus_i,
    input  producer_slot_t              read_slot0_i,
    input  producer_slot_t              read_slot1_i,
    input  producer_slot_t              read_slot2_i,
    input  producer_slot_t              read_slot3_i,
    input  producer_slot_t              retire_slot0_i,
    input  producer_slot_t              retire_slot1_i,
    output wire [REGS_DATA_WIDTH-1:0]   read_data0_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data1_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data2_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data3_o,
    output wire [REGS_DATA_WIDTH-1:0]   retire_data0_o,
    output wire [REGS_DATA_WIDTH-1:0]   retire_data1_o
);
    localparam int BANK_DEPTH = PRODUCER_NUM / 2;
    localparam int BANK_INDEX_WIDTH = $clog2(BANK_DEPTH);

    // Producer metadata qualifies every consumer, so stale payload is harmless.
    // Avoiding reset/retire/recovery clears removes those controls from 384 FFs.
    (* keep = "true" *) reg [REGS_DATA_WIDTH-1:0]
        value_bank0_q [0:BANK_DEPTH-1];
    (* keep = "true" *) reg [REGS_DATA_WIDTH-1:0]
        value_bank1_q [0:BANK_DEPTH-1];

    producer_slot_t completion_slot0;
    producer_slot_t completion_slot1;
    producer_slot_t completion_slot2;
    producer_slot_t completion_slot3;
    assign completion_slot0 = completion_bus_i[COMPLETION_ALU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot1 = completion_bus_i[COMPLETION_LSU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot2 = completion_bus_i[COMPLETION_MUL].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];
    assign completion_slot3 = completion_bus_i[COMPLETION_DUAL_ALU].producer_id[
        PRODUCER_SLOT_WIDTH-1:0];

    wire completion_write0 = completion_bus_i[COMPLETION_ALU].valid &&
        completion_bus_i[COMPLETION_ALU].producer_tracked;
    wire completion_write1 = completion_bus_i[COMPLETION_LSU].valid &&
        completion_bus_i[COMPLETION_LSU].producer_tracked;
    wire completion_write2 = completion_bus_i[COMPLETION_MUL].valid &&
        completion_bus_i[COMPLETION_MUL].producer_tracked;
    wire completion_write3 = completion_bus_i[COMPLETION_DUAL_ALU].valid &&
        completion_bus_i[COMPLETION_DUAL_ALU].producer_tracked;

    // Each comparison is a fixed per-slot write enable. Slots 0..5 and 6..11
    // form separate physical banks while retaining four completion write lanes.
    integer value_slot;
    always_ff @(posedge clk) begin
        for (value_slot = 0; value_slot < BANK_DEPTH; value_slot++) begin
            if (completion_write0 &&
                (completion_slot0 == producer_slot_t'(value_slot)))
                value_bank0_q[value_slot] <=
                    completion_bus_i[COMPLETION_ALU].data;
            if (completion_write1 &&
                (completion_slot1 == producer_slot_t'(value_slot)))
                value_bank0_q[value_slot] <=
                    completion_bus_i[COMPLETION_LSU].data;
            if (completion_write2 &&
                (completion_slot2 == producer_slot_t'(value_slot)))
                value_bank0_q[value_slot] <=
                    completion_bus_i[COMPLETION_MUL].data;
            if (completion_write3 &&
                (completion_slot3 == producer_slot_t'(value_slot)))
                value_bank0_q[value_slot] <=
                    completion_bus_i[COMPLETION_DUAL_ALU].data;

            if (completion_write0 &&
                (completion_slot0 == producer_slot_t'(value_slot+BANK_DEPTH)))
                value_bank1_q[value_slot] <=
                    completion_bus_i[COMPLETION_ALU].data;
            if (completion_write1 &&
                (completion_slot1 == producer_slot_t'(value_slot+BANK_DEPTH)))
                value_bank1_q[value_slot] <=
                    completion_bus_i[COMPLETION_LSU].data;
            if (completion_write2 &&
                (completion_slot2 == producer_slot_t'(value_slot+BANK_DEPTH)))
                value_bank1_q[value_slot] <=
                    completion_bus_i[COMPLETION_MUL].data;
            if (completion_write3 &&
                (completion_slot3 == producer_slot_t'(value_slot+BANK_DEPTH)))
                value_bank1_q[value_slot] <=
                    completion_bus_i[COMPLETION_DUAL_ALU].data;
        end
    end

    wire [BANK_INDEX_WIDTH-1:0] read_index0 =
        BANK_INDEX_WIDTH'((read_slot0_i < producer_slot_t'(BANK_DEPTH)) ?
        read_slot0_i : read_slot0_i - producer_slot_t'(BANK_DEPTH));
    wire [BANK_INDEX_WIDTH-1:0] read_index1 =
        BANK_INDEX_WIDTH'((read_slot1_i < producer_slot_t'(BANK_DEPTH)) ?
        read_slot1_i : read_slot1_i - producer_slot_t'(BANK_DEPTH));
    wire [BANK_INDEX_WIDTH-1:0] read_index2 =
        BANK_INDEX_WIDTH'((read_slot2_i < producer_slot_t'(BANK_DEPTH)) ?
        read_slot2_i : read_slot2_i - producer_slot_t'(BANK_DEPTH));
    wire [BANK_INDEX_WIDTH-1:0] read_index3 =
        BANK_INDEX_WIDTH'((read_slot3_i < producer_slot_t'(BANK_DEPTH)) ?
        read_slot3_i : read_slot3_i - producer_slot_t'(BANK_DEPTH));
    wire [BANK_INDEX_WIDTH-1:0] retire_index0 =
        BANK_INDEX_WIDTH'((retire_slot0_i < producer_slot_t'(BANK_DEPTH)) ?
        retire_slot0_i : retire_slot0_i - producer_slot_t'(BANK_DEPTH));
    wire [BANK_INDEX_WIDTH-1:0] retire_index1 =
        BANK_INDEX_WIDTH'((retire_slot1_i < producer_slot_t'(BANK_DEPTH)) ?
        retire_slot1_i : retire_slot1_i - producer_slot_t'(BANK_DEPTH));

    assign read_data0_o = (read_slot0_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[read_index0] : value_bank1_q[read_index0];
    assign read_data1_o = (read_slot1_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[read_index1] : value_bank1_q[read_index1];
    assign read_data2_o = (read_slot2_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[read_index2] : value_bank1_q[read_index2];
    assign read_data3_o = (read_slot3_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[read_index3] : value_bank1_q[read_index3];
    assign retire_data0_o =
        (retire_slot0_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[retire_index0] : value_bank1_q[retire_index0];
    assign retire_data1_o =
        (retire_slot1_i < producer_slot_t'(BANK_DEPTH)) ?
        value_bank0_q[retire_index1] : value_bank1_q[retire_index1];

`ifndef SYNTHESIS
    initial assert ((PRODUCER_NUM == 12) && ((PRODUCER_NUM % 2) == 0))
        else $fatal(1, "value file requires the 12-slot two-bank producer layout");
`endif
endmodule
