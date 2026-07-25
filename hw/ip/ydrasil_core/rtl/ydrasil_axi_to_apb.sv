module ydrasil_axi_to_apb
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  ydrasil_axi_lite_m2s_pkt_t   axi_m2s_i,
    output ydrasil_axi_lite_s2m_pkt_t   axi_s2m_o,
    output ydrasil_apb_req_pkt_t        apb_req_o,
    input  ydrasil_apb_rsp_pkt_t        apb_rsp_i
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_WRITE_COLLECT,
        S_WRITE_SETUP,
        S_WRITE_ACCESS,
        S_WRITE_RESP,
        S_READ_SETUP,
        S_READ_ACCESS,
        S_READ_RESP
    } state_t;

    state_t state_q;
    logic [BUS_ADDR_WIDTH-1:0] addr_q;
    logic [BUS_DATA_WIDTH-1:0] wdata_q;
    logic [3:0] wstrb_q;
    logic [2:0] prot_q;
    logic aw_have_q;
    logic w_have_q;
    logic [BUS_DATA_WIDTH-1:0] rdata_q;
    logic [1:0] resp_q;

    wire write_collect = (state_q == S_IDLE) || (state_q == S_WRITE_COLLECT);
    wire aw_ready = write_collect && !aw_have_q;
    wire w_ready = write_collect && !w_have_q;
    wire aw_fire = axi_m2s_i.awvalid && aw_ready;
    wire w_fire = axi_m2s_i.wvalid && w_ready;
    wire ar_fire = axi_m2s_i.arvalid && axi_s2m_o.arready;
    wire apb_fire = apb_req_o.psel && apb_req_o.penable && apb_rsp_i.pready;

    always_comb begin
        axi_s2m_o = '0;
        axi_s2m_o.awready = aw_ready;
        axi_s2m_o.wready = w_ready;
        axi_s2m_o.arready = (state_q == S_IDLE) && !axi_m2s_i.awvalid &&
            !axi_m2s_i.wvalid;
        axi_s2m_o.bvalid = (state_q == S_WRITE_RESP);
        axi_s2m_o.bresp = resp_q;
        axi_s2m_o.rvalid = (state_q == S_READ_RESP);
        axi_s2m_o.rdata = rdata_q;
        axi_s2m_o.rresp = resp_q;
    end

    always_comb begin
        apb_req_o = '0;
        apb_req_o.paddr = addr_q;
        apb_req_o.pwdata = wdata_q;
        apb_req_o.pstrb = wstrb_q;
        apb_req_o.pprot = prot_q;
        apb_req_o.pwrite = (state_q == S_WRITE_SETUP) ||
            (state_q == S_WRITE_ACCESS);
        apb_req_o.psel = (state_q == S_WRITE_SETUP) ||
            (state_q == S_WRITE_ACCESS) || (state_q == S_READ_SETUP) ||
            (state_q == S_READ_ACCESS);
        apb_req_o.penable = (state_q == S_WRITE_ACCESS) ||
            (state_q == S_READ_ACCESS);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            addr_q <= '0;
            wdata_q <= '0;
            wstrb_q <= '0;
            prot_q <= '0;
            aw_have_q <= 1'b0;
            w_have_q <= 1'b0;
            rdata_q <= '0;
            resp_q <= 2'b00;
        end else begin
            unique case (state_q)
                S_IDLE, S_WRITE_COLLECT: begin
                    if (aw_fire) begin
                        addr_q <= axi_m2s_i.awaddr;
                        prot_q <= axi_m2s_i.awprot;
                        aw_have_q <= 1'b1;
                    end
                    if (w_fire) begin
                        wdata_q <= axi_m2s_i.wdata;
                        wstrb_q <= axi_m2s_i.wstrb;
                        w_have_q <= 1'b1;
                    end
                    if ((aw_have_q || aw_fire) && (w_have_q || w_fire)) begin
                        state_q <= S_WRITE_SETUP;
                        aw_have_q <= 1'b0;
                        w_have_q <= 1'b0;
                    end else if (aw_have_q || aw_fire || w_have_q || w_fire) begin
                        state_q <= S_WRITE_COLLECT;
                    end else if (ar_fire) begin
                        addr_q <= axi_m2s_i.araddr;
                        prot_q <= axi_m2s_i.arprot;
                        wdata_q <= '0;
                        wstrb_q <= '0;
                        state_q <= S_READ_SETUP;
                    end
                end
                S_WRITE_SETUP: state_q <= S_WRITE_ACCESS;
                S_WRITE_ACCESS: begin
                    if (apb_fire) begin
                        resp_q <= apb_rsp_i.pslverr ? 2'b10 : 2'b00;
                        state_q <= S_WRITE_RESP;
                    end
                end
                S_WRITE_RESP: begin
                    if (axi_m2s_i.bready) begin
                        resp_q <= 2'b00;
                        state_q <= S_IDLE;
                    end
                end
                S_READ_SETUP: state_q <= S_READ_ACCESS;
                S_READ_ACCESS: begin
                    if (apb_fire) begin
                        rdata_q <= apb_rsp_i.prdata;
                        resp_q <= apb_rsp_i.pslverr ? 2'b10 : 2'b00;
                        state_q <= S_READ_RESP;
                    end
                end
                S_READ_RESP: begin
                    if (axi_m2s_i.rready) begin
                        resp_q <= 2'b00;
                        state_q <= S_IDLE;
                    end
                end
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule
