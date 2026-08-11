`timescale 1ns/1ps

module ydrasil_soc_tb #(
    parameter int UART_DIV = 16
);
    logic cpu_clk = 1'b0;
    logic apb_clk = 1'b0;
    logic cpu_rst_n = 1'b0;
    logic apb_rst_n = 1'b0;
    logic uart0_rx = 1'b1;
    logic uart1_rx = 1'b1;
    logic spi_miso;
    logic [31:0] gpio_external = '0;

    wire uart0_tx;
    wire uart1_tx;
    wire spi_sclk;
    wire spi_mosi;
    wire [3:0] spi_cs_n;
    wire i2c_scl_drive_low;
    wire i2c_sda_drive_low;
    wire i2c_scl = i2c_scl_drive_low ? 1'b0 : 1'b1;
    wire i2c_sda = i2c_sda_drive_low ? 1'b0 : 1'b1;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;
    wire [31:0] gpio_i = (gpio_o & gpio_oe) |
        (gpio_external & ~gpio_oe);
    wire coremark_active;

    string itcm_file;
    string dtcm_file;
    string uart0_rx_text;
    integer uart_start_apb_cycles = 100000;
    integer max_cpu_cycles = 200000;
    integer local_wave_start = -1;
    integer local_wave_end = -1;
    integer cpu_cycles = 0;
    integer retired_instructions = 0;
    logic [31:0] stop_pc = '0;
    bit stop_pc_enable = 1'b0;
    bit coremark_seen = 1'b0;
    bit finish_on_coremark = 1'b0;
    bit uart_debug = 1'b0;
    bit core_debug = 1'b0;
    logic [2:0] uart_rx_state_prev = '0;

    always #3.333 cpu_clk = ~cpu_clk;
    always #10 apb_clk = ~apb_clk;

    assign spi_miso = spi_mosi;

    ydrasil_soc_core #(
        .UART0_BIT_PERIOD_OVERRIDE(UART_DIV)
    ) u_soc (
        .cpu_clk_i(cpu_clk),
        .cpu_rst_n_i(cpu_rst_n),
        .apb_clk_i(apb_clk),
        .apb_rst_n_i(apb_rst_n),
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe),
        .uart0_rx_i(uart0_rx),
        .uart0_tx_o(uart0_tx),
        .uart1_rx_i(uart1_rx),
        .uart1_tx_o(uart1_tx),
        .spi_miso_i(spi_miso),
        .spi_sclk_o(spi_sclk),
        .spi_mosi_o(spi_mosi),
        .spi_cs_n_o(spi_cs_n),
        .i2c_scl_i(i2c_scl),
        .i2c_sda_i(i2c_sda),
        .i2c_scl_drive_low_o(i2c_scl_drive_low),
        .i2c_sda_drive_low_o(i2c_sda_drive_low),
        .coremark_active_o(coremark_active)
    );

    task automatic uart0_send_byte(input byte data);
        integer bit_index;
        begin
            uart0_rx = 1'b0;
            repeat (UART_DIV) @(posedge apb_clk);
            for (bit_index = 0; bit_index < 8; bit_index++) begin
                uart0_rx = data[bit_index];
                repeat (UART_DIV) @(posedge apb_clk);
            end
            uart0_rx = 1'b1;
            repeat (UART_DIV) @(posedge apb_clk);
        end
    endtask

    initial begin : configure_test
        logic [31:0] stop_pc_arg;
        void'($value$plusargs("uart_start_apb_cycles=%d",
            uart_start_apb_cycles));
        void'($value$plusargs("max_cpu_cycles=%d", max_cpu_cycles));
        void'($value$plusargs("local_wave_start=%d", local_wave_start));
        void'($value$plusargs("local_wave_end=%d", local_wave_end));
        void'($value$plusargs("gpio_input=%h", gpio_external));
        finish_on_coremark = $test$plusargs("finish_on_coremark");
        uart_debug = $test$plusargs("uart_debug");
        core_debug = $test$plusargs("core_debug");
        if ($value$plusargs("stop_pc=%h", stop_pc_arg)) begin
            stop_pc = stop_pc_arg;
            stop_pc_enable = 1'b1;
        end

        if (local_wave_start >= 0 && local_wave_end > local_wave_start) begin
            $dumpfile("ydrasil_soc_local.vcd");
            $dumpvars(0,
                cpu_clk, cpu_cycles, u_soc.irq,
                u_soc.retire0_valid, u_soc.retire0_pc,
                u_soc.retire1_valid, u_soc.retire1_pc,
                u_soc.u_core.if_resume_pc,
                u_soc.u_core.if_id_valid, u_soc.u_core.if_id_pc,
                u_soc.u_core.if_id1_valid, u_soc.u_core.if_id1_pc,
                u_soc.u_core.id_ex_valid, u_soc.u_core.id_instr_addr,
                u_soc.u_core.dual_id_ex_valid,
                u_soc.u_core.dual_id_ex_pc,
                u_soc.u_core.ex_pc_redirect,
                u_soc.u_core.ex_pc_redirect_target,
                u_soc.u_core.ex_bp_train_pkt,
                u_soc.u_core.rob_head_id,
                u_soc.u_core.u_ctrl.queue_head_q,
                u_soc.u_core.u_ctrl.queue_tail_q,
                u_soc.u_core.u_ctrl.queue_count_q,
                u_soc.u_core.u_ctrl.producer_valid_q,
                u_soc.u_core.u_ctrl.producer_done_q,
                u_soc.u_core.u_ctrl.producer_pc_q,
                u_soc.u_core.u_ctrl.serial_pending_q,
                u_soc.u_core.u_ydrasil_execute_stage.agu_req_i,
                u_soc.u_core.u_ydrasil_execute_stage.agu_recovery_keep,
                u_soc.u_core.lsu_req_pkt,
                u_soc.u_core.dtcm_load_valid,
                u_soc.u_core.dtcm_load_addr,
                u_soc.u_core.lsu_completion_valid,
                u_soc.u_core.lsu_completion_producer_id,
                u_soc.u_core.lsu_completion_producer_tracked,
                u_soc.u_core.u_ydrasil_load_store_unit.queue_enqueue,
                u_soc.u_core.u_ydrasil_load_store_unit.queue_dequeue,
                u_soc.u_core.u_ydrasil_load_store_unit.queue_count_q,
                u_soc.u_core.u_ydrasil_load_store_unit.queue_head_q,
                u_soc.u_core.u_ydrasil_load_store_unit.queue_tail_q,
                u_soc.u_core.u_ydrasil_load_store_unit.active_pkt,
                u_soc.u_core.u_ydrasil_load_store_unit.dtcm_load_fire,
                u_soc.u_core.u_ydrasil_load_store_unit.load_s1_valid_q,
                u_soc.u_core.u_ydrasil_load_store_unit.
                    load_s1_producer_id_q,
                u_soc.u_core.u_ydrasil_load_store_unit.recovery_pending_q,
                u_soc.u_core.u_ydrasil_load_store_unit.
                    recovery_head_slot_q,
                u_soc.u_core.u_ydrasil_load_store_unit.
                    recovery_branch_slot_q);
            $dumpoff;
        end

        repeat (8) @(posedge apb_clk);
        #1;
        if ($value$plusargs("itcmfile=%s", itcm_file)) begin
            $display("[SOC TB] loading ITCM: %s", itcm_file);
            $readmemh(itcm_file,
                u_soc.u_core.u_ydrasil_mems.u_itcm.u_impl.mem_r);
        end
        if ($value$plusargs("dtcmfile=%s", dtcm_file)) begin
            $display("[SOC TB] loading DTCM: %s", dtcm_file);
            $readmemh(dtcm_file,
                u_soc.u_core.u_ydrasil_mems.u_dtcm.u_impl.mem_r);
        end
        apb_rst_n = 1'b1;
        repeat (4) @(posedge cpu_clk);
        cpu_rst_n = 1'b1;
    end

    always @(posedge apb_clk) begin
        if (uart_debug && apb_rst_n) begin
            if (u_soc.u_mmio.u_uart0.rx_state_q != uart_rx_state_prev)
                $display("[SOC TB] UART0 RX state=%0d timer=%0d line=%0d",
                    u_soc.u_mmio.u_uart0.rx_state_q,
                    u_soc.u_mmio.u_uart0.rx_timer_q,
                    u_soc.u_mmio.u_uart0.rx_sync_q);
            if (u_soc.u_mmio.u_uart0.rx_fifo_push)
                $display("[SOC TB] UART0 RX byte=%02x count=%0d",
                    u_soc.u_mmio.u_uart0.rx_shift_q,
                    u_soc.u_mmio.u_uart0.rx_count_q);
        end
        uart_rx_state_prev <= u_soc.u_mmio.u_uart0.rx_state_q;
    end

    initial begin : uart0_stimulus
        integer char_index;
        wait (cpu_rst_n && apb_rst_n);
        if ($value$plusargs("uart0_rx_text=%s", uart0_rx_text)) begin
            repeat (uart_start_apb_cycles) @(posedge apb_clk);
            for (char_index = 0; char_index < uart0_rx_text.len();
                 char_index++)
                uart0_send_byte(uart0_rx_text[char_index]);
        end
    end

    initial begin : uart0_console_decoder
        byte received_byte;
        integer bit_index;
        forever begin
            @(negedge uart0_tx);
            repeat (UART_DIV + (UART_DIV / 2)) @(posedge apb_clk);
            for (bit_index = 0; bit_index < 8; bit_index++) begin
                received_byte[bit_index] = uart0_tx;
                repeat (UART_DIV) @(posedge apb_clk);
            end
            if (uart0_tx)
                $write("%c", received_byte);
        end
    end

    always @(posedge cpu_clk) begin
        if (!cpu_rst_n) begin
            cpu_cycles <= 0;
            retired_instructions <= 0;
            coremark_seen <= 1'b0;
        end else begin
            cpu_cycles <= cpu_cycles + 1;
            retired_instructions <= retired_instructions +
                u_soc.retire0_valid + u_soc.retire1_valid;
            if (coremark_active)
                coremark_seen <= 1'b1;

            if (stop_pc_enable &&
                ((u_soc.retire0_valid && u_soc.retire0_pc == stop_pc) ||
                 (u_soc.retire1_valid && u_soc.retire1_pc == stop_pc))) begin
                $display("\n[SOC TB] stop PC %08x retired after %0d cycles",
                    stop_pc, cpu_cycles);
                $finish;
            end
            if (finish_on_coremark && coremark_seen && !coremark_active) begin
                $display("\n[SOC TB] CoreMark completed after %0d total cycles, workload cycles=%0d",
                    cpu_cycles, u_soc.coremark_cycles);
                $finish;
            end
            if (cpu_cycles >= max_cpu_cycles) begin
                $display("\n[SOC TB] timeout after %0d cycles, retired=%0d, pc0=%08x/%0d pc1=%08x/%0d",
                    cpu_cycles, retired_instructions,
                    u_soc.retire0_pc, u_soc.retire0_valid,
                    u_soc.retire1_pc, u_soc.retire1_valid);
                $display("[SOC TB] UART0 tx_count=%0d busy=%0d timer=%0d",
                    u_soc.u_mmio.u_uart0.tx_count_q,
                    u_soc.u_mmio.u_uart0.tx_busy_q,
                    u_soc.u_mmio.u_uart0.tx_timer_q);
                $display("[SOC TB] UART0 rx_count=%0d state=%0d timer=%0d divisor=%0d ier=%02x; PLIC pending=%02x enable=%02x",
                    u_soc.u_mmio.u_uart0.rx_count_q,
                    u_soc.u_mmio.u_uart0.rx_state_q,
                    u_soc.u_mmio.u_uart0.rx_timer_q,
                    u_soc.u_mmio.u_uart0.divisor_q,
                    u_soc.u_mmio.u_uart0.ier_q,
                    u_soc.u_mmio.u_plic.pending_q,
                    u_soc.u_mmio.u_plic.enable_q);
                $display("[SOC TB] core frontend=%08x if0=%08x/%0d if1=%08x/%0d laneA=%08x/%0d laneB=%08x/%0d backend_empty=%0d rob_count=%0d",
                    u_soc.u_core.if_resume_pc,
                    u_soc.u_core.if_id_pc, u_soc.u_core.if_id_valid,
                    u_soc.u_core.if_id1_pc, u_soc.u_core.if_id1_valid,
                    u_soc.u_core.id_instr_addr, u_soc.u_core.id_ex_valid,
                    u_soc.u_core.dual_id_ex_pc,
                    u_soc.u_core.dual_id_ex_valid,
                    u_soc.u_core.backend_empty,
                    u_soc.u_core.u_ctrl.queue_count_q);
                $display("[SOC TB] trap state=%0d stall=%0d redirect=%0d mepc=%08x mstatus=%08x mie=%08x mip=%08x irq=%03b",
                    u_soc.u_core.u_ydrasil_exception_stage.
                        u_exception_ctrl.state_q,
                    u_soc.u_core.trap_ctrl_pkt.stall,
                    u_soc.u_core.trap_ctrl_pkt.redirect,
                    u_soc.u_core.trap_csr_state_pkt.mepc,
                    u_soc.u_core.trap_csr_state_pkt.mstatus,
                    u_soc.u_core.trap_csr_state_pkt.mie,
                    u_soc.u_core.trap_csr_state_pkt.mip,
                    u_soc.irq);
                $display("[SOC TB] ROB head=%0d pc=%08x done=%0d class=%0d valid=%03x done_vec=%03x serial=%0d recover=%0d",
                    u_soc.u_core.u_ctrl.queue_head_q,
                    u_soc.u_core.u_ctrl.producer_pc_q[
                        u_soc.u_core.u_ctrl.queue_head_q],
                    u_soc.u_core.u_ctrl.producer_done_q[
                        u_soc.u_core.u_ctrl.queue_head_q],
                    u_soc.u_core.u_ctrl.producer_result_class_q[
                        u_soc.u_core.u_ctrl.queue_head_q],
                    u_soc.u_core.u_ctrl.producer_valid_q,
                    u_soc.u_core.u_ctrl.producer_done_q,
                    u_soc.u_core.u_ctrl.serial_pending_q,
                    u_soc.u_core.u_ctrl.recovering_q);
                $display("[SOC TB] issue dep=%0d/%0d lsu=%0d/%0d src_wait=%04b pipe_room=%0d dispatch=%0d/%0d redirect_pending=%0d",
                    u_soc.u_core.issue_dependency_wait,
                    u_soc.u_core.issue_dependency_wait1,
                    u_soc.u_core.issue_lsu_struct_stall,
                    u_soc.u_core.issue_lsu_struct_stall1,
                    {u_soc.u_core.issue_src3_wait,
                     u_soc.u_core.issue_src2_wait,
                     u_soc.u_core.issue_src1_wait,
                     u_soc.u_core.issue_src0_wait},
                    u_soc.u_core.issue_pipe_has_room,
                    u_soc.u_core.dispatch_ready,
                    u_soc.u_core.dispatch_two_ready,
                    u_soc.u_core.ex_pc_redirect || u_soc.u_core.id_fence_i);
                $finish;
            end
        end
    end

    always @(posedge cpu_clk) begin
        if (local_wave_start >= 0 && cpu_cycles == local_wave_start) begin
            $display("[SOC TB] local wave start at cycle %0d", cpu_cycles);
            $dumpon;
        end
        if (local_wave_end >= 0 && cpu_cycles == local_wave_end) begin
            $dumpoff;
            $display("[SOC TB] local wave end at cycle %0d", cpu_cycles);
        end
    end

    always @(posedge cpu_clk) begin
        if (core_debug && coremark_seen && !coremark_active) begin
            if (u_soc.retire0_valid || u_soc.retire1_valid)
                $display("[SOC CORE] retire pc0=%08x/%0d pc1=%08x/%0d rob_head=%0d count=%0d",
                    u_soc.retire0_pc, u_soc.retire0_valid,
                    u_soc.retire1_pc, u_soc.retire1_valid,
                    u_soc.u_core.u_ctrl.queue_head_q,
                    u_soc.u_core.u_ctrl.queue_count_q);
            if (u_soc.u_core.dtcm_load_valid)
                $display("[SOC CORE] load launch addr=%08x producer=%0d head=%0d",
                    u_soc.u_core.dtcm_load_addr,
                    u_soc.u_core.u_ydrasil_load_store_unit.
                        load_launch_producer_id,
                    u_soc.u_core.rob_head_id);
            if (u_soc.u_core.lsu_completion_valid)
                $display("[SOC CORE] load complete producer=%0d tracked=%0d data=%08x",
                    u_soc.u_core.lsu_completion_producer_id,
                    u_soc.u_core.lsu_completion_producer_tracked,
                    u_soc.u_core.lsu_completion_data);
            if (u_soc.u_core.ex_pc_redirect)
                $display("[SOC CORE] branch redirect pc=%08x target=%08x producer=%0d head=%0d",
                    u_soc.u_core.ex_bp_train_pkt.pc,
                    u_soc.u_core.ex_pc_redirect_target,
                    u_soc.u_core.ex_bp_train_pkt.producer_id,
                    u_soc.u_core.rob_head_id);
        end
    end
endmodule
