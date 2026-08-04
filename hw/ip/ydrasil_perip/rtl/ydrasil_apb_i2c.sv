module ydrasil_apb_i2c
import ydrasil_apb_pkg::*;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    input  wire                  scl_i,
    input  wire                  sda_i,
    output wire                  scl_drive_low_o,
    output wire                  sda_drive_low_o,
    output wire                  irq_o
);
    localparam logic [2:0] REG_PRESCALE = 3'h0;
    localparam logic [2:0] REG_CONTROL  = 3'h1;
    localparam logic [2:0] REG_RECEIVE  = 3'h2;
    localparam logic [2:0] REG_STATUS   = 3'h3;
    localparam logic [2:0] REG_TRANSMIT = 3'h4;
    localparam logic [2:0] REG_COMMAND  = 3'h5;

    typedef enum logic [3:0] {
        I2C_IDLE, I2C_START_RELEASE, I2C_START_SDA, I2C_START_SCL,
        I2C_BIT_SETUP, I2C_BIT_HIGH, I2C_BIT_LOW,
        I2C_ACK_SETUP, I2C_ACK_HIGH, I2C_ACK_LOW,
        I2C_STOP_LOW, I2C_STOP_HIGH, I2C_STOP_RELEASE, I2C_DONE
    } i2c_state_t;

    logic [15:0] prescaler_q;
    logic [7:0] control_q;
    logic [7:0] transmit_q;
    logic [7:0] receive_q;
    logic [7:0] command_q;
    logic received_nack_q;
    logic bus_busy_q;
    logic arbitration_lost_q;
    logic transfer_in_progress_q;
    logic interrupt_flag_q;

    i2c_state_t state_q;
    logic [15:0] phase_count_q;
    logic [2:0] bit_index_q;
    logic read_transfer_q;
    logic stop_requested_q;
    logic send_nack_q;
    logic scl_low_q;
    logic sda_low_q;
    logic scl_meta_q;
    logic scl_sync_q;
    logic sda_meta_q;
    logic sda_sync_q;
    logic [31:0] read_data;

    wire apb_write = apb_req_i.psel && apb_req_i.penable &&
        apb_req_i.pwrite;
    wire [2:0] register_index = apb_req_i.paddr[4:2];
    wire core_enable = control_q[7];
    wire interrupt_enable = control_q[6];
    wire phase_tick = phase_count_q == 0;
    wire [7:0] status_value = {received_nack_q, bus_busy_q,
        arbitration_lost_q, 3'b000, transfer_in_progress_q,
        interrupt_flag_q};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescaler_q <= 16'd99;
            control_q <= '0;
            transmit_q <= '0;
            receive_q <= '0;
            command_q <= '0;
            received_nack_q <= 1'b0;
            bus_busy_q <= 1'b0;
            arbitration_lost_q <= 1'b0;
            transfer_in_progress_q <= 1'b0;
            interrupt_flag_q <= 1'b0;
            state_q <= I2C_IDLE;
            phase_count_q <= '0;
            bit_index_q <= 3'd7;
            read_transfer_q <= 1'b0;
            stop_requested_q <= 1'b0;
            send_nack_q <= 1'b0;
            scl_low_q <= 1'b0;
            sda_low_q <= 1'b0;
            scl_meta_q <= 1'b1;
            scl_sync_q <= 1'b1;
            sda_meta_q <= 1'b1;
            sda_sync_q <= 1'b1;
        end else begin
            scl_meta_q <= scl_i;
            scl_sync_q <= scl_meta_q;
            sda_meta_q <= sda_i;
            sda_sync_q <= sda_meta_q;

            if (apb_write) begin
                unique case (register_index)
                    REG_PRESCALE: prescaler_q <= apb_req_i.pwdata[15:0];
                    REG_CONTROL: control_q <= apb_req_i.pwdata[7:0];
                    REG_TRANSMIT: transmit_q <= apb_req_i.pwdata[7:0];
                    REG_COMMAND: begin
                        if (apb_req_i.pwdata[0])
                            interrupt_flag_q <= 1'b0;
                        if (core_enable && !transfer_in_progress_q &&
                            (apb_req_i.pwdata[7:4] != 0)) begin
                            command_q <= apb_req_i.pwdata[7:0];
                            read_transfer_q <= apb_req_i.pwdata[5];
                            stop_requested_q <= apb_req_i.pwdata[6];
                            send_nack_q <= apb_req_i.pwdata[3];
                            bit_index_q <= 3'd7;
                            receive_q <= '0;
                            received_nack_q <= 1'b0;
                            arbitration_lost_q <= 1'b0;
                            transfer_in_progress_q <= 1'b1;
                            phase_count_q <= prescaler_q;
                            if (apb_req_i.pwdata[7]) begin
                                state_q <= I2C_START_RELEASE;
                                scl_low_q <= 1'b0;
                                sda_low_q <= 1'b0;
                            end else begin
                                state_q <= I2C_BIT_SETUP;
                                scl_low_q <= 1'b1;
                            end
                        end
                    end
                    default: ;
                endcase
            end

            if (state_q != I2C_IDLE && state_q != I2C_DONE) begin
                if (!phase_tick) begin
                    phase_count_q <= phase_count_q - 1'b1;
                end else begin
                    phase_count_q <= prescaler_q;
                    unique case (state_q)
                        I2C_START_RELEASE: begin
                            if (scl_sync_q && sda_sync_q) begin
                                sda_low_q <= 1'b1;
                                bus_busy_q <= 1'b1;
                                state_q <= I2C_START_SDA;
                            end
                        end
                        I2C_START_SDA: begin
                            scl_low_q <= 1'b1;
                            state_q <= I2C_START_SCL;
                        end
                        I2C_START_SCL: begin
                            state_q <= I2C_BIT_SETUP;
                        end
                        I2C_BIT_SETUP: begin
                            scl_low_q <= 1'b1;
                            sda_low_q <= read_transfer_q ? 1'b0 :
                                ~transmit_q[bit_index_q];
                            state_q <= I2C_BIT_HIGH;
                        end
                        I2C_BIT_HIGH: begin
                            scl_low_q <= 1'b0;
                            if (scl_sync_q) begin
                                if (read_transfer_q)
                                    receive_q[bit_index_q] <= sda_sync_q;
                                else if (transmit_q[bit_index_q] &&
                                    !sda_sync_q)
                                    arbitration_lost_q <= 1'b1;
                                state_q <= I2C_BIT_LOW;
                            end
                        end
                        I2C_BIT_LOW: begin
                            scl_low_q <= 1'b1;
                            if (arbitration_lost_q) begin
                                scl_low_q <= 1'b0;
                                sda_low_q <= 1'b0;
                                bus_busy_q <= 1'b0;
                                state_q <= I2C_DONE;
                            end else if (bit_index_q == 0) begin
                                state_q <= I2C_ACK_SETUP;
                            end else begin
                                bit_index_q <= bit_index_q - 1'b1;
                                state_q <= I2C_BIT_SETUP;
                            end
                        end
                        I2C_ACK_SETUP: begin
                            sda_low_q <= read_transfer_q && !send_nack_q;
                            state_q <= I2C_ACK_HIGH;
                        end
                        I2C_ACK_HIGH: begin
                            scl_low_q <= 1'b0;
                            if (scl_sync_q) begin
                                if (!read_transfer_q)
                                    received_nack_q <= sda_sync_q;
                                state_q <= I2C_ACK_LOW;
                            end
                        end
                        I2C_ACK_LOW: begin
                            scl_low_q <= 1'b1;
                            sda_low_q <= 1'b0;
                            state_q <= stop_requested_q ?
                                I2C_STOP_LOW : I2C_DONE;
                        end
                        I2C_STOP_LOW: begin
                            scl_low_q <= 1'b1;
                            sda_low_q <= 1'b1;
                            state_q <= I2C_STOP_HIGH;
                        end
                        I2C_STOP_HIGH: begin
                            scl_low_q <= 1'b0;
                            if (scl_sync_q)
                                state_q <= I2C_STOP_RELEASE;
                        end
                        I2C_STOP_RELEASE: begin
                            sda_low_q <= 1'b0;
                            bus_busy_q <= 1'b0;
                            state_q <= I2C_DONE;
                        end
                        default: state_q <= I2C_DONE;
                    endcase
                end
            end else if (state_q == I2C_DONE) begin
                transfer_in_progress_q <= 1'b0;
                interrupt_flag_q <= 1'b1;
                command_q[7:3] <= '0;
                state_q <= I2C_IDLE;
            end
        end
    end

    always_comb begin
        read_data = '0;
        unique case (register_index)
            REG_PRESCALE: read_data[15:0] = prescaler_q;
            REG_CONTROL: read_data[7:0] = control_q;
            REG_RECEIVE: read_data[7:0] = receive_q;
            REG_STATUS: read_data[7:0] = status_value;
            REG_TRANSMIT: read_data[7:0] = transmit_q;
            REG_COMMAND: read_data[7:0] = command_q;
            default: ;
        endcase
    end

    assign scl_drive_low_o = scl_low_q;
    assign sda_drive_low_o = sda_low_q;
    assign irq_o = interrupt_enable && interrupt_flag_q;
    assign apb_rsp_o.prdata = read_data;
    assign apb_rsp_o.pready = 1'b1;
    assign apb_rsp_o.pslverr = 1'b0;
endmodule
