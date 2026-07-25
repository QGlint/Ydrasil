`timescale 1ns / 1ns

module perip_bridge
import ydrasil_apb_pkg::*;
(
    input  wire                    clk,
    input  wire                    rst,
    input  ydrasil_apb_req_pkt_t   apb_req_i,
    output ydrasil_apb_rsp_pkt_t   apb_rsp_o,
    input  wire [63:0]             virtual_sw_input,
    input  wire [7:0]              virtual_key_input,
    output wire [39:0]             virtual_seg_output,
    output wire [31:0]             virtual_led_output
);
    localparam logic [31:0] SW0_ADDR = 32'h8020_0000;
    localparam logic [31:0] SW1_ADDR = 32'h8020_0004;
    localparam logic [31:0] KEY_ADDR = 32'h8020_0010;
    localparam logic [31:0] SEG_ADDR = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR = 32'h8020_0040;
    localparam logic [31:0] CNT_ADDR = 32'h8020_0050;
    localparam logic [31:0] SIM_STDOUT_ADDR = 32'h8020_0060;
    localparam logic [31:0] SIM_DUMP_ADDR = 32'h8020_0064;

    logic [31:0] led_q;
    logic [31:0] seg_wdata_q;
    wire [31:0] cnt_rdata;
    wire [39:0] seg_output;
    logic cnt_cmd_valid_q;
    logic cnt_cmd_start_q;
    logic cnt_cmd_stop_q;
    wire apb_access = apb_req_i.psel && apb_req_i.penable;
    wire apb_write = apb_access && apb_req_i.pwrite;

    function automatic [31:0] apply_strobe(
        input [31:0] old_value,
        input [31:0] new_value,
        input [3:0] strobe
    );
        integer byte_idx;
        begin
            apply_strobe = old_value;
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1)
                if (strobe[byte_idx])
                    apply_strobe[byte_idx*8 +: 8] = new_value[byte_idx*8 +: 8];
        end
    endfunction

    wire address_valid =
        (apb_req_i.paddr == SW0_ADDR) || (apb_req_i.paddr == SW1_ADDR) ||
        (apb_req_i.paddr == KEY_ADDR) || (apb_req_i.paddr == SEG_ADDR) ||
        (apb_req_i.paddr == LED_ADDR) || (apb_req_i.paddr == CNT_ADDR) ||
        (apb_req_i.paddr == SIM_STDOUT_ADDR) ||
        (apb_req_i.paddr == SIM_DUMP_ADDR);

    always_comb begin
        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        unique case (apb_req_i.paddr)
            SW0_ADDR: apb_rsp_o.prdata = virtual_sw_input[31:0];
            SW1_ADDR: apb_rsp_o.prdata = virtual_sw_input[63:32];
            KEY_ADDR: apb_rsp_o.prdata = {24'b0, virtual_key_input};
            SEG_ADDR: apb_rsp_o.prdata = seg_wdata_q;
            LED_ADDR: apb_rsp_o.prdata = led_q;
            CNT_ADDR: apb_rsp_o.prdata = cnt_rdata;
            default: apb_rsp_o.prdata = 32'b0;
        endcase
        apb_rsp_o.pslverr = apb_access && !address_valid;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            led_q <= '0;
            seg_wdata_q <= '0;
            cnt_cmd_valid_q <= 1'b0;
            cnt_cmd_start_q <= 1'b0;
            cnt_cmd_stop_q <= 1'b0;
        end else begin
            cnt_cmd_valid_q <= apb_write && (apb_req_i.paddr == CNT_ADDR);
            cnt_cmd_start_q <= (apb_req_i.pwdata == 32'h8000_0000);
            cnt_cmd_stop_q <= (apb_req_i.pwdata == 32'hffff_ffff);
            if (apb_write) begin
                unique case (apb_req_i.paddr)
                    LED_ADDR: led_q <= apply_strobe(
                        led_q, apb_req_i.pwdata, apb_req_i.pstrb);
                    SEG_ADDR: seg_wdata_q <= apply_strobe(
                        seg_wdata_q, apb_req_i.pwdata, apb_req_i.pstrb);
                    default: begin
                    end
                endcase
            end
        end
    end

    display_seg seg_driver (
        .clk(clk),
        .rst(rst),
        .s(seg_wdata_q),
        .seg1(seg_output[6:0]),
        .seg2(seg_output[16:10]),
        .seg3(seg_output[26:20]),
        .seg4(seg_output[36:30]),
        .ans({seg_output[39:38], seg_output[29:28],
              seg_output[19:18], seg_output[9:8]})
    );

    assign seg_output[7] = 1'b0;
    assign seg_output[17] = 1'b0;
    assign seg_output[27] = 1'b0;
    assign seg_output[37] = 1'b0;

    counter counter_inst (
        .clk(clk),
        .rst(rst),
        .cmd_valid_i(cnt_cmd_valid_q),
        .cmd_start_i(cnt_cmd_start_q),
        .cmd_stop_i(cnt_cmd_stop_q),
        .count_o(cnt_rdata)
    );

    assign virtual_led_output = led_q;
    assign virtual_seg_output = seg_output;
endmodule
