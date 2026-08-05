module ydrasil_apb_spi
import ydrasil_apb_pkg::*;
#(
    parameter int NUM_CS = 4,
    parameter int FIFO_DEPTH = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    input  wire                  miso_i,
    output wire                  sclk_o,
    output wire                  mosi_o,
    output wire [NUM_CS-1:0]     cs_n_o,
    output wire                  irq_o
);
    localparam int PTR_WIDTH = $clog2(FIFO_DEPTH);
    localparam int COUNT_WIDTH = $clog2(FIFO_DEPTH + 1);

    localparam logic [3:0] REG_STATUS = 4'h0;
    localparam logic [3:0] REG_CLKDIV = 4'h1;
    localparam logic [3:0] REG_SPICMD = 4'h2;
    localparam logic [3:0] REG_SPIADR = 4'h3;
    localparam logic [3:0] REG_SPILEN = 4'h4;
    localparam logic [3:0] REG_SPIDUM = 4'h5;
    localparam logic [3:0] REG_TXFIFO = 4'h6;
    localparam logic [3:0] REG_RXFIFO = 4'h8;
    localparam logic [3:0] REG_INTCFG = 4'h9;
    localparam logic [3:0] REG_INTSTA = 4'hA;

    typedef enum logic [2:0] {
        SPI_IDLE, SPI_COMMAND, SPI_ADDRESS, SPI_DUMMY,
        SPI_DATA, SPI_FINISH
    } spi_state_t;

    // Keep the FIFO front in a register so RXFIFO remains a zero-extra-cycle
    // APB read.  The remaining entries live in synchronous block RAM.
    logic [31:0] tx_head_q;
    logic [31:0] rx_head_q;
    logic tx_head_valid_q;
    logic rx_head_valid_q;
    logic tx_word_stall_q;
    logic [31:0] tx_bram_rdata;
    logic [31:0] rx_bram_rdata;
    // The BRAM wrapper has a registered read output.  `*_rvalid_q` delays
    // cache refill until the cycle after the registered BRAM response.
    logic tx_bram_ren_q;
    logic rx_bram_ren_q;
    logic tx_bram_rvalid_q;
    logic rx_bram_rvalid_q;
    logic tx_bram_wen_q;
    logic rx_bram_wen_q;
    logic [PTR_WIDTH-1:0] tx_bram_raddr_q;
    logic [PTR_WIDTH-1:0] rx_bram_raddr_q;
    logic [PTR_WIDTH-1:0] tx_bram_waddr_q;
    logic [PTR_WIDTH-1:0] rx_bram_waddr_q;
    logic [31:0] tx_bram_wdata_q;
    logic [31:0] rx_bram_wdata_q;
    logic rx_bram_deferred_write_q;
    logic [PTR_WIDTH-1:0] rx_bram_deferred_addr_q;
    logic [31:0] rx_bram_deferred_data_q;
    logic [PTR_WIDTH-1:0] tx_write_ptr_q;
    logic [PTR_WIDTH-1:0] tx_read_ptr_q;
    logic [PTR_WIDTH-1:0] rx_write_ptr_q;
    logic [PTR_WIDTH-1:0] rx_read_ptr_q;
    logic [COUNT_WIDTH-1:0] tx_count_q;
    logic [COUNT_WIDTH-1:0] rx_count_q;

    logic [7:0] clock_divider_q;
    logic [31:0] command_q;
    logic [31:0] address_q;
    logic [5:0] command_length_q;
    logic [5:0] address_length_q;
    logic [15:0] data_length_q;
    logic [15:0] dummy_read_q;
    logic [15:0] dummy_write_q;
    logic [4:0] tx_irq_threshold_q;
    logic [4:0] rx_irq_threshold_q;
    logic interrupt_enable_q;

    spi_state_t state_q;
    logic transaction_read_q;
    logic [NUM_CS-1:0] chip_select_q;
    logic [15:0] divider_count_q;
    logic [15:0] segment_bits_q;
    logic [5:0] word_bit_index_q;
    logic [31:0] transmit_shift_q;
    logic [31:0] receive_shift_q;
    logic serial_clock_q;
    logic serial_data_q;
    logic end_event_q;
    logic [31:0] read_data;

    wire apb_write = apb_req_i.psel && apb_req_i.penable &&
        apb_req_i.pwrite;
    wire apb_read = apb_req_i.psel && apb_req_i.penable &&
        !apb_req_i.pwrite;
    wire [3:0] register_index = apb_req_i.paddr[5:2];
    wire tx_fifo_push = apb_write && (register_index == REG_TXFIFO) &&
        (tx_count_q < COUNT_WIDTH'(FIFO_DEPTH));
    wire rx_fifo_pop = apb_read && (register_index == REG_RXFIFO) &&
        (rx_count_q != 0) && rx_head_valid_q;
    wire fifo_clear = apb_write && (register_index == REG_STATUS) &&
        apb_req_i.pwdata[4];
    // The cached RX head normally preserves the old one-access APB read.
    // Only a read arriving during the synchronous refill is stretched.
    wire rx_fifo_read_wait = apb_read && (register_index == REG_RXFIFO) &&
        (rx_count_q != 0) && !rx_head_valid_q;
    wire divider_tick = divider_count_q == 0;
    wire busy = state_q != SPI_IDLE;
    wire tx_irq = tx_count_q < tx_irq_threshold_q;
    wire rx_irq = rx_count_q > rx_irq_threshold_q;
    wire [31:0] status_value = {
        8'(tx_count_q), 8'(rx_count_q), 8'h00,
        1'b0, (state_q == SPI_FINISH), (state_q == SPI_DATA),
        (state_q == SPI_DUMMY), 1'b0, (state_q == SPI_ADDRESS),
        (state_q == SPI_COMMAND), !busy};

    ydrasil_1r1w_bram #(
        .DEPTH(FIFO_DEPTH), .DATA_WIDTH(32), .ADDR_WIDTH(PTR_WIDTH),
        .INIT_VALUE('0)
    ) u_tx_fifo_bram (
        .clk(clk), .ren_i(tx_bram_ren_q),
        .raddr_i(tx_bram_raddr_q), .rdata_o(tx_bram_rdata),
        .wen_i(tx_bram_wen_q), .waddr_i(tx_bram_waddr_q),
        .wdata_i(tx_bram_wdata_q)
    );

    ydrasil_1r1w_bram #(
        .DEPTH(FIFO_DEPTH), .DATA_WIDTH(32), .ADDR_WIDTH(PTR_WIDTH),
        .INIT_VALUE('0)
    ) u_rx_fifo_bram (
        .clk(clk), .ren_i(rx_bram_ren_q),
        .raddr_i(rx_bram_raddr_q), .rdata_o(rx_bram_rdata),
        .wen_i(rx_bram_wen_q), .waddr_i(rx_bram_waddr_q),
        .wdata_i(rx_bram_wdata_q)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        logic [NUM_CS-1:0] requested_cs;
        logic start_read;
        logic start_write;
        logic [15:0] requested_dummy;
        logic transmit_fifo_pop;
        logic receive_fifo_push;
        logic [31:0] receive_fifo_data;
        if (!rst_n) begin
            tx_write_ptr_q <= '0;
            tx_read_ptr_q <= '0;
            rx_write_ptr_q <= '0;
            rx_read_ptr_q <= '0;
            tx_count_q <= '0;
            rx_count_q <= '0;
            tx_head_q <= '0;
            rx_head_q <= '0;
            tx_head_valid_q <= 1'b0;
            rx_head_valid_q <= 1'b0;
            tx_word_stall_q <= 1'b0;
            tx_bram_ren_q <= 1'b0;
            rx_bram_ren_q <= 1'b0;
            tx_bram_rvalid_q <= 1'b0;
            rx_bram_rvalid_q <= 1'b0;
            tx_bram_wen_q <= 1'b0;
            rx_bram_wen_q <= 1'b0;
            tx_bram_raddr_q <= '0;
            rx_bram_raddr_q <= '0;
            tx_bram_waddr_q <= '0;
            rx_bram_waddr_q <= '0;
            tx_bram_wdata_q <= '0;
            rx_bram_wdata_q <= '0;
            rx_bram_deferred_write_q <= 1'b0;
            rx_bram_deferred_addr_q <= '0;
            rx_bram_deferred_data_q <= '0;
            clock_divider_q <= 8'd3;
            command_q <= '0;
            address_q <= '0;
            command_length_q <= '0;
            address_length_q <= '0;
            data_length_q <= '0;
            dummy_read_q <= '0;
            dummy_write_q <= '0;
            tx_irq_threshold_q <= '0;
            rx_irq_threshold_q <= '0;
            interrupt_enable_q <= 1'b0;
            state_q <= SPI_IDLE;
            transaction_read_q <= 1'b0;
            chip_select_q <= '0;
            divider_count_q <= '0;
            segment_bits_q <= '0;
            word_bit_index_q <= '0;
            transmit_shift_q <= '0;
            receive_shift_q <= '0;
            serial_clock_q <= 1'b0;
            serial_data_q <= 1'b0;
            end_event_q <= 1'b0;
        end else begin
            end_event_q <= 1'b0;
            transmit_fifo_pop = 1'b0;
            receive_fifo_push = 1'b0;
            receive_fifo_data = '0;
            tx_bram_ren_q <= 1'b0;
            rx_bram_ren_q <= 1'b0;
            tx_bram_wen_q <= 1'b0;
            rx_bram_wen_q <= 1'b0;
            tx_bram_rvalid_q <= tx_bram_ren_q;
            rx_bram_rvalid_q <= rx_bram_ren_q;

            if (tx_bram_rvalid_q && !fifo_clear) begin
                tx_head_q <= tx_bram_rdata;
                tx_head_valid_q <= 1'b1;
            end
            if (rx_bram_rvalid_q && !fifo_clear) begin
                rx_head_q <= rx_bram_rdata;
                rx_head_valid_q <= 1'b1;
            end

            if (apb_write) begin
                unique case (register_index)
                    REG_CLKDIV: clock_divider_q <= apb_req_i.pwdata[7:0];
                    REG_SPICMD: command_q <= apb_req_i.pwdata;
                    REG_SPIADR: address_q <= apb_req_i.pwdata;
                    REG_SPILEN: begin
                        command_length_q <= apb_req_i.pwdata[5:0];
                        address_length_q <= apb_req_i.pwdata[13:8];
                        data_length_q <= apb_req_i.pwdata[31:16];
                    end
                    REG_SPIDUM: begin
                        dummy_read_q <= apb_req_i.pwdata[15:0];
                        dummy_write_q <= apb_req_i.pwdata[31:16];
                    end
                    REG_INTCFG: begin
                        tx_irq_threshold_q <= apb_req_i.pwdata[4:0];
                        rx_irq_threshold_q <= apb_req_i.pwdata[12:8];
                        interrupt_enable_q <= apb_req_i.pwdata[31];
                    end
                    default: ;
                endcase
            end

            if (apb_write && (register_index == REG_STATUS)) begin
                start_read = apb_req_i.pwdata[0] || apb_req_i.pwdata[2];
                start_write = apb_req_i.pwdata[1] || apb_req_i.pwdata[3];
                requested_cs = NUM_CS'(apb_req_i.pwdata[8 +: NUM_CS]);
                if (apb_req_i.pwdata[4]) begin
                    state_q <= SPI_IDLE;
                    chip_select_q <= '0;
                    serial_clock_q <= 1'b0;
                    tx_write_ptr_q <= '0;
                    tx_read_ptr_q <= '0;
                    rx_write_ptr_q <= '0;
                    rx_read_ptr_q <= '0;
                    tx_count_q <= '0;
                    rx_count_q <= '0;
                    tx_head_q <= '0;
                    rx_head_q <= '0;
                    tx_head_valid_q <= 1'b0;
                    rx_head_valid_q <= 1'b0;
                    tx_word_stall_q <= 1'b0;
                    tx_bram_ren_q <= 1'b0;
                    rx_bram_ren_q <= 1'b0;
                    tx_bram_rvalid_q <= 1'b0;
                    rx_bram_rvalid_q <= 1'b0;
                    tx_bram_wen_q <= 1'b0;
                    rx_bram_wen_q <= 1'b0;
                    rx_bram_deferred_write_q <= 1'b0;
                end else if (!busy && (start_read || start_write)) begin
                    transaction_read_q <= start_read;
                    chip_select_q <= (requested_cs == '0) ?
                        NUM_CS'(1) : requested_cs;
                    divider_count_q <= {8'h00, clock_divider_q};
                    serial_clock_q <= 1'b0;
                    word_bit_index_q <= '0;
                    receive_shift_q <= '0;
                    tx_word_stall_q <= 1'b0;
                    if (command_length_q != 0) begin
                        state_q <= SPI_COMMAND;
                        segment_bits_q <= {10'h000, command_length_q};
                        transmit_shift_q <= command_q;
                        serial_data_q <= command_q[31];
                    end else if (address_length_q != 0) begin
                        state_q <= SPI_ADDRESS;
                        segment_bits_q <= {10'h000, address_length_q};
                        transmit_shift_q <= address_q;
                        serial_data_q <= address_q[31];
                    end else begin
                        requested_dummy = start_read ? dummy_read_q : dummy_write_q;
                        if (requested_dummy != 0) begin
                            state_q <= SPI_DUMMY;
                            segment_bits_q <= requested_dummy;
                            serial_data_q <= 1'b0;
                        end else if (data_length_q != 0) begin
                            state_q <= SPI_DATA;
                            segment_bits_q <= data_length_q;
                            if (!start_read && (tx_count_q != 0)) begin
                                if (tx_head_valid_q) begin
                                    transmit_shift_q <= tx_head_q;
                                    serial_data_q <= tx_head_q[31];
                                    transmit_fifo_pop = 1'b1;
                                end else begin
                                    serial_data_q <= 1'b0;
                                    tx_word_stall_q <= 1'b1;
                                end
                            end else begin
                                serial_data_q <= 1'b0;
                            end
                        end else begin
                            state_q <= SPI_FINISH;
                        end
                    end
                end
            end

            if (busy && (state_q != SPI_FINISH)) begin
                if (!divider_tick) begin
                    divider_count_q <= divider_count_q - 1'b1;
                end else begin
                    divider_count_q <= {8'h00, clock_divider_q};
                    if (!serial_clock_q) begin
                        if ((state_q == SPI_DATA) && !transaction_read_q &&
                            tx_word_stall_q) begin
                            if (tx_head_valid_q) begin
                                transmit_shift_q <= tx_head_q;
                                serial_data_q <= tx_head_q[31];
                                tx_word_stall_q <= 1'b0;
                                transmit_fifo_pop = 1'b1;
                            end
                        end else begin
                            serial_clock_q <= 1'b1;
                            if ((state_q == SPI_DATA) && transaction_read_q)
                                receive_shift_q <=
                                    {receive_shift_q[30:0], miso_i};
                        end
                    end else begin
                        serial_clock_q <= 1'b0;
                        if (segment_bits_q > 1) begin
                            segment_bits_q <= segment_bits_q - 1'b1;
                            if ((state_q == SPI_COMMAND) ||
                                (state_q == SPI_ADDRESS)) begin
                                transmit_shift_q <=
                                    {transmit_shift_q[30:0], 1'b0};
                                serial_data_q <= transmit_shift_q[30];
                            end else if (state_q == SPI_DATA) begin
                                word_bit_index_q <= word_bit_index_q + 1'b1;
                                if (transaction_read_q) begin
                                    if (word_bit_index_q == 6'd31) begin
                                        if ((rx_count_q <
                                            COUNT_WIDTH'(FIFO_DEPTH)) ||
                                            rx_fifo_pop) begin
                                            receive_fifo_push = 1'b1;
                                            receive_fifo_data = receive_shift_q;
                                        end
                                        word_bit_index_q <= '0;
                                        receive_shift_q <= '0;
                                    end
                                end else if (word_bit_index_q == 6'd31) begin
                                    word_bit_index_q <= '0;
                                    if (tx_count_q != 0) begin
                                        if (tx_head_valid_q) begin
                                            transmit_shift_q <= tx_head_q;
                                            serial_data_q <= tx_head_q[31];
                                            transmit_fifo_pop = 1'b1;
                                        end else begin
                                            serial_data_q <= 1'b0;
                                            tx_word_stall_q <= 1'b1;
                                        end
                                    end else begin
                                        transmit_shift_q <= '0;
                                        serial_data_q <= 1'b0;
                                    end
                                end else begin
                                    transmit_shift_q <=
                                        {transmit_shift_q[30:0], 1'b0};
                                    serial_data_q <= transmit_shift_q[30];
                                end
                            end
                        end else begin
                            requested_dummy = transaction_read_q ?
                                dummy_read_q : dummy_write_q;
                            if (state_q == SPI_COMMAND &&
                                (address_length_q != 0)) begin
                                state_q <= SPI_ADDRESS;
                                segment_bits_q <=
                                    {10'h000, address_length_q};
                                transmit_shift_q <= address_q;
                                serial_data_q <= address_q[31];
                            end else if ((state_q == SPI_COMMAND ||
                                state_q == SPI_ADDRESS) &&
                                (requested_dummy != 0)) begin
                                state_q <= SPI_DUMMY;
                                segment_bits_q <= requested_dummy;
                                serial_data_q <= 1'b0;
                            end else if ((state_q != SPI_DATA) &&
                                (data_length_q != 0)) begin
                                state_q <= SPI_DATA;
                                segment_bits_q <= data_length_q;
                                word_bit_index_q <= '0;
                                if (!transaction_read_q &&
                                    (tx_count_q != 0)) begin
                                    if (tx_head_valid_q) begin
                                        transmit_shift_q <= tx_head_q;
                                        serial_data_q <= tx_head_q[31];
                                        transmit_fifo_pop = 1'b1;
                                    end else begin
                                        serial_data_q <= 1'b0;
                                        tx_word_stall_q <= 1'b1;
                                    end
                                end else begin
                                    serial_data_q <= 1'b0;
                                end
                            end else begin
                                if ((state_q == SPI_DATA) &&
                                    transaction_read_q &&
                                    (word_bit_index_q != 0) &&
                                    ((rx_count_q <
                                      COUNT_WIDTH'(FIFO_DEPTH)) ||
                                     rx_fifo_pop)) begin
                                    receive_fifo_push = 1'b1;
                                    receive_fifo_data = receive_shift_q;
                                end
                                state_q <= SPI_FINISH;
                                serial_data_q <= 1'b0;
                            end
                        end
                    end
                end
            end else if (state_q == SPI_FINISH) begin
                state_q <= SPI_IDLE;
                chip_select_q <= '0;
                serial_clock_q <= 1'b0;
                tx_word_stall_q <= 1'b0;
                end_event_q <= 1'b1;
            end

            if (!fifo_clear) begin
                if (tx_fifo_push) begin
                    if ((tx_count_q == 0) ||
                        (transmit_fifo_pop && (tx_count_q == 1))) begin
                        tx_head_q <= apb_req_i.pwdata;
                        tx_head_valid_q <= 1'b1;
                    end else begin
                        tx_bram_wen_q <= 1'b1;
                        tx_bram_waddr_q <= tx_write_ptr_q;
                        tx_bram_wdata_q <= apb_req_i.pwdata;
                        tx_write_ptr_q <= tx_write_ptr_q + 1'b1;
                    end
                end
                if (transmit_fifo_pop) begin
                    if (tx_count_q > 1) begin
                        tx_head_valid_q <= 1'b0;
                        tx_bram_ren_q <= 1'b1;
                        tx_bram_raddr_q <= tx_read_ptr_q;
                        tx_read_ptr_q <= tx_read_ptr_q + 1'b1;
                    end else if (!tx_fifo_push) begin
                        tx_head_valid_q <= 1'b0;
                    end
                end

                if (rx_bram_deferred_write_q) begin
                    rx_bram_wen_q <= 1'b1;
                    rx_bram_waddr_q <= rx_bram_deferred_addr_q;
                    rx_bram_wdata_q <= rx_bram_deferred_data_q;
                    rx_bram_deferred_write_q <= 1'b0;
                end
                if (receive_fifo_push) begin
                    if ((rx_count_q == 0) ||
                        (rx_fifo_pop && (rx_count_q == 1))) begin
                        rx_head_q <= receive_fifo_data;
                        rx_head_valid_q <= 1'b1;
                    end else if (rx_fifo_pop &&
                        (rx_count_q == COUNT_WIDTH'(FIFO_DEPTH))) begin
                        // On a full FIFO, defer the replacement write until
                        // the read port has captured the displaced entry.
                        rx_bram_deferred_write_q <= 1'b1;
                        rx_bram_deferred_addr_q <= rx_write_ptr_q;
                        rx_bram_deferred_data_q <= receive_fifo_data;
                        rx_write_ptr_q <= rx_write_ptr_q + 1'b1;
                    end else begin
                        rx_bram_wen_q <= 1'b1;
                        rx_bram_waddr_q <= rx_write_ptr_q;
                        rx_bram_wdata_q <= receive_fifo_data;
                        rx_write_ptr_q <= rx_write_ptr_q + 1'b1;
                    end
                end
                if (rx_fifo_pop) begin
                    if (rx_count_q > 1) begin
                        rx_head_valid_q <= 1'b0;
                        rx_bram_ren_q <= 1'b1;
                        rx_bram_raddr_q <= rx_read_ptr_q;
                        rx_read_ptr_q <= rx_read_ptr_q + 1'b1;
                    end else if (!receive_fifo_push) begin
                        rx_head_valid_q <= 1'b0;
                    end
                end

                unique case ({tx_fifo_push, transmit_fifo_pop})
                    2'b10: tx_count_q <= tx_count_q + 1'b1;
                    2'b01: tx_count_q <= tx_count_q - 1'b1;
                    default: ;
                endcase
                unique case ({receive_fifo_push, rx_fifo_pop})
                    2'b10: rx_count_q <= rx_count_q + 1'b1;
                    2'b01: rx_count_q <= rx_count_q - 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        read_data = '0;
        unique case (register_index)
            REG_STATUS: read_data = status_value;
            REG_CLKDIV: read_data[7:0] = clock_divider_q;
            REG_SPICMD: read_data = command_q;
            REG_SPIADR: read_data = address_q;
            REG_SPILEN: read_data = {data_length_q, 2'b00,
                address_length_q, 2'b00, command_length_q};
            REG_SPIDUM: read_data = {dummy_write_q, dummy_read_q};
            REG_RXFIFO:
                read_data = ((rx_count_q != 0) && rx_head_valid_q) ?
                    rx_head_q : 32'h00000000;
            REG_INTCFG: read_data = {interrupt_enable_q, 18'h00000,
                rx_irq_threshold_q, 3'b000, tx_irq_threshold_q};
            REG_INTSTA: read_data = {30'h00000000, rx_irq, tx_irq};
            default: ;
        endcase
    end

    assign sclk_o = serial_clock_q;
    assign mosi_o = serial_data_q;
    assign cs_n_o = ~chip_select_q;
    assign irq_o = interrupt_enable_q && (tx_irq || rx_irq || end_event_q);
    assign apb_rsp_o.prdata = read_data;
    assign apb_rsp_o.pready = !rx_fifo_read_wait;
    assign apb_rsp_o.pslverr = 1'b0;
endmodule
