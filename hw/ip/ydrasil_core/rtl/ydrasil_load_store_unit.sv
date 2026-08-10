module ydrasil_load_store_unit
import ydrasil_pkg::*;
(
    input  wire                            clk,
    input  wire                            rst_n,
    input  ydrasil_lsu_req_pkt_t           req_i,
    input  wire                            alloc0_valid_i,
    input  producer_id_t                   alloc0_producer_id_i,
    input  wire                            alloc0_is_load_i,
    input  wire                            alloc0_is_store_i,
    input  wire                            alloc1_valid_i,
    input  producer_id_t                   alloc1_producer_id_i,
    input  wire                            alloc1_is_load_i,
    input  wire                            alloc1_is_store_i,
    input  wire                            checkpoint0_valid_i,
    input  producer_id_t                   checkpoint0_id_i,
    input  wire                            checkpoint1_valid_i,
    input  producer_id_t                   checkpoint1_id_i,
    output wire                            alloc_ready_o,
    output wire                            alloc_two_ready_o,
    output producer_slot_t                 alloc0_index_o,
    output producer_slot_t                 alloc1_index_o,
    input  wire                            commit0_valid_i,
    input  producer_id_t                   commit0_id_i,
    input  wire                            commit1_valid_i,
    input  producer_id_t                   commit1_id_i,
    input  wire                            branch_recovery_i,
    input  wire                            trap_flush_i,
    input  producer_slot_t                 recovery_head_slot_i,
    input  producer_slot_t                 recovery_branch_slot_i,
    input  producer_id_t                   recovery_branch_id_i,
    input  producer_id_t                   rob_head_id_i,
    input  ydrasil_completion_meta_t       completion_meta_i [COMPLETION_LANES],
    input  wire [REGS_DATA_WIDTH-1:0]      completion_data_i [COMPLETION_LANES],
    input  wire [BUS_DATA_WIDTH-1:0]       dtcm_rdata_i,
    output wire                            dtcm_load_valid_o,
    output wire [BUS_ADDR_WIDTH-1:0]       dtcm_load_addr_o,
    output wire                            dtcm_store_valid_o,
    output wire [BUS_ADDR_WIDTH-1:0]       dtcm_store_addr_o,
    output wire [BUS_DATA_WIDTH-1:0]       dtcm_store_data_o,
    output wire [3:0]                      dtcm_store_mask_o,
    input  ydrasil_mem_rsp_pkt_t           mmio_rsp_i,
    input  wire                            mmio_ready_i,
    output ydrasil_mem_req_pkt_t           mmio_req_o,
    output ydrasil_lsu_status_pkt_t        status_o,
    output wire                            completion_valid_o,
    output wire [REGS_DATA_WIDTH-1:0]      completion_data_o,
    output wire [REGS_ADDR_WIDTH-1:0]      completion_addr_o,
    output producer_id_t                   completion_producer_id_o,
    output wire                            completion_producer_tracked_o
);
    localparam int LSQ_DEPTH = PRODUCER_NUM;
    localparam int LSQ_COUNT_WIDTH = $clog2(LSQ_DEPTH + 1);

    typedef struct packed {
        logic                         valid;
        logic                         is_load;
        logic                         is_store;
        logic                         addr_valid;
        logic                         addr_is_dtcm;
        // Keep the row for alias checks until retirement, but never launch
        // one memory operation more than once.
        logic                         issued;
        logic [OP_LSU_INFO_WIDTH-1:0] op;
        logic [BUS_ADDR_WIDTH-1:0]    addr;
        logic [REGS_ADDR_WIDTH-1:0]   rd_addr;
        producer_id_t                 producer_id;
        logic                         store_data_valid;
        logic [BUS_DATA_WIDTH-1:0]    store_data;
        logic [3:0]                   store_mask;
        producer_id_t                 store_producer_id;
        logic                         store_producer_tracked;
        logic                         retired;
    } lsq_entry_t;

    lsq_entry_t lsq_q [0:LSQ_DEPTH-1];
    producer_slot_t head_q;
    producer_slot_t tail_q;
    reg [LSQ_COUNT_WIDTH-1:0] count_q;
    // Registered allocation owner credit. The scheduler consumes this token
    // at dispatch and the LSQ returns it after the same-edge remove/recovery
    // update, so admission never depends on the live LSQ count cone.
    reg [LSQ_COUNT_WIDTH-1:0] alloc_credit_q;

    // Dispatch and AGU ownership cross into the LSQ through registered
    // tokens.  The scheduler still receives the live tail/index reservation
    // in the dispatch cycle; these tokens only move the row write and address
    // backfill to the next edge, cutting raw ctrl/issue cones into lsq_q.
    reg alloc0_token_valid_q;
    producer_id_t alloc0_token_producer_id_q;
    reg alloc0_token_is_load_q;
    reg alloc0_token_is_store_q;
    producer_slot_t alloc0_token_index_q;
    reg alloc1_token_valid_q;
    producer_id_t alloc1_token_producer_id_q;
    reg alloc1_token_is_load_q;
    reg alloc1_token_is_store_q;
    producer_slot_t alloc1_token_index_q;
    ydrasil_lsu_req_pkt_t req_token_q;
    wire [1:0] alloc_token_count = {1'b0, alloc0_token_valid_q} +
        {1'b0, alloc1_token_valid_q};

    reg checkpoint_valid_q [0:LSQ_DEPTH-1];
    producer_id_t checkpoint_id_q [0:LSQ_DEPTH-1];
    producer_slot_t checkpoint_head_q [0:LSQ_DEPTH-1];
    producer_slot_t checkpoint_tail_q [0:LSQ_DEPTH-1];
    reg [LSQ_COUNT_WIDTH-1:0] checkpoint_count_q [0:LSQ_DEPTH-1];
    reg checkpoint0_token_valid_q;
    producer_id_t checkpoint0_token_id_q;
    producer_slot_t checkpoint0_token_head_q;
    producer_slot_t checkpoint0_token_tail_q;
    reg [LSQ_COUNT_WIDTH-1:0] checkpoint0_token_count_q;
    reg checkpoint1_token_valid_q;
    producer_id_t checkpoint1_token_id_q;
    producer_slot_t checkpoint1_token_head_q;
    producer_slot_t checkpoint1_token_tail_q;
    reg [LSQ_COUNT_WIDTH-1:0] checkpoint1_token_count_q;
    reg recovery_pending_q;
    producer_slot_t recovery_head_q;
    producer_slot_t recovery_tail_q;
    // Recovery arithmetic consumes a registered post-retirement head and the
    // checkpoint head captured at redirect.  This keeps the LSQ validity
    // window off the live head/LSQ -> ptr_distance timing cone while retaining
    // same-cycle commit/remove semantics at the redirect boundary.
    producer_slot_t recovery_checkpoint_head_q;
    producer_slot_t recovery_head_after_remove_q;
    reg recovery_checkpoint_valid_q;
    reg [LSQ_COUNT_WIDTH-1:0] recovery_checkpoint_count_q;
    wire [LSQ_COUNT_WIDTH-1:0] recovery_retired_count_effective_q =
        recovery_checkpoint_valid_q ?
        LSQ_COUNT_WIDTH'(ptr_distance(recovery_checkpoint_head_q,
                                       recovery_head_after_remove_q)) : '0;
    wire [LSQ_COUNT_WIDTH-1:0] recovery_count_q =
        recovery_checkpoint_valid_q ?
        (recovery_checkpoint_count_q - recovery_retired_count_effective_q) : '0;
    // recovery_tail_q holds the checkpoint tail when one exists.  The
    // no-checkpoint case reuses the separately registered post-remove head,
    // avoiding a live head/remove mux into the recovery token.
    wire producer_slot_t recovery_tail_effective_q =
        recovery_checkpoint_valid_q ? recovery_tail_q :
        recovery_head_after_remove_q;

    function automatic producer_slot_t ptr_add(
        input producer_slot_t base,
        input integer amount
    );
        integer value;
        begin
            value = integer'(base) + amount;
            if (value >= LSQ_DEPTH)
                value = value - LSQ_DEPTH;
            if (value >= LSQ_DEPTH)
                value = value - LSQ_DEPTH;
            ptr_add = producer_slot_t'(value);
        end
    endfunction

    function automatic [LSQ_COUNT_WIDTH-1:0] ptr_distance(
        input producer_slot_t from_ptr,
        input producer_slot_t to_ptr
    );
        integer value;
        begin
            value = integer'(to_ptr) - integer'(from_ptr);
            if (value < 0)
                value = value + LSQ_DEPTH;
            ptr_distance = LSQ_COUNT_WIDTH'(value);
        end
    endfunction

    function automatic logic ptr_in_count(
        input producer_slot_t start_ptr,
        input producer_slot_t value_ptr,
        input [LSQ_COUNT_WIDTH-1:0] span
    );
        ptr_in_count = ptr_distance(start_ptr, value_ptr) < span;
    endfunction

    wire [1:0] alloc_count = {1'b0, alloc0_valid_i} +
        {1'b0, alloc1_valid_i};
    // alloc_credit_q/tail_q describe rows already materialized in lsq_q.
    // Fold in the held allocation token for same-cycle scheduler reservation,
    // while keeping raw accept signals out of the physical state update.
    wire [LSQ_COUNT_WIDTH-1:0] alloc_reservation_credit =
        alloc_credit_q - LSQ_COUNT_WIDTH'(alloc_token_count);
    wire producer_slot_t alloc_reservation_tail = ptr_add(tail_q,
        integer'(alloc_token_count));
    wire count_has_one = alloc_reservation_credit != '0;
    wire count_has_two = alloc_reservation_credit >= LSQ_COUNT_WIDTH'(2);
    assign alloc_ready_o = count_has_one && !recovery_pending_q;
    assign alloc_two_ready_o = count_has_two && !recovery_pending_q;
    assign alloc0_index_o = alloc_reservation_tail;
    // Allocation ports are memory-filtered dispatch ports.  Use the lane-0
    // uop class, rather than alloc_valid feedback, to keep the index path
    // acyclic.  A lane-1 memory uop after a non-memory lane 0 still occupies
    // the current tail.
    wire alloc0_is_memory = alloc0_is_load_i || alloc0_is_store_i;
    assign alloc1_index_o = ptr_add(alloc_reservation_tail,
        alloc0_is_memory ? 1 : 0);

    wire producer_slot_t head1 = ptr_add(head_q, 1);
    wire lsq_entry_t head_entry = lsq_q[head_q];
    wire lsq_entry_t head1_entry = lsq_q[head1];
    wire commit_head_match = head_entry.valid &&
        ((commit0_valid_i && (commit0_id_i == head_entry.producer_id)) ||
         (commit1_valid_i && (commit1_id_i == head_entry.producer_id)));
    wire commit_head1_match = head1_entry.valid &&
        ((commit0_valid_i && (commit0_id_i == head1_entry.producer_id)) ||
         (commit1_valid_i && (commit1_id_i == head1_entry.producer_id)));

    wire mmio_req_valid_q;
    reg mmio_req_valid_r;
    reg mmio_is_load_q;
    reg [BUS_ADDR_WIDTH-1:0] mmio_addr_q;
    reg [BUS_DATA_WIDTH-1:0] mmio_wdata_q;
    reg [3:0] mmio_wmask_q;
    reg [1:0] mmio_addr_index_q;
    reg [OP_LSU_INFO_WIDTH-1:0] mmio_op_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_rd_addr_q;
    producer_id_t mmio_producer_id_q;
    reg mmio_producer_tracked_q;
    reg mmio_wb_valid_q;
    reg [REGS_DATA_WIDTH-1:0] mmio_wb_data_q;
    reg [REGS_ADDR_WIDTH-1:0] mmio_wb_rd_addr_q;
    producer_id_t mmio_wb_producer_id_q;
    reg mmio_wb_tracked_q;
    assign mmio_req_valid_q = mmio_req_valid_r;

    reg load_s1_valid_q;
    reg [REGS_ADDR_WIDTH-1:0] load_s1_rd_addr_q;
    producer_id_t load_s1_producer_id_q;
    reg load_s1_tracked_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_s1_op_q;
    reg [1:0] load_s1_addr_index_q;
    reg [3:0] load_s1_forward_mask_q;
    reg [BUS_DATA_WIDTH-1:0] load_s1_forward_data_q;

    // Registered AGU decision boundary. The forwarding/age scan is allowed
    // to be wide, but it cannot feed the DTCM launch or LSQ write in the same
    // combinational path.
    reg load_issue_valid_q;
    producer_slot_t load_issue_index_q;
    reg [BUS_ADDR_WIDTH-1:0] load_issue_addr_q;
    reg [REGS_ADDR_WIDTH-1:0] load_issue_rd_addr_q;
    producer_id_t load_issue_producer_id_q;
    reg [OP_LSU_INFO_WIDTH-1:0] load_issue_op_q;
    reg [1:0] load_issue_addr_index_q;
    reg [3:0] load_issue_forward_mask_q;
    reg [BUS_DATA_WIDTH-1:0] load_issue_forward_data_q;

    // Final age/forward selection is a separate reservation boundary.  The
    // selector may inspect the banked snapshot, but the issue/fire logic only
    // consumes this registered candidate, keeping LSQ next-state logic out of
    // the launch timing path.
    reg load_candidate_valid_q;
    producer_slot_t load_candidate_index_q;
    lsq_entry_t load_candidate_entry_q;
    reg load_candidate_live_q;
    reg [3:0] load_candidate_forward_mask_q;
    reg [BUS_DATA_WIDTH-1:0] load_candidate_forward_data_q;

    // Registered launch boundary.  The selector and LSQ state update happen
    // at this edge; the memory sees the request during the following cycle.
    // S1 metadata is captured from this register on the next edge, matching
    // the synchronous DTCM read result.
    reg dtcm_launch_valid_q;
    reg [BUS_ADDR_WIDTH-1:0] dtcm_launch_addr_q;
    reg [REGS_ADDR_WIDTH-1:0] dtcm_launch_rd_addr_q;
    producer_id_t dtcm_launch_producer_id_q;
    reg [OP_LSU_INFO_WIDTH-1:0] dtcm_launch_op_q;
    reg [1:0] dtcm_launch_addr_index_q;
    reg [3:0] dtcm_launch_forward_mask_q;
    reg [BUS_DATA_WIDTH-1:0] dtcm_launch_forward_data_q;
    reg dtcm_store_launch_valid_q;
    reg [BUS_ADDR_WIDTH-1:0] dtcm_store_launch_addr_q;
    reg [BUS_DATA_WIDTH-1:0] dtcm_store_launch_data_q;
    reg [3:0] dtcm_store_launch_mask_q;
    reg store_issue_valid_q;
    reg [BUS_ADDR_WIDTH-1:0] store_issue_addr_q;
    reg [BUS_DATA_WIDTH-1:0] store_issue_data_q;
    reg [3:0] store_issue_mask_q;

    wire load_issue_keep = load_issue_valid_q &&
        (!branch_recovery_i || producer_slot_in_window(
            load_issue_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i));

    // Snapshot the LSQ in age order once, then scan two fixed six-entry
    // banks.  The fixed relationships below let synthesis build a bounded
    // compare/reduction tree instead of a pointer-indexed procedural chain.
    localparam int LOAD_SCAN_BANK_DEPTH = LSQ_DEPTH / 2;
    localparam int LSQ_ENTRY_BITS = $bits(lsq_entry_t);
    lsq_entry_t lsq_scan_q [0:LSQ_DEPTH-1];
    producer_slot_t lsq_scan_slot_q [0:LSQ_DEPTH-1];
    reg [LSQ_COUNT_WIDTH-1:0] lsq_scan_count_q;
    lsq_entry_t lsq_bank1_q [0:LSQ_DEPTH-1];
    producer_slot_t lsq_bank1_slot_q [0:LSQ_DEPTH-1];
    reg [LSQ_COUNT_WIDTH-1:0] lsq_bank1_count_q;
    lsq_entry_t lsq_final_q [0:LSQ_DEPTH-1];
    producer_slot_t lsq_final_slot_q [0:LSQ_DEPTH-1];
    reg [LSQ_COUNT_WIDTH-1:0] lsq_final_count_q;

    wire load_scan_base [0:LSQ_DEPTH-1];
    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank0_block_term [0:LSQ_DEPTH-1];
    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank0_writes [0:LSQ_DEPTH-1][0:3];
    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank0_winner [0:LSQ_DEPTH-1][0:3];
    wire load_bank0_block [0:LSQ_DEPTH-1];
    wire load_bank0_eligible_d [0:LSQ_DEPTH-1];
    wire [3:0] load_bank0_mask_d [0:LSQ_DEPTH-1];
    wire [BUS_DATA_WIDTH-1:0] load_bank0_data_d [0:LSQ_DEPTH-1];
    reg [LSQ_DEPTH-1:0] load_bank0_eligible_q;
    reg [3:0] load_bank0_mask_q [0:LSQ_DEPTH-1];
    reg [BUS_DATA_WIDTH-1:0] load_bank0_data_q [0:LSQ_DEPTH-1];

    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank1_block_term [0:LSQ_DEPTH-1];
    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank1_writes [0:LSQ_DEPTH-1][0:3];
    wire [LOAD_SCAN_BANK_DEPTH-1:0] load_bank1_winner [0:LSQ_DEPTH-1][0:3];
    wire load_bank1_block [0:LSQ_DEPTH-1];
    wire load_final_eligible_d [0:LSQ_DEPTH-1];
    wire [3:0] load_final_mask_d [0:LSQ_DEPTH-1];
    wire [BUS_DATA_WIDTH-1:0] load_final_data_d [0:LSQ_DEPTH-1];
    reg [LSQ_DEPTH-1:0] load_final_eligible_q;
    reg [3:0] load_final_mask_q [0:LSQ_DEPTH-1];
    reg [BUS_DATA_WIDTH-1:0] load_final_data_q [0:LSQ_DEPTH-1];

    genvar scan_load_g;
    genvar bank0_store_g;
    genvar bank0_byte_g;
    generate
        for (scan_load_g = 0; scan_load_g < LSQ_DEPTH;
             scan_load_g = scan_load_g + 1) begin : g_load_bank0
            assign load_scan_base[scan_load_g] =
                (scan_load_g < lsq_scan_count_q) &&
                lsq_scan_q[scan_load_g].valid &&
                lsq_scan_q[scan_load_g].is_load &&
                lsq_scan_q[scan_load_g].addr_valid &&
                lsq_scan_q[scan_load_g].addr_is_dtcm &&
                !lsq_scan_q[scan_load_g].issued;
            for (bank0_store_g = 0; bank0_store_g < LOAD_SCAN_BANK_DEPTH;
                 bank0_store_g = bank0_store_g + 1) begin : g_store
                if (bank0_store_g < scan_load_g) begin : g_older
                    wire word_match =
                        lsq_scan_q[bank0_store_g].addr[BUS_ADDR_WIDTH-1:2] ==
                        lsq_scan_q[scan_load_g].addr[BUS_ADDR_WIDTH-1:2];
                    wire store_live = lsq_scan_q[bank0_store_g].valid &&
                        lsq_scan_q[bank0_store_g].is_store;
                    assign load_bank0_block_term[scan_load_g][bank0_store_g] =
                        store_live && (!lsq_scan_q[bank0_store_g].addr_valid ||
                        (word_match && !lsq_scan_q[bank0_store_g].store_data_valid));
                    for (bank0_byte_g = 0; bank0_byte_g < 4;
                         bank0_byte_g = bank0_byte_g + 1) begin : g_byte
                        assign load_bank0_writes[scan_load_g][bank0_byte_g][bank0_store_g] =
                            store_live && lsq_scan_q[bank0_store_g].addr_valid &&
                            lsq_scan_q[bank0_store_g].store_data_valid &&
                            word_match &&
                            lsq_scan_q[bank0_store_g].store_mask[bank0_byte_g];
                        if (bank0_store_g == LOAD_SCAN_BANK_DEPTH - 1) begin : g_youngest
                            assign load_bank0_winner[scan_load_g][bank0_byte_g][bank0_store_g] =
                                load_bank0_writes[scan_load_g][bank0_byte_g][bank0_store_g];
                        end else begin : g_has_younger
                            assign load_bank0_winner[scan_load_g][bank0_byte_g][bank0_store_g] =
                                load_bank0_writes[scan_load_g][bank0_byte_g][bank0_store_g] &&
                                !(|load_bank0_writes[scan_load_g][bank0_byte_g]
                                    [LOAD_SCAN_BANK_DEPTH-1:bank0_store_g+1]);
                        end
                    end
                end else begin : g_not_older
                    assign load_bank0_block_term[scan_load_g][bank0_store_g] = 1'b0;
                    for (bank0_byte_g = 0; bank0_byte_g < 4;
                         bank0_byte_g = bank0_byte_g + 1) begin : g_byte
                        assign load_bank0_writes[scan_load_g][bank0_byte_g][bank0_store_g] = 1'b0;
                        assign load_bank0_winner[scan_load_g][bank0_byte_g][bank0_store_g] = 1'b0;
                    end
                end
            end
            assign load_bank0_block[scan_load_g] =
                |load_bank0_block_term[scan_load_g];
            assign load_bank0_eligible_d[scan_load_g] =
                load_scan_base[scan_load_g] && !load_bank0_block[scan_load_g];
            for (bank0_byte_g = 0; bank0_byte_g < 4;
                 bank0_byte_g = bank0_byte_g + 1) begin : g_result_byte
                assign load_bank0_mask_d[scan_load_g][bank0_byte_g] =
                    |load_bank0_writes[scan_load_g][bank0_byte_g];
                assign load_bank0_data_d[scan_load_g][bank0_byte_g*8 +: 8] =
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][0]}} &
                     lsq_scan_q[0].store_data[bank0_byte_g*8 +: 8]) |
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][1]}} &
                     lsq_scan_q[1].store_data[bank0_byte_g*8 +: 8]) |
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][2]}} &
                     lsq_scan_q[2].store_data[bank0_byte_g*8 +: 8]) |
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][3]}} &
                     lsq_scan_q[3].store_data[bank0_byte_g*8 +: 8]) |
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][4]}} &
                     lsq_scan_q[4].store_data[bank0_byte_g*8 +: 8]) |
                    ({8{load_bank0_winner[scan_load_g][bank0_byte_g][5]}} &
                     lsq_scan_q[5].store_data[bank0_byte_g*8 +: 8]);
            end
        end
    endgenerate

    genvar bank1_load_g;
    genvar bank1_store_g;
    genvar bank1_byte_g;
    generate
        for (bank1_load_g = 0; bank1_load_g < LSQ_DEPTH;
             bank1_load_g = bank1_load_g + 1) begin : g_load_bank1
            for (bank1_store_g = 0; bank1_store_g < LOAD_SCAN_BANK_DEPTH;
                 bank1_store_g = bank1_store_g + 1) begin : g_store
                localparam int STORE_INDEX = LOAD_SCAN_BANK_DEPTH + bank1_store_g;
                if (STORE_INDEX < bank1_load_g) begin : g_older
                    wire word_match =
                        lsq_bank1_q[STORE_INDEX].addr[BUS_ADDR_WIDTH-1:2] ==
                        lsq_bank1_q[bank1_load_g].addr[BUS_ADDR_WIDTH-1:2];
                    wire store_live = lsq_bank1_q[STORE_INDEX].valid &&
                        lsq_bank1_q[STORE_INDEX].is_store;
                    assign load_bank1_block_term[bank1_load_g][bank1_store_g] =
                        store_live && (!lsq_bank1_q[STORE_INDEX].addr_valid ||
                        (word_match && !lsq_bank1_q[STORE_INDEX].store_data_valid));
                    for (bank1_byte_g = 0; bank1_byte_g < 4;
                         bank1_byte_g = bank1_byte_g + 1) begin : g_byte
                        assign load_bank1_writes[bank1_load_g][bank1_byte_g][bank1_store_g] =
                            store_live && lsq_bank1_q[STORE_INDEX].addr_valid &&
                            lsq_bank1_q[STORE_INDEX].store_data_valid &&
                            word_match &&
                            lsq_bank1_q[STORE_INDEX].store_mask[bank1_byte_g];
                        if (bank1_store_g == LOAD_SCAN_BANK_DEPTH - 1) begin : g_youngest
                            assign load_bank1_winner[bank1_load_g][bank1_byte_g][bank1_store_g] =
                                load_bank1_writes[bank1_load_g][bank1_byte_g][bank1_store_g];
                        end else begin : g_has_younger
                            assign load_bank1_winner[bank1_load_g][bank1_byte_g][bank1_store_g] =
                                load_bank1_writes[bank1_load_g][bank1_byte_g][bank1_store_g] &&
                                !(|load_bank1_writes[bank1_load_g][bank1_byte_g]
                                    [LOAD_SCAN_BANK_DEPTH-1:bank1_store_g+1]);
                        end
                    end
                end else begin : g_not_older
                    assign load_bank1_block_term[bank1_load_g][bank1_store_g] = 1'b0;
                    for (bank1_byte_g = 0; bank1_byte_g < 4;
                         bank1_byte_g = bank1_byte_g + 1) begin : g_byte
                        assign load_bank1_writes[bank1_load_g][bank1_byte_g][bank1_store_g] = 1'b0;
                        assign load_bank1_winner[bank1_load_g][bank1_byte_g][bank1_store_g] = 1'b0;
                    end
                end
            end
            assign load_bank1_block[bank1_load_g] =
                |load_bank1_block_term[bank1_load_g];
            assign load_final_eligible_d[bank1_load_g] =
                load_bank0_eligible_q[bank1_load_g] &&
                !load_bank1_block[bank1_load_g];
            for (bank1_byte_g = 0; bank1_byte_g < 4;
                 bank1_byte_g = bank1_byte_g + 1) begin : g_result_byte
                wire bank1_byte_valid =
                    |load_bank1_writes[bank1_load_g][bank1_byte_g];
                wire [7:0] bank1_byte_data =
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][0]}} &
                     lsq_bank1_q[6].store_data[bank1_byte_g*8 +: 8]) |
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][1]}} &
                     lsq_bank1_q[7].store_data[bank1_byte_g*8 +: 8]) |
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][2]}} &
                     lsq_bank1_q[8].store_data[bank1_byte_g*8 +: 8]) |
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][3]}} &
                     lsq_bank1_q[9].store_data[bank1_byte_g*8 +: 8]) |
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][4]}} &
                     lsq_bank1_q[10].store_data[bank1_byte_g*8 +: 8]) |
                    ({8{load_bank1_winner[bank1_load_g][bank1_byte_g][5]}} &
                     lsq_bank1_q[11].store_data[bank1_byte_g*8 +: 8]);
                assign load_final_mask_d[bank1_load_g][bank1_byte_g] =
                    load_bank0_mask_q[bank1_load_g][bank1_byte_g] ||
                    bank1_byte_valid;
                assign load_final_data_d[bank1_load_g][bank1_byte_g*8 +: 8] =
                    bank1_byte_valid ? bank1_byte_data :
                    load_bank0_data_q[bank1_load_g][bank1_byte_g*8 +: 8];
            end
        end
    endgenerate

    wire [LSQ_DEPTH-1:0] load_candidate_select;
    genvar candidate_g;
    generate
        for (candidate_g = 0; candidate_g < LSQ_DEPTH;
             candidate_g = candidate_g + 1) begin : g_load_candidate
            if (candidate_g == 0) begin : g_first
                assign load_candidate_select[candidate_g] =
                    (candidate_g < lsq_final_count_q) &&
                    load_final_eligible_q[candidate_g];
            end else begin : g_later
                assign load_candidate_select[candidate_g] =
                    (candidate_g < lsq_final_count_q) &&
                    load_final_eligible_q[candidate_g] &&
                    !(|load_final_eligible_q[candidate_g-1:0]);
            end
        end
    endgenerate

    wire load_candidate_valid_d = |load_candidate_select;
    wire [PRODUCER_SLOT_WIDTH-1:0] load_index_bits_d =
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[0]}} & lsq_final_slot_q[0]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[1]}} & lsq_final_slot_q[1]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[2]}} & lsq_final_slot_q[2]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[3]}} & lsq_final_slot_q[3]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[4]}} & lsq_final_slot_q[4]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[5]}} & lsq_final_slot_q[5]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[6]}} & lsq_final_slot_q[6]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[7]}} & lsq_final_slot_q[7]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[8]}} & lsq_final_slot_q[8]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[9]}} & lsq_final_slot_q[9]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[10]}} & lsq_final_slot_q[10]) |
        ({PRODUCER_SLOT_WIDTH{load_candidate_select[11]}} & lsq_final_slot_q[11]);
    wire producer_slot_t load_index_d = producer_slot_t'(load_index_bits_d);
    wire [LSQ_ENTRY_BITS-1:0] load_entry_bits_d =
        ({LSQ_ENTRY_BITS{load_candidate_select[0]}} & lsq_final_q[0]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[1]}} & lsq_final_q[1]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[2]}} & lsq_final_q[2]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[3]}} & lsq_final_q[3]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[4]}} & lsq_final_q[4]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[5]}} & lsq_final_q[5]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[6]}} & lsq_final_q[6]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[7]}} & lsq_final_q[7]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[8]}} & lsq_final_q[8]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[9]}} & lsq_final_q[9]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[10]}} & lsq_final_q[10]) |
        ({LSQ_ENTRY_BITS{load_candidate_select[11]}} & lsq_final_q[11]);
    wire lsq_entry_t load_entry_d = lsq_entry_t'(load_entry_bits_d);
    wire [3:0] load_forward_mask_sel_d =
        ({4{load_candidate_select[0]}} & load_final_mask_q[0]) |
        ({4{load_candidate_select[1]}} & load_final_mask_q[1]) |
        ({4{load_candidate_select[2]}} & load_final_mask_q[2]) |
        ({4{load_candidate_select[3]}} & load_final_mask_q[3]) |
        ({4{load_candidate_select[4]}} & load_final_mask_q[4]) |
        ({4{load_candidate_select[5]}} & load_final_mask_q[5]) |
        ({4{load_candidate_select[6]}} & load_final_mask_q[6]) |
        ({4{load_candidate_select[7]}} & load_final_mask_q[7]) |
        ({4{load_candidate_select[8]}} & load_final_mask_q[8]) |
        ({4{load_candidate_select[9]}} & load_final_mask_q[9]) |
        ({4{load_candidate_select[10]}} & load_final_mask_q[10]) |
        ({4{load_candidate_select[11]}} & load_final_mask_q[11]);
    wire [BUS_DATA_WIDTH-1:0] load_forward_data_sel_d =
        ({BUS_DATA_WIDTH{load_candidate_select[0]}} & load_final_data_q[0]) |
        ({BUS_DATA_WIDTH{load_candidate_select[1]}} & load_final_data_q[1]) |
        ({BUS_DATA_WIDTH{load_candidate_select[2]}} & load_final_data_q[2]) |
        ({BUS_DATA_WIDTH{load_candidate_select[3]}} & load_final_data_q[3]) |
        ({BUS_DATA_WIDTH{load_candidate_select[4]}} & load_final_data_q[4]) |
        ({BUS_DATA_WIDTH{load_candidate_select[5]}} & load_final_data_q[5]) |
        ({BUS_DATA_WIDTH{load_candidate_select[6]}} & load_final_data_q[6]) |
        ({BUS_DATA_WIDTH{load_candidate_select[7]}} & load_final_data_q[7]) |
        ({BUS_DATA_WIDTH{load_candidate_select[8]}} & load_final_data_q[8]) |
        ({BUS_DATA_WIDTH{load_candidate_select[9]}} & load_final_data_q[9]) |
        ({BUS_DATA_WIDTH{load_candidate_select[10]}} & load_final_data_q[10]) |
        ({BUS_DATA_WIDTH{load_candidate_select[11]}} & load_final_data_q[11]);

    // The simulated/synthesized DTCM is a one-read/one-write RAM with
    // read-before-write behavior.  A younger load to the same word must wait
    // until a registered store launch has left the port, otherwise it can
    // observe the pre-store value after the store row was retired from LSQ.
    wire load_candidate_live_d = load_candidate_valid_d &&
        lsq_q[load_index_d].valid &&
        (lsq_q[load_index_d].producer_id == load_entry_d.producer_id) &&
        !lsq_q[load_index_d].issued;
    wire dtcm_store_load_conflict = dtcm_store_launch_valid_q &&
        (dtcm_store_launch_addr_q[BUS_ADDR_WIDTH-1:2] ==
         load_candidate_entry_q.addr[BUS_ADDR_WIDTH-1:2]);
    wire load_candidate_reserved = load_issue_valid_q &&
        (load_issue_producer_id_q == load_candidate_entry_q.producer_id);
    wire load_candidate_live = load_candidate_valid_q &&
        load_candidate_live_q && !load_candidate_reserved;
    wire dtcm_load_fire = load_candidate_live &&
        !dtcm_store_load_conflict && !branch_recovery_i &&
        !recovery_pending_q;
    wire head_store_ready = (count_q != '0) && head_entry.valid &&
        head_entry.is_store && head_entry.retired && head_entry.addr_valid &&
        head_entry.store_data_valid;
    // The head store is already retired and therefore architectural.  A
    // redirect can discard younger LSQ rows, but it must never withdraw this
    // side effect.
    wire dtcm_store_fire = head_store_ready && head_entry.addr_is_dtcm &&
        !recovery_pending_q;
    wire mmio_head_candidate = (count_q != '0) && head_entry.valid &&
        !head_entry.addr_is_dtcm && head_entry.addr_valid &&
        !head_entry.issued &&
        (head_entry.producer_id == rob_head_id_i);
    wire mmio_store_candidate = mmio_head_candidate && head_entry.is_store &&
        head_entry.retired && head_entry.store_data_valid;
    wire mmio_load_candidate = mmio_head_candidate && head_entry.is_load;
    wire mmio_busy = mmio_req_valid_q || mmio_wb_valid_q;
    // Capture the request into the registered MMIO token as soon as the
    // retired head is eligible.  The AXI-lite master consumes the held valid
    // request when it becomes ready; a committed store must not be withdrawn
    // by a later redirect or trap.
    wire mmio_store_fire = mmio_store_candidate && !mmio_busy &&
        !recovery_pending_q;
    wire mmio_load_fire = mmio_load_candidate && !mmio_busy &&
        !branch_recovery_i && !recovery_pending_q;
    wire mmio_fire = mmio_store_fire || mmio_load_fire;
    wire head_load_commit_remove = (count_q != '0) && head_entry.valid &&
        head_entry.is_load && commit_head_match;
    wire head_store_remove = dtcm_store_fire || mmio_fire;
    wire head_remove = head_load_commit_remove || head_store_remove;
    wire head1_remove = head_remove && head1_entry.valid &&
        head1_entry.is_load && commit_head1_match;
    wire [1:0] remove_count = head1_remove ? 2'd2 :
        (head_remove ? 2'd1 : 2'd0);
    wire producer_slot_t head_after_remove =
        head1_remove ? ptr_add(head_q, 2) :
        (head_remove ? head1 : head_q);

    wire checkpoint_branch_slot_valid = checkpoint_valid_q[
        recovery_branch_slot_i] &&
        (checkpoint_id_q[recovery_branch_slot_i] == recovery_branch_id_i);

    wire req_existing_match = req_token_q.valid && req_token_q.producer_tracked &&
        lsq_q[req_token_q.lsq_index].valid &&
        (lsq_q[req_token_q.lsq_index].producer_id == req_token_q.producer_id);
    wire [LSQ_DEPTH-1:0] recovery_valid_mask_q;
    genvar recovery_mask_g;
    generate
        for (recovery_mask_g = 0; recovery_mask_g < LSQ_DEPTH;
             recovery_mask_g = recovery_mask_g + 1) begin : g_recovery_mask
            assign recovery_valid_mask_q[recovery_mask_g] =
                ptr_in_count(recovery_head_q,
                    producer_slot_t'(recovery_mask_g), recovery_count_q);
        end
    endgenerate

    // Each row has one fixed combinational next-state writer.  Keeping the
    // row index static prevents a procedural array-bound signal from feeding
    // back into the packed LSQ next-state vector during recovery.
    lsq_entry_t lsq_d [0:LSQ_DEPTH-1];
    genvar lsq_row_g;
    generate
        for (lsq_row_g = 0; lsq_row_g < LSQ_DEPTH; lsq_row_g = lsq_row_g + 1) begin : g_lsq_next
            always_comb begin
                lsq_d[lsq_row_g] = lsq_q[lsq_row_g];

                if (lsq_q[lsq_row_g].valid && lsq_q[lsq_row_g].is_store &&
                    !lsq_q[lsq_row_g].store_data_valid &&
                    lsq_q[lsq_row_g].store_producer_tracked) begin
                    if (completion_meta_i[COMPLETION_ALU].valid &&
                        completion_meta_i[COMPLETION_ALU].producer_tracked &&
                        completion_meta_i[COMPLETION_ALU].producer_id ==
                        lsq_q[lsq_row_g].store_producer_id) begin
                        lsq_d[lsq_row_g].store_data = completion_data_i[COMPLETION_ALU];
                        lsq_d[lsq_row_g].store_data_valid = 1'b1;
                        lsq_d[lsq_row_g].store_producer_tracked = 1'b0;
                    end else if (completion_meta_i[COMPLETION_LSU].valid &&
                        completion_meta_i[COMPLETION_LSU].producer_tracked &&
                        completion_meta_i[COMPLETION_LSU].producer_id ==
                        lsq_q[lsq_row_g].store_producer_id) begin
                        lsq_d[lsq_row_g].store_data = completion_data_i[COMPLETION_LSU];
                        lsq_d[lsq_row_g].store_data_valid = 1'b1;
                        lsq_d[lsq_row_g].store_producer_tracked = 1'b0;
                    end else if (completion_meta_i[COMPLETION_DUAL_ALU].valid &&
                        completion_meta_i[COMPLETION_DUAL_ALU].producer_tracked &&
                        completion_meta_i[COMPLETION_DUAL_ALU].producer_id ==
                        lsq_q[lsq_row_g].store_producer_id) begin
                        lsq_d[lsq_row_g].store_data = completion_data_i[COMPLETION_DUAL_ALU];
                        lsq_d[lsq_row_g].store_data_valid = 1'b1;
                        lsq_d[lsq_row_g].store_producer_tracked = 1'b0;
                    end else if (completion_meta_i[COMPLETION_MUL].valid &&
                        completion_meta_i[COMPLETION_MUL].producer_tracked &&
                        completion_meta_i[COMPLETION_MUL].producer_id ==
                        lsq_q[lsq_row_g].store_producer_id) begin
                        lsq_d[lsq_row_g].store_data = completion_data_i[COMPLETION_MUL];
                        lsq_d[lsq_row_g].store_data_valid = 1'b1;
                        lsq_d[lsq_row_g].store_producer_tracked = 1'b0;
                    end
                end
                if (commit0_valid_i && lsq_q[lsq_row_g].valid &&
                    lsq_q[lsq_row_g].is_store &&
                    (commit0_id_i == lsq_q[lsq_row_g].producer_id))
                    lsq_d[lsq_row_g].retired = 1'b1;
                if (commit1_valid_i && lsq_q[lsq_row_g].valid &&
                    lsq_q[lsq_row_g].is_store &&
                    (commit1_id_i == lsq_q[lsq_row_g].producer_id))
                    lsq_d[lsq_row_g].retired = 1'b1;

                if (!branch_recovery_i && !recovery_pending_q) begin
                    if (alloc0_token_valid_q && (alloc0_token_index_q ==
                        producer_slot_t'(lsq_row_g))) begin
                        lsq_d[lsq_row_g] = '0;
                        lsq_d[lsq_row_g].valid = 1'b1;
                        lsq_d[lsq_row_g].is_load = alloc0_token_is_load_q;
                        lsq_d[lsq_row_g].is_store = alloc0_token_is_store_q;
                        lsq_d[lsq_row_g].producer_id = alloc0_token_producer_id_q;
                    end
                    if (alloc1_token_valid_q &&
                        (alloc1_token_index_q ==
                         producer_slot_t'(lsq_row_g))) begin
                        lsq_d[lsq_row_g] = '0;
                        lsq_d[lsq_row_g].valid = 1'b1;
                        lsq_d[lsq_row_g].is_load = alloc1_token_is_load_q;
                        lsq_d[lsq_row_g].is_store = alloc1_token_is_store_q;
                        lsq_d[lsq_row_g].producer_id = alloc1_token_producer_id_q;
                    end
                end

                if (req_existing_match && (req_token_q.lsq_index ==
                    producer_slot_t'(lsq_row_g))) begin
                    lsq_d[lsq_row_g].addr_valid = 1'b1;
                    lsq_d[lsq_row_g].addr = req_token_q.addr;
                    lsq_d[lsq_row_g].addr_is_dtcm = req_token_q.addr_is_dtcm;
                    lsq_d[lsq_row_g].op = req_token_q.op;
                    lsq_d[lsq_row_g].rd_addr = req_token_q.rd_addr;
                    if (req_token_q.is_store) begin
                        lsq_d[lsq_row_g].store_producer_id = req_token_q.store_producer_id;
                        lsq_d[lsq_row_g].store_mask = req_token_q.store_mask;
                        if (req_token_q.store_data_valid) begin
                            lsq_d[lsq_row_g].store_data = req_token_q.store_data;
                            lsq_d[lsq_row_g].store_data_valid = 1'b1;
                            lsq_d[lsq_row_g].store_producer_tracked = 1'b0;
                        end else if (!lsq_d[lsq_row_g].store_data_valid)
                            lsq_d[lsq_row_g].store_producer_tracked =
                                req_token_q.store_producer_tracked;
                    end
                end

                if (dtcm_load_fire && (load_candidate_index_q ==
                    producer_slot_t'(lsq_row_g)))
                    lsq_d[lsq_row_g].issued = 1'b1;
                if (mmio_fire && (head_q == producer_slot_t'(lsq_row_g)))
                    lsq_d[lsq_row_g].issued = 1'b1;

                if (!branch_recovery_i && !recovery_pending_q) begin
                    if (head_remove && (head_q == producer_slot_t'(lsq_row_g)))
                        lsq_d[lsq_row_g].valid = 1'b0;
                    if (head1_remove && (head1 == producer_slot_t'(lsq_row_g)))
                        lsq_d[lsq_row_g].valid = 1'b0;
                end else if (recovery_pending_q) begin
                    lsq_d[lsq_row_g].valid = recovery_valid_mask_q[lsq_row_g];
                end
            end
        end
    endgenerate

    reg [BUS_DATA_WIDTH-1:0] dtcm_load_word;
    reg [BUS_DATA_WIDTH-1:0] dtcm_load_shifted;
    reg [REGS_DATA_WIDTH-1:0] dtcm_load_result;
    reg [REGS_DATA_WIDTH-1:0] mmio_load_shifted;
    reg [REGS_DATA_WIDTH-1:0] mmio_load_result;
    integer format_byte;
    always_comb begin
        dtcm_load_word = dtcm_rdata_i;
        for (format_byte = 0; format_byte < 4; format_byte = format_byte + 1)
            if (load_s1_forward_mask_q[format_byte])
                dtcm_load_word[format_byte*8 +: 8] =
                    load_s1_forward_data_q[format_byte*8 +: 8];
        dtcm_load_shifted = dtcm_load_word >>
            ({3'b000, load_s1_addr_index_q} << 3);
        unique case (1'b1)
            load_s1_op_q[OP_LSU_LB]:
                dtcm_load_result = {{24{dtcm_load_shifted[7]}}, dtcm_load_shifted[7:0]};
            load_s1_op_q[OP_LSU_LBU]:
                dtcm_load_result = {24'b0, dtcm_load_shifted[7:0]};
            load_s1_op_q[OP_LSU_LH]:
                dtcm_load_result = {{16{dtcm_load_shifted[15]}}, dtcm_load_shifted[15:0]};
            load_s1_op_q[OP_LSU_LHU]:
                dtcm_load_result = {16'b0, dtcm_load_shifted[15:0]};
            default: dtcm_load_result = dtcm_load_shifted;
        endcase

        mmio_load_shifted = mmio_rsp_i.rdata >>
            ({3'b000, mmio_addr_index_q} << 3);
        unique case (1'b1)
            mmio_op_q[OP_LSU_LB]:
                mmio_load_result = {{24{mmio_load_shifted[7]}}, mmio_load_shifted[7:0]};
            mmio_op_q[OP_LSU_LBU]:
                mmio_load_result = {24'b0, mmio_load_shifted[7:0]};
            mmio_op_q[OP_LSU_LH]:
                mmio_load_result = {{16{mmio_load_shifted[15]}}, mmio_load_shifted[15:0]};
            mmio_op_q[OP_LSU_LHU]:
                mmio_load_result = {16'b0, mmio_load_shifted[15:0]};
            default: mmio_load_result = mmio_load_shifted;
        endcase
    end

    wire load_response_keep = load_s1_valid_q &&
        (!branch_recovery_i || producer_slot_in_window(
            load_s1_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i));
    wire dtcm_launch_keep = dtcm_launch_valid_q &&
        (!branch_recovery_i || producer_slot_in_window(
            dtcm_launch_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i));
    wire mmio_request_keep = mmio_req_valid_q &&
        (!mmio_is_load_q || !branch_recovery_i || producer_slot_in_window(
            mmio_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i));
    wire mmio_response_keep = mmio_wb_valid_q &&
        (!branch_recovery_i || producer_slot_in_window(
            mmio_wb_producer_id_q[PRODUCER_SLOT_WIDTH-1:0],
            recovery_head_slot_i, recovery_branch_slot_i));
    wire mmio_rsp_keep = mmio_req_valid_q && mmio_rsp_i.valid &&
        mmio_is_load_q && mmio_request_keep;
    wire mmio_response_valid = mmio_response_keep && !load_response_keep;
    assign completion_valid_o = load_response_keep ? load_s1_tracked_q :
        (mmio_response_valid && mmio_wb_tracked_q);
    assign completion_data_o = load_response_keep ? dtcm_load_result :
        mmio_wb_data_q;
    assign completion_addr_o = load_response_keep ? load_s1_rd_addr_q :
        mmio_wb_rd_addr_q;
    assign completion_producer_id_o = load_response_keep ? load_s1_producer_id_q :
        mmio_wb_producer_id_q;
    assign completion_producer_tracked_o = load_response_keep ? load_s1_tracked_q :
        mmio_wb_tracked_q;

    assign dtcm_load_valid_o = dtcm_launch_keep && !trap_flush_i;
    assign dtcm_load_addr_o = dtcm_launch_addr_q;
    assign dtcm_store_valid_o = dtcm_store_launch_valid_q;
    assign dtcm_store_addr_o = dtcm_store_launch_addr_q;
    assign dtcm_store_data_o = dtcm_store_launch_data_q;
    assign dtcm_store_mask_o = dtcm_store_launch_mask_q;

    wire mmio_request_visible = mmio_request_keep &&
        (!trap_flush_i || !mmio_is_load_q);
    assign mmio_req_o.valid = mmio_request_visible;
    assign mmio_req_o.write = mmio_request_visible && !mmio_is_load_q;
    assign mmio_req_o.addr = mmio_addr_q;
    assign mmio_req_o.wdata = mmio_wdata_q;
    assign mmio_req_o.wmask = (mmio_request_visible && !mmio_is_load_q) ?
        mmio_wmask_q : 4'b0;

    assign status_o.busy = (alloc_reservation_credit == '0);
    assign status_o.idle = (count_q == '0) && (alloc_token_count == '0) && !mmio_busy &&
        !recovery_pending_q &&
        !load_issue_valid_q && !dtcm_launch_valid_q && !load_s1_valid_q &&
        !store_issue_valid_q && !dtcm_store_launch_valid_q;
    assign status_o.fast_load = 1'b0;

    // One sequential writer per row keeps allocation, AGU, completion and
    // recovery on the same registered boundary without a multiwrite array
    // endpoint in the structural model.
    genvar lsq_row_ff_g;
    generate
        for (lsq_row_ff_g = 0; lsq_row_ff_g < LSQ_DEPTH;
             lsq_row_ff_g = lsq_row_ff_g + 1) begin : g_lsq_row_ff
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n || trap_flush_i)
                    lsq_q[lsq_row_ff_g] <= '0;
                else
                    lsq_q[lsq_row_ff_g] <= lsq_d[lsq_row_ff_g];
            end
        end
    endgenerate

    integer lsq_idx;
    integer load_pipe_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            alloc_credit_q <= LSQ_COUNT_WIDTH'(LSQ_DEPTH);
            alloc0_token_valid_q <= 1'b0;
            alloc0_token_producer_id_q <= '0;
            alloc0_token_is_load_q <= 1'b0;
            alloc0_token_is_store_q <= 1'b0;
            alloc0_token_index_q <= '0;
            alloc1_token_valid_q <= 1'b0;
            alloc1_token_producer_id_q <= '0;
            alloc1_token_is_load_q <= 1'b0;
            alloc1_token_is_store_q <= 1'b0;
            alloc1_token_index_q <= '0;
            req_token_q <= '0;
            recovery_pending_q <= 1'b0;
            recovery_head_q <= '0;
            recovery_tail_q <= '0;
            recovery_checkpoint_head_q <= '0;
            recovery_head_after_remove_q <= '0;
            recovery_checkpoint_valid_q <= 1'b0;
            recovery_checkpoint_count_q <= '0;
            mmio_req_valid_r <= 1'b0;
            mmio_is_load_q <= 1'b0;
            mmio_addr_q <= '0;
            mmio_wdata_q <= '0;
            mmio_wmask_q <= '0;
            mmio_addr_index_q <= '0;
            mmio_op_q <= '0;
            mmio_rd_addr_q <= '0;
            mmio_producer_id_q <= '0;
            mmio_producer_tracked_q <= 1'b0;
            mmio_wb_valid_q <= 1'b0;
            mmio_wb_data_q <= '0;
            mmio_wb_rd_addr_q <= '0;
            mmio_wb_producer_id_q <= '0;
            mmio_wb_tracked_q <= 1'b0;
            load_s1_valid_q <= 1'b0;
            load_s1_rd_addr_q <= '0;
            load_s1_producer_id_q <= '0;
            load_s1_tracked_q <= 1'b0;
            load_s1_op_q <= '0;
            load_s1_addr_index_q <= '0;
            load_s1_forward_mask_q <= '0;
            load_s1_forward_data_q <= '0;
            load_issue_valid_q <= 1'b0;
            load_issue_index_q <= '0;
            load_issue_addr_q <= '0;
            load_issue_rd_addr_q <= '0;
            load_issue_producer_id_q <= '0;
            load_issue_op_q <= '0;
            load_issue_addr_index_q <= '0;
            load_issue_forward_mask_q <= '0;
            load_issue_forward_data_q <= '0;
            load_candidate_valid_q <= 1'b0;
            load_candidate_index_q <= '0;
            load_candidate_entry_q <= '0;
            load_candidate_live_q <= 1'b0;
            load_candidate_forward_mask_q <= '0;
            load_candidate_forward_data_q <= '0;
            dtcm_launch_valid_q <= 1'b0;
            dtcm_launch_addr_q <= '0;
            dtcm_launch_rd_addr_q <= '0;
            dtcm_launch_producer_id_q <= '0;
            dtcm_launch_op_q <= '0;
            dtcm_launch_addr_index_q <= '0;
            dtcm_launch_forward_mask_q <= '0;
            dtcm_launch_forward_data_q <= '0;
            for (lsq_idx = 0; lsq_idx < LSQ_DEPTH; lsq_idx = lsq_idx + 1) begin
                checkpoint_valid_q[lsq_idx] <= 1'b0;
                checkpoint_id_q[lsq_idx] <= '0;
                checkpoint_head_q[lsq_idx] <= '0;
                checkpoint_tail_q[lsq_idx] <= '0;
                checkpoint_count_q[lsq_idx] <= '0;
            end
            checkpoint0_token_valid_q <= 1'b0;
            checkpoint0_token_id_q <= '0;
            checkpoint0_token_head_q <= '0;
            checkpoint0_token_tail_q <= '0;
            checkpoint0_token_count_q <= '0;
            checkpoint1_token_valid_q <= 1'b0;
            checkpoint1_token_id_q <= '0;
            checkpoint1_token_head_q <= '0;
            checkpoint1_token_tail_q <= '0;
            checkpoint1_token_count_q <= '0;
        end else if (trap_flush_i) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            alloc_credit_q <= LSQ_COUNT_WIDTH'(LSQ_DEPTH);
            alloc0_token_valid_q <= 1'b0;
            alloc1_token_valid_q <= 1'b0;
            req_token_q <= '0;
            recovery_pending_q <= 1'b0;
            recovery_head_q <= '0;
            recovery_tail_q <= '0;
            recovery_checkpoint_head_q <= '0;
            recovery_head_after_remove_q <= '0;
            recovery_checkpoint_valid_q <= 1'b0;
            recovery_checkpoint_count_q <= '0;
            // A retired MMIO store is an architectural side effect.  Keep
            // its request token alive through trap recovery until the AXI
            // response arrives; speculative MMIO loads may be discarded.
            if (mmio_req_valid_q && mmio_rsp_i.valid) begin
                if (mmio_store_candidate) begin
                    // The response retired the previous request.  Reuse the
                    // token for the next architectural store before the LSQ
                    // is flushed, preserving one side effect per response.
                    mmio_req_valid_r <= 1'b1;
                    mmio_is_load_q <= 1'b0;
                    mmio_addr_q <= head_entry.addr;
                    mmio_wdata_q <= head_entry.store_data;
                    mmio_wmask_q <= head_entry.op[OP_LSU_SB] ?
                        (4'b0001 << head_entry.addr[1:0]) :
                        head_entry.op[OP_LSU_SH] ?
                        (head_entry.addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
                    mmio_addr_index_q <= head_entry.addr[1:0];
                    mmio_op_q <= head_entry.op;
                    mmio_rd_addr_q <= head_entry.rd_addr;
                    mmio_producer_id_q <= head_entry.producer_id;
                    mmio_producer_tracked_q <= 1'b0;
                end else begin
                    mmio_req_valid_r <= 1'b0;
                end
            end else if (mmio_req_valid_q && !mmio_is_load_q) begin
                mmio_req_valid_r <= 1'b1;
            end else if (mmio_store_candidate && !mmio_busy) begin
                // Capture a just-retired store even when trap_flush shares
                // the cycle with retirement.  The LSQ is cleared below, so
                // all request metadata must be copied into this token now.
                mmio_req_valid_r <= 1'b1;
                mmio_is_load_q <= 1'b0;
                mmio_addr_q <= head_entry.addr;
                mmio_wdata_q <= head_entry.store_data;
                mmio_wmask_q <= head_entry.op[OP_LSU_SB] ?
                    (4'b0001 << head_entry.addr[1:0]) :
                    head_entry.op[OP_LSU_SH] ?
                    (head_entry.addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
                mmio_addr_index_q <= head_entry.addr[1:0];
                mmio_op_q <= head_entry.op;
                mmio_rd_addr_q <= head_entry.rd_addr;
                mmio_producer_id_q <= head_entry.producer_id;
                mmio_producer_tracked_q <= 1'b0;
            end else begin
                mmio_req_valid_r <= 1'b0;
            end
            mmio_wb_valid_q <= 1'b0;
            load_s1_valid_q <= 1'b0;
            load_issue_valid_q <= 1'b0;
            load_candidate_valid_q <= 1'b0;
            load_candidate_live_q <= 1'b0;
            dtcm_launch_valid_q <= 1'b0;
            for (lsq_idx = 0; lsq_idx < LSQ_DEPTH; lsq_idx = lsq_idx + 1) begin
                checkpoint_valid_q[lsq_idx] <= 1'b0;
            end
            checkpoint0_token_valid_q <= 1'b0;
            checkpoint1_token_valid_q <= 1'b0;
        end else begin
            // Registered ownership handoff.  The live alloc indices remain
            // visible to scheduler admission in this cycle, while row
            // allocation, AGU backfill, and checkpoint capture consume the
            // previous-cycle tokens below.
            if (branch_recovery_i || recovery_pending_q) begin
                alloc0_token_valid_q <= 1'b0;
                alloc1_token_valid_q <= 1'b0;
                req_token_q.valid <= 1'b0;
                checkpoint0_token_valid_q <= 1'b0;
                checkpoint1_token_valid_q <= 1'b0;
            end else begin
                alloc0_token_valid_q <= alloc0_valid_i;
                alloc0_token_producer_id_q <= alloc0_producer_id_i;
                alloc0_token_is_load_q <= alloc0_is_load_i;
                alloc0_token_is_store_q <= alloc0_is_store_i;
                alloc0_token_index_q <= alloc_reservation_tail;
                alloc1_token_valid_q <= alloc1_valid_i;
                alloc1_token_producer_id_q <= alloc1_producer_id_i;
                alloc1_token_is_load_q <= alloc1_is_load_i;
                alloc1_token_is_store_q <= alloc1_is_store_i;
                alloc1_token_index_q <= ptr_add(alloc_reservation_tail,
                    alloc0_is_memory ? 1 : 0);
                req_token_q <= req_i;

                checkpoint0_token_valid_q <= checkpoint0_valid_i;
                checkpoint0_token_id_q <= checkpoint0_id_i;
                checkpoint0_token_head_q <= head_q;
                checkpoint0_token_tail_q <= ptr_add(alloc_reservation_tail,
                    alloc0_valid_i ? 1 : 0);
                checkpoint0_token_count_q <= count_q +
                    LSQ_COUNT_WIDTH'(alloc_token_count) +
                    LSQ_COUNT_WIDTH'(alloc0_valid_i ? 1 : 0);
                checkpoint1_token_valid_q <= checkpoint1_valid_i;
                checkpoint1_token_id_q <= checkpoint1_id_i;
                checkpoint1_token_head_q <= head_q;
                checkpoint1_token_tail_q <= ptr_add(alloc_reservation_tail,
                    integer'(alloc_count));
                checkpoint1_token_count_q <= count_q +
                    LSQ_COUNT_WIDTH'(alloc_token_count) +
                    LSQ_COUNT_WIDTH'(alloc_count);
            end

            // Lock the oldest eligible snapshot result before it reaches the
            // issue/fire decision.  Liveness is sampled against the current
            // LSQ at this boundary; recovery clears the valid bit above.
            if (branch_recovery_i || recovery_pending_q) begin
                load_candidate_valid_q <= 1'b0;
                load_candidate_live_q <= 1'b0;
            end else begin
                load_candidate_valid_q <= load_candidate_valid_d;
                load_candidate_live_q <= load_candidate_live_d;
                if (load_candidate_valid_d) begin
                    load_candidate_index_q <= load_index_d;
                    load_candidate_entry_q <= load_entry_d;
                    load_candidate_forward_mask_q <= load_forward_mask_sel_d;
                    load_candidate_forward_data_q <= load_forward_data_sel_d;
                end
            end

            // Advance the registered launch into the response/S1 boundary.
            // DTCM is synchronous, so this metadata is sampled on the same
            // edge that returns the word selected by the launch register.
            load_s1_valid_q <= dtcm_launch_keep;
            if (dtcm_launch_keep) begin
                load_s1_rd_addr_q <= dtcm_launch_rd_addr_q;
                load_s1_producer_id_q <= dtcm_launch_producer_id_q;
                load_s1_tracked_q <= 1'b1;
                load_s1_op_q <= dtcm_launch_op_q;
                load_s1_addr_index_q <= dtcm_launch_addr_index_q;
                load_s1_forward_mask_q <= dtcm_launch_forward_mask_q;
                load_s1_forward_data_q <= dtcm_launch_forward_data_q;
            end
            // First register the AGU decision, then launch it on the next
            // edge. The LSQ issued bit and DTCM metadata share this boundary.
            load_issue_valid_q <= dtcm_load_fire;
            if (dtcm_load_fire) begin
                load_issue_index_q <= load_candidate_index_q;
                load_issue_addr_q <= load_candidate_entry_q.addr;
                load_issue_rd_addr_q <= load_candidate_entry_q.rd_addr;
                load_issue_producer_id_q <= load_candidate_entry_q.producer_id;
                load_issue_op_q <= load_candidate_entry_q.op;
                load_issue_addr_index_q <= load_candidate_entry_q.addr[1:0];
                load_issue_forward_mask_q <= load_candidate_forward_mask_q;
                load_issue_forward_data_q <= load_candidate_forward_data_q;
            end
            dtcm_launch_valid_q <= load_issue_keep;
            if (load_issue_keep) begin
                dtcm_launch_addr_q <= load_issue_addr_q;
                dtcm_launch_rd_addr_q <= load_issue_rd_addr_q;
                dtcm_launch_producer_id_q <= load_issue_producer_id_q;
                dtcm_launch_op_q <= load_issue_op_q;
                dtcm_launch_addr_index_q <= load_issue_addr_index_q;
                dtcm_launch_forward_mask_q <= load_issue_forward_mask_q;
                dtcm_launch_forward_data_q <= load_issue_forward_data_q;
            end

            if (mmio_fire) begin
                mmio_req_valid_r <= 1'b1;
                mmio_is_load_q <= mmio_load_candidate;
                mmio_addr_q <= head_entry.addr;
                mmio_wdata_q <= head_entry.store_data;
                mmio_wmask_q <= head_entry.op[OP_LSU_SB] ?
                    (4'b0001 << head_entry.addr[1:0]) :
                    head_entry.op[OP_LSU_SH] ?
                    (head_entry.addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
                mmio_addr_index_q <= head_entry.addr[1:0];
                mmio_op_q <= head_entry.op;
                mmio_rd_addr_q <= head_entry.rd_addr;
                mmio_producer_id_q <= head_entry.producer_id;
                mmio_producer_tracked_q <= mmio_load_candidate;
            end
            if (mmio_req_valid_q && mmio_rsp_i.valid) begin
                mmio_req_valid_r <= 1'b0;
                if (mmio_is_load_q) begin
                    mmio_wb_valid_q <= 1'b1;
                    mmio_wb_data_q <= mmio_load_result;
                    mmio_wb_rd_addr_q <= mmio_rd_addr_q;
                    mmio_wb_producer_id_q <= mmio_producer_id_q;
                    mmio_wb_tracked_q <= mmio_producer_tracked_q;
                end
            end else if (mmio_wb_valid_q && !load_response_keep) begin
                mmio_wb_valid_q <= 1'b0;
            end

            if (branch_recovery_i) begin
                recovery_pending_q <= 1'b1;
                recovery_head_q <= head_after_remove;
                recovery_tail_q <= checkpoint_branch_slot_valid ?
                    checkpoint_tail_q[recovery_branch_slot_i] : '0;
                recovery_checkpoint_head_q <= checkpoint_branch_slot_valid ?
                    checkpoint_head_q[recovery_branch_slot_i] : '0;
                recovery_head_after_remove_q <= head_after_remove;
                recovery_checkpoint_valid_q <= checkpoint_branch_slot_valid;
                recovery_checkpoint_count_q <= checkpoint_branch_slot_valid ?
                    checkpoint_count_q[recovery_branch_slot_i] : '0;
            end else if (recovery_pending_q) begin
                recovery_pending_q <= 1'b0;
            end

            if (!branch_recovery_i && !recovery_pending_q) begin
                if (checkpoint0_token_valid_q) begin
                    checkpoint_valid_q[checkpoint0_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
                    checkpoint_id_q[checkpoint0_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= checkpoint0_token_id_q;
                    checkpoint_head_q[checkpoint0_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= checkpoint0_token_head_q;
                    checkpoint_tail_q[checkpoint0_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <=
                        checkpoint0_token_tail_q;
                    checkpoint_count_q[checkpoint0_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <=
                        checkpoint0_token_count_q;
                end
                if (checkpoint1_token_valid_q) begin
                    checkpoint_valid_q[checkpoint1_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= 1'b1;
                    checkpoint_id_q[checkpoint1_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= checkpoint1_token_id_q;
                    checkpoint_head_q[checkpoint1_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <= checkpoint1_token_head_q;
                    checkpoint_tail_q[checkpoint1_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <=
                        checkpoint1_token_tail_q;
                    checkpoint_count_q[checkpoint1_token_id_q[PRODUCER_SLOT_WIDTH-1:0]] <=
                        checkpoint1_token_count_q;
                end
                if (head_remove)
                    head_q <= head_after_remove;
                if (alloc_token_count != '0)
                    tail_q <= ptr_add(tail_q, integer'(alloc_token_count));
                count_q <= count_q + LSQ_COUNT_WIDTH'(alloc_token_count) -
                    LSQ_COUNT_WIDTH'(remove_count);
                alloc_credit_q <= LSQ_COUNT_WIDTH'(LSQ_DEPTH) -
                    (count_q + LSQ_COUNT_WIDTH'(alloc_token_count) -
                     LSQ_COUNT_WIDTH'(remove_count));
                for (lsq_idx = 0; lsq_idx < LSQ_DEPTH; lsq_idx = lsq_idx + 1) begin
                    if ((commit0_valid_i && checkpoint_valid_q[lsq_idx] &&
                         checkpoint_id_q[lsq_idx] == commit0_id_i) ||
                        (commit1_valid_i && checkpoint_valid_q[lsq_idx] &&
                         checkpoint_id_q[lsq_idx] == commit1_id_i))
                        checkpoint_valid_q[lsq_idx] <= 1'b0;
                end
            end else if (branch_recovery_i) begin
                // recovery_head_slot_i is a ROB slot, not an LSQ pointer.
                // Older LSQ rows may have retired since the checkpoint was
                // captured, so rebuild from the current post-retirement head.
                if (!mmio_request_keep && !mmio_store_fire)
                    mmio_req_valid_r <= 1'b0;
                if (!(mmio_response_keep || mmio_rsp_keep))
                    mmio_wb_valid_q <= 1'b0;
                for (lsq_idx = 0; lsq_idx < LSQ_DEPTH; lsq_idx = lsq_idx + 1) begin
                    checkpoint_valid_q[lsq_idx] <= checkpoint_valid_q[lsq_idx] &&
                        producer_slot_in_window(
                            checkpoint_id_q[lsq_idx][PRODUCER_SLOT_WIDTH-1:0],
                            recovery_head_slot_i, recovery_branch_slot_i);
                end
            end else begin
                // Apply the registered recovery token one cycle after the
                // redirect.  Allocation, issue and memory fire are quiesced
                // while this boundary updates the row validity mask.
                head_q <= recovery_head_q;
                tail_q <= recovery_tail_effective_q;
                count_q <= recovery_count_q;
                alloc_credit_q <= LSQ_COUNT_WIDTH'(LSQ_DEPTH) -
                    recovery_count_q;
            end
        end
    end

    // A retired store is an architectural side effect, not speculative work.
    // Keep this two-stage token alive through redirects and trap flushes. The
    // pipeline accepts one new DTCM store per cycle while the previous token
    // advances to the external write port.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            store_issue_valid_q <= 1'b0;
            store_issue_addr_q <= '0;
            store_issue_data_q <= '0;
            store_issue_mask_q <= '0;
            dtcm_store_launch_valid_q <= 1'b0;
            dtcm_store_launch_addr_q <= '0;
            dtcm_store_launch_data_q <= '0;
            dtcm_store_launch_mask_q <= '0;
        end else begin
            dtcm_store_launch_valid_q <= store_issue_valid_q;
            if (store_issue_valid_q) begin
                dtcm_store_launch_addr_q <= store_issue_addr_q;
                dtcm_store_launch_data_q <= store_issue_data_q;
                dtcm_store_launch_mask_q <= store_issue_mask_q;
            end
            store_issue_valid_q <= dtcm_store_fire;
            if (dtcm_store_fire) begin
                store_issue_addr_q <= head_entry.addr;
                store_issue_data_q <= head_entry.store_data;
                store_issue_mask_q <= head_entry.op[OP_LSU_SB] ?
                    (4'b0001 << head_entry.addr[1:0]) :
                    head_entry.op[OP_LSU_SH] ?
                    (head_entry.addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
            end
        end
    end

    // The age snapshot, bank-0 result, and bank-1 result are separate
    // register boundaries. A branch/trap drops all pending scan work; the
    // survivor rows are sampled again after recovery has updated the LSQ.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || trap_flush_i || branch_recovery_i || recovery_pending_q) begin
            lsq_scan_count_q <= '0;
            lsq_bank1_count_q <= '0;
            lsq_final_count_q <= '0;
            for (load_pipe_idx = 0; load_pipe_idx < LSQ_DEPTH;
                 load_pipe_idx = load_pipe_idx + 1) begin
                lsq_scan_q[load_pipe_idx] <= '0;
                lsq_scan_slot_q[load_pipe_idx] <= '0;
                lsq_bank1_q[load_pipe_idx] <= '0;
                lsq_bank1_slot_q[load_pipe_idx] <= '0;
                lsq_final_q[load_pipe_idx] <= '0;
                lsq_final_slot_q[load_pipe_idx] <= '0;
                load_bank0_eligible_q[load_pipe_idx] <= 1'b0;
                load_bank0_mask_q[load_pipe_idx] <= '0;
                load_bank0_data_q[load_pipe_idx] <= '0;
                load_final_eligible_q[load_pipe_idx] <= 1'b0;
                load_final_mask_q[load_pipe_idx] <= '0;
                load_final_data_q[load_pipe_idx] <= '0;
            end
        end else begin
            lsq_scan_count_q <= count_q;
            lsq_bank1_count_q <= lsq_scan_count_q;
            lsq_final_count_q <= lsq_bank1_count_q;
            for (load_pipe_idx = 0; load_pipe_idx < LSQ_DEPTH;
                 load_pipe_idx = load_pipe_idx + 1) begin
                lsq_scan_q[load_pipe_idx] <=
                    lsq_q[ptr_add(head_q, load_pipe_idx)];
                lsq_scan_slot_q[load_pipe_idx] <=
                    ptr_add(head_q, load_pipe_idx);
                lsq_bank1_q[load_pipe_idx] <= lsq_scan_q[load_pipe_idx];
                lsq_bank1_slot_q[load_pipe_idx] <= lsq_scan_slot_q[load_pipe_idx];
                lsq_final_q[load_pipe_idx] <= lsq_bank1_q[load_pipe_idx];
                lsq_final_slot_q[load_pipe_idx] <=
                    lsq_bank1_slot_q[load_pipe_idx];
                load_bank0_eligible_q[load_pipe_idx] <=
                    load_bank0_eligible_d[load_pipe_idx];
                load_bank0_mask_q[load_pipe_idx] <=
                    load_bank0_mask_d[load_pipe_idx];
                load_bank0_data_q[load_pipe_idx] <=
                    load_bank0_data_d[load_pipe_idx];
                load_final_eligible_q[load_pipe_idx] <=
                    load_final_eligible_d[load_pipe_idx];
                load_final_mask_q[load_pipe_idx] <=
                    load_final_mask_d[load_pipe_idx];
                load_final_data_q[load_pipe_idx] <=
                    load_final_data_d[load_pipe_idx];
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && req_i.valid && req_i.producer_tracked)
            assert (lsq_q[req_i.lsq_index].valid &&
                    lsq_q[req_i.lsq_index].producer_id == req_i.producer_id)
                else $fatal(1, "LSQ AGU identity mismatch");
        if (rst_n && dtcm_store_fire)
            assert (head_entry.retired && head_entry.store_data_valid)
                else $fatal(1, "LSQ store launched before retirement/data");
    end
`endif
endmodule
