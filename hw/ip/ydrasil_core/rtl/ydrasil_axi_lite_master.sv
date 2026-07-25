module ydrasil_axi_lite_master
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  ydrasil_mem_req_pkt_t        mem_req_i,
    output ydrasil_mem_rsp_pkt_t        mem_rsp_o,
    output ydrasil_axi_lite_m2s_pkt_t   axi_m2s_o,
    input  ydrasil_axi_lite_s2m_pkt_t   axi_s2m_i
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_WRITE_ADDR_DATA,
        S_WRITE_RESP,
        S_READ_ADDR,
        S_READ_DATA
    } state_t;

    state_t state_q;
    logic [BUS_ADDR_WIDTH-1:0] addr_q;
    logic [BUS_DATA_WIDTH-1:0] wdata_q;
    logic [3:0] wstrb_q;
    logic aw_done_q;
    logic w_done_q;

    wire aw_fire = axi_m2s_o.awvalid && axi_s2m_i.awready;
    wire w_fire = axi_m2s_o.wvalid && axi_s2m_i.wready;
    wire ar_fire = axi_m2s_o.arvalid && axi_s2m_i.arready;
    wire b_fire = axi_s2m_i.bvalid && axi_m2s_o.bready;
    wire r_fire = axi_s2m_i.rvalid && axi_m2s_o.rready;

    always_comb begin
        axi_m2s_o = '0;
        axi_m2s_o.awaddr = addr_q;
        axi_m2s_o.awprot = 3'b000;
        axi_m2s_o.wdata = wdata_q;
        axi_m2s_o.wstrb = wstrb_q;
        axi_m2s_o.araddr = addr_q;
        axi_m2s_o.arprot = 3'b000;

        unique case (state_q)
            S_WRITE_ADDR_DATA: begin
                axi_m2s_o.awvalid = !aw_done_q;
                axi_m2s_o.wvalid = !w_done_q;
            end
            S_WRITE_RESP: axi_m2s_o.bready = 1'b1;
            S_READ_ADDR: axi_m2s_o.arvalid = 1'b1;
            S_READ_DATA: axi_m2s_o.rready = 1'b1;
            default: begin
            end
        endcase
    end

    always_comb begin
        mem_rsp_o = '0;
        if ((state_q == S_WRITE_RESP) && b_fire) begin
            mem_rsp_o.valid = 1'b1;
            mem_rsp_o.error = axi_s2m_i.bresp[1];
        end else if ((state_q == S_READ_DATA) && r_fire) begin
            mem_rsp_o.valid = 1'b1;
            mem_rsp_o.rdata = axi_s2m_i.rdata;
            mem_rsp_o.error = axi_s2m_i.rresp[1];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            addr_q <= '0;
            wdata_q <= '0;
            wstrb_q <= '0;
            aw_done_q <= 1'b0;
            w_done_q <= 1'b0;
        end else begin
            unique case (state_q)
                S_IDLE: begin
                    aw_done_q <= 1'b0;
                    w_done_q <= 1'b0;
                    if (mem_req_i.valid) begin
                        addr_q <= mem_req_i.addr;
                        wdata_q <= mem_req_i.wdata;
                        wstrb_q <= mem_req_i.wmask;
                        state_q <= mem_req_i.write ?
                            S_WRITE_ADDR_DATA : S_READ_ADDR;
                    end
                end
                S_WRITE_ADDR_DATA: begin
                    if (aw_fire)
                        aw_done_q <= 1'b1;
                    if (w_fire)
                        w_done_q <= 1'b1;
                    if ((aw_done_q || aw_fire) && (w_done_q || w_fire))
                        state_q <= S_WRITE_RESP;
                end
                S_WRITE_RESP: begin
                    if (b_fire)
                        state_q <= S_IDLE;
                end
                S_READ_ADDR: begin
                    if (ar_fire)
                        state_q <= S_READ_DATA;
                end
                S_READ_DATA: begin
                    if (r_fire)
                        state_q <= S_IDLE;
                end
                default: state_q <= S_IDLE;
            endcase
        end
    end
endmodule
