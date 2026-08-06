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
    // Physical banks own even and odd producer slots; the low slot bit is the
    // bank select and the remaining bits directly index the six-entry bank.
    (* keep = "true" *) reg [REGS_DATA_WIDTH-1:0]
        value_even_q [0:BANK_DEPTH-1];
    (* keep = "true" *) reg [REGS_DATA_WIDTH-1:0]
        value_odd_q [0:BANK_DEPTH-1];

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

    // Slow completion lanes are assigned first. ALU lanes are last so their
    // same-edge write path has the highest FF D-input priority.
    integer value_slot;
    always_ff @(posedge clk) begin
        for (value_slot = 0; value_slot < BANK_DEPTH; value_slot++) begin
            if (completion_write1 && !completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
                    completion_bus_i[COMPLETION_LSU].data;
            if (completion_write2 && !completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
                    completion_bus_i[COMPLETION_MUL].data;
            if (completion_write0 && !completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
                    completion_bus_i[COMPLETION_ALU].data;
            if (completion_write3 && !completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
                    completion_bus_i[COMPLETION_DUAL_ALU].data;

            if (completion_write1 && completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
                    completion_bus_i[COMPLETION_LSU].data;
            if (completion_write2 && completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
                    completion_bus_i[COMPLETION_MUL].data;
            if (completion_write0 && completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
                    completion_bus_i[COMPLETION_ALU].data;
            if (completion_write3 && completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
                    completion_bus_i[COMPLETION_DUAL_ALU].data;
        end
    end

    wire [BANK_INDEX_WIDTH-1:0] read_index0 =
        read_slot0_i[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] read_index1 =
        read_slot1_i[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] read_index2 =
        read_slot2_i[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] read_index3 =
        read_slot3_i[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] retire_index0 =
        retire_slot0_i[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] retire_index1 =
        retire_slot1_i[PRODUCER_SLOT_WIDTH-1:1];

    assign read_data0_o = read_slot0_i[0] ?
        value_odd_q[read_index0] : value_even_q[read_index0];
    assign read_data1_o = read_slot1_i[0] ?
        value_odd_q[read_index1] : value_even_q[read_index1];
    assign read_data2_o = read_slot2_i[0] ?
        value_odd_q[read_index2] : value_even_q[read_index2];
    assign read_data3_o = read_slot3_i[0] ?
        value_odd_q[read_index3] : value_even_q[read_index3];
    assign retire_data0_o = retire_slot0_i[0] ?
        value_odd_q[retire_index0] : value_even_q[retire_index0];
    assign retire_data1_o = retire_slot1_i[0] ?
        value_odd_q[retire_index1] : value_even_q[retire_index1];

`ifndef SYNTHESIS
    initial assert ((PRODUCER_NUM == 12) && ((PRODUCER_NUM % 2) == 0))
        else $fatal(1, "value file requires the 12-slot two-bank producer layout");
`endif
endmodule
