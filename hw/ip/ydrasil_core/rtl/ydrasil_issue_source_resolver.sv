module ydrasil_issue_source_resolver
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
) (
    input  ydrasil_source_desc_t         source_i,
    input  wire [DATA_WIDTH-1:0]         value_i,
    input  wire                          value_epoch_i,
    input  wire                          value_valid_i,
    input  wire [DATA_WIDTH-1:0]         arf_i,
    input  ydrasil_commit_pkt_t          commit_pkt_i,
    input  ydrasil_commit_pkt_t          commit_pkt1_i,
    input  ydrasil_completion_meta_t     completion_meta_i [COMPLETION_LANES],
    input  wire [DATA_WIDTH-1:0]         completion_data_i [COMPLETION_LANES],
    output wire                          ready_o,
    output wire [DATA_WIDTH-1:0]         data_o,
    output wire                          data_valid_o
);
    wire source_nonzero = source_i.arch_addr != '0;
    wire source_value_epoch_match = value_epoch_i ==
        source_i.producer_tag[PRODUCER_ID_WIDTH-1];
    // Allocation records the current slot generation even before data is
    // present. A mismatching generation therefore proves this producer has
    // retired and the slot has been reused, making ARF the legal source.
    wire source_slot_reallocated = source_i.tag_valid &&
        !source_value_epoch_match;
    wire source_value_hit = source_i.used && source_nonzero &&
        source_i.tag_valid && value_valid_i && source_value_epoch_match;
    wire commit0_arch_hit = source_i.used && source_nonzero &&
        commit_pkt_i.valid && commit_pkt_i.writes_gpr &&
        (source_i.arch_addr == commit_pkt_i.rd_addr);
    wire commit1_arch_hit = source_i.used && source_nonzero &&
        commit_pkt1_i.valid && commit_pkt1_i.writes_gpr &&
        (source_i.arch_addr == commit_pkt1_i.rd_addr);
    // A tagged source may only consume its own retiring producer. An untagged
    // source was renamed after the RAT clear and therefore consumes the
    // youngest same-cycle architectural commit (lane 1 has priority).
    wire commit0_hit = commit0_arch_hit &&
        (!source_i.tag_valid ||
         (source_i.producer_tag == commit_pkt_i.producer_id));
    wire commit1_hit = commit1_arch_hit &&
        (!source_i.tag_valid ||
         (source_i.producer_tag == commit_pkt1_i.producer_id));
    wire [COMPLETION_LANES-1:0] completion_hit;
    genvar completion_idx;
    generate
        for (completion_idx = 0; completion_idx < COMPLETION_LANES;
             completion_idx = completion_idx + 1) begin : g_completion_hit
            assign completion_hit[completion_idx] = source_i.used &&
                source_nonzero && source_i.tag_valid &&
                completion_meta_i[completion_idx].valid &&
                completion_meta_i[completion_idx].producer_tracked &&
                (source_i.producer_tag ==
                 completion_meta_i[completion_idx].producer_id);
        end
    endgenerate
    assign ready_o = !source_i.used || (source_i.arch_addr == '0) ||
        !source_i.tag_valid || source_i.ready || source_slot_reallocated;
    assign data_o = completion_hit[COMPLETION_DUAL_ALU] ?
            completion_data_i[COMPLETION_DUAL_ALU] :
        completion_hit[COMPLETION_ALU] ?
            completion_data_i[COMPLETION_ALU] :
        completion_hit[COMPLETION_MUL] ?
            completion_data_i[COMPLETION_MUL] :
        completion_hit[COMPLETION_LSU] ?
            completion_data_i[COMPLETION_LSU] :
        source_value_hit ? value_i :
        commit1_hit ? commit_pkt1_i.value :
        commit0_hit ? commit_pkt_i.value : arf_i;
    // When a different generation of the same architectural register retires,
    // ARF is not a legal fallback for a still-tagged source in this cycle.
    assign data_valid_o = !source_i.used || !source_nonzero ||
        !source_i.tag_valid || (|completion_hit) ||
        source_value_hit || source_slot_reallocated ||
        commit0_hit || commit1_hit;
endmodule
