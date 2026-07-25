`timescale 1ns/1ns

module ydrasil_bus_irq_tb
import ydrasil_pkg::*;
import ydrasil_axi_pkg::*;
import ydrasil_apb_pkg::*;
(
`ifdef VERILATOR_CC
    input wire clk,
    input wire rst_n
`endif
);
`ifndef VERILATOR_CC
    logic clk;
    logic apb_clk;
    logic rst_n;
    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end
    initial begin
        apb_clk = 1'b0;
        forever #3 apb_clk = ~apb_clk;
    end
    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end
`endif
`ifdef VERILATOR_CC
    logic apb_clk;
    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n)
            apb_clk <= 1'b0;
        else
            apb_clk <= ~apb_clk;
    end
`endif

    ydrasil_axi_lite_m2s_pkt_t axi_m2s;
    ydrasil_axi_lite_s2m_pkt_t axi_s2m;
    ydrasil_apb_req_pkt_t bridge_apb_req;
    ydrasil_apb_rsp_pkt_t bridge_apb_rsp;
    logic [2:0] configured_wait_q;
    logic [2:0] wait_count_q;
    logic model_error_q;
    logic [31:0] model_rdata_q;
    logic setup_seen_q;
    logic [31:0] held_addr_q;

    ydrasil_axi_to_apb u_bridge (
        .axi_clk_i(clk),
        .axi_rst_n_i(rst_n),
        .axi_m2s_i(axi_m2s),
        .axi_s2m_o(axi_s2m),
        .apb_clk_i(apb_clk),
        .apb_rst_n_i(rst_n),
        .apb_req_o(bridge_apb_req),
        .apb_rsp_i(bridge_apb_rsp)
    );

    always_comb begin
        bridge_apb_rsp = '0;
        bridge_apb_rsp.pready = (wait_count_q == 0);
        bridge_apb_rsp.prdata = model_rdata_q;
        bridge_apb_rsp.pslverr = model_error_q;
    end

    always_ff @(posedge apb_clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_count_q <= '0;
            setup_seen_q <= 1'b0;
            held_addr_q <= '0;
        end else begin
            if (bridge_apb_req.psel && !bridge_apb_req.penable) begin
                wait_count_q <= configured_wait_q;
                setup_seen_q <= 1'b1;
                held_addr_q <= bridge_apb_req.paddr;
            end else if (bridge_apb_req.psel && bridge_apb_req.penable &&
                         (wait_count_q != 0)) begin
                wait_count_q <= wait_count_q - 1'b1;
            end
            if (bridge_apb_req.penable) begin
                if (!setup_seen_q)
                    $fatal(1, "APB access phase occurred without setup phase");
                if (bridge_apb_req.paddr != held_addr_q)
                    $fatal(1, "APB address changed while transfer was active");
            end
            if (bridge_apb_req.psel && bridge_apb_req.penable &&
                bridge_apb_rsp.pready)
                setup_seen_q <= 1'b0;
        end
    end

    task automatic axi_write_split(
        input [31:0] addr,
        input [31:0] data,
        input [3:0] strb,
        input bit data_first,
        output [1:0] response
    );
        begin
            @(negedge clk);
            axi_m2s.bready = 1'b1;
            if (data_first) begin
                axi_m2s.wdata = data;
                axi_m2s.wstrb = strb;
                axi_m2s.wvalid = 1'b1;
                while (!axi_s2m.wready) @(posedge clk);
                @(negedge clk);
                axi_m2s.wvalid = 1'b0;
                repeat (2) @(posedge clk);
                @(negedge clk);
                axi_m2s.awaddr = addr;
                axi_m2s.awvalid = 1'b1;
                while (!axi_s2m.awready) @(posedge clk);
                @(negedge clk);
                axi_m2s.awvalid = 1'b0;
            end else begin
                axi_m2s.awaddr = addr;
                axi_m2s.awvalid = 1'b1;
                while (!axi_s2m.awready) @(posedge clk);
                @(negedge clk);
                axi_m2s.awvalid = 1'b0;
                repeat (2) @(posedge clk);
                @(negedge clk);
                axi_m2s.wdata = data;
                axi_m2s.wstrb = strb;
                axi_m2s.wvalid = 1'b1;
                while (!axi_s2m.wready) @(posedge clk);
                @(negedge clk);
                axi_m2s.wvalid = 1'b0;
            end
            while (!axi_s2m.bvalid) @(posedge clk);
            response = axi_s2m.bresp;
            @(negedge clk);
            axi_m2s.bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input [31:0] addr,
        output [31:0] data,
        output [1:0] response
    );
        begin
            @(negedge clk);
            axi_m2s.araddr = addr;
            axi_m2s.arvalid = 1'b1;
            axi_m2s.rready = 1'b1;
            while (!axi_s2m.arready) @(posedge clk);
            @(negedge clk);
            axi_m2s.arvalid = 1'b0;
            while (!axi_s2m.rvalid) @(posedge clk);
            data = axi_s2m.rdata;
            response = axi_s2m.rresp;
            @(negedge clk);
            axi_m2s.rready = 1'b0;
        end
    endtask

    ydrasil_apb_req_pkt_t clint_apb_req;
    ydrasil_apb_rsp_pkt_t clint_apb_rsp;
    wire clint_software_irq;
    wire clint_timer_irq;
    wire [1:0] clint_irq_axi;

    ydrasil_clint u_clint (
        .clk(apb_clk),
        .rst_n(rst_n),
        .apb_req_i(clint_apb_req),
        .apb_rsp_o(clint_apb_rsp),
        .software_irq_o(clint_software_irq),
        .timer_irq_o(clint_timer_irq)
    );

    ydrasil_cdc_sync #(.WIDTH(2)) u_clint_irq_sync (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .async_i({clint_timer_irq, clint_software_irq}),
        .sync_o(clint_irq_axi)
    );

    task automatic clint_write(
        input [31:0] addr,
        input [31:0] data,
        input [3:0] strb
    );
        begin
            @(negedge apb_clk);
            clint_apb_req = '0;
            clint_apb_req.psel = 1'b1;
            clint_apb_req.pwrite = 1'b1;
            clint_apb_req.paddr = addr;
            clint_apb_req.pwdata = data;
            clint_apb_req.pstrb = strb;
            @(posedge apb_clk);
            @(negedge apb_clk);
            clint_apb_req.penable = 1'b1;
            @(posedge apb_clk);
            if (!clint_apb_rsp.pready || clint_apb_rsp.pslverr)
                $fatal(1, "CLINT APB write failed addr=%08x", addr);
            @(negedge apb_clk);
            clint_apb_req = '0;
        end
    endtask

    logic [2:0] instret_inc_count;
    logic ex_csr_wen;
    logic [11:0] ex_csr_raddr;
    logic [11:0] ex_csr_waddr;
    logic [31:0] ex_csr_wdata;
    ydrasil_csr_write_pkt_t trap_csr_write;
    ydrasil_irq_pkt_t trap_irq;
    ydrasil_csr_trap_state_pkt_t trap_csr_state;
    wire [31:0] csr_ex_data;
    wire [2:0] csr_frm;
    wire csr_fp_enabled;
    ydrasil_exception_req_pkt_t exception_req;
    ydrasil_trap_ctrl_pkt_t trap_ctrl;
    logic [31:0] async_pc;

    ydrasil_registers_csr u_csr (
        .clk(clk),
        .rst_n(rst_n),
        .instret_inc_count_i(instret_inc_count),
        .ex_csr_wen_i(ex_csr_wen),
        .id_csr_raddr_i(ex_csr_raddr),
        .ex_csr_waddr_i(ex_csr_waddr),
        .ex_csr_data_i(ex_csr_wdata),
        .trap_csr_write_i(trap_csr_write),
        .irq_i(trap_irq),
        .fp_flags_valid_i(1'b0),
        .fp_flags_i(5'b0),
        .fp_state_dirty_i(1'b0),
        .frm_o(csr_frm),
        .fp_enabled_o(csr_fp_enabled),
        .trap_state_o(trap_csr_state),
        .csr_ex_data_o(csr_ex_data)
    );

    ydrasil_exception_ctrl u_exception_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .exception_req_i(exception_req),
        .irq_i(trap_irq),
        .csr_state_i(trap_csr_state),
        .backend_idle_i(1'b1),
        .async_pc_i(async_pc),
        .csr_write_o(trap_csr_write),
        .trap_ctrl_o(trap_ctrl)
    );

    task automatic csr_write(input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            ex_csr_waddr = addr;
            ex_csr_wdata = data;
            ex_csr_wen = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ex_csr_wen = 1'b0;
        end
    endtask

    task automatic run_interrupt(
        input ydrasil_irq_pkt_t request,
        input [31:0] expected_cause,
        input [31:0] expected_target
    );
        integer timeout;
        begin
            @(negedge clk);
            trap_irq = request;
            timeout = 0;
            while (!trap_ctrl.stall && timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!trap_ctrl.stall)
                $fatal(1, "enabled IRQ was not accepted");
            @(negedge clk);
            trap_irq = '0;
            timeout = 0;
            while (!trap_ctrl.redirect && timeout < 30) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!trap_ctrl.redirect)
                $fatal(1, "IRQ trap did not redirect");
            if (trap_ctrl.redirect_addr != expected_target)
                $fatal(1, "IRQ target mismatch got=%08x expected=%08x",
                    trap_ctrl.redirect_addr, expected_target);
            if (u_csr.mcause != expected_cause)
                $fatal(1, "mcause mismatch got=%08x expected=%08x",
                    u_csr.mcause, expected_cause);
            if (u_csr.mepc != async_pc)
                $fatal(1, "mepc mismatch got=%08x expected=%08x",
                    u_csr.mepc, async_pc);
            if (u_csr.mstatus[3] || !u_csr.mstatus[7])
                $fatal(1, "mstatus trap stacking is incorrect");
            @(negedge clk);
            exception_req = '0;
            exception_req.valid = 1'b1;
            exception_req.mret = 1'b1;
            @(posedge clk);
            @(negedge clk);
            exception_req = '0;
            timeout = 0;
            while (!trap_ctrl.redirect && timeout < 10) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!trap_ctrl.redirect || trap_ctrl.redirect_addr != async_pc)
                $fatal(1, "mret redirect failed");
            @(posedge clk);
            if (!u_csr.mstatus[3])
                $fatal(1, "mret did not restore MIE");
        end
    endtask

    logic [1:0] response;
    logic [31:0] read_data;
    ydrasil_irq_pkt_t irq_request;
    integer timer_timeout;
    initial begin
        axi_m2s = '0;
        configured_wait_q = '0;
        model_error_q = 1'b0;
        model_rdata_q = 32'h1234_5678;
        clint_apb_req = '0;
        instret_inc_count = '0;
        ex_csr_wen = 1'b0;
        ex_csr_raddr = '0;
        ex_csr_waddr = '0;
        ex_csr_wdata = '0;
        trap_irq = '0;
        exception_req = '0;
        async_pc = 32'h8000_0100;
        wait (rst_n);
        repeat (3) @(posedge clk);

        configured_wait_q = 3;
        axi_write_split(32'h8020_0040, 32'ha5a5_5a5a, 4'b1111, 1'b0,
            response);
        if (response != 2'b00)
            $fatal(1, "AXI write returned unexpected response");
        configured_wait_q = 2;
        axi_write_split(32'h8020_0020, 32'h1122_3344, 4'b0011, 1'b1,
            response);
        if (response != 2'b00)
            $fatal(1, "AXI data-first write failed");
        configured_wait_q = 2;
        model_rdata_q = 32'hcafe_f00d;
        axi_read(32'h8020_0000, read_data, response);
        if ((response != 2'b00) || (read_data != 32'hcafe_f00d))
            $fatal(1, "AXI/APB read failed data=%08x resp=%x", read_data,
                response);
        model_error_q = 1'b1;
        configured_wait_q = 0;
        axi_read(32'hdead_0000, read_data, response);
        if (response != 2'b10)
            $fatal(1, "APB PSLVERR was not converted to AXI SLVERR");
        model_error_q = 1'b0;

        clint_write(32'h0200_0000, 32'h1, 4'b0001);
        if (!clint_software_irq)
            $fatal(1, "MSIP set did not assert software IRQ");
        repeat (3) @(posedge clk);
        if (!clint_irq_axi[0])
            $fatal(1, "software IRQ was not synchronized to AXI clock domain");
        clint_write(32'h0200_0000, 32'h0, 4'b0000);
        if (!clint_software_irq)
            $fatal(1, "zero PSTRB modified MSIP");
        clint_write(32'h0200_0000, 32'h0, 4'b0001);
        if (clint_software_irq)
            $fatal(1, "MSIP clear did not deassert software IRQ");
        repeat (3) @(posedge clk);
        if (clint_irq_axi[0])
            $fatal(1, "software IRQ deassertion was not synchronized");

        clint_write(32'h0200_4004, 32'h0, 4'b1111);
        clint_write(32'h0200_4000, 32'd100, 4'b1111);
        clint_write(32'h0200_bffc, 32'h0, 4'b1111);
        clint_write(32'h0200_bff8, 32'h0, 4'b1111);
        if (clint_timer_irq)
            $fatal(1, "timer IRQ asserted before mtimecmp");
        timer_timeout = 0;
        while (!clint_timer_irq && timer_timeout < 130) begin
            @(posedge apb_clk);
            timer_timeout = timer_timeout + 1;
        end
        if (!clint_timer_irq)
            $fatal(1, "mtime did not reach mtimecmp");
        clint_write(32'h0200_bffc, 32'hffff_ffff, 4'b1111);
        clint_write(32'h0200_bff8, 32'hffff_fffd, 4'b1111);
        repeat (6) @(posedge apb_clk);
        if (u_clint.mtime_q[63:32] != 32'h0000_0000)
            $fatal(1, "mtime rollover failed value=%016x", u_clint.mtime_q);

        csr_write(CSR_MTVEC, 32'h0000_0101);
        csr_write(CSR_MIE, 32'h0000_0888);
        csr_write(CSR_MSTATUS, 32'h0000_0008);
        irq_request = '0;
        irq_request.software = 1'b1;
        irq_request.timer = 1'b1;
        irq_request.external = 1'b1;
        run_interrupt(irq_request, 32'h8000_000b, 32'h0000_012c);

        csr_write(CSR_MSTATUS, 32'h0000_0008);
        irq_request = '0;
        irq_request.timer = 1'b1;
        run_interrupt(irq_request, 32'h8000_0007, 32'h0000_011c);

        csr_write(CSR_MSTATUS, 32'h0000_0008);
        irq_request = '0;
        irq_request.software = 1'b1;
        run_interrupt(irq_request, 32'h8000_0003, 32'h0000_010c);

        csr_write(CSR_MIE, 32'h0);
        csr_write(CSR_MSTATUS, 32'h8);
        @(negedge clk);
        trap_irq.external = 1'b1;
        repeat (5) @(posedge clk);
        if (trap_ctrl.stall)
            $fatal(1, "masked external IRQ stalled the pipeline");
        trap_irq = '0;

        $display("BUS_IRQ_TEST_PASS");
        $finish;
    end

    initial begin
        wait (rst_n);
        repeat (3000) @(posedge clk);
        $fatal(1, "BUS_IRQ_TEST_TIMEOUT");
    end
endmodule
