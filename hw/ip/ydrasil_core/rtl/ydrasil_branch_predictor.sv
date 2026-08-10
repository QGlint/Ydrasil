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
    output wire [1:0]                      predict_counter_o,
    output wire [1:0]                      predict_global_counter_o,
    output wire [1:0]                      predict_local_counter_o,
    output bp_bht_index_t                    predict_bht_index_o,
    output bp_ghr_t                          predict_ghr_checkpoint_o,
    input  wire                            predict0_spec_valid_i,
    input  wire                            predict0_spec_conditional_i,
    input  wire                            predict0_spec_taken_i,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc1_i,
    output wire                            predict1_hit_o,
    output wire                            predict1_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict1_target_o,
    output wire [1:0]                      predict1_counter_o,
    output wire [1:0]                      predict1_global_counter_o,
    output wire [1:0]                      predict1_local_counter_o,
    output bp_bht_index_t                    predict1_bht_index_o,
    output bp_ghr_t                          predict1_ghr_checkpoint_o,
    input  wire                            predict1_spec_valid_i,
    input  wire                            predict1_spec_conditional_i,
    input  wire                            predict1_spec_taken_i,

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
    localparam int GHR_WIDTH =
        (BHT_ROW_WIDTH < ydrasil_pkg::BP_GHR_WIDTH) ?
        BHT_ROW_WIDTH : ydrasil_pkg::BP_GHR_WIDTH;
    // Six generations fit in both the 32-bit BTB word and the existing 8-bit
    // BHT word. Sixty-three invalidations remain zero-cycle; the next one
    // performs a parallel two-bank scrub before the generation wraps.
    localparam int EPOCH_WIDTH = 6;
    localparam int BTB_DATA_WIDTH = 1 + EPOCH_WIDTH + BTB_TAG_WIDTH +
        BTB_LOCAL_ADDR_WIDTH;
    localparam int BTB_MEM_DATA_WIDTH = ((BTB_DATA_WIDTH + 7) / 8) * 8;
    localparam int BHT_DATA_WIDTH = EPOCH_WIDTH + 2;
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
    // The fetch response from the preceding request advances history before
    // the next BHT lookup is registered. The resulting address still crosses
    // the existing synchronous BHT boundary; it cannot feed the PC in-cycle.
    wire spec0_advance = USE_GSHARE && predict0_spec_valid_i &&
        predict0_spec_conditional_i;
    wire [GHR_WIDTH-1:0] ghr_after_spec0 = spec0_advance ?
        ((ghr_q << 1) | GHR_WIDTH'(predict0_spec_taken_i)) : ghr_q;
    wire spec1_advance = USE_GSHARE && predict1_spec_valid_i &&
        predict1_spec_conditional_i;
    wire [GHR_WIDTH-1:0] ghr_lookup = spec1_advance ?
        ((ghr_after_spec0 << 1) | GHR_WIDTH'(predict1_spec_taken_i)) :
        ghr_after_spec0;
    wire [GHR_WIDTH-1:0] ghr_value = USE_GSHARE ? ghr_lookup : '0;
    // Both lanes are read in parallel from the same fetch word. Lane 1 keeps
    // the same lookup checkpoint; the lane-0 decoded direction is only known
    // after this BRAM address has been registered.
    wire [GHR_WIDTH-1:0] lane1_ghr = ghr_value;
    wire [BHT_ROW_WIDTH-1:0] ghr_row_mask = USE_GSHARE ?
        BHT_ROW_WIDTH'(ghr_value) : '0;
    wire [BHT_ROW_WIDTH-1:0] lane1_ghr_row_mask = USE_GSHARE ?
        BHT_ROW_WIDTH'(lane1_ghr) : '0;

    wire [BTB_LOCAL_ADDR_WIDTH-1:0] predict_btb_addr = {
        predict_pc_i[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2] ==
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        predict_pc_i[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]};
    wire [BTB_LOCAL_ADDR_WIDTH-1:0] predict_btb_addr1 = {
        predict_pc1_i[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2] ==
            ydrasil_pkg::DTCM_BASE_ADDR[ydrasil_pkg::INST_ADDR_WIDTH-1:
            ydrasil_pkg::ITCM_ADDR_WIDTH+2],
        predict_pc1_i[ydrasil_pkg::ITCM_ADDR_WIDTH+1:2]};
    wire predict_btb_bank = predict_btb_addr[0];
    wire predict_btb_bank1 = predict_btb_addr1[0];
    wire [BTB_ROW_WIDTH-1:0] predict_btb_row =
        predict_btb_addr[BTB_INDEX_WIDTH-1:1];
    wire [BTB_ROW_WIDTH-1:0] predict_btb_row1 =
        predict_btb_addr1[BTB_INDEX_WIDTH-1:1];
    wire [BTB_TAG_WIDTH-1:0] predict_btb_tag =
        predict_btb_addr[BTB_LOCAL_ADDR_WIDTH-1:BTB_INDEX_WIDTH];
    wire [BTB_TAG_WIDTH-1:0] predict_btb_tag1 =
        predict_btb_addr1[BTB_LOCAL_ADDR_WIDTH-1:BTB_INDEX_WIDTH];

    // Keep PC[2] as the physical bank bit. GShare hashes only the row, so a
    // naturally aligned 64-bit fetch always reads one entry from each bank.
    wire predict_bht_bank = predict_pc_i[2];
    wire predict_bht_bank1 = predict_pc1_i[2];
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row =
        BHT_ROW_WIDTH'(predict_pc_i >> 3) ^ ghr_row_mask;
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row1 =
        BHT_ROW_WIDTH'(predict_pc1_i >> 3) ^ lane1_ghr_row_mask;
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index =
        {predict_bht_row, predict_bht_bank};
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index1 =
        {predict_bht_row1, predict_bht_bank1};

    // Preserve a PC-indexed direction table beside GShare.  Its address uses
    // the same registered BRAM lookup boundary and physical bank split, so the
    // fallback cannot enter the fetch-PC control cone.  This retains local
    // direction stability where unrelated global histories alias a BHT row.
    wire [BHT_ROW_WIDTH-1:0] predict_local_bht_row =
        BHT_ROW_WIDTH'(predict_pc_i >> 3);
    wire [BHT_ROW_WIDTH-1:0] predict_local_bht_row1 =
        BHT_ROW_WIDTH'(predict_pc1_i >> 3);

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
    wire train_bht_bank = train_i.bht_index[0];
    wire [BHT_ROW_WIDTH-1:0] train_bht_row =
        train_i.bht_index[BHT_INDEX_WIDTH-1:1];

    wire [BTB_ROW_WIDTH-1:0] btb_read_row0 =
        predict_btb_bank ? predict_btb_row1 : predict_btb_row;
    wire [BTB_ROW_WIDTH-1:0] btb_read_row1 =
        predict_btb_bank ? predict_btb_row : predict_btb_row1;
    wire [BHT_ROW_WIDTH-1:0] bht_read_row0 =
        predict_bht_bank ? predict_bht_row1 : predict_bht_row;
    wire [BHT_ROW_WIDTH-1:0] bht_read_row1 =
        predict_bht_bank ? predict_bht_row : predict_bht_row1;
    wire [BHT_ROW_WIDTH-1:0] local_bht_read_row0 =
        predict_bht_bank ? predict_local_bht_row1 : predict_local_bht_row;
    wire [BHT_ROW_WIDTH-1:0] local_bht_read_row1 =
        predict_bht_bank ? predict_local_bht_row : predict_local_bht_row1;

    logic [EPOCH_WIDTH-1:0] epoch_q;
    logic btb_clear_active_q;
    logic bht_clear_active_q;
    logic [BTB_ROW_WIDTH-1:0] btb_clear_row_q;
    logic [BHT_ROW_WIDTH-1:0] bht_clear_row_q;
    wire clear_active = btb_clear_active_q || bht_clear_active_q;
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
    wire [BHT_DATA_WIDTH-1:0] bht_write_payload =
        {epoch_q, bht_next_counter ^ 2'b01};
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_train_data =
        {{(BHT_MEM_DATA_WIDTH-BHT_DATA_WIDTH){1'b0}}, bht_write_payload};

    wire btb_wen0 = btb_clear_active_q || (train_fire && !train_btb_bank);
    wire btb_wen1 = btb_clear_active_q || (train_fire && train_btb_bank);
    wire [BTB_ROW_WIDTH-1:0] btb_write_row = btb_clear_active_q ?
        btb_clear_row_q : train_btb_row;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_write_data = btb_clear_active_q ?
        '0 : btb_train_data;
    wire bht_wen0 = bht_clear_active_q || (train_fire && !train_bht_bank);
    wire bht_wen1 = bht_clear_active_q || (train_fire && train_bht_bank);
    wire [BHT_ROW_WIDTH-1:0] bht_write_row = bht_clear_active_q ?
        bht_clear_row_q : train_bht_row;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_write_data = bht_clear_active_q ?
        '0 : bht_train_data;
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
         {epoch_q, local_bht_next_counter ^ 2'b01}};
    wire local_bht_wen0 = bht_clear_active_q ||
        (train_fire && !local_bht_train_bank);
    wire local_bht_wen1 = bht_clear_active_q ||
        (train_fire && local_bht_train_bank);
    wire [BHT_ROW_WIDTH-1:0] local_bht_write_row = bht_clear_active_q ?
        bht_clear_row_q : local_bht_train_row;
    wire [BHT_MEM_DATA_WIDTH-1:0] local_bht_write_data = bht_clear_active_q ?
        '0 : local_bht_train_data;

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
    logic predict_btb_bank1_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag1_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index1_q;
    logic [GHR_WIDTH-1:0] predict_ghr_q;
    logic [GHR_WIDTH-1:0] predict_ghr1_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_bank_q <= 1'b0;
            predict_btb_bank1_q <= 1'b1;
            predict_btb_tag_q <= '0;
            predict_btb_tag1_q <= '0;
            predict_bht_index_q <= '0;
            predict_bht_index1_q <= '0;
            predict_ghr_q <= '0;
            predict_ghr1_q <= '0;
        end else begin
            predict_btb_bank_q <= predict_btb_bank;
            predict_btb_bank1_q <= predict_btb_bank1;
            predict_btb_tag_q <= predict_btb_tag;
            predict_btb_tag1_q <= predict_btb_tag1;
            predict_bht_index_q <= predict_bht_index;
            predict_bht_index1_q <= predict_bht_index1;
            predict_ghr_q <= ghr_value;
            predict_ghr1_q <= lane1_ghr;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_q <= '0;
            btb_clear_active_q <= 1'b0;
            bht_clear_active_q <= 1'b0;
            btb_clear_row_q <= '0;
            bht_clear_row_q <= '0;
        end else if (invalidate_i) begin
            if (!clear_active) begin
                if (&epoch_q) begin
                    epoch_q <= '0;
                    btb_clear_active_q <= 1'b1;
                    bht_clear_active_q <= 1'b1;
                    btb_clear_row_q <= '0;
                    bht_clear_row_q <= '0;
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
            if (bht_clear_active_q) begin
                if (&bht_clear_row_q) begin
                    bht_clear_active_q <= 1'b0;
                    bht_clear_row_q <= '0;
                end else begin
                    bht_clear_row_q <= bht_clear_row_q + 1'b1;
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
                ghr_q <= train_i.conditional ?
                    ((GHR_WIDTH'(train_i.ghr_checkpoint) << 1) |
                     GHR_WIDTH'(train_i.taken)) :
                    GHR_WIDTH'(train_i.ghr_checkpoint);
            end else begin
                ghr_q <= ghr_lookup;
            end
        end else begin
            ghr_q <= '0;
        end
    end

    wire [BTB_DATA_WIDTH-1:0] lane0_btb_data = predict_btb_bank_q ?
        btb_mem_rdata1[BTB_DATA_WIDTH-1:0] : btb_mem_rdata0[BTB_DATA_WIDTH-1:0];
    wire [BTB_DATA_WIDTH-1:0] lane1_btb_data = predict_btb_bank1_q ?
        btb_mem_rdata1[BTB_DATA_WIDTH-1:0] : btb_mem_rdata0[BTB_DATA_WIDTH-1:0];
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
    wire [BHT_DATA_WIDTH-1:0] lane1_bht_data = predict_bht_index1_q[0] ?
        bht_mem_rdata1[BHT_DATA_WIDTH-1:0] : bht_mem_rdata0[BHT_DATA_WIDTH-1:0];
    wire [EPOCH_WIDTH-1:0] lane0_bht_epoch = lane0_bht_data[BHT_DATA_WIDTH-1:2];
    wire [EPOCH_WIDTH-1:0] lane1_bht_epoch = lane1_bht_data[BHT_DATA_WIDTH-1:2];
    wire [1:0] lane0_bht_counter = (lane0_bht_epoch == epoch_q) ?
        (lane0_bht_data[1:0] ^ 2'b01) : 2'b01;
    wire [1:0] lane1_bht_counter = (lane1_bht_epoch == epoch_q) ?
        (lane1_bht_data[1:0] ^ 2'b01) : 2'b01;
    wire [BHT_DATA_WIDTH-1:0] lane0_local_bht_data = predict_bht_index_q[0] ?
        local_bht_mem_rdata1[BHT_DATA_WIDTH-1:0] :
        local_bht_mem_rdata0[BHT_DATA_WIDTH-1:0];
    wire [BHT_DATA_WIDTH-1:0] lane1_local_bht_data = predict_bht_index1_q[0] ?
        local_bht_mem_rdata1[BHT_DATA_WIDTH-1:0] :
        local_bht_mem_rdata0[BHT_DATA_WIDTH-1:0];
    wire [EPOCH_WIDTH-1:0] lane0_local_bht_epoch =
        lane0_local_bht_data[BHT_DATA_WIDTH-1:2];
    wire [EPOCH_WIDTH-1:0] lane1_local_bht_epoch =
        lane1_local_bht_data[BHT_DATA_WIDTH-1:2];
    wire [1:0] lane0_local_bht_counter =
        (lane0_local_bht_epoch == epoch_q) ?
        (lane0_local_bht_data[1:0] ^ 2'b01) : 2'b01;
    wire [1:0] lane1_local_bht_counter =
        (lane1_local_bht_epoch == epoch_q) ?
        (lane1_local_bht_data[1:0] ^ 2'b01) : 2'b01;
    wire lane0_global_confident = (lane0_bht_counter == 2'b00) ||
        (lane0_bht_counter == 2'b11);
    wire lane1_global_confident = (lane1_bht_counter == 2'b00) ||
        (lane1_bht_counter == 2'b11);
    wire [1:0] lane0_selected_counter = !USE_GSHARE || lane0_global_confident ?
        lane0_bht_counter : lane0_local_bht_counter;
    wire [1:0] lane1_selected_counter = !USE_GSHARE || lane1_global_confident ?
        lane1_bht_counter : lane1_local_bht_counter;

    wire lane0_btb_hit = lane0_btb_valid && (lane0_btb_epoch == epoch_q) &&
        (lane0_btb_tag == predict_btb_tag_q);
    wire lane1_btb_hit = lane1_btb_valid && (lane1_btb_epoch == epoch_q) &&
        (lane1_btb_tag == predict_btb_tag1_q);

    assign predict_hit_o = predict_ready && lane0_btb_hit;
    assign predict_counter_o = predict_ready ? lane0_selected_counter : 2'b01;
    assign predict_global_counter_o = predict_ready ? lane0_bht_counter : 2'b01;
    assign predict_local_counter_o = predict_ready ? lane0_local_bht_counter :
        2'b01;
    assign predict_taken_o = predict_hit_o && predict_counter_o[1];
    assign predict_target_o = lane0_btb_target;
    assign predict_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(predict_bht_index_q);
    assign predict_ghr_checkpoint_o =
        ydrasil_pkg::BP_GHR_WIDTH'(predict_ghr_q);

    assign predict1_hit_o = predict_ready && lane1_btb_hit;
    assign predict1_counter_o = predict_ready ? lane1_selected_counter : 2'b01;
    assign predict1_global_counter_o = predict_ready ? lane1_bht_counter : 2'b01;
    assign predict1_local_counter_o = predict_ready ? lane1_local_bht_counter :
        2'b01;
    assign predict1_taken_o = predict1_hit_o && predict1_counter_o[1];
    assign predict1_target_o = lane1_btb_target;
    assign predict1_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(predict_bht_index1_q);
    assign predict1_ghr_checkpoint_o =
        ydrasil_pkg::BP_GHR_WIDTH'(predict_ghr1_q);

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n)
            assert (predict_pc_i[2] != predict_pc1_i[2])
                else $fatal(1, "predictor lanes must address opposite parity banks");
    end
`endif

endmodule
