module ydrasil_axi_to_apb
import ydrasil_axi_pkg::*;
import ydrasil_apb_pkg::*;
(
    input  wire                         axi_clk_i,
    input  wire                         axi_rst_n_i,
    input  ydrasil_axi_lite_m2s_pkt_t   axi_m2s_i,
    output ydrasil_axi_lite_s2m_pkt_t   axi_s2m_o,
    input  wire                         apb_clk_i,
    input  wire                         apb_rst_n_i,
    output ydrasil_apb_req_pkt_t        apb_req_o,
    input  ydrasil_apb_rsp_pkt_t        apb_rsp_i
);
    typedef struct packed {
        logic                      write;
        logic [AXI_ADDR_WIDTH-1:0] addr;
        logic [AXI_DATA_WIDTH-1:0] wdata;
        logic [AXI_STRB_WIDTH-1:0] wstrb;
        logic [2:0]                prot;
    } bridge_req_t;

    typedef enum logic [2:0] {
        AXI_IDLE,
        AXI_WRITE_COLLECT,
        AXI_WAIT_RESPONSE,
        AXI_WRITE_RESPONSE,
        AXI_READ_RESPONSE
    } axi_state_t;

    typedef enum logic [1:0] {
        APB_IDLE,
        APB_SETUP,
        APB_ACCESS
    } apb_state_t;

    axi_state_t axi_state_q;
    apb_state_t apb_state_q;
    bridge_req_t req_axi_q;
    bridge_req_t req_apb_q;
    ydrasil_apb_rsp_pkt_t rsp_apb_q;
    logic [AXI_DATA_WIDTH-1:0] rsp_rdata_axi_q;
    logic [1:0] rsp_code_axi_q;
    logic aw_have_q;
    logic w_have_q;
    logic pending_write_q;
    logic req_toggle_axi_q;
    logic req_toggle_apb_seen_q;
    logic rsp_toggle_apb_q;
    logic rsp_toggle_axi_seen_q;
    wire req_toggle_apb_sync;
    wire rsp_toggle_axi_sync;

    wire write_collect = (axi_state_q == AXI_IDLE) ||
        (axi_state_q == AXI_WRITE_COLLECT);
    wire aw_ready = write_collect && !aw_have_q;
    wire w_ready = write_collect && !w_have_q;
    wire aw_fire = axi_m2s_i.awvalid && aw_ready;
    wire w_fire = axi_m2s_i.wvalid && w_ready;
    wire ar_fire = axi_m2s_i.arvalid && axi_s2m_o.arready;
    wire apb_fire = apb_req_o.psel && apb_req_o.penable && apb_rsp_i.pready;

    ydrasil_cdc_sync u_req_toggle_sync (
        .clk_i(apb_clk_i),
        .rst_n_i(apb_rst_n_i),
        .async_i(req_toggle_axi_q),
        .sync_o(req_toggle_apb_sync)
    );

    ydrasil_cdc_sync u_rsp_toggle_sync (
        .clk_i(axi_clk_i),
        .rst_n_i(axi_rst_n_i),
        .async_i(rsp_toggle_apb_q),
        .sync_o(rsp_toggle_axi_sync)
    );

    always_comb begin
        axi_s2m_o = '0;
        axi_s2m_o.awready = aw_ready;
        axi_s2m_o.wready = w_ready;
        axi_s2m_o.arready = (axi_state_q == AXI_IDLE) &&
            !axi_m2s_i.awvalid && !axi_m2s_i.wvalid;
        axi_s2m_o.bvalid = (axi_state_q == AXI_WRITE_RESPONSE);
        axi_s2m_o.bresp = rsp_code_axi_q;
        axi_s2m_o.rvalid = (axi_state_q == AXI_READ_RESPONSE);
        axi_s2m_o.rdata = rsp_rdata_axi_q;
        axi_s2m_o.rresp = rsp_code_axi_q;
    end

    always_comb begin
        apb_req_o = '0;
        apb_req_o.paddr = req_apb_q.addr;
        apb_req_o.pwdata = req_apb_q.wdata;
        apb_req_o.pstrb = req_apb_q.wstrb;
        apb_req_o.pprot = req_apb_q.prot;
        apb_req_o.pwrite = req_apb_q.write;
        apb_req_o.psel = (apb_state_q == APB_SETUP) ||
            (apb_state_q == APB_ACCESS);
        apb_req_o.penable = (apb_state_q == APB_ACCESS);
    end

    always_ff @(posedge axi_clk_i or negedge axi_rst_n_i) begin
        if (!axi_rst_n_i) begin
            axi_state_q <= AXI_IDLE;
            req_axi_q <= '0;
            aw_have_q <= 1'b0;
            w_have_q <= 1'b0;
            pending_write_q <= 1'b0;
            req_toggle_axi_q <= 1'b0;
            rsp_toggle_axi_seen_q <= 1'b0;
            rsp_rdata_axi_q <= '0;
            rsp_code_axi_q <= '0;
        end else begin
            unique case (axi_state_q)
                AXI_IDLE, AXI_WRITE_COLLECT: begin
                    if (aw_fire) begin
                        req_axi_q.addr <= axi_m2s_i.awaddr;
                        req_axi_q.prot <= axi_m2s_i.awprot;
                        aw_have_q <= 1'b1;
                    end
                    if (w_fire) begin
                        req_axi_q.wdata <= axi_m2s_i.wdata;
                        req_axi_q.wstrb <= axi_m2s_i.wstrb;
                        w_have_q <= 1'b1;
                    end
                    if ((aw_have_q || aw_fire) && (w_have_q || w_fire)) begin
                        req_axi_q.write <= 1'b1;
                        pending_write_q <= 1'b1;
                        req_toggle_axi_q <= ~req_toggle_axi_q;
                        aw_have_q <= 1'b0;
                        w_have_q <= 1'b0;
                        axi_state_q <= AXI_WAIT_RESPONSE;
                    end else if (aw_have_q || aw_fire || w_have_q || w_fire) begin
                        axi_state_q <= AXI_WRITE_COLLECT;
                    end else if (ar_fire) begin
                        req_axi_q.write <= 1'b0;
                        req_axi_q.addr <= axi_m2s_i.araddr;
                        req_axi_q.wdata <= '0;
                        req_axi_q.wstrb <= '0;
                        req_axi_q.prot <= axi_m2s_i.arprot;
                        pending_write_q <= 1'b0;
                        req_toggle_axi_q <= ~req_toggle_axi_q;
                        axi_state_q <= AXI_WAIT_RESPONSE;
                    end
                end
                AXI_WAIT_RESPONSE: begin
                    if (rsp_toggle_axi_sync != rsp_toggle_axi_seen_q) begin
                        rsp_toggle_axi_seen_q <= rsp_toggle_axi_sync;
                        rsp_rdata_axi_q <= rsp_apb_q.prdata;
                        rsp_code_axi_q <= rsp_apb_q.pslverr ? 2'b10 : 2'b00;
                        axi_state_q <= pending_write_q ?
                            AXI_WRITE_RESPONSE : AXI_READ_RESPONSE;
                    end
                end
                AXI_WRITE_RESPONSE: begin
                    if (axi_m2s_i.bready) begin
                        rsp_code_axi_q <= '0;
                        axi_state_q <= AXI_IDLE;
                    end
                end
                AXI_READ_RESPONSE: begin
                    if (axi_m2s_i.rready) begin
                        rsp_code_axi_q <= '0;
                        axi_state_q <= AXI_IDLE;
                    end
                end
                default: axi_state_q <= AXI_IDLE;
            endcase
        end
    end

    always_ff @(posedge apb_clk_i or negedge apb_rst_n_i) begin
        if (!apb_rst_n_i) begin
            apb_state_q <= APB_IDLE;
            req_apb_q <= '0;
            rsp_apb_q <= '0;
            req_toggle_apb_seen_q <= 1'b0;
            rsp_toggle_apb_q <= 1'b0;
        end else begin
            unique case (apb_state_q)
                APB_IDLE: begin
                    if (req_toggle_apb_sync != req_toggle_apb_seen_q) begin
                        req_toggle_apb_seen_q <= req_toggle_apb_sync;
                        req_apb_q <= req_axi_q;
                        apb_state_q <= APB_SETUP;
                    end
                end
                APB_SETUP: apb_state_q <= APB_ACCESS;
                APB_ACCESS: begin
                    if (apb_fire) begin
                        rsp_apb_q <= apb_rsp_i;
                        rsp_toggle_apb_q <= ~rsp_toggle_apb_q;
                        apb_state_q <= APB_IDLE;
                    end
                end
                default: apb_state_q <= APB_IDLE;
            endcase
        end
    end
endmodule
