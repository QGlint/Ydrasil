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
    input  ydrasil_csr_write_pkt_t        trap_csr_write_i,
    input  ydrasil_irq_pkt_t              irq_i,
    output ydrasil_csr_trap_state_pkt_t   trap_state_o,
    output wire [REGS_DATA_WIDTH-1:0]     csr_ex_data_o
);
    wire [2:0] instret_inc_count = {2'b0, retire_i.valid} +
        {2'b0, retire1_i.valid};

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
        .csr_ex_data_o      (csr_ex_data_o)
    );
endmodule
