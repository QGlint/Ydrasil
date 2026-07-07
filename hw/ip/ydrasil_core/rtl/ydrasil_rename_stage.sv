module ydrasil_rename_stage
import ydrasil_pkg::*;
import ydrasil_pipeline_pkg::*;
#(
    parameter int DATA_WIDTH = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush_i,
    input  wire              stall_i,
    input  wire              bubble_i,

    input  decode_pair_pkt_t id_decode_pair_i,
    input  rename_pkt_t      rn_live0_i,
	    input  rename_pkt_t      rn_live1_i,
	    input  wire              rn_alloc_stall_i,
	    input  wire              issue_stall_i,
	    input  wire [5:0]        alloc0_rob_idx_i,
	    input  wire [5:0]        alloc1_rob_idx_i,

    output issue_pair_pkt_t  rename_issue_pair_o,
    output wire              rename_frontend_stall_o,

    output wire              rn_alloc_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0] rn_alloc_rd_addr_o,
    output wire              rn_if_rd_valid_o,
    output wire              rn_alloc1_valid_o,
    output wire [REGS_ADDR_WIDTH-1:0] rn_alloc1_rd_addr_o,
    output wire              rn_if1_rd_valid_o,
    output wire              rn_if_ctrl_valid_o
`ifndef SYNTHESIS
    ,
    output wire              commit_trace_alloc_valid_o,
    output wire [DATA_WIDTH-1:0] commit_trace_alloc_pc_o,
    output wire [DATA_WIDTH-1:0] commit_trace_alloc_instr_o,
    output wire              commit_trace_alloc1_valid_o,
    output wire [DATA_WIDTH-1:0] commit_trace_alloc1_pc_o,
    output wire [DATA_WIDTH-1:0] commit_trace_alloc1_instr_o
`endif
);

    issue_pair_pkt_t issue_pair_ff;
    issue_pair_pkt_t issue_pair_next;

    wire slot0_in_valid = id_decode_pair_i.slot0.valid;
    wire slot1_in_valid =
        id_decode_pair_i.pair_ctrl.decode_pair_allow &&
        id_decode_pair_i.pair_ctrl.slot1_valid &&
        id_decode_pair_i.slot1.valid;
    wire slot0_needs_rd =
        id_decode_pair_i.slot0.valid &&
        (id_decode_pair_i.slot0.rf_wen_rd ||
         id_decode_pair_i.slot0.operator_type[OPERATOR_TYPE_LOAD]) &&
        (id_decode_pair_i.slot0.rf_waddr_rd != '0) &&
        !id_decode_pair_i.slot0.operator_type[OPERATOR_TYPE_SYS];
    wire slot1_needs_rd =
        id_decode_pair_i.slot1.valid &&
        (id_decode_pair_i.slot1.rf_wen_rd ||
         id_decode_pair_i.slot1.operator_type[OPERATOR_TYPE_LOAD]) &&
        (id_decode_pair_i.slot1.rf_waddr_rd != '0) &&
        !id_decode_pair_i.slot1.operator_type[OPERATOR_TYPE_SYS];
    wire slot0_needs_rob =
        id_decode_pair_i.slot0.valid &&
        (slot0_needs_rd ||
         id_decode_pair_i.slot0.operator_type[OPERATOR_TYPE_BJP]);

    wire output_valid = issue_pair_ff.slot0.dec.valid;
    wire issue_accept = output_valid && !issue_stall_i;
    wire output_space = !output_valid || issue_accept;
    wire id_input_advance = !stall_i && !bubble_i && !flush_i;
    wire rename_request = id_input_advance && output_space && slot0_in_valid;
    wire rename_accept = rename_request && !rn_alloc_stall_i;

    assign rn_alloc_valid_o = rename_request && slot0_needs_rob;
    assign rn_alloc_rd_addr_o = id_decode_pair_i.slot0.rf_waddr_rd;
    assign rn_if_rd_valid_o = slot0_needs_rd;
    assign rn_if_ctrl_valid_o =
        slot0_in_valid &&
        id_decode_pair_i.slot0.operator_type[OPERATOR_TYPE_BJP];

    assign rn_alloc1_valid_o = rename_request && slot1_in_valid && slot1_needs_rd;
    assign rn_alloc1_rd_addr_o = id_decode_pair_i.slot1.rf_waddr_rd;
    assign rn_if1_rd_valid_o = slot1_in_valid && slot1_needs_rd;

    assign rename_frontend_stall_o =
        id_input_advance && slot0_in_valid && (!output_space || rn_alloc_stall_i);
    assign rename_issue_pair_o = issue_pair_ff;

    always_comb begin
        issue_pair_next = '0;
        issue_pair_next.slot0.dec = id_decode_pair_i.slot0;
	        issue_pair_next.slot0.rn = rn_live0_i;
	        issue_pair_next.slot0.rn.pdst_valid = slot0_needs_rd;
	        issue_pair_next.slot0.rn.rob_idx = alloc0_rob_idx_i;
	        issue_pair_next.slot0.rn.rob_valid = slot0_needs_rob;
	        issue_pair_next.slot0.wait_rs1 = 1'b0;
        issue_pair_next.slot0.wait_rs2 = 1'b0;
        issue_pair_next.pair_ctrl = id_decode_pair_i.pair_ctrl;

        if (slot1_in_valid) begin
            issue_pair_next.slot1.dec = id_decode_pair_i.slot1;
	            issue_pair_next.slot1.rn = rn_live1_i;
	            issue_pair_next.slot1.rn.pdst_valid = slot1_needs_rd;
	            issue_pair_next.slot1.rn.rob_idx = alloc1_rob_idx_i;
	            issue_pair_next.slot1.rn.rob_valid = slot1_needs_rd;
	            issue_pair_next.slot1.wait_rs1 = 1'b0;
            issue_pair_next.slot1.wait_rs2 = 1'b0;
        end else begin
            issue_pair_next.pair_ctrl.slot1_valid = 1'b0;
            issue_pair_next.pair_ctrl.decode_pair_allow = 1'b0;
        end
    end

`ifndef SYNTHESIS
    assign commit_trace_alloc_valid_o = rename_accept && slot0_needs_rd;
    assign commit_trace_alloc_pc_o = id_decode_pair_i.slot0.pc;
    assign commit_trace_alloc_instr_o = id_decode_pair_i.slot0.instr;
    assign commit_trace_alloc1_valid_o = rename_accept && slot1_in_valid && slot1_needs_rd;
    assign commit_trace_alloc1_pc_o = id_decode_pair_i.slot1.pc;
    assign commit_trace_alloc1_instr_o = id_decode_pair_i.slot1.instr;
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_pair_ff <= '0;
        end else if (flush_i) begin
            issue_pair_ff <= '0;
        end else begin
            if (issue_accept) begin
                issue_pair_ff <= '0;
            end
            if (rename_accept) begin
                issue_pair_ff <= issue_pair_next;
            end
        end
    end
endmodule
