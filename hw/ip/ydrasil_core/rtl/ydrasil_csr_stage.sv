module ydrasil_csr_stage
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  ydrasil_commit_pkt_t           retire_i,
    input  ydrasil_commit_pkt_t           retire1_i,
    input  wire                           ex_csr_wen_i,
    input  wire [CSR_ADDR_WIDTH-1:0]      id_csr_raddr_i,
    input  wire [CSR_ADDR_WIDTH-1:0]      ex_csr_waddr_i,
    input  wire [REGS_DATA_WIDTH-1:0]     ex_csr_data_i,
    input  wire                           fpu_flags_valid_i,
    input  wire [4:0]                     fpu_fflags_i,
    input  ydrasil_csr_write_pkt_t        trap_csr_write_i,
    input  ydrasil_irq_pkt_t              irq_i,
    output ydrasil_csr_trap_state_pkt_t   trap_state_o,
    output wire [REGS_DATA_WIDTH-1:0]     csr_ex_data_o,
    output wire [2:0]                     fpu_frm_o
);
    wire [2:0] instret_inc_count = {2'b0, retire_i.valid} +
        {2'b0, retire1_i.valid};

    wire [REGS_DATA_WIDTH-1:0] csr_ex_data_base;
    reg [4:0] fflags_q;
    reg [2:0] frm_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fflags_q <= '0;
            frm_q <= '0;
        end else if (ex_csr_wen_i &&
            (ex_csr_waddr_i == CSR_FCSR)) begin
            fflags_q <= ex_csr_data_i[4:0];
            frm_q <= ex_csr_data_i[7:5];
        end else if (ex_csr_wen_i &&
            (ex_csr_waddr_i == CSR_FFLAGS)) begin
            fflags_q <= ex_csr_data_i[4:0];
        end else if (ex_csr_wen_i &&
            (ex_csr_waddr_i == CSR_FRM)) begin
            frm_q <= ex_csr_data_i[2:0];
        end else if (fpu_flags_valid_i) begin
            fflags_q <= fflags_q | fpu_fflags_i;
        end
    end

    assign fpu_frm_o = frm_q;

    reg [REGS_DATA_WIDTH-1:0] csr_ex_data_mux;
    always_comb begin
        csr_ex_data_mux = csr_ex_data_base;
        unique case (id_csr_raddr_i)
            CSR_FFLAGS: csr_ex_data_mux = ex_csr_wen_i &&
                (ex_csr_waddr_i == CSR_FFLAGS) ?
                {27'b0, ex_csr_data_i[4:0]} : {27'b0, fflags_q};
            CSR_FRM: csr_ex_data_mux = ex_csr_wen_i &&
                (ex_csr_waddr_i == CSR_FRM) ?
                {29'b0, ex_csr_data_i[2:0]} : {29'b0, frm_q};
            CSR_FCSR: csr_ex_data_mux = ex_csr_wen_i &&
                (ex_csr_waddr_i == CSR_FCSR) ?
                {24'b0, ex_csr_data_i[7:0]} :
                {24'b0, frm_q, fflags_q};
            default: begin end
        endcase
    end

    assign csr_ex_data_o = csr_ex_data_mux;

    ydrasil_registers_csr u_registers_csr (
        .clk                (clk),
        .rst_n              (rst_n),
        .instret_inc_count_i(instret_inc_count),
        .ex_csr_wen_i       (ex_csr_wen_i),
        .id_csr_raddr_i     (id_csr_raddr_i),
        .ex_csr_waddr_i     (ex_csr_waddr_i),
        .ex_csr_data_i      (ex_csr_data_i),
        .trap_csr_write_i   (trap_csr_write_i),
        .irq_i              (irq_i),
        .trap_state_o       (trap_state_o),
        .csr_ex_data_o      (csr_ex_data_base)
    );
endmodule
