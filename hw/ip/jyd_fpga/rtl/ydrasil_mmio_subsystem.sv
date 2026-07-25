module ydrasil_mmio_subsystem
import ydrasil_pkg::*;
(
    input  wire                         clk,
    input  wire                         cnt_clk,
    input  wire                         rst_n,
    input  ydrasil_axi_lite_m2s_pkt_t   axi_m2s_i,
    output ydrasil_axi_lite_s2m_pkt_t   axi_s2m_o,
    input  wire                         external_irq_i,
    output ydrasil_irq_pkt_t            irq_o,
    input  wire [63:0]                  virtual_sw_input,
    input  wire [7:0]                   virtual_key_input,
    output wire [39:0]                  virtual_seg_output,
    output wire [31:0]                  virtual_led_output
);
    ydrasil_apb_req_pkt_t apb_req;
    ydrasil_apb_req_pkt_t clint_apb_req;
    ydrasil_apb_req_pkt_t perip_apb_req;
    ydrasil_apb_rsp_pkt_t apb_rsp;
    ydrasil_apb_rsp_pkt_t clint_apb_rsp;
    ydrasil_apb_rsp_pkt_t perip_apb_rsp;
    wire software_irq;
    wire timer_irq;
    wire clint_select = (apb_req.paddr[31:16] == 16'h0200);
    wire perip_select = (apb_req.paddr[31:16] == 16'h8020);

    ydrasil_axi_to_apb u_axi_to_apb (
        .clk(clk),
        .rst_n(rst_n),
        .axi_m2s_i(axi_m2s_i),
        .axi_s2m_o(axi_s2m_o),
        .apb_req_o(apb_req),
        .apb_rsp_i(apb_rsp)
    );

    always_comb begin
        clint_apb_req = apb_req;
        perip_apb_req = apb_req;
        clint_apb_req.psel = apb_req.psel && clint_select;
        perip_apb_req.psel = apb_req.psel && perip_select;
        apb_rsp = '0;
        apb_rsp.pready = 1'b1;
        apb_rsp.pslverr = apb_req.psel && apb_req.penable;
        if (clint_select)
            apb_rsp = clint_apb_rsp;
        else if (perip_select)
            apb_rsp = perip_apb_rsp;
    end

    ydrasil_clint u_clint (
        .clk(clk),
        .rst_n(rst_n),
        .apb_req_i(clint_apb_req),
        .apb_rsp_o(clint_apb_rsp),
        .software_irq_o(software_irq),
        .timer_irq_o(timer_irq)
    );

    perip_bridge u_perip_bridge (
        .clk(clk),
        .cnt_clk(cnt_clk),
        .rst(!rst_n),
        .apb_req_i(perip_apb_req),
        .apb_rsp_o(perip_apb_rsp),
        .virtual_sw_input(virtual_sw_input),
        .virtual_key_input(virtual_key_input),
        .virtual_seg_output(virtual_seg_output),
        .virtual_led_output(virtual_led_output)
    );

    assign irq_o.software = software_irq;
    assign irq_o.timer = timer_irq;
    assign irq_o.external = external_irq_i;
endmodule
