module ydrasil_apb_uart
import ydrasil_apb_pkg::*;
#(
    parameter int CLOCK_FREQ_HZ = 50000000,
    parameter int RESET_BAUD = 115200,
    parameter int FIFO_DEPTH = 16,
    parameter int BIT_PERIOD_OVERRIDE = 0
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    input  wire                  rx_i,
    output wire                  tx_o,
    output wire                  irq_o
);
    localparam int PTR_WIDTH = $clog2(FIFO_DEPTH);
    localparam int COUNT_WIDTH = $clog2(FIFO_DEPTH + 1);
    localparam int RESET_DIV_VALUE =
        ((CLOCK_FREQ_HZ / RESET_BAUD) > 0) ?
        (CLOCK_FREQ_HZ / RESET_BAUD) : 1;

    localparam logic [2:0] REG_RBR_THR_DLL = 3'h0;
    localparam logic [2:0] REG_IER_DLM     = 3'h1;
    localparam logic [2:0] REG_IIR_FCR     = 3'h2;
    localparam logic [2:0] REG_LCR         = 3'h3;
    localparam logic [2:0] REG_MCR         = 3'h4;
    localparam logic [2:0] REG_LSR         = 3'h5;
    localparam logic [2:0] REG_MSR         = 3'h6;
    localparam logic [2:0] REG_SCR         = 3'h7;

    typedef enum logic [2:0] {
        RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP
    } rx_state_t;

    logic [7:0] tx_fifo [0:FIFO_DEPTH-1];
    logic [7:0] rx_fifo [0:FIFO_DEPTH-1];
    logic [PTR_WIDTH-1:0] tx_write_ptr_q;
    logic [PTR_WIDTH-1:0] tx_read_ptr_q;
    logic [PTR_WIDTH-1:0] rx_write_ptr_q;
    logic [PTR_WIDTH-1:0] rx_read_ptr_q;
    logic [COUNT_WIDTH-1:0] tx_count_q;
    logic [COUNT_WIDTH-1:0] rx_count_q;

    logic [15:0] divisor_q;
    logic [7:0] ier_q;
    logic [7:0] lcr_q;
    logic [7:0] mcr_q;
    logic [7:0] scr_q;
    logic [1:0] rx_trigger_q;
    logic overrun_error_q;
    logic parity_error_q;
    logic framing_error_q;

    logic rx_meta_q;
    logic rx_sync_q;
    rx_state_t rx_state_q;
    logic [15:0] rx_timer_q;
    logic [2:0] rx_bit_index_q;
    logic [7:0] rx_shift_q;
    logic rx_parity_q;

    logic tx_busy_q;
    logic [15:0] tx_timer_q;
    logic [3:0] tx_bit_index_q;
    logic [3:0] tx_frame_bits_q;
    logic [10:0] tx_frame_q;
    logic tx_line_q;
    logic [31:0] read_data;

    wire apb_write = apb_req_i.psel && apb_req_i.penable &&
        apb_req_i.pwrite;
    wire apb_read = apb_req_i.psel && apb_req_i.penable &&
        !apb_req_i.pwrite;
    wire [2:0] register_index = apb_req_i.paddr[4:2];
    wire dlab = lcr_q[7];
    wire [15:0] bit_period = (BIT_PERIOD_OVERRIDE != 0) ?
        16'(BIT_PERIOD_OVERRIDE) :
        ((divisor_q == 0) ? 16'd1 : divisor_q);
    wire [3:0] configured_data_bits = {2'b00, lcr_q[1:0]} + 4'd5;
    wire tx_fifo_push = apb_write &&
        (register_index == REG_RBR_THR_DLL) && !dlab &&
        (tx_count_q < COUNT_WIDTH'(FIFO_DEPTH));
    wire rx_fifo_pop = apb_read &&
        (register_index == REG_RBR_THR_DLL) && !dlab &&
        (rx_count_q != 0);
    wire rx_fifo_push = (rx_state_q == RX_STOP) &&
        (rx_timer_q == 0) &&
        ((rx_count_q < COUNT_WIDTH'(FIFO_DEPTH)) || rx_fifo_pop);
    wire tx_fifo_pop = !tx_busy_q && (tx_count_q != 0);
    wire rx_threshold =
        (rx_trigger_q == 2'b00) ? (rx_count_q >= 1) :
        (rx_trigger_q == 2'b01) ? (rx_count_q >= 4) :
        (rx_trigger_q == 2'b10) ? (rx_count_q >= 8) :
                                  (rx_count_q >= 14);
    wire line_status_irq = ier_q[2] &&
        (overrun_error_q || parity_error_q || framing_error_q);
    wire rx_irq = ier_q[0] && rx_threshold;
    wire tx_irq = ier_q[1] && (tx_count_q == 0) && !tx_busy_q;
    wire [7:0] lsr = {1'b0, ((tx_count_q == 0) && !tx_busy_q),
        (tx_count_q == 0), 1'b0, framing_error_q, parity_error_q,
        overrun_error_q, (rx_count_q != 0)};
    wire [7:0] iir = line_status_irq ? 8'hC6 :
        rx_irq ? 8'hC4 : tx_irq ? 8'hC2 : 8'hC1;

    always_ff @(posedge clk or negedge rst_n) begin
        integer frame_index;
        logic parity_bit;
        if (!rst_n) begin
            tx_write_ptr_q <= '0;
            tx_read_ptr_q <= '0;
            rx_write_ptr_q <= '0;
            rx_read_ptr_q <= '0;
            tx_count_q <= '0;
            rx_count_q <= '0;
            divisor_q <= 16'(RESET_DIV_VALUE);
            ier_q <= '0;
            lcr_q <= 8'h03;
            mcr_q <= '0;
            scr_q <= '0;
            rx_trigger_q <= '0;
            overrun_error_q <= 1'b0;
            parity_error_q <= 1'b0;
            framing_error_q <= 1'b0;
            rx_meta_q <= 1'b1;
            rx_sync_q <= 1'b1;
            rx_state_q <= RX_IDLE;
            rx_timer_q <= '0;
            rx_bit_index_q <= '0;
            rx_shift_q <= '0;
            rx_parity_q <= 1'b0;
            tx_busy_q <= 1'b0;
            tx_timer_q <= '0;
            tx_bit_index_q <= '0;
            tx_frame_bits_q <= '0;
            tx_frame_q <= '1;
            tx_line_q <= 1'b1;
        end else begin
            rx_meta_q <= rx_i;
            rx_sync_q <= rx_meta_q;

            if (apb_write) begin
                unique case (register_index)
                    REG_RBR_THR_DLL: begin
                        if (dlab)
                            divisor_q[7:0] <= apb_req_i.pwdata[7:0];
                    end
                    REG_IER_DLM: begin
                        if (dlab)
                            divisor_q[15:8] <= apb_req_i.pwdata[7:0];
                        else
                            ier_q <= apb_req_i.pwdata[7:0];
                    end
                    REG_IIR_FCR: begin
                        rx_trigger_q <= apb_req_i.pwdata[7:6];
                        if (apb_req_i.pwdata[1]) begin
                            rx_write_ptr_q <= '0;
                            rx_read_ptr_q <= '0;
                            rx_count_q <= '0;
                        end
                        if (apb_req_i.pwdata[2]) begin
                            tx_write_ptr_q <= '0;
                            tx_read_ptr_q <= '0;
                            tx_count_q <= '0;
                        end
                    end
                    REG_LCR: lcr_q <= apb_req_i.pwdata[7:0];
                    REG_MCR: mcr_q <= apb_req_i.pwdata[7:0];
                    REG_SCR: scr_q <= apb_req_i.pwdata[7:0];
                    default: ;
                endcase
            end

            if (apb_read && (register_index == REG_LSR)) begin
                overrun_error_q <= 1'b0;
                parity_error_q <= 1'b0;
                framing_error_q <= 1'b0;
            end

            if (tx_fifo_push) begin
                tx_fifo[tx_write_ptr_q] <= apb_req_i.pwdata[7:0];
                tx_write_ptr_q <= tx_write_ptr_q + 1'b1;
            end
            if (tx_fifo_pop)
                tx_read_ptr_q <= tx_read_ptr_q + 1'b1;
            unique case ({tx_fifo_push, tx_fifo_pop})
                2'b10: tx_count_q <= tx_count_q + 1'b1;
                2'b01: tx_count_q <= tx_count_q - 1'b1;
                default: ;
            endcase

            if (rx_fifo_pop)
                rx_read_ptr_q <= rx_read_ptr_q + 1'b1;

            if (tx_fifo_pop) begin
                tx_frame_q <= '1;
                tx_frame_q[0] <= 1'b0;
                parity_bit = lcr_q[5] ? ~lcr_q[4] : lcr_q[4];
                for (frame_index = 0; frame_index < 8; frame_index++) begin
                    if (frame_index < configured_data_bits) begin
                        tx_frame_q[frame_index + 1] <=
                            tx_fifo[tx_read_ptr_q][frame_index];
                        parity_bit = parity_bit ^
                            tx_fifo[tx_read_ptr_q][frame_index];
                    end
                end
                if (lcr_q[3]) begin
                    tx_frame_q[configured_data_bits + 1] <= parity_bit;
                    tx_frame_bits_q <= configured_data_bits +
                        (lcr_q[2] ? 4'd4 : 4'd3);
                end else begin
                    tx_frame_bits_q <= configured_data_bits +
                        (lcr_q[2] ? 4'd3 : 4'd2);
                end
                tx_busy_q <= 1'b1;
                tx_bit_index_q <= '0;
                tx_line_q <= 1'b0;
                tx_timer_q <= bit_period - 1'b1;
            end else if (tx_busy_q) begin
                if (tx_timer_q != 0) begin
                    tx_timer_q <= tx_timer_q - 1'b1;
                end else if (tx_bit_index_q + 1'b1 >= tx_frame_bits_q) begin
                    tx_busy_q <= 1'b0;
                    tx_line_q <= 1'b1;
                end else begin
                    tx_bit_index_q <= tx_bit_index_q + 1'b1;
                    tx_line_q <= tx_frame_q[tx_bit_index_q + 1'b1];
                    tx_timer_q <= bit_period - 1'b1;
                end
            end

            unique case (rx_state_q)
                RX_IDLE: begin
                    if (!rx_sync_q) begin
                        rx_state_q <= RX_START;
                        rx_timer_q <= bit_period >> 1;
                    end
                end
                RX_START: begin
                    if (rx_timer_q != 0)
                        rx_timer_q <= rx_timer_q - 1'b1;
                    else if (!rx_sync_q) begin
                        rx_state_q <= RX_DATA;
                        rx_timer_q <= bit_period - 1'b1;
                        rx_bit_index_q <= '0;
                        rx_shift_q <= '0;
                        rx_parity_q <= 1'b0;
                    end else begin
                        rx_state_q <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (rx_timer_q != 0) begin
                        rx_timer_q <= rx_timer_q - 1'b1;
                    end else begin
                        rx_shift_q[rx_bit_index_q] <= rx_sync_q;
                        rx_parity_q <= rx_parity_q ^ rx_sync_q;
                        rx_timer_q <= bit_period - 1'b1;
                        if (rx_bit_index_q + 1'b1 >= configured_data_bits)
                            rx_state_q <= lcr_q[3] ? RX_PARITY : RX_STOP;
                        else
                            rx_bit_index_q <= rx_bit_index_q + 1'b1;
                    end
                end
                RX_PARITY: begin
                    if (rx_timer_q != 0) begin
                        rx_timer_q <= rx_timer_q - 1'b1;
                    end else begin
                        parity_error_q <= rx_sync_q !=
                            (lcr_q[5] ? ~lcr_q[4] :
                            (rx_parity_q ^ lcr_q[4]));
                        rx_state_q <= RX_STOP;
                        rx_timer_q <= bit_period - 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_timer_q != 0) begin
                        rx_timer_q <= rx_timer_q - 1'b1;
                    end else begin
                        framing_error_q <= !rx_sync_q;
                        if (rx_fifo_push) begin
                            rx_fifo[rx_write_ptr_q] <= rx_shift_q;
                            rx_write_ptr_q <= rx_write_ptr_q + 1'b1;
                        end else begin
                            overrun_error_q <= 1'b1;
                        end
                        rx_state_q <= RX_IDLE;
                    end
                end
                default: rx_state_q <= RX_IDLE;
            endcase

            unique case ({rx_fifo_push, rx_fifo_pop})
                2'b10: rx_count_q <= rx_count_q + 1'b1;
                2'b01: rx_count_q <= rx_count_q - 1'b1;
                default: ;
            endcase
        end
    end

    always_comb begin
        read_data = '0;
        unique case (register_index)
            REG_RBR_THR_DLL:
                read_data[7:0] = dlab ? divisor_q[7:0] :
                    ((rx_count_q != 0) ? rx_fifo[rx_read_ptr_q] : 8'h00);
            REG_IER_DLM:
                read_data[7:0] = dlab ? divisor_q[15:8] : ier_q;
            REG_IIR_FCR: read_data[7:0] = iir;
            REG_LCR: read_data[7:0] = lcr_q;
            REG_MCR: read_data[7:0] = mcr_q;
            REG_LSR: read_data[7:0] = lsr;
            REG_MSR: read_data[7:0] = 8'h00;
            REG_SCR: read_data[7:0] = scr_q;
            default: ;
        endcase
    end

    assign tx_o = tx_line_q;
    assign irq_o = line_status_irq || rx_irq || tx_irq;
    assign apb_rsp_o.prdata = read_data;
    assign apb_rsp_o.pready = 1'b1;
    assign apb_rsp_o.pslverr = 1'b0;
endmodule
