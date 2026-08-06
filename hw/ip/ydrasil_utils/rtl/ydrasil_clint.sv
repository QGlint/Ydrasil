module ydrasil_clint
import ydrasil_apb_pkg::*;
#(
    parameter logic [31:0] BASE_ADDR = 32'h0200_0000
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  ydrasil_apb_req_pkt_t   apb_req_i,
    output ydrasil_apb_rsp_pkt_t   apb_rsp_o,
    output wire                    software_irq_o,
    output wire                    timer_irq_o
);
    localparam logic [31:0] MSIP_ADDR = BASE_ADDR + 32'h0000_0000;
    localparam logic [31:0] MTIMECMP_LO_ADDR = BASE_ADDR + 32'h0000_4000;
    localparam logic [31:0] MTIMECMP_HI_ADDR = BASE_ADDR + 32'h0000_4004;
    localparam logic [31:0] MTIME_LO_ADDR = BASE_ADDR + 32'h0000_BFF8;
    localparam logic [31:0] MTIME_HI_ADDR = BASE_ADDR + 32'h0000_BFFC;

    logic msip_q;
    logic [63:0] mtime_q;
    logic [63:0] mtimecmp_q;
    wire apb_access = apb_req_i.psel && apb_req_i.penable;
    wire [31:0] apb_write_mask = {
        {8{apb_req_i.pstrb[3]}}, {8{apb_req_i.pstrb[2]}},
        {8{apb_req_i.pstrb[1]}}, {8{apb_req_i.pstrb[0]}}};
    wire [31:0] mtimecmp_lo_write =
        (mtimecmp_q[31:0] & ~apb_write_mask) |
        (apb_req_i.pwdata & apb_write_mask);
    wire [31:0] mtimecmp_hi_write =
        (mtimecmp_q[63:32] & ~apb_write_mask) |
        (apb_req_i.pwdata & apb_write_mask);
    wire [31:0] mtime_lo_write =
        (mtime_q[31:0] & ~apb_write_mask) |
        (apb_req_i.pwdata & apb_write_mask);
    wire [31:0] mtime_hi_write =
        (mtime_q[63:32] & ~apb_write_mask) |
        (apb_req_i.pwdata & apb_write_mask);

    wire address_valid =
        (apb_req_i.paddr == MSIP_ADDR) ||
        (apb_req_i.paddr == MTIMECMP_LO_ADDR) ||
        (apb_req_i.paddr == MTIMECMP_HI_ADDR) ||
        (apb_req_i.paddr == MTIME_LO_ADDR) ||
        (apb_req_i.paddr == MTIME_HI_ADDR);

    always_comb begin
        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        unique case (apb_req_i.paddr)
            MSIP_ADDR: apb_rsp_o.prdata = {31'b0, msip_q};
            MTIMECMP_LO_ADDR: apb_rsp_o.prdata = mtimecmp_q[31:0];
            MTIMECMP_HI_ADDR: apb_rsp_o.prdata = mtimecmp_q[63:32];
            MTIME_LO_ADDR: apb_rsp_o.prdata = mtime_q[31:0];
            MTIME_HI_ADDR: apb_rsp_o.prdata = mtime_q[63:32];
            default: apb_rsp_o.prdata = '0;
        endcase
        apb_rsp_o.pslverr = apb_access && !address_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_q <= 1'b0;
            mtime_q <= 64'b0;
            mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
        end else begin
            mtime_q <= mtime_q + 64'd1;
            if (apb_access && apb_req_i.pwrite && address_valid) begin
                unique case (apb_req_i.paddr)
                    MSIP_ADDR: begin
                        if (apb_req_i.pstrb[0])
                            msip_q <= apb_req_i.pwdata[0];
                    end
                    MTIMECMP_LO_ADDR:
                        mtimecmp_q[31:0] <= mtimecmp_lo_write;
                    MTIMECMP_HI_ADDR:
                        mtimecmp_q[63:32] <= mtimecmp_hi_write;
                    MTIME_LO_ADDR:
                        mtime_q[31:0] <= mtime_lo_write;
                    MTIME_HI_ADDR:
                        mtime_q[63:32] <= mtime_hi_write;
                    default: begin
                    end
                endcase
            end
        end
    end

    assign software_irq_o = msip_q;
    assign timer_irq_o = (mtime_q >= mtimecmp_q);
endmodule
