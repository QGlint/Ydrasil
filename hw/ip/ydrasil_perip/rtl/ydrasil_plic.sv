module ydrasil_plic
import ydrasil_apb_pkg::*;
#(
    parameter int NUM_SOURCES = 8
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  ydrasil_apb_req_pkt_t       apb_req_i,
    output ydrasil_apb_rsp_pkt_t       apb_rsp_o,
    input  wire [NUM_SOURCES-1:0]      source_i,
    output wire                        irq_o
);
    localparam logic [15:0] REG_PENDING = 16'h0000;
    localparam logic [15:0] REG_ENABLE  = 16'h0004;
    localparam logic [15:0] REG_CLAIM   = 16'h0008;
    localparam logic [15:0] REG_FORCE   = 16'h000c;

    logic [NUM_SOURCES-1:0] pending_q;
    logic [NUM_SOURCES-1:0] enable_q;
    logic [NUM_SOURCES-1:0] force_q;
    logic [$clog2(NUM_SOURCES+1)-1:0] claim_id;
    integer source_idx;

    wire [15:0] reg_offset = apb_req_i.paddr[15:0];
    wire apb_access = apb_req_i.psel && apb_req_i.penable;
    wire apb_write = apb_access && apb_req_i.pwrite;
    wire claim_read = apb_access && !apb_req_i.pwrite &&
        (reg_offset == REG_CLAIM);
    wire address_valid = (reg_offset == REG_PENDING) ||
        (reg_offset == REG_ENABLE) || (reg_offset == REG_CLAIM) ||
        (reg_offset == REG_FORCE);

    always_comb begin
        claim_id = '0;
        for (source_idx = NUM_SOURCES-1; source_idx >= 0; source_idx = source_idx - 1)
            if (pending_q[source_idx] && enable_q[source_idx])
                claim_id = $clog2(NUM_SOURCES+1)'(source_idx + 1);

        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        unique case (reg_offset)
            REG_PENDING: apb_rsp_o.prdata = 32'(pending_q);
            REG_ENABLE:  apb_rsp_o.prdata = 32'(enable_q);
            REG_CLAIM:   apb_rsp_o.prdata = 32'(claim_id);
            REG_FORCE:   apb_rsp_o.prdata = 32'(force_q);
            default:     apb_rsp_o.prdata = '0;
        endcase
        apb_rsp_o.pslverr = apb_access && !address_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_q <= '0;
            enable_q <= '0;
            force_q <= '0;
        end else begin
            pending_q <= pending_q | source_i | force_q;
            if (claim_read && (claim_id != '0))
                pending_q[$clog2(NUM_SOURCES)'(claim_id - 1'b1)] <= 1'b0;
            if (apb_write) begin
                unique case (reg_offset)
                    REG_ENABLE: enable_q <= NUM_SOURCES'(apb_req_i.pwdata);
                    REG_CLAIM: begin
                        if ((apb_req_i.pwdata > 0) &&
                            (apb_req_i.pwdata <= NUM_SOURCES))
                            pending_q[$clog2(NUM_SOURCES)'(
                                apb_req_i.pwdata - 1'b1)] <= 1'b0;
                    end
                    REG_FORCE: force_q <= NUM_SOURCES'(apb_req_i.pwdata);
                    default: begin
                    end
                endcase
            end
        end
    end

    assign irq_o = |(pending_q & enable_q);
endmodule
