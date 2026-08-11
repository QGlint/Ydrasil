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
    input  wire                           backend_empty_i,
    input  wire                           mul_stall_i,
    input  wire                           redirect_pending_i,
    output ydrasil_csr_write_pkt_t        csr_write_o,
    output ydrasil_trap_ctrl_pkt_t        trap_ctrl_o
);
    ydrasil_exception_req_pkt_t exception_req;
    reg backend_idle_q;
    reg [INST_ADDR_WIDTH-1:0] async_pc_q;
    wire [INST_ADDR_WIDTH-1:0] async_pc;

    always_comb begin
        exception_req = '0;
        exception_req.valid =
            (ex_accept_valid_i && operator_type_i[OPERATOR_TYPE_SYS]) ||
            illegal_instr_i;
        exception_req.ecall = sys_info_i[OP_SYS_ECALL];
        exception_req.ebreak = sys_info_i[OP_SYS_EBREAK];
        exception_req.mret = sys_info_i[OP_SYS_MRET];
        exception_req.illegal = illegal_instr_i;
        // SERIAL uops, including illegal encodings, execute on P1. Use the
        // PC carried by that registered token even though illegal retains the
        // SYS base class for serialization and ROB draining.
        exception_req.pc = lane_b_pc_i;
    end

    assign async_pc = lane_b_valid_i ? (lane_b_pc_i + 32'd4) :
        lane_a_valid_i ? (lane_a_pc_i + 32'd4) : frontend_pc_i;
    wire backend_idle = lsu_idle_i && backend_empty_i &&
        !lane_a_valid_i && !lane_b_valid_i && !mul_stall_i &&
        !redirect_pending_i;
    // Exception control consumes a local observation, not the live global
    // drain cone.  Normal execution is unaffected; traps spend a complete
    // cycle in S_DRAIN before this sample can advance the controller.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            backend_idle_q <= 1'b0;
            async_pc_q <= '0;
        end else begin
            backend_idle_q <= backend_idle;
            async_pc_q <= async_pc;
        end
    end

    ydrasil_exception_ctrl u_exception_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .exception_req_i(exception_req),
        .irq_i          (irq_i),
        .csr_state_i    (csr_state_i),
        .backend_idle_i (backend_idle_q),
        .async_pc_i     (async_pc_q),
        .csr_write_o    (csr_write_o),
        .trap_ctrl_o    (trap_ctrl_o)
    );
endmodule
