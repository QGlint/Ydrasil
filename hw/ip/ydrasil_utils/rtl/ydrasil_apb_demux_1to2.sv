module ydrasil_apb_demux_1to2
import ydrasil_apb_pkg::*;
#(
    parameter logic [APB_ADDR_WIDTH-1:0] SLAVE0_ADDR_BASE = '0,
    parameter logic [APB_ADDR_WIDTH-1:0] SLAVE0_ADDR_MASK = '0,
    parameter logic [APB_ADDR_WIDTH-1:0] SLAVE1_ADDR_BASE = '0,
    parameter logic [APB_ADDR_WIDTH-1:0] SLAVE1_ADDR_MASK = '0
) (
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    output ydrasil_apb_req_pkt_t slave0_req_o,
    input  ydrasil_apb_rsp_pkt_t slave0_rsp_i,
    output ydrasil_apb_req_pkt_t slave1_req_o,
    input  ydrasil_apb_rsp_pkt_t slave1_rsp_i
);
    wire slave0_select =
        (apb_req_i.paddr & SLAVE0_ADDR_MASK) == SLAVE0_ADDR_BASE;
    wire slave1_select = !slave0_select &&
        ((apb_req_i.paddr & SLAVE1_ADDR_MASK) == SLAVE1_ADDR_BASE);

    always_comb begin
        slave0_req_o = apb_req_i;
        slave1_req_o = apb_req_i;
        slave0_req_o.psel = apb_req_i.psel && slave0_select;
        slave1_req_o.psel = apb_req_i.psel && slave1_select;

        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        apb_rsp_o.pslverr = apb_req_i.psel && apb_req_i.penable;
        if (slave0_select)
            apb_rsp_o = slave0_rsp_i;
        else if (slave1_select)
            apb_rsp_o = slave1_rsp_i;
    end
endmodule
