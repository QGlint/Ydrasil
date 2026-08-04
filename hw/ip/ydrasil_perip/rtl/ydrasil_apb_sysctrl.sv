module ydrasil_apb_sysctrl
import ydrasil_apb_pkg::*;
#(
    parameter logic [31:0] SOC_ID = 32'h5944_5231
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  ydrasil_apb_req_pkt_t apb_req_i,
    output ydrasil_apb_rsp_pkt_t apb_rsp_o,
    input  wire                  coremark_active_i,
    input  wire [63:0]           coremark_cycles_i,
    output wire                  coremark_start_toggle_o,
    output wire                  coremark_stop_toggle_o,
    output wire                  coremark_auto_enable_o,
    output wire [31:0]           coremark_pc_base_o,
    output wire [31:0]           coremark_pc_limit_o,
    output wire [31:0]           coremark_timeout_o
);
    localparam logic [11:0] REG_ID       = 12'h000;
    localparam logic [11:0] REG_SCRATCH  = 12'h004;
    localparam logic [11:0] REG_CM_CTRL  = 12'h010;
    localparam logic [11:0] REG_CM_STAT  = 12'h014;
    localparam logic [11:0] REG_CM_BASE  = 12'h018;
    localparam logic [11:0] REG_CM_LIMIT = 12'h01c;
    localparam logic [11:0] REG_CM_TO    = 12'h020;
    localparam logic [11:0] REG_CM_CYCLO = 12'h024;
    localparam logic [11:0] REG_CM_CYCHI = 12'h028;

    logic [31:0] scratch_q;
    logic        start_toggle_q;
    logic        stop_toggle_q;
    logic        auto_enable_q;
    logic [31:0] pc_base_q;
    logic [31:0] pc_limit_q;
    logic [31:0] timeout_q;

    wire apb_access = apb_req_i.psel && apb_req_i.penable;
    wire apb_write = apb_access && apb_req_i.pwrite;
    wire [11:0] reg_offset = apb_req_i.paddr[11:0];
    wire address_valid = (reg_offset == REG_ID) ||
        (reg_offset == REG_SCRATCH) || (reg_offset == REG_CM_CTRL) ||
        (reg_offset == REG_CM_STAT) || (reg_offset == REG_CM_BASE) ||
        (reg_offset == REG_CM_LIMIT) || (reg_offset == REG_CM_TO) ||
        (reg_offset == REG_CM_CYCLO) || (reg_offset == REG_CM_CYCHI);

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

    always_comb begin
        apb_rsp_o = '0;
        apb_rsp_o.pready = 1'b1;
        unique case (reg_offset)
            REG_ID:       apb_rsp_o.prdata = SOC_ID;
            REG_SCRATCH:  apb_rsp_o.prdata = scratch_q;
            REG_CM_CTRL:  apb_rsp_o.prdata = {29'b0, auto_enable_q, 2'b0};
            REG_CM_STAT:  apb_rsp_o.prdata = {31'b0, coremark_active_i};
            REG_CM_BASE:  apb_rsp_o.prdata = pc_base_q;
            REG_CM_LIMIT: apb_rsp_o.prdata = pc_limit_q;
            REG_CM_TO:    apb_rsp_o.prdata = timeout_q;
            REG_CM_CYCLO: apb_rsp_o.prdata = coremark_cycles_i[31:0];
            REG_CM_CYCHI: apb_rsp_o.prdata = coremark_cycles_i[63:32];
            default:      apb_rsp_o.prdata = '0;
        endcase
        apb_rsp_o.pslverr = apb_access && !address_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch_q <= '0;
            start_toggle_q <= 1'b0;
            stop_toggle_q <= 1'b0;
            auto_enable_q <= 1'b0;
            pc_base_q <= '0;
            pc_limit_q <= '0;
            timeout_q <= 32'd100000;
        end else if (apb_write) begin
            unique case (reg_offset)
                REG_SCRATCH: scratch_q <= apply_strobe(
                    scratch_q, apb_req_i.pwdata, apb_req_i.pstrb);
                REG_CM_CTRL: begin
                    if (apb_req_i.pstrb[0]) begin
                        if (apb_req_i.pwdata[0])
                            start_toggle_q <= ~start_toggle_q;
                        if (apb_req_i.pwdata[1])
                            stop_toggle_q <= ~stop_toggle_q;
                        auto_enable_q <= apb_req_i.pwdata[2];
                    end
                end
                REG_CM_BASE: pc_base_q <= apply_strobe(
                    pc_base_q, apb_req_i.pwdata, apb_req_i.pstrb);
                REG_CM_LIMIT: pc_limit_q <= apply_strobe(
                    pc_limit_q, apb_req_i.pwdata, apb_req_i.pstrb);
                REG_CM_TO: timeout_q <= apply_strobe(
                    timeout_q, apb_req_i.pwdata, apb_req_i.pstrb);
                default: begin
                end
            endcase
        end
    end

    assign coremark_start_toggle_o = start_toggle_q;
    assign coremark_stop_toggle_o = stop_toggle_q;
    assign coremark_auto_enable_o = auto_enable_q;
    assign coremark_pc_base_o = pc_base_q;
    assign coremark_pc_limit_o = pc_limit_q;
    assign coremark_timeout_o = timeout_q;
endmodule
