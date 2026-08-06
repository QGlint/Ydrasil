module ydrasil_exception_stage
import ydrasil_pkg::*;
(
    input  wire                           clk,
    input  wire                           rst_n,
    input  ydrasil_irq_pkt_t              irq_i,
    input  ydrasil_csr_trap_state_pkt_t   csr_state_i,
    input  wire                           ex_accept_valid_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0] operator_type_i,
    input  wire [OP_SYS_INFO_WIDTH-1:0]   sys_info_i,
    input  wire                           illegal_instr_i,
    input  wire                           lane_a_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0]     lane_a_pc_i,
    input  wire                           lane_b_valid_i,
    input  wire [INST_ADDR_WIDTH-1:0]     lane_b_pc_i,
    input  wire [INST_ADDR_WIDTH-1:0]     frontend_pc_i,
    input  wire                           lsu_idle_i,
    input  wire [REGS_NUM-1:0]           gpr_pending_i,
    input  wire                           mul_stall_i,
    output ydrasil_csr_write_pkt_t        csr_write_o,
    output ydrasil_trap_ctrl_pkt_t        trap_ctrl_o
);
    ydrasil_exception_req_pkt_t exception_req;
    wire backend_idle;
    wire [INST_ADDR_WIDTH-1:0] async_pc;

    always_comb begin
        exception_req = '0;
        exception_req.valid =
            (ex_accept_valid_i && operator_type_i[OPERATOR_TYPE_SYS]) ||
            (lane_a_valid_i && illegal_instr_i);
        exception_req.ecall = sys_info_i[OP_SYS_ECALL];
        exception_req.ebreak = sys_info_i[OP_SYS_EBREAK];
        exception_req.mret = sys_info_i[OP_SYS_MRET];
        exception_req.illegal = lane_a_valid_i && illegal_instr_i;
        exception_req.pc = lane_a_pc_i;
    end

    assign async_pc = lane_b_valid_i ? (lane_b_pc_i + 32'd4) :
        lane_a_valid_i ? (lane_a_pc_i + 32'd4) : frontend_pc_i;
    assign backend_idle = lsu_idle_i && !(|gpr_pending_i) &&
        !lane_a_valid_i && !lane_b_valid_i && !mul_stall_i;

    ydrasil_exception_ctrl u_exception_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .exception_req_i(exception_req),
        .irq_i          (irq_i),
        .csr_state_i    (csr_state_i),
        .backend_idle_i (backend_idle),
        .async_pc_i     (async_pc),
        .csr_write_o    (csr_write_o),
        .trap_ctrl_o    (trap_ctrl_o)
    );
endmodule
