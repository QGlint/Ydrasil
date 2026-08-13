module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES  = 0,
    parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
    parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES,
    parameter bit USE_GSHARE  = 1'b0
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,
    output wire [ydrasil_pkg::ITCM_ADDR_WIDTH:0] predict_target_token_o,
    output wire [1:0]                      predict_counter_o,
    output wire [1:0]                      predict_global_counter_o,
    output wire [1:0]                      predict_local_counter_o,
    output bp_bht_index_t                    predict_bht_index_o,
    input  wire                            predict0_spec_valid_i,
    input  wire                            predict0_spec_conditional_i,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc1_i,
    output wire                            predict1_hit_o,
    output wire                            predict1_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict1_target_o,
    output wire [ydrasil_pkg::ITCM_ADDR_WIDTH:0] predict1_target_token_o,
    output wire [1:0]                      predict1_counter_o,
    output wire [1:0]                      predict1_global_counter_o,
    output wire [1:0]                      predict1_local_counter_o,
    output bp_bht_index_t                    predict1_bht_index_o,
    input  wire                            predict1_spec_valid_i,
    input  wire                            predict1_spec_conditional_i,

    input  ydrasil_bp_train_pkt_t          train_i,
    input  wire                            invalidate_i
);

    localparam int BTB_INDEX_WIDTH = $clog2(BTB_ENTRIES);
    localparam int BHT_INDEX_WIDTH = $clog2(BHT_ENTRIES);
    localparam int BTB_BANK_DEPTH = BTB_ENTRIES / 2;
    localparam int BHT_BANK_DEPTH = BHT_ENTRIES / 2;
    localparam int BTB_ROW_WIDTH = $clog2(BTB_BANK_DEPTH);
    localparam int BHT_ROW_WIDTH = $clog2(BHT_BANK_DEPTH);
    localparam int BTB_LOCAL_ADDR_WIDTH = ydrasil_pkg::ITCM_ADDR_WIDTH + 1;
    localparam int BTB_TAG_WIDTH = BTB_LOCAL_ADDR_WIDTH - BTB_INDEX_WIDTH;
    localparam int GHR_WIDTH = BHT_ROW_WIDTH;
    // Only target state is invalidated by FENCE.I. Direction counters cannot
    // make a prediction without a current-generation BTB hit, so retaining
    // them removes the BHT epoch compare from the response-to-history path.
    // Sixty-three BTB invalidations remain zero-cycle; the next one scrubs.
    localparam int EPOCH_WIDTH = 6;
    localparam int BTB_DATA_WIDTH = 1 + EPOCH_WIDTH + BTB_TAG_WIDTH +
        BTB_LOCAL_ADDR_WIDTH;
    localparam int BTB_MEM_DATA_WIDTH = ((BTB_DATA_WIDTH + 7) / 8) * 8;
    localparam int BHT_DATA_WIDTH = 2;
    // Each physical BHT word is byte-wide, while only the low counter bits
    // were previously used. Keep the chooser beside the global counter in
    // those existing spare bits; this does not change the BRAM shape.
    localparam int BHT_CHOOSER_LSB = BHT_DATA_WIDTH;
    localparam int BHT_USED_WIDTH = BHT_DATA_WIDTH + 2 + 1;
    localparam int BHT_MEM_DATA_WIDTH = 8;

    if ((BTB_ENTRIES < 4) || ((BTB_ENTRIES & (BTB_ENTRIES - 1)) != 0)) begin : g_bad_btb_entries
        initial $fatal(1, "BTB_ENTRIES must be a power of two and at least 4");
    end
    if ((BHT_ENTRIES < 4) || ((BHT_ENTRIES & (BHT_ENTRIES - 1)) != 0)) begin : g_bad_bht_entries
        initial $fatal(1, "BHT_ENTRIES must be a power of two and at least 4");
    end
    if (BTB_TAG_WIDTH < 1) begin : g_bad_btb_tag_width
        initial $fatal(1, "BTB_ENTRIES leaves no BTB tag bits");
    end
    if (BHT_INDEX_WIDTH > ydrasil_pkg::BP_BHT_INDEX_WIDTH) begin : g_bad_bht_index_width
        initial $fatal(1, "BHT_ENTRIES exceeds the carried BHT index width");
    end

    logic [GHR_WIDTH-1:0] ghr_q;
    wire lane0_pred_taken;
    wire lane1_pred_taken;
    // The fetch response from the preceding request advances history before
    // the next BHT lookup is registered. The resulting address still crosses
    // the existing synchronous BHT boundary; it cannot feed the PC in-cycle.
    wire spec0_advance = USE_GSHARE && predict0_spec_valid_i &&
        predict0_spec_conditional_i;
    wire [GHR_WIDTH-1:0] ghr_after_spec0 = spec0_advance ?
        ((ghr_q << 1) | GHR_WIDTH'(lane0_pred_taken)) : ghr_q;
    wire spec1_advance = USE_GSHARE && predict1_spec_valid_i &&
        predict1_spec_conditional_i && !lane0_pred_taken;
    wire [GHR_WIDTH-1:0] ghr_lookup = spec1_advance ?
        ((ghr_after_spec0 << 1) | GHR_WIDTH'(lane1_pred_taken)) :
        ghr_after_spec0;

    wire [BTB_LOCAL_ADDR_WIDTH-1:0] predict_btb_addr = {
        predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2] ==
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        predict_pc_i[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]};
    wire predict_btb_bank = predict_btb_addr[0];
    wire [BTB_ROW_WIDTH-1:0] predict_btb_row =
        predict_btb_addr[BTB_INDEX_WIDTH-1:1];
    wire [BTB_TAG_WIDTH-1:0] predict_btb_tag =
        predict_btb_addr[BTB_LOCAL_ADDR_WIDTH-1:BTB_INDEX_WIDTH];

    // Keep PC[2] as the physical bank bit. GShare hashes only the row, so a
    // naturally aligned 64-bit fetch always reads one entry from each bank.
    wire predict_bht_bank = predict_pc_i[2];
    wire [BHT_ROW_WIDTH-1:0] predict_pc_row =
        BHT_ROW_WIDTH'(predict_pc_i >> 3);
    // The two BHT BRAMs are independent physical consumers. Preserve one
    // equivalent bit-local history selector beside each address port so the
    // FPGA mapper does not rebuild a shared, routed row mux between banks.
    // Both rows intentionally implement the same history/PC hash.
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row0;
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row1;
    for (genvar ghr_bit = 0; ghr_bit < BHT_ROW_WIDTH; ghr_bit++) begin : g_bht_row
        (* keep = "true" *) wire selected_history0;
        (* keep = "true" *) wire selected_history1;
        if (ghr_bit == 0) begin : g_bit0
            assign selected_history0 = spec1_advance ? lane1_pred_taken :
                (spec0_advance ? lane0_pred_taken : ghr_q[0]);
            assign selected_history1 = spec1_advance ? lane1_pred_taken :
                (spec0_advance ? lane0_pred_taken : ghr_q[0]);
        end else if (ghr_bit == 1) begin : g_bit1
            assign selected_history0 = spec1_advance ?
                (spec0_advance ? lane0_pred_taken : ghr_q[0]) :
                (spec0_advance ? ghr_q[0] : ghr_q[1]);
            assign selected_history1 = spec1_advance ?
                (spec0_advance ? lane0_pred_taken : ghr_q[0]) :
                (spec0_advance ? ghr_q[0] : ghr_q[1]);
        end else begin : g_bitn
            assign selected_history0 = spec1_advance ?
                (spec0_advance ? ghr_q[ghr_bit-2] : ghr_q[ghr_bit-1]) :
                (spec0_advance ? ghr_q[ghr_bit-1] : ghr_q[ghr_bit]);
            assign selected_history1 = spec1_advance ?
                (spec0_advance ? ghr_q[ghr_bit-2] : ghr_q[ghr_bit-1]) :
                (spec0_advance ? ghr_q[ghr_bit-1] : ghr_q[ghr_bit]);
        end
        assign predict_bht_row0[ghr_bit] = predict_pc_row[ghr_bit] ^
            (USE_GSHARE ? selected_history0 : 1'b0);
        assign predict_bht_row1[ghr_bit] = predict_pc_row[ghr_bit] ^
            (USE_GSHARE ? selected_history1 : 1'b0);
    end
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index =
        {predict_bht_row0, predict_bht_bank};

    // Preserve a PC-indexed direction table beside GShare.  Its address uses
    // the same registered BRAM lookup boundary and physical bank split, so the
    // fallback cannot enter the fetch-PC control cone.  This retains local
    // direction stability where unrelated global histories alias a BHT row.
    wire [BHT_ROW_WIDTH-1:0] predict_local_bht_row =
        BHT_ROW_WIDTH'(predict_pc_i >> 3);

    wire [BTB_LOCAL_ADDR_WIDTH-1:0] train_btb_addr = {
        train_i.pc[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2] ==
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        train_i.pc[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]};
    wire train_btb_bank = train_btb_addr[0];
    wire [BTB_ROW_WIDTH-1:0] train_btb_row =
        train_btb_addr[BTB_INDEX_WIDTH-1:1];
    wire [BTB_TAG_WIDTH-1:0] train_btb_tag =
        train_btb_addr[BTB_LOCAL_ADDR_WIDTH-1:BTB_INDEX_WIDTH];
    wire train_bht_bank = train_i.pc[2];
    wire [BHT_ROW_WIDTH-1:0] train_bht_row =
        train_i.bht_index[BHT_INDEX_WIDTH-1:1];

    // IF issues a pair only from an 8-byte-aligned PC. Both physical banks
    // therefore use the same row; an odd-bank request carries no valid lane 1.
    wire [BTB_ROW_WIDTH-1:0] btb_read_row0 = predict_btb_row;
    wire [BTB_ROW_WIDTH-1:0] btb_read_row1 = predict_btb_row;
    (* keep = "true" *) wire [BHT_ROW_WIDTH-1:0] bht_read_row0 =
        predict_bht_row0;
    (* keep = "true" *) wire [BHT_ROW_WIDTH-1:0] bht_read_row1 =
        predict_bht_row1;
    wire [BHT_ROW_WIDTH-1:0] local_bht_read_row0 = predict_local_bht_row;
    wire [BHT_ROW_WIDTH-1:0] local_bht_read_row1 = predict_local_bht_row;

    logic [EPOCH_WIDTH-1:0] epoch_q;
    logic btb_clear_active_q;
    logic [BTB_ROW_WIDTH-1:0] btb_clear_row_q;
    wire clear_active = btb_clear_active_q;
    wire predict_ready = rst_n && !invalidate_i && !clear_active;
    wire train_fire = train_i.valid && !invalidate_i && !clear_active;

    // Keep the legacy single-table interface bit-exact when GShare is off:
    // unit tests and non-GShare users carry only train_i.counter.  With
    // GShare enabled this is the independently captured GShare state.
    wire [1:0] train_global_counter = USE_GSHARE ? train_i.global_counter :
        train_i.counter;
    wire [1:0] conditional_next_counter = train_i.taken ?
        ((train_global_counter == 2'b11) ? train_global_counter :
         train_global_counter + 2'b01) :
        ((train_global_counter == 2'b00) ? train_global_counter :
         train_global_counter - 2'b01);
    wire [1:0] bht_next_counter = train_i.conditional ?
        conditional_next_counter : 2'b11;
    wire [BTB_LOCAL_ADDR_WIDTH-1:0] btb_train_target = {
        train_i.target[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2] ==
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        train_i.target[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]};
    wire [BTB_DATA_WIDTH-1:0] btb_write_payload =
        {1'b1, epoch_q, train_btb_tag, btb_train_target};
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_train_data =
        {{(BTB_MEM_DATA_WIDTH-BTB_DATA_WIDTH){1'b0}}, btb_write_payload};
    // In GShare mode pred_counter carries the chooser state captured at
    // prediction time. Train it only when global and local disagree.
    wire [1:0] train_chooser = train_i.counter;
    wire train_global_taken = train_i.global_counter[1];
    wire train_local_taken = train_i.local_counter[1];
    wire train_global_correct = (train_global_taken == train_i.taken);
    wire train_local_correct = (train_local_taken == train_i.taken);
    wire [1:0] chooser_next =
        (!USE_GSHARE || !train_i.conditional) ? train_chooser :
        (train_global_correct && !train_local_correct) ?
            ((train_chooser == 2'b11) ? train_chooser : train_chooser + 2'b01) :
        (!train_global_correct && train_local_correct) ?
            ((train_chooser == 2'b00) ? train_chooser : train_chooser - 2'b01) :
        train_chooser;
    wire [BHT_USED_WIDTH-1:0] bht_write_payload = {
        1'b1, chooser_next, bht_next_counter ^ 2'b01};
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_train_data =
        {{(BHT_MEM_DATA_WIDTH-BHT_USED_WIDTH){1'b0}}, bht_write_payload};

    wire btb_wen0 = btb_clear_active_q || (train_fire && !train_btb_bank);
    wire btb_wen1 = btb_clear_active_q || (train_fire && train_btb_bank);
    wire [BTB_ROW_WIDTH-1:0] btb_write_row = btb_clear_active_q ?
        btb_clear_row_q : train_btb_row;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_write_data = btb_clear_active_q ?
        '0 : btb_train_data;
    wire bht_wen0 = train_fire && !train_bht_bank;
    wire bht_wen1 = train_fire && train_bht_bank;
    wire [BHT_ROW_WIDTH-1:0] bht_write_row = train_bht_row;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_write_data = bht_train_data;
    wire local_bht_train_bank = train_i.pc[2];
    wire [BHT_ROW_WIDTH-1:0] local_bht_train_row =
        BHT_ROW_WIDTH'(train_i.pc >> 3);
    wire [1:0] local_conditional_next_counter = train_i.taken ?
        ((train_i.local_counter == 2'b11) ? train_i.local_counter :
         train_i.local_counter + 2'b01) :
        ((train_i.local_counter == 2'b00) ? train_i.local_counter :
         train_i.local_counter - 2'b01);
    // Both tables are trained from their own carried prediction state.  This
    // prevents a local fallback decision from perturbing the GShare counter.
    wire [1:0] local_bht_next_counter = train_i.conditional ?
        local_conditional_next_counter : 2'b11;
    wire [BHT_MEM_DATA_WIDTH-1:0] local_bht_train_data =
        {{(BHT_MEM_DATA_WIDTH-BHT_DATA_WIDTH){1'b0}},
         local_bht_next_counter ^ 2'b01};
    wire local_bht_wen0 = train_fire && !local_bht_train_bank;
    wire local_bht_wen1 = train_fire && local_bht_train_bank;
    wire [BHT_ROW_WIDTH-1:0] local_bht_write_row = local_bht_train_row;
    wire [BHT_MEM_DATA_WIDTH-1:0] local_bht_write_data =
        local_bht_train_data;

    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata0;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata1;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata0;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata1;
    wire [BHT_MEM_DATA_WIDTH-1:0] local_bht_mem_rdata0;
    wire [BHT_MEM_DATA_WIDTH-1:0] local_bht_mem_rdata1;

    ydrasil_1r1w_bram #(
        .DEPTH(BTB_BANK_DEPTH), .DATA_WIDTH(BTB_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BTB_ROW_WIDTH), .INIT_VALUE('0)
    ) u_btb_bank0 (
        .clk(clk), .ren_i(1'b1), .raddr_i(btb_read_row0), .rdata_o(btb_mem_rdata0),
        .wen_i(btb_wen0), .waddr_i(btb_write_row), .wdata_i(btb_write_data)
    );
    ydrasil_1r1w_bram #(
        .DEPTH(BTB_BANK_DEPTH), .DATA_WIDTH(BTB_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BTB_ROW_WIDTH), .INIT_VALUE('0)
    ) u_btb_bank1 (
        .clk(clk), .ren_i(1'b1), .raddr_i(btb_read_row1), .rdata_o(btb_mem_rdata1),
        .wen_i(btb_wen1), .waddr_i(btb_write_row), .wdata_i(btb_write_data)
    );
    ydrasil_1r1w_bram #(
        .DEPTH(BHT_BANK_DEPTH), .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_ROW_WIDTH), .INIT_VALUE('0)
    ) u_bht_bank0 (
        .clk(clk), .ren_i(1'b1), .raddr_i(bht_read_row0), .rdata_o(bht_mem_rdata0),
        .wen_i(bht_wen0), .waddr_i(bht_write_row), .wdata_i(bht_write_data)
    );
    ydrasil_1r1w_bram #(
        .DEPTH(BHT_BANK_DEPTH), .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_ROW_WIDTH), .INIT_VALUE('0)
    ) u_bht_bank1 (
        .clk(clk), .ren_i(1'b1), .raddr_i(bht_read_row1), .rdata_o(bht_mem_rdata1),
        .wen_i(bht_wen1), .waddr_i(bht_write_row), .wdata_i(bht_write_data)
    );
    ydrasil_1r1w_bram #(
        .DEPTH(BHT_BANK_DEPTH), .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_ROW_WIDTH), .INIT_VALUE('0)
    ) u_local_bht_bank0 (
        .clk(clk), .ren_i(1'b1), .raddr_i(local_bht_read_row0),
        .rdata_o(local_bht_mem_rdata0), .wen_i(local_bht_wen0),
        .waddr_i(local_bht_write_row), .wdata_i(local_bht_write_data)
    );
    ydrasil_1r1w_bram #(
        .DEPTH(BHT_BANK_DEPTH), .DATA_WIDTH(BHT_MEM_DATA_WIDTH),
        .ADDR_WIDTH(BHT_ROW_WIDTH), .INIT_VALUE('0)
    ) u_local_bht_bank1 (
        .clk(clk), .ren_i(1'b1), .raddr_i(local_bht_read_row1),
        .rdata_o(local_bht_mem_rdata1), .wen_i(local_bht_wen1),
        .waddr_i(local_bht_write_row), .wdata_i(local_bht_write_data)
    );

    logic predict_btb_bank_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag1_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index_q;
    logic [BHT_ROW_WIDTH-1:0] predict1_bht_row_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_bank_q <= 1'b0;
            predict_btb_tag_q <= '0;
            predict_btb_tag1_q <= '0;
            predict_bht_index_q <= '0;
            predict1_bht_row_q <= '0;
        end else begin
            predict_btb_bank_q <= predict_btb_bank;
            predict_btb_tag_q <= predict_btb_tag;
            predict_btb_tag1_q <= predict_btb_tag;
            predict_bht_index_q <= predict_bht_index;
            predict1_bht_row_q <= predict_bht_row1;
        end
    end

    wire [GHR_WIDTH-1:0] recovered_lookup_history =
        GHR_WIDTH'(train_i.bht_index[BHT_INDEX_WIDTH-1:1]) ^
        GHR_WIDTH'(train_i.pc >> 3);
    wire [GHR_WIDTH-1:0] recovered_branch_checkpoint =
        train_i.bht_index[0] ? (recovered_lookup_history << 1) :
        recovered_lookup_history;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_q <= '0;
            btb_clear_active_q <= 1'b0;
            btb_clear_row_q <= '0;
        end else if (invalidate_i) begin
            if (!clear_active) begin
                if (&epoch_q) begin
                    epoch_q <= '0;
                    btb_clear_active_q <= 1'b1;
                    btb_clear_row_q <= '0;
                end else begin
                    epoch_q <= epoch_q + 1'b1;
                end
            end
        end else begin
            if (btb_clear_active_q) begin
                if (&btb_clear_row_q) begin
                    btb_clear_active_q <= 1'b0;
                    btb_clear_row_q <= '0;
                end else begin
                    btb_clear_row_q <= btb_clear_row_q + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || invalidate_i) begin
            ghr_q <= '0;
        end else if (USE_GSHARE) begin
            // A recovery discards every younger speculative bit. The resolving
            // conditional branch is reinserted with its architectural result;
            // direct jumps only restore their older history checkpoint.
            if (train_fire && train_i.recover) begin
                // The carried hash row XOR the branch PC row reconstructs the
                // pre-lookup history. Bit 0 is a lane-1 marker: a surviving
                // lane-1 branch follows a lane-0 conditional predicted NT.
                ghr_q <= train_i.conditional ?
                    ((recovered_branch_checkpoint << 1) |
                     GHR_WIDTH'(train_i.taken)) :
                    recovered_branch_checkpoint;
            end else begin
                ghr_q <= ghr_lookup;
            end
        end else begin
            ghr_q <= '0;
        end
    end

    wire [BTB_DATA_WIDTH-1:0] lane0_btb_data = predict_btb_bank_q ?
        btb_mem_rdata1[BTB_DATA_WIDTH-1:0] : btb_mem_rdata0[BTB_DATA_WIDTH-1:0];
    // A valid lane 1 exists only for an 8-byte-aligned pair lookup, so it is
    // physically bank 1. Odd-PC requests contain only lane 0 and discard every
    // lane-1 output. Keep the lane-1 response local to bank 1 instead of
    // rebuilding three bank muxes on the predictor-to-FetchQ/history paths.
    wire [BTB_DATA_WIDTH-1:0] lane1_btb_data =
        btb_mem_rdata1[BTB_DATA_WIDTH-1:0];
    wire lane0_btb_valid;
    wire lane1_btb_valid;
    wire [EPOCH_WIDTH-1:0] lane0_btb_epoch;
    wire [EPOCH_WIDTH-1:0] lane1_btb_epoch;
    wire [BTB_TAG_WIDTH-1:0] lane0_btb_tag;
    wire [BTB_TAG_WIDTH-1:0] lane1_btb_tag;
    wire [BTB_LOCAL_ADDR_WIDTH-1:0] lane0_btb_target_token;
    wire [BTB_LOCAL_ADDR_WIDTH-1:0] lane1_btb_target_token;
    assign {lane0_btb_valid, lane0_btb_epoch, lane0_btb_tag, lane0_btb_target_token} =
        lane0_btb_data;
    assign {lane1_btb_valid, lane1_btb_epoch, lane1_btb_tag, lane1_btb_target_token} =
        lane1_btb_data;
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] lane0_btb_target = {
        lane0_btb_target_token[BTB_LOCAL_ADDR_WIDTH-1] ?
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
                ydrasil_pkg::ITCM_ADDR_WIDTH+2] :
            ydrasil_pkg::ITCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
                ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        lane0_btb_target_token[ydrasil_pkg::ITCM_ADDR_WIDTH-1:0], 2'b00};
    wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] lane1_btb_target = {
        lane1_btb_target_token[BTB_LOCAL_ADDR_WIDTH-1] ?
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
                ydrasil_pkg::ITCM_ADDR_WIDTH+2] :
            ydrasil_pkg::ITCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
                ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        lane1_btb_target_token[ydrasil_pkg::ITCM_ADDR_WIDTH-1:0], 2'b00};

    wire [BHT_DATA_WIDTH-1:0] lane0_bht_data = predict_bht_index_q[0] ?
        bht_mem_rdata1[BHT_DATA_WIDTH-1:0] : bht_mem_rdata0[BHT_DATA_WIDTH-1:0];
    wire [BHT_DATA_WIDTH-1:0] lane1_bht_data =
        bht_mem_rdata1[BHT_DATA_WIDTH-1:0];
    wire [1:0] lane0_chooser = predict_bht_index_q[0] ?
        bht_mem_rdata1[BHT_CHOOSER_LSB +: 2] :
        bht_mem_rdata0[BHT_CHOOSER_LSB +: 2];
    wire [1:0] lane1_chooser =
        bht_mem_rdata1[BHT_CHOOSER_LSB +: 2];
    wire lane0_chooser_valid = predict_bht_index_q[0] ?
        bht_mem_rdata1[BHT_USED_WIDTH-1] : bht_mem_rdata0[BHT_USED_WIDTH-1];
    wire lane1_chooser_valid = bht_mem_rdata1[BHT_USED_WIDTH-1];
    wire [1:0] lane0_bht_counter = lane0_bht_data ^ 2'b01;
    wire [1:0] lane1_bht_counter = lane1_bht_data ^ 2'b01;
    wire [BHT_DATA_WIDTH-1:0] lane0_local_bht_data = predict_bht_index_q[0] ?
        local_bht_mem_rdata1[BHT_DATA_WIDTH-1:0] :
        local_bht_mem_rdata0[BHT_DATA_WIDTH-1:0];
    wire [BHT_DATA_WIDTH-1:0] lane1_local_bht_data =
        local_bht_mem_rdata1[BHT_DATA_WIDTH-1:0];
    wire [1:0] lane0_local_bht_counter = lane0_local_bht_data ^ 2'b01;
    wire [1:0] lane1_local_bht_counter = lane1_local_bht_data ^ 2'b01;
    wire lane0_global_confident =
        lane0_bht_counter[1] == lane0_bht_counter[0];
    wire lane1_global_confident =
        lane1_bht_counter[1] == lane1_bht_counter[0];
    // Chooser MSB selects the source in GShare mode. The legacy confidence
    // rule is retained for untrained rows and all non-GShare instances.
    wire lane0_use_global = !USE_GSHARE ? 1'b1 :
        (lane0_chooser_valid ? lane0_chooser[1] : lane0_global_confident);
    wire lane1_use_global = !USE_GSHARE ? 1'b1 :
        (lane1_chooser_valid ? lane1_chooser[1] : lane1_global_confident);
    wire [1:0] lane0_selected_counter = lane0_use_global ?
        lane0_bht_counter : lane0_local_bht_counter;
    wire [1:0] lane1_selected_counter = lane1_use_global ?
        lane1_bht_counter : lane1_local_bht_counter;
    // Storage encoding flips only counter bit zero. Direction therefore uses
    // the raw MSB and bypasses the decode plus full 2-bit selected-counter mux.
    wire lane0_selected_taken = lane0_use_global ? lane0_bht_data[1] :
        lane0_local_bht_data[1];
    wire lane1_selected_taken = lane1_use_global ? lane1_bht_data[1] :
        lane1_local_bht_data[1];

    wire lane0_btb_hit = lane0_btb_valid && (lane0_btb_epoch == epoch_q) &&
        (lane0_btb_tag == predict_btb_tag_q);
    wire lane1_btb_hit = lane1_btb_valid && (lane1_btb_epoch == epoch_q) &&
        (lane1_btb_tag == predict_btb_tag1_q);
    assign lane0_pred_taken = predict_ready && lane0_btb_hit &&
        lane0_selected_taken;
    assign lane1_pred_taken = predict_ready && lane1_btb_hit &&
        lane1_selected_taken;

    assign predict_hit_o = predict_ready && lane0_btb_hit;
    // Carry chooser state through the existing two-bit counter field. It is
    // consumed only by GShare training; non-GShare keeps the old interface.
    assign predict_counter_o = predict_hit_o ?
        (USE_GSHARE ? lane0_chooser : lane0_selected_counter) : 2'b01;
    assign predict_global_counter_o = predict_hit_o ? lane0_bht_counter : 2'b01;
    assign predict_local_counter_o = predict_hit_o ? lane0_local_bht_counter :
        2'b01;
    assign predict_taken_o = lane0_pred_taken;
    assign predict_target_o = lane0_btb_target;
    assign predict_target_token_o = lane0_btb_target_token;
    // The physical bank is recovered from branch PC at training. Carried bit
    // zero is reserved for IF's lane-1 checkpoint marker.
    assign predict_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(
        {predict_bht_index_q[BHT_INDEX_WIDTH-1:1], 1'b0});

    assign predict1_hit_o = predict_ready && lane1_btb_hit;
    assign predict1_counter_o = predict1_hit_o ?
        (USE_GSHARE ? lane1_chooser : lane1_selected_counter) : 2'b01;
    assign predict1_global_counter_o = predict1_hit_o ? lane1_bht_counter : 2'b01;
    assign predict1_local_counter_o = predict1_hit_o ? lane1_local_bht_counter :
        2'b01;
    assign predict1_taken_o = lane1_pred_taken;
    assign predict1_target_o = lane1_btb_target;
    assign predict1_target_token_o = lane1_btb_target_token;
    assign predict1_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(
        {predict1_bht_row_q, 1'b0});

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (predict_pc_i[2] != predict_pc1_i[2])
                else $fatal(1, "predictor lanes must address opposite parity banks");
            assert (!predict1_spec_valid_i || !predict_btb_bank_q)
                else $fatal(1, "lane 1 speculation requires an aligned pair lookup");
        end
    end
`endif

endmodule
