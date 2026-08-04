module ydrasil_apb_gpio
import ydrasil_apb_pkg::*;
#(
    parameter int WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    input  wire [WIDTH-1:0]      gpio_i,
    output wire [WIDTH-1:0]      gpio_o,
    output wire [WIDTH-1:0]      gpio_oe_o,
    output wire                  irq_o
);
    localparam logic [3:0] REG_PADDIR    = 4'h0;
    localparam logic [3:0] REG_PADIN     = 4'h1;
    localparam logic [3:0] REG_PADOUT    = 4'h2;
    localparam logic [3:0] REG_INTEN     = 4'h3;
    localparam logic [3:0] REG_INTTYPE0  = 4'h4;
    localparam logic [3:0] REG_INTTYPE1  = 4'h5;
    localparam logic [3:0] REG_INTSTATUS = 4'h6;
    localparam logic [3:0] REG_IOFCFG    = 4'h7;

    logic [WIDTH-1:0] input_meta_q;
    logic [WIDTH-1:0] input_sync_q;
    logic [WIDTH-1:0] input_prev_q;
    logic [WIDTH-1:0] direction_q;
    logic [WIDTH-1:0] output_q;
    logic [WIDTH-1:0] interrupt_enable_q;
    logic [WIDTH-1:0] interrupt_type0_q;
    logic [WIDTH-1:0] interrupt_type1_q;
    logic [WIDTH-1:0] interrupt_pending_q;
    logic [WIDTH-1:0] iof_config_q;
    logic [31:0] read_data;

    wire apb_write = apb_req_i.psel && apb_req_i.penable &&
        apb_req_i.pwrite;
    wire apb_read = apb_req_i.psel && apb_req_i.penable &&
        !apb_req_i.pwrite;
    wire [3:0] register_index = apb_req_i.paddr[5:2];
    wire [WIDTH-1:0] rising = input_sync_q & ~input_prev_q;
    wire [WIDTH-1:0] falling = ~input_sync_q & input_prev_q;
    wire [WIDTH-1:0] interrupt_event = interrupt_enable_q &
        (( interrupt_type1_q & ~interrupt_type0_q & rising) |
         ( interrupt_type1_q &  interrupt_type0_q & falling) |
         (~interrupt_type1_q & ~interrupt_type0_q & input_sync_q) |
         (~interrupt_type1_q &  interrupt_type0_q & ~input_sync_q));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_meta_q <= '0;
            input_sync_q <= '0;
            input_prev_q <= '0;
            direction_q <= '0;
            output_q <= '0;
            interrupt_enable_q <= '0;
            interrupt_type0_q <= '0;
            interrupt_type1_q <= '0;
            interrupt_pending_q <= '0;
            iof_config_q <= '0;
        end else begin
            input_meta_q <= gpio_i;
            input_sync_q <= input_meta_q;
            input_prev_q <= input_sync_q;
            interrupt_pending_q <= interrupt_pending_q | interrupt_event;

            if (apb_read && (register_index == REG_INTSTATUS))
                interrupt_pending_q <= interrupt_event;

            if (apb_write) begin
                unique case (register_index)
                    REG_PADDIR: direction_q <= WIDTH'(apb_req_i.pwdata);
                    REG_PADOUT: output_q <= WIDTH'(apb_req_i.pwdata);
                    REG_INTEN:
                        interrupt_enable_q <= WIDTH'(apb_req_i.pwdata);
                    REG_INTTYPE0:
                        interrupt_type0_q <= WIDTH'(apb_req_i.pwdata);
                    REG_INTTYPE1:
                        interrupt_type1_q <= WIDTH'(apb_req_i.pwdata);
                    REG_INTSTATUS:
                        interrupt_pending_q <= interrupt_pending_q &
                            ~WIDTH'(apb_req_i.pwdata);
                    REG_IOFCFG: iof_config_q <= WIDTH'(apb_req_i.pwdata);
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        read_data = '0;
        unique case (register_index)
            REG_PADDIR: read_data = 32'(direction_q);
            REG_PADIN: read_data = 32'(input_sync_q);
            REG_PADOUT: read_data = 32'(output_q);
            REG_INTEN: read_data = 32'(interrupt_enable_q);
            REG_INTTYPE0: read_data = 32'(interrupt_type0_q);
            REG_INTTYPE1: read_data = 32'(interrupt_type1_q);
            REG_INTSTATUS: read_data = 32'(interrupt_pending_q);
            REG_IOFCFG: read_data = 32'(iof_config_q);
            default: ;
        endcase
    end

    assign gpio_o = output_q;
    assign gpio_oe_o = direction_q;
    assign irq_o = |interrupt_pending_q;
    assign apb_rsp_o.prdata = read_data;
    assign apb_rsp_o.pready = 1'b1;
    assign apb_rsp_o.pslverr = 1'b0;
endmodule
