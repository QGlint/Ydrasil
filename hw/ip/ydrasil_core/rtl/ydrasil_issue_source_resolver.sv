module ydrasil_issue_source_resolver
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
) (
    input  ydrasil_source_desc_t         source_i,
    input  ydrasil_rob_source_state_t    state_i,
    input  wire [DATA_WIDTH-1:0]         value_i,
    input  wire [DATA_WIDTH-1:0]         arf_i,
    input  ydrasil_reservation_pkt_t     dtcm_reservation_i,
    input  wire                          early_main_valid_i,
    input  producer_id_t                 early_main_id_i,
    input  wire [REGS_ADDR_WIDTH-1:0]    early_main_rd_i,
    input  wire                          early_dual_valid_i,
    input  producer_id_t                 early_dual_id_i,
    input  wire [REGS_ADDR_WIDTH-1:0]    early_dual_rd_i,
    output wire                          ready_o,
    output wire [DATA_WIDTH-1:0]         data_o,
    output wire                          dtcm_hit_o,
    output wire                          early_main_hit_o,
    output wire                          early_dual_hit_o
);
    wire source_nonzero = source_i.arch_addr != '0;
    wire source_dtcm_key_match =
        {source_i.producer_class, source_i.producer_tag, source_i.arch_addr} ==
        {dtcm_reservation_i.result_class, dtcm_reservation_i.producer_id,
         dtcm_reservation_i.arch_addr};
    wire source_main_key_match =
        {source_i.producer_class, source_i.producer_tag, source_i.arch_addr} ==
        {RESULT_ALU, early_main_id_i, early_main_rd_i};
    wire source_dual_key_match =
        {source_i.producer_class, source_i.producer_tag, source_i.arch_addr} ==
        {RESULT_ALU, early_dual_id_i, early_dual_rd_i};
    assign dtcm_hit_o = &{source_i.used, source_nonzero, source_i.tag_valid,
        dtcm_reservation_i.valid, dtcm_reservation_i.producer_tracked,
        source_dtcm_key_match};
    assign early_main_hit_o = &{source_i.used, source_nonzero,
        source_i.tag_valid, early_main_valid_i, source_main_key_match};
    assign early_dual_hit_o = &{source_i.used, source_nonzero,
        source_i.tag_valid, early_dual_valid_i, source_dual_key_match};
    assign ready_o = !source_i.used || (source_i.arch_addr == '0) ||
        !state_i.live || state_i.done || dtcm_hit_o ||
        early_main_hit_o || early_dual_hit_o;
    assign data_o = (source_i.used && (source_i.arch_addr != '0) &&
        state_i.live) ? value_i : arf_i;
endmodule
