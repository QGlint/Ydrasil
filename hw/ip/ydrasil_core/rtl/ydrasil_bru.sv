module ydrasil_bru
import ydrasil_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            flush_i,

    input  wire [DATA_WIDTH-1:0]           operand_a_i,
    input  wire [DATA_WIDTH-1:0]           operand_b_i,
    input  wire [DATA_WIDTH-1:0]           bt_a_operand_i,
    input  wire [DATA_WIDTH-1:0]           bt_b_operand_i,
    input  wire [OPERATOR_WIDTH-1:0]       operator_i,
    input  wire [OPERATOR_TYPE_WIDTH-1:0]  operator_type_i,
    input  wire                            id_ex_valid_i,
    input  wire                            id_ex_jalr_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_branch_target_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_branch_next_pc_i,
    input  wire                            id_ex_branch_eq_i,
    input  wire                            id_ex_branch_ge_signed_i,
    input  wire                            id_ex_branch_ge_unsigned_i,
    input  wire                            id_ex_pred_hit_i,
    input  wire                            id_ex_pred_taken_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_target_i,
    input  wire [1:0]                      id_ex_pred_counter_i,
    input  wire [DATA_WIDTH-1:0]           id_ex_pred_bht_index_i,
    input  producer_id_t                   id_ex_producer_id_i,
    input  wire                            trap_redirect_i,
    input  wire [INST_ADDR_WIDTH-1:0]      trap_redirect_addr_i,

    output wire                            ex_branch_jump_o,
    output wire [DATA_WIDTH-1:0]           ex_branch_target_o,
    output wire                            ex_pc_redirect_o,
    output wire [DATA_WIDTH-1:0]           ex_pc_redirect_target_o,
    output ydrasil_bp_train_pkt_t          ex_bp_train_o,
    output wire                            ex_branch_mispredict_o
