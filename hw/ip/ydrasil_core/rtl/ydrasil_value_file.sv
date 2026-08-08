module ydrasil_value_file
import ydrasil_pkg::*;
(
    input  wire                         clk,
	    input  wire                         rst_n,
	    input  wire                         alloc0_valid_i,
	    input  producer_id_t                alloc0_id_i,
	    input  wire                         alloc1_valid_i,
	    input  producer_id_t                alloc1_id_i,
	    input  ydrasil_completion_meta_t    completion_meta_i [COMPLETION_LANES],
	    input  wire [REGS_DATA_WIDTH-1:0]   completion_data_i [COMPLETION_LANES],
    input  producer_id_t                lookup_tag0_i,
    input  producer_id_t                lookup_tag1_i,
    input  producer_id_t                lookup_tag2_i,
    input  producer_id_t                lookup_tag3_i,
    input  producer_slot_t              read_slot0_i,
    input  producer_slot_t              read_slot1_i,
    input  producer_slot_t              read_slot2_i,
    input  producer_slot_t              read_slot3_i,
    input  producer_id_t                retire_id0_i,
    input  producer_id_t                retire_id1_i,
    output wire [REGS_DATA_WIDTH-1:0]   read_data0_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data1_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data2_o,
    output wire [REGS_DATA_WIDTH-1:0]   read_data3_o,
    output wire                         read_epoch0_o,
    output wire                         read_epoch1_o,
    output wire                         read_epoch2_o,
    output wire                         read_epoch3_o,
	    output wire                         read_valid0_o,
	    output wire                         read_valid1_o,
	    output wire                         read_valid2_o,
	    output wire                         read_valid3_o,
    output wire                         lookup_resident0_o,
    output wire                         lookup_resident1_o,
    output wire                         lookup_resident2_o,
    output wire                         lookup_resident3_o,
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
    reg [BANK_DEPTH-1:0] value_epoch_even_q;
    reg [BANK_DEPTH-1:0] value_epoch_odd_q;
	    reg [BANK_DEPTH-1:0] value_valid_even_q;
	    reg [BANK_DEPTH-1:0] value_valid_odd_q;

    producer_slot_t completion_slot0;
    producer_slot_t completion_slot1;
    producer_slot_t completion_slot2;
    producer_slot_t completion_slot3;
	    assign completion_slot0 = completion_meta_i[COMPLETION_ALU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot1 = completion_meta_i[COMPLETION_LSU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot2 = completion_meta_i[COMPLETION_MUL].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];
	    assign completion_slot3 = completion_meta_i[COMPLETION_DUAL_ALU].producer_id[
	        PRODUCER_SLOT_WIDTH-1:0];

	    wire completion_write0 = completion_meta_i[COMPLETION_ALU].valid &&
	        completion_meta_i[COMPLETION_ALU].producer_tracked;
	    wire completion_write1 = completion_meta_i[COMPLETION_LSU].valid &&
	        completion_meta_i[COMPLETION_LSU].producer_tracked;
	    wire completion_write2 = completion_meta_i[COMPLETION_MUL].valid &&
	        completion_meta_i[COMPLETION_MUL].producer_tracked;
	    wire completion_write3 = completion_meta_i[COMPLETION_DUAL_ALU].valid &&
	        completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked;

	    // Validity follows actual data completion, not the earlier ROB due token.
	    // Allocation clears the physical slot so a store cannot accept data from
	    // the same full producer ID after two generation wraps.
	    integer valid_slot;
	    always_ff @(posedge clk) begin
	        if (!rst_n) begin
	            value_valid_even_q <= '0;
	            value_valid_odd_q <= '0;
	        end else begin
	            for (valid_slot = 0; valid_slot < BANK_DEPTH;
	                 valid_slot = valid_slot + 1) begin
	                if (completion_write0 && !completion_slot0[0] &&
	                    (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b1;
	                if (completion_write1 && !completion_slot1[0] &&
	                    (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b1;
	                if (completion_write2 && !completion_slot2[0] &&
	                    (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b1;
	                if (completion_write3 && !completion_slot3[0] &&
	                    (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b1;
	                if (completion_write0 && completion_slot0[0] &&
	                    (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b1;
	                if (completion_write1 && completion_slot1[0] &&
	                    (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b1;
	                if (completion_write2 && completion_slot2[0] &&
	                    (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b1;
	                if (completion_write3 && completion_slot3[0] &&
	                    (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b1;
	                if (alloc0_valid_i && !alloc0_id_i[0] &&
	                    (alloc0_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b0;
	                if (alloc1_valid_i && !alloc1_id_i[0] &&
	                    (alloc1_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_even_q[valid_slot] <= 1'b0;
	                if (alloc0_valid_i && alloc0_id_i[0] &&
	                    (alloc0_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b0;
	                if (alloc1_valid_i && alloc1_id_i[0] &&
	                    (alloc1_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
	                     BANK_INDEX_WIDTH'(valid_slot)))
	                    value_valid_odd_q[valid_slot] <= 1'b0;
	            end
	        end
	    end

    // Slow completion lanes are assigned first. ALU lanes are last so their
    // same-edge write path has the highest FF D-input priority.
    integer value_slot;
    always_ff @(posedge clk) begin
        for (value_slot = 0; value_slot < BANK_DEPTH; value_slot++) begin
            if (completion_write1 && !completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
	                    completion_data_i[COMPLETION_LSU];
            if (completion_write1 && !completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    completion_meta_i[COMPLETION_LSU].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write2 && !completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
	                    completion_data_i[COMPLETION_MUL];
            if (completion_write2 && !completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    completion_meta_i[COMPLETION_MUL].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write0 && !completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
	                    completion_data_i[COMPLETION_ALU];
            if (completion_write0 && !completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    completion_meta_i[COMPLETION_ALU].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write3 && !completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_even_q[value_slot] <=
	                    completion_data_i[COMPLETION_DUAL_ALU];
            if (completion_write3 && !completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    completion_meta_i[COMPLETION_DUAL_ALU].producer_id[
                        PRODUCER_ID_WIDTH-1];

            if (completion_write1 && completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
	                    completion_data_i[COMPLETION_LSU];
            if (completion_write1 && completion_slot1[0] &&
                (completion_slot1[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    completion_meta_i[COMPLETION_LSU].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write2 && completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
	                    completion_data_i[COMPLETION_MUL];
            if (completion_write2 && completion_slot2[0] &&
                (completion_slot2[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    completion_meta_i[COMPLETION_MUL].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write0 && completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
	                    completion_data_i[COMPLETION_ALU];
            if (completion_write0 && completion_slot0[0] &&
                (completion_slot0[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    completion_meta_i[COMPLETION_ALU].producer_id[
                        PRODUCER_ID_WIDTH-1];
            if (completion_write3 && completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_odd_q[value_slot] <=
	                    completion_data_i[COMPLETION_DUAL_ALU];
            if (completion_write3 && completion_slot3[0] &&
                (completion_slot3[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    completion_meta_i[COMPLETION_DUAL_ALU].producer_id[
                        PRODUCER_ID_WIDTH-1];

            // Allocation owns the final priority, matching value_valid_q.
            // Recording generation before completion lets Operand distinguish
            // an unavailable live value from a retired, reused producer slot.
            if (alloc0_valid_i && !alloc0_id_i[0] &&
                (alloc0_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    alloc0_id_i[PRODUCER_ID_WIDTH-1];
            if (alloc1_valid_i && !alloc1_id_i[0] &&
                (alloc1_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_even_q[value_slot] <=
                    alloc1_id_i[PRODUCER_ID_WIDTH-1];
            if (alloc0_valid_i && alloc0_id_i[0] &&
                (alloc0_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    alloc0_id_i[PRODUCER_ID_WIDTH-1];
            if (alloc1_valid_i && alloc1_id_i[0] &&
                (alloc1_id_i[PRODUCER_SLOT_WIDTH-1:1] ==
                 BANK_INDEX_WIDTH'(value_slot)))
                value_epoch_odd_q[value_slot] <=
                    alloc1_id_i[PRODUCER_ID_WIDTH-1];
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
    wire producer_slot_t lookup_slot0 =
        lookup_tag0_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t lookup_slot1 =
        lookup_tag1_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t lookup_slot2 =
        lookup_tag2_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t lookup_slot3 =
        lookup_tag3_i[PRODUCER_SLOT_WIDTH-1:0];
    wire [BANK_INDEX_WIDTH-1:0] lookup_index0 =
        lookup_slot0[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] lookup_index1 =
        lookup_slot1[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] lookup_index2 =
        lookup_slot2[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] lookup_index3 =
        lookup_slot3[PRODUCER_SLOT_WIDTH-1:1];
    wire producer_slot_t retire_slot0 =
        retire_id0_i[PRODUCER_SLOT_WIDTH-1:0];
    wire producer_slot_t retire_slot1 =
        retire_id1_i[PRODUCER_SLOT_WIDTH-1:0];
    wire [BANK_INDEX_WIDTH-1:0] retire_index0 =
        retire_slot0[PRODUCER_SLOT_WIDTH-1:1];
    wire [BANK_INDEX_WIDTH-1:0] retire_index1 =
        retire_slot1[PRODUCER_SLOT_WIDTH-1:1];
    wire retire_hit00 = completion_write0 &&
        (completion_meta_i[COMPLETION_ALU].producer_id == retire_id0_i);
    wire retire_hit01 = completion_write1 &&
        (completion_meta_i[COMPLETION_LSU].producer_id == retire_id0_i);
    wire retire_hit02 = completion_write2 &&
        (completion_meta_i[COMPLETION_MUL].producer_id == retire_id0_i);
    wire retire_hit03 = completion_write3 &&
        (completion_meta_i[COMPLETION_DUAL_ALU].producer_id == retire_id0_i);
    wire retire_hit10 = completion_write0 &&
        (completion_meta_i[COMPLETION_ALU].producer_id == retire_id1_i);
    wire retire_hit11 = completion_write1 &&
        (completion_meta_i[COMPLETION_LSU].producer_id == retire_id1_i);
    wire retire_hit12 = completion_write2 &&
        (completion_meta_i[COMPLETION_MUL].producer_id == retire_id1_i);
    wire retire_hit13 = completion_write3 &&
        (completion_meta_i[COMPLETION_DUAL_ALU].producer_id == retire_id1_i);
    wire [REGS_DATA_WIDTH-1:0] retire_stored_data0 = retire_slot0[0] ?
        value_odd_q[retire_index0] : value_even_q[retire_index0];
    wire [REGS_DATA_WIDTH-1:0] retire_stored_data1 = retire_slot1[0] ?
        value_odd_q[retire_index1] : value_even_q[retire_index1];

    assign read_data0_o = read_slot0_i[0] ?
        value_odd_q[read_index0] : value_even_q[read_index0];
    assign read_data1_o = read_slot1_i[0] ?
        value_odd_q[read_index1] : value_even_q[read_index1];
    assign read_data2_o = read_slot2_i[0] ?
        value_odd_q[read_index2] : value_even_q[read_index2];
    assign read_data3_o = read_slot3_i[0] ?
        value_odd_q[read_index3] : value_even_q[read_index3];
    assign read_epoch0_o = read_slot0_i[0] ?
        value_epoch_odd_q[read_index0] : value_epoch_even_q[read_index0];
    assign read_epoch1_o = read_slot1_i[0] ?
        value_epoch_odd_q[read_index1] : value_epoch_even_q[read_index1];
    assign read_epoch2_o = read_slot2_i[0] ?
        value_epoch_odd_q[read_index2] : value_epoch_even_q[read_index2];
    assign read_epoch3_o = read_slot3_i[0] ?
        value_epoch_odd_q[read_index3] : value_epoch_even_q[read_index3];
	    assign read_valid0_o = read_slot0_i[0] ?
	        value_valid_odd_q[read_index0] : value_valid_even_q[read_index0];
	    assign read_valid1_o = read_slot1_i[0] ?
	        value_valid_odd_q[read_index1] : value_valid_even_q[read_index1];
	    assign read_valid2_o = read_slot2_i[0] ?
	        value_valid_odd_q[read_index2] : value_valid_even_q[read_index2];
	    assign read_valid3_o = read_slot3_i[0] ?
	        value_valid_odd_q[read_index3] : value_valid_even_q[read_index3];
    // The registered allocation lookup asks whether a generation-qualified
    // value is resident. Its one-bit result writes only the newly allocated
    // RS entry's ready FF; it does not cross the current Select priority tree
    // or participate in Decode/frontend ready.
    assign lookup_resident0_o = lookup_slot0[0] ?
        (value_valid_odd_q[lookup_index0] &&
         (value_epoch_odd_q[lookup_index0] ==
          lookup_tag0_i[PRODUCER_ID_WIDTH-1])) :
        (value_valid_even_q[lookup_index0] &&
         (value_epoch_even_q[lookup_index0] ==
          lookup_tag0_i[PRODUCER_ID_WIDTH-1]));
    assign lookup_resident1_o = lookup_slot1[0] ?
        (value_valid_odd_q[lookup_index1] &&
         (value_epoch_odd_q[lookup_index1] ==
          lookup_tag1_i[PRODUCER_ID_WIDTH-1])) :
        (value_valid_even_q[lookup_index1] &&
         (value_epoch_even_q[lookup_index1] ==
          lookup_tag1_i[PRODUCER_ID_WIDTH-1]));
    assign lookup_resident2_o = lookup_slot2[0] ?
        (value_valid_odd_q[lookup_index2] &&
         (value_epoch_odd_q[lookup_index2] ==
          lookup_tag2_i[PRODUCER_ID_WIDTH-1])) :
        (value_valid_even_q[lookup_index2] &&
         (value_epoch_even_q[lookup_index2] ==
          lookup_tag2_i[PRODUCER_ID_WIDTH-1]));
    assign lookup_resident3_o = lookup_slot3[0] ?
        (value_valid_odd_q[lookup_index3] &&
         (value_epoch_odd_q[lookup_index3] ==
          lookup_tag3_i[PRODUCER_ID_WIDTH-1])) :
        (value_valid_even_q[lookup_index3] &&
         (value_epoch_even_q[lookup_index3] ==
          lookup_tag3_i[PRODUCER_ID_WIDTH-1]));
    // Ready is captured from raw narrow metadata on the same edge that the
    // registered completion lane captures data. Retire therefore bypasses the
    // just-registered lane by full producer identity instead of reading the
    // Value File one edge too early. The lane priority matches the write order.
    assign retire_data0_o = retire_hit03 ? completion_data_i[COMPLETION_DUAL_ALU] :
        retire_hit00 ? completion_data_i[COMPLETION_ALU] :
        retire_hit02 ? completion_data_i[COMPLETION_MUL] :
        retire_hit01 ? completion_data_i[COMPLETION_LSU] : retire_stored_data0;
    assign retire_data1_o = retire_hit13 ? completion_data_i[COMPLETION_DUAL_ALU] :
        retire_hit10 ? completion_data_i[COMPLETION_ALU] :
        retire_hit12 ? completion_data_i[COMPLETION_MUL] :
        retire_hit11 ? completion_data_i[COMPLETION_LSU] : retire_stored_data1;

`ifndef SYNTHESIS
    initial assert ((PRODUCER_NUM == 12) && ((PRODUCER_NUM % 2) == 0))
        else $fatal(1, "value file requires the 12-slot two-bank producer layout");
`endif
endmodule
