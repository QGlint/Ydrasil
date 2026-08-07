module ydrasil_issue_source_resolver
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
) (
    input  ydrasil_source_desc_t         source_i,
    input  wire [DATA_WIDTH-1:0]         value_i,
    input  wire                          value_epoch_i,
    input  wire [DATA_WIDTH-1:0]         arf_i,
    input  ydrasil_reservation_pkt_t     dtcm_reservation_i,
    input  ydrasil_reservation_pkt_t     mdu_reservation_i,
    input  wire [DATA_WIDTH-1:0]         mdu_bypass_data_i,
    input  ydrasil_completion_meta_t     mdu_completion_i,
    input  wire [DATA_WIDTH-1:0]         mdu_completion_data_i,
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
    ,output wire                         mdu_hit_o
);
    wire source_nonzero = source_i.arch_addr != '0;
    // The generation-qualified producer ID is the functional identity. Class
    // and architectural destination are metadata checks, not mux selectors.
    wire source_dtcm_key_match =
        source_i.producer_tag == dtcm_reservation_i.producer_id;
    wire source_main_key_match =
        source_i.producer_tag == early_main_id_i;
    wire source_dual_key_match =
        source_i.producer_tag == early_dual_id_i;
    wire source_mdu_key_match =
        source_i.producer_tag == mdu_reservation_i.producer_id;
    wire source_mdu_completion_key_match =
        source_i.producer_tag == mdu_completion_i.producer_id;
    wire source_value_epoch_match = value_epoch_i ==
        source_i.producer_tag[PRODUCER_ID_WIDTH-1];
    assign dtcm_hit_o = &{source_i.used, source_nonzero, source_i.tag_valid,
        dtcm_reservation_i.valid, dtcm_reservation_i.producer_tracked,
        source_dtcm_key_match};
    assign early_main_hit_o = &{source_i.used, source_nonzero,
        source_i.tag_valid, early_main_valid_i, source_main_key_match};
    assign early_dual_hit_o = &{source_i.used, source_nonzero,
        source_i.tag_valid, early_dual_valid_i, source_dual_key_match};
    assign mdu_hit_o = &{source_i.used, source_nonzero, source_i.tag_valid,
        mdu_reservation_i.valid, mdu_reservation_i.producer_tracked,
        source_mdu_key_match};
    wire mdu_completion_hit = &{source_i.used, source_nonzero,
        source_i.tag_valid, mdu_completion_i.valid,
        mdu_completion_i.producer_tracked, source_mdu_completion_key_match};
    assign ready_o = !source_i.used || (source_i.arch_addr == '0) ||
        !source_i.tag_valid || source_i.ready || dtcm_hit_o ||
        early_main_hit_o || early_dual_hit_o || mdu_hit_o ||
        mdu_completion_hit;
    assign data_o = mdu_completion_hit ? mdu_completion_data_i :
        mdu_hit_o ? mdu_bypass_data_i :
        (source_i.used && (source_i.arch_addr != '0) &&
         source_i.tag_valid && source_value_epoch_match) ? value_i : arf_i;

`ifndef SYNTHESIS
    always_comb begin
        if (dtcm_hit_o) begin
            assert (source_i.producer_class == dtcm_reservation_i.result_class)
                else $fatal(1, "DTCM wakeup producer class mismatch");
            assert (source_i.arch_addr == dtcm_reservation_i.arch_addr)
                else $fatal(1, "DTCM wakeup destination mismatch");
        end
        if (early_main_hit_o) begin
            assert (source_i.producer_class == RESULT_ALU)
                else $fatal(1, "main ALU wakeup producer class mismatch");
            assert (source_i.arch_addr == early_main_rd_i)
                else $fatal(1, "main ALU wakeup destination mismatch");
        end
        if (early_dual_hit_o) begin
            assert (source_i.producer_class == RESULT_ALU)
                else $fatal(1, "dual ALU wakeup producer class mismatch");
            assert (source_i.arch_addr == early_dual_rd_i)
                else $fatal(1, "dual ALU wakeup destination mismatch");
        end
        if (mdu_hit_o) begin
            assert (source_i.producer_class == RESULT_MDU)
                else $fatal(1, "MDU bypass producer class mismatch");
            assert (source_i.arch_addr == mdu_reservation_i.arch_addr)
                else $fatal(1, "MDU bypass destination mismatch");
        end
        if (mdu_completion_hit) begin
            assert (source_i.producer_class == RESULT_MDU)
                else $fatal(1, "MDU completion producer class mismatch");
        end
    end
`endif
endmodule