`ifndef SYNTHESIS
    ,output wire                           dbg_bp_resolve_valid_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_resolve_pc_o
    ,output wire                           dbg_bp_actual_taken_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_actual_target_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_actual_next_pc_o
    ,output wire                           dbg_bp_pred_hit_o
    ,output wire                           dbg_bp_pred_taken_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_pred_target_o
    ,output wire [1:0]                     dbg_bp_pred_counter_o
    ,output wire [DATA_WIDTH-1:0]          dbg_bp_pred_next_pc_o
    ,output wire                           dbg_bp_mispredict_o
`endif
);

    wire [DATA_WIDTH-1:0] bt_alu_result = bt_a_operand_i + bt_b_operand_i;
    wire [DATA_WIDTH-1:0] ex_jump_target = id_ex_jalr_i ?
        {bt_alu_result[DATA_WIDTH-1:1], 1'b0} : id_ex_branch_target_i;
    wire [DATA_WIDTH-1:0] ex_branch_target = id_ex_branch_target_i;
    wire [DATA_WIDTH-1:0] ex_branch_pc = id_ex_branch_next_pc_i - DATA_WIDTH'(4);
    wire [DATA_WIDTH-1:0] ex_branch_next_pc = id_ex_branch_next_pc_i;

    wire ex_bjp_op   = operator_type_i[OPERATOR_TYPE_BJP];
    wire ex_bjp_jump = ex_bjp_op & operator_i[OP_BJP_JUMP];
    wire ex_bjp_beq  = ex_bjp_op & operator_i[OP_BJP_BEQ];
    wire ex_bjp_bne  = ex_bjp_op & operator_i[OP_BJP_BNE];
    wire ex_bjp_blt  = ex_bjp_op & operator_i[OP_BJP_BLT];
    wire ex_bjp_bge  = ex_bjp_op & operator_i[OP_BJP_BGE];
    wire ex_bjp_bltu = ex_bjp_op & operator_i[OP_BJP_BLTU];
    wire ex_bjp_bgeu = ex_bjp_op & operator_i[OP_BJP_BGEU];

    wire ex_is_jump = id_ex_valid_i & ex_bjp_jump;
    wire ex_is_branch =
        id_ex_valid_i &
        (ex_bjp_beq  |
         ex_bjp_bne  |
         ex_bjp_blt  |
         ex_bjp_bge  |
         ex_bjp_bltu |
         ex_bjp_bgeu);

    // Compare only the registered Lane B operands. All bypass selection ended
    // at the Issue/EX boundary.
    wire ex_branch_eq = (operand_a_i == operand_b_i);
    wire ex_branch_ge_signed = ($signed(operand_a_i) >= $signed(operand_b_i));
    wire ex_branch_ge_unsigned = (operand_a_i >= operand_b_i);

    // The request register can retain an old branch opcode after its valid
    // bit has advanced.  Gate the resolved redirect itself, otherwise that
    // stale opcode creates a second redirect with cleared target metadata.
    wire ex_branch_jump = id_ex_valid_i &&
        (ex_bjp_jump |
         (ex_bjp_beq  &  ex_branch_eq) |
         (ex_bjp_bne  & !ex_branch_eq) |
         (ex_bjp_blt  & !ex_branch_ge_signed) |
         (ex_bjp_bge  &  ex_branch_ge_signed) |
         (ex_bjp_bltu & !ex_branch_ge_unsigned) |
         (ex_bjp_bgeu &  ex_branch_ge_unsigned));
    wire ex_branch_taken = ex_is_branch & ex_branch_jump & !trap_redirect_i;
    wire ex_pred_taken = id_ex_pred_hit_i & id_ex_pred_taken_i;
    wire [DATA_WIDTH-1:0] ex_branch_actual_next_pc =
        ex_branch_taken ? ex_branch_target : ex_branch_next_pc;
    wire [DATA_WIDTH-1:0] ex_branch_pred_next_pc =
        ex_pred_taken ? id_ex_pred_target_i : ex_branch_next_pc;
    wire ex_branch_direction_miss = ex_branch_taken ^ ex_pred_taken;
    wire ex_branch_target_miss =
        ex_branch_taken & ex_pred_taken & (ex_branch_target != id_ex_pred_target_i);
    wire ex_branch_mispredict =
        ex_is_branch & !trap_redirect_i &
        (ex_branch_direction_miss | ex_branch_target_miss);
    wire ex_jump_mispredict = ex_is_jump & !trap_redirect_i &
        (!ex_pred_taken || (id_ex_pred_target_i != ex_jump_target));

    wire ex_pc_redirect =
        trap_redirect_i | ex_jump_mispredict | ex_branch_mispredict;
    wire ex_direct_redirect = trap_redirect_i | ex_is_jump;
    ydrasil_bp_train_pkt_t ex_bp_train;

    always_comb begin
        ex_bp_train = '0;
        ex_bp_train.valid = (ex_is_branch | ex_is_jump) & !trap_redirect_i;
        ex_bp_train.producer_id = id_ex_producer_id_i;
        ex_bp_train.conditional = ex_is_branch;
        ex_bp_train.pc = ex_branch_pc;
        ex_bp_train.taken = ex_is_jump | ex_branch_taken;
        ex_bp_train.target = ex_is_jump ? ex_jump_target : ex_branch_target;
        ex_bp_train.counter = id_ex_pred_counter_i;
        ex_bp_train.bht_index = id_ex_pred_bht_index_i;
    end

    reg                       ex2_branch_jump_q;
    reg [DATA_WIDTH-1:0]      ex2_branch_target_q;
    reg                       ex2_pc_redirect_q;
    reg                       ex2_direct_redirect_q;
    reg [DATA_WIDTH-1:0]      ex2_branch_next_pc_q;
    ydrasil_bp_train_pkt_t    ex2_bp_train_q;
    reg                       ex2_branch_mispredict_q;
`ifndef SYNTHESIS
    reg                       dbg_bp_resolve_valid_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_resolve_pc_q;
    reg                       dbg_bp_actual_taken_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_actual_target_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_actual_next_pc_q;
    reg                       dbg_bp_pred_hit_q;
    reg                       dbg_bp_pred_taken_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_pred_target_q;
    reg [1:0]                 dbg_bp_pred_counter_q;
    reg [DATA_WIDTH-1:0]      dbg_bp_pred_next_pc_q;
    reg                       dbg_bp_mispredict_q;
`endif

    // Branch recovery state is on the fetch redirect path.  Keep reset
    // synchronous so these registers can use the FPGA's native CE/reset
    // mapping instead of adding asynchronous-reset routing to the cone.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex2_branch_jump_q <= 1'b0;
            ex2_branch_target_q <= '0;
            ex2_pc_redirect_q <= 1'b0;
            ex2_direct_redirect_q <= 1'b0;
            ex2_branch_next_pc_q <= '0;
            ex2_bp_train_q <= '0;
            ex2_branch_mispredict_q <= 1'b0;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= 1'b0;
            dbg_bp_resolve_pc_q <= '0;
            dbg_bp_actual_taken_q <= 1'b0;
            dbg_bp_actual_target_q <= '0;
            dbg_bp_actual_next_pc_q <= '0;
            dbg_bp_pred_hit_q <= 1'b0;
            dbg_bp_pred_taken_q <= 1'b0;
            dbg_bp_pred_target_q <= '0;
            dbg_bp_pred_counter_q <= 2'b01;
            dbg_bp_pred_next_pc_q <= '0;
            dbg_bp_mispredict_q <= 1'b0;
`endif
        end else if (flush_i) begin
            ex2_branch_jump_q <= 1'b0;
            ex2_branch_target_q <= '0;
            ex2_pc_redirect_q <= 1'b0;
            ex2_direct_redirect_q <= 1'b0;
            ex2_branch_next_pc_q <= '0;
            ex2_bp_train_q <= '0;
            ex2_branch_mispredict_q <= 1'b0;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= 1'b0;
            dbg_bp_resolve_pc_q <= '0;
            dbg_bp_actual_taken_q <= 1'b0;
            dbg_bp_actual_target_q <= '0;
            dbg_bp_actual_next_pc_q <= '0;
            dbg_bp_pred_hit_q <= 1'b0;
            dbg_bp_pred_taken_q <= 1'b0;
            dbg_bp_pred_target_q <= '0;
            dbg_bp_pred_counter_q <= 2'b01;
            dbg_bp_pred_next_pc_q <= '0;
            dbg_bp_mispredict_q <= 1'b0;
`endif
        end else begin
            ex2_branch_jump_q <= ex_branch_jump | trap_redirect_i;
            ex2_branch_target_q <= trap_redirect_i ? trap_redirect_addr_i : ex_jump_target;
            ex2_pc_redirect_q <= ex_pc_redirect;
            ex2_direct_redirect_q <= ex_direct_redirect;
            ex2_branch_next_pc_q <= ex_branch_next_pc;
            ex2_bp_train_q <= ex_bp_train;
            ex2_branch_mispredict_q <= ex_branch_mispredict;
`ifndef SYNTHESIS
            dbg_bp_resolve_valid_q <= ex_is_branch & !trap_redirect_i;
            dbg_bp_resolve_pc_q <= ex_branch_pc;
            dbg_bp_actual_taken_q <= ex_branch_taken;
            dbg_bp_actual_target_q <= ex_branch_target;
            dbg_bp_actual_next_pc_q <= ex_branch_actual_next_pc;
            dbg_bp_pred_hit_q <= id_ex_pred_hit_i;
            dbg_bp_pred_taken_q <= id_ex_pred_taken_i;
            dbg_bp_pred_target_q <= id_ex_pred_target_i;
            dbg_bp_pred_counter_q <= id_ex_pred_counter_i;
            dbg_bp_pred_next_pc_q <= ex_branch_pred_next_pc;
            dbg_bp_mispredict_q <= ex_branch_mispredict;
`endif
        end
    end

    assign ex_branch_jump_o = ex2_branch_jump_q;
    assign ex_branch_target_o = ex2_branch_target_q;
    assign ex_branch_mispredict_o = ex2_branch_mispredict_q;
    assign ex_pc_redirect_o = ex2_pc_redirect_q;
    assign ex_pc_redirect_target_o = ex2_direct_redirect_q ?
        ex2_branch_target_q :
        (ex2_bp_train_q.taken ? ex2_bp_train_q.target : ex2_branch_next_pc_q);
    assign ex_bp_train_o = ex2_bp_train_q;
`ifndef SYNTHESIS
    assign dbg_bp_resolve_valid_o = dbg_bp_resolve_valid_q;
    assign dbg_bp_resolve_pc_o = dbg_bp_resolve_pc_q;
    assign dbg_bp_actual_taken_o = dbg_bp_actual_taken_q;
    assign dbg_bp_actual_target_o = dbg_bp_actual_target_q;
    assign dbg_bp_actual_next_pc_o = dbg_bp_actual_next_pc_q;
    assign dbg_bp_pred_hit_o = dbg_bp_pred_hit_q;
    assign dbg_bp_pred_taken_o = dbg_bp_pred_taken_q;
    assign dbg_bp_pred_target_o = dbg_bp_pred_target_q;
    assign dbg_bp_pred_counter_o = dbg_bp_pred_counter_q;
    assign dbg_bp_pred_next_pc_o = dbg_bp_pred_next_pc_q;
    assign dbg_bp_mispredict_o = dbg_bp_mispredict_q;
`endif

endmodule
