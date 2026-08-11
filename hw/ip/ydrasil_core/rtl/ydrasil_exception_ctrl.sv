module ydrasil_exception_ctrl
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  ydrasil_exception_req_pkt_t    exception_req_i,
    input  ydrasil_irq_pkt_t              irq_i,
    input  ydrasil_csr_trap_state_pkt_t   csr_state_i,
    input  wire                           backend_idle_i,
    input  wire [INST_ADDR_WIDTH-1:0]     async_pc_i,
    output ydrasil_csr_write_pkt_t        csr_write_o,
    output wire                           trap_stall_o,
    output ydrasil_trap_ctrl_pkt_t        trap_ctrl_o
);
    typedef enum logic [3:0] {
        S_IDLE,
        S_DRAIN,
        S_WRITE_MEPC,
        S_WRITE_MSTATUS,
        S_WRITE_MCAUSE,
        S_WRITE_MTVAL,
        S_REDIRECT,
        S_MRET_STATUS,
        S_MRET_REDIRECT
    } state_t;

    state_t state_q;
    logic [31:0] cause_q;
    logic [31:0] epc_q;
    logic [31:0] tval_q;
    logic is_interrupt_q;
    logic drain_armed_q;

    wire irq_mei = csr_state_i.mstatus[3] && csr_state_i.mie[11] &&
        csr_state_i.mip[11];
    wire irq_mti = csr_state_i.mstatus[3] && csr_state_i.mie[7] &&
        csr_state_i.mip[7];
    wire irq_msi = csr_state_i.mstatus[3] && csr_state_i.mie[3] &&
        csr_state_i.mip[3];
    wire irq_pending = irq_mei || irq_mti || irq_msi;
    wire [31:0] irq_cause = irq_mei ? 32'h8000_000b :
        irq_mti ? 32'h8000_0007 : 32'h8000_0003;

    logic [31:0] trap_mstatus;
    logic [31:0] mret_mstatus;
    logic [31:0] trap_target;
    always_comb begin
        trap_mstatus = csr_state_i.mstatus;
        trap_mstatus[7] = csr_state_i.mstatus[3];
        trap_mstatus[3] = 1'b0;
        trap_mstatus[12:11] = 2'b11;

        mret_mstatus = csr_state_i.mstatus;
        mret_mstatus[3] = csr_state_i.mstatus[7];
        mret_mstatus[7] = 1'b1;
        mret_mstatus[12:11] = 2'b00;

        trap_target = {csr_state_i.mtvec[31:2], 2'b00};
        if (is_interrupt_q && (csr_state_i.mtvec[1:0] == 2'b01))
            trap_target = {csr_state_i.mtvec[31:2], 2'b00} +
                ({27'b0, cause_q[4:0]} << 2);
    end

    always_comb begin
        csr_write_o = '0;
        unique case (state_q)
            S_WRITE_MEPC: begin
                csr_write_o.valid = 1'b1;
                csr_write_o.addr = CSR_MEPC;
                csr_write_o.data = epc_q;
            end
            S_WRITE_MSTATUS: begin
                csr_write_o.valid = 1'b1;
                csr_write_o.addr = CSR_MSTATUS;
                csr_write_o.data = trap_mstatus;
            end
            S_WRITE_MCAUSE: begin
                csr_write_o.valid = 1'b1;
                csr_write_o.addr = CSR_MCAUSE;
                csr_write_o.data = cause_q;
            end
            S_WRITE_MTVAL: begin
                csr_write_o.valid = 1'b1;
                csr_write_o.addr = CSR_MTVAL;
                csr_write_o.data = tval_q;
            end
            S_MRET_STATUS: begin
                csr_write_o.valid = 1'b1;
                csr_write_o.addr = CSR_MSTATUS;
                csr_write_o.data = mret_mstatus;
            end
            default: begin
            end
        endcase
    end

    // Keep control bits structurally independent from the redirect target.
    // Requests enter the registered drain state at the next edge, so request
    // detection does not feed combinationally back into Issue/Fetch control.
    assign trap_stall_o = state_q != S_IDLE;
    assign trap_ctrl_o.stall = trap_stall_o;
    assign trap_ctrl_o.retire = state_q == S_MRET_REDIRECT;
    assign trap_ctrl_o.redirect =
        (state_q == S_REDIRECT) || (state_q == S_MRET_REDIRECT);
    assign trap_ctrl_o.redirect_addr = (state_q == S_MRET_REDIRECT) ?
        csr_state_i.mepc : trap_target;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            cause_q <= '0;
            epc_q <= '0;
            tval_q <= '0;
            is_interrupt_q <= 1'b0;
            drain_armed_q <= 1'b0;
        end else begin
            unique case (state_q)
                S_IDLE: begin
                    drain_armed_q <= 1'b0;
                    if (exception_req_i.valid && exception_req_i.mret) begin
                        state_q <= S_MRET_STATUS;
                    end else if (exception_req_i.valid) begin
                        cause_q <= exception_req_i.illegal ? 32'd2 :
                            exception_req_i.ecall ? 32'd11 : 32'd3;
                        epc_q <= exception_req_i.pc;
                        tval_q <= exception_req_i.illegal ?
                            exception_req_i.tval : 32'b0;
                        is_interrupt_q <= 1'b0;
                        state_q <= S_DRAIN;
                    end else if (irq_pending) begin
                        cause_q <= irq_cause;
                        tval_q <= 32'b0;
                        is_interrupt_q <= 1'b1;
                        state_q <= S_DRAIN;
                    end
                end
                S_DRAIN: begin
                    drain_armed_q <= 1'b1;
                    if (drain_armed_q && backend_idle_i) begin
                        if (is_interrupt_q)
                            epc_q <= async_pc_i;
                        state_q <= S_WRITE_MEPC;
                    end
                end
                S_WRITE_MEPC: state_q <= S_WRITE_MSTATUS;
                S_WRITE_MSTATUS: state_q <= S_WRITE_MCAUSE;
                S_WRITE_MCAUSE: state_q <= (cause_q == 32'd2) ?
                    S_WRITE_MTVAL : S_REDIRECT;
                S_WRITE_MTVAL: state_q <= S_REDIRECT;
                S_REDIRECT: state_q <= S_IDLE;
                S_MRET_STATUS: state_q <= S_MRET_REDIRECT;
                S_MRET_REDIRECT: state_q <= S_IDLE;
                default: state_q <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && irq_i.external && irq_i.timer && irq_i.software &&
            irq_pending)
            assert (irq_cause == 32'h8000_000b)
                else $fatal(1, "IRQ priority must be MEI > MTI > MSI");
    end
`endif
endmodule
