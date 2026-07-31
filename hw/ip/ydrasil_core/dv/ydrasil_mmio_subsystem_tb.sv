// Test-only MMIO composition.
//
// This mirrors the production subsystem and inserts a controllable PREADY
// delay at the peripheral APB response.  The production MMIO hierarchy is
// intentionally untouched; normal runs use a zero-cycle delay.
module ydrasil_mmio_subsystem_tb
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
import ydrasil_apb_pkg::*;
(
    input  wire                         axi_clk,
    input  wire                         apb_clk,
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
    ydrasil_apb_rsp_pkt_t perip_apb_rsp_raw;
    ydrasil_apb_rsp_pkt_t perip_apb_rsp;
    wire software_irq;
    wire timer_irq;
    wire [2:0] irq_apb = {external_irq_i, timer_irq, software_irq};
    wire [2:0] irq_axi;

    logic [7:0] perip_wait_cycles_cfg;
    logic [7:0] perip_wait_count_q;
    logic perip_access_active_q;
    logic [31:0] perip_hold_addr_q;
    logic perip_hold_write_q;
    logic [31:0] perip_hold_wdata_q;
    logic [3:0] perip_hold_mask_q;
    wire perip_setup = perip_apb_req.psel && !perip_apb_req.penable;
    wire perip_access = perip_apb_req.psel && perip_apb_req.penable;
    wire perip_pready = (perip_wait_count_q == '0);

    initial begin
        perip_wait_cycles_cfg = '0;
        void'($value$plusargs("perip_wait_cycles=%d", perip_wait_cycles_cfg));
    end

    always_comb begin
        perip_apb_rsp = perip_apb_rsp_raw;
        perip_apb_rsp.pready = perip_pready;
    end

    // The APB bundle originates at the full-core AXI/APB path.  Check it is
    // held through every injected wait cycle before allowing a response.
    always_ff @(posedge apb_clk or negedge rst_n) begin
        if (!rst_n) begin
            perip_wait_count_q <= '0;
            perip_access_active_q <= 1'b0;
            perip_hold_addr_q <= '0;
            perip_hold_write_q <= 1'b0;
            perip_hold_wdata_q <= '0;
            perip_hold_mask_q <= '0;
        end else if (perip_setup) begin
            if (perip_access_active_q && (perip_wait_count_q != '0))
                $fatal(1, "APB started a peripheral request before completion");
            perip_wait_count_q <= perip_wait_cycles_cfg;
            perip_access_active_q <= 1'b1;
            perip_hold_addr_q <= perip_apb_req.paddr;
            perip_hold_write_q <= perip_apb_req.pwrite;
            perip_hold_wdata_q <= perip_apb_req.pwdata;
            perip_hold_mask_q <= perip_apb_req.pstrb;
        end else if (perip_access) begin
            if (!perip_access_active_q)
                $fatal(1, "APB peripheral access occurred without setup");
            if ((perip_apb_req.paddr != perip_hold_addr_q) ||
                (perip_apb_req.pwrite != perip_hold_write_q) ||
                (perip_apb_req.pwdata != perip_hold_wdata_q) ||
                (perip_apb_req.pstrb != perip_hold_mask_q))
                $fatal(1, "APB peripheral request changed while PREADY was low");
            if (perip_wait_count_q != '0)
                perip_wait_count_q <= perip_wait_count_q - 1'b1;
            else
                perip_access_active_q <= 1'b0;
        end
    end

    ydrasil_axi_to_apb u_axi_to_apb (
        .axi_clk_i(axi_clk),
        .axi_rst_n_i(rst_n),
        .axi_m2s_i(axi_m2s_i),
        .axi_s2m_o(axi_s2m_o),
        .apb_clk_i(apb_clk),
        .apb_rst_n_i(rst_n),
        .apb_req_o(apb_req),
        .apb_rsp_i(apb_rsp)
    );

    ydrasil_apb_demux_1to2 #(
        .SLAVE0_ADDR_BASE(32'h0200_0000),
        .SLAVE0_ADDR_MASK(32'hffff_0000),
        .SLAVE1_ADDR_BASE(32'h8020_0000),
        .SLAVE1_ADDR_MASK(32'hffff_0000)
    ) u_apb_demux (
        .apb_req_i(apb_req),
        .apb_rsp_o(apb_rsp),
        .slave0_req_o(clint_apb_req),
        .slave0_rsp_i(clint_apb_rsp),
        .slave1_req_o(perip_apb_req),
        .slave1_rsp_i(perip_apb_rsp)
    );

    ydrasil_clint u_clint (
        .clk(apb_clk),
        .rst_n(rst_n),
        .apb_req_i(clint_apb_req),
        .apb_rsp_o(clint_apb_rsp),
        .software_irq_o(software_irq),
        .timer_irq_o(timer_irq)
    );

    perip_bridge u_perip_bridge (
        .clk(apb_clk),
        .rst(!rst_n),
        .apb_req_i(perip_apb_req),
        .apb_rsp_o(perip_apb_rsp_raw),
        .virtual_sw_input(virtual_sw_input),
        .virtual_key_input(virtual_key_input),
        .virtual_seg_output(virtual_seg_output),
        .virtual_led_output(virtual_led_output)
    );

    ydrasil_cdc_sync #(.WIDTH(3)) u_irq_sync (
        .clk_i(axi_clk),
        .rst_n_i(rst_n),
        .async_i(irq_apb),
        .sync_o(irq_axi)
    );

    assign irq_o.software = irq_axi[0];
    assign irq_o.timer = irq_axi[1];
    assign irq_o.external = irq_axi[2];
endmodule
