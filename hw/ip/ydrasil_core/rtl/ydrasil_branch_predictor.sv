module ydrasil_branch_predictor
import ydrasil_pkg::*;
#(
    parameter int BP_ENTRIES  = 0,
    parameter int BTB_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BTB_ENTRIES,
    parameter int BHT_ENTRIES = (BP_ENTRIES != 0) ? BP_ENTRIES : ydrasil_pkg::BP_BHT_ENTRIES
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc_i,
    output wire                            predict_hit_o,
    output wire                            predict_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_target_o,
    output wire [1:0]                      predict_counter_o,
    output bp_bht_index_t                    predict_bht_index_o,

    input  wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict_pc1_i,
    output wire                            predict1_hit_o,
    output wire                            predict1_taken_o,
    output wire [ydrasil_pkg::INST_ADDR_WIDTH-1:0] predict1_target_o,
    output wire [1:0]                      predict1_counter_o,
    output bp_bht_index_t                    predict1_bht_index_o,

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
    // Six generations fit in both the 32-bit BTB word and the existing 8-bit
    // BHT word. Sixty-three invalidations remain zero-cycle; the next one
    // performs a parallel two-bank scrub before the generation wraps.
    localparam int EPOCH_WIDTH = 6;
    localparam int BTB_DATA_WIDTH = 1 + EPOCH_WIDTH + BTB_TAG_WIDTH +
        BTB_LOCAL_ADDR_WIDTH;
    localparam int BTB_MEM_DATA_WIDTH = ((BTB_DATA_WIDTH + 7) / 8) * 8;
    localparam int BHT_DATA_WIDTH = EPOCH_WIDTH + 2;
    localparam int BHT_MEM_DATA_WIDTH = 8;
    localparam int ALT_ENTRIES = 64;
    localparam int ALT_BANK_DEPTH = ALT_ENTRIES / 2;
    localparam int ALT_INDEX_WIDTH = $clog2(ALT_ENTRIES);
    localparam int ALT_ROW_WIDTH = $clog2(ALT_BANK_DEPTH);
    localparam int ALT_TAG_WIDTH = BTB_LOCAL_ADDR_WIDTH - ALT_INDEX_WIDTH;
    localparam int ALT_DATA_WIDTH = ALT_TAG_WIDTH + 3;

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

    // Keep PC[2] as the physical bank bit so an aligned 64-bit fetch reads
    // one entry from each bank.
    wire predict_bht_bank = predict_pc_i[2];
    wire predict_bht_bank1 = predict_pc1_i[2];
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row =
        BHT_ROW_WIDTH'(predict_pc_i >> 3);
    wire [BHT_ROW_WIDTH-1:0] predict_bht_row1 =
        BHT_ROW_WIDTH'(predict_pc1_i >> 3);
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index =
        {predict_bht_row, predict_bht_bank};
    wire [BHT_INDEX_WIDTH-1:0] predict_bht_index1 =
        {predict_bht_row1, predict_bht_bank1};

    wire predict_alt_bank = predict_btb_addr[0];
    wire predict_alt_bank1 = predict_btb_addr1[0];
    wire [ALT_ROW_WIDTH-1:0] predict_alt_row =
        predict_btb_addr[ALT_INDEX_WIDTH-1:1];
    wire [ALT_ROW_WIDTH-1:0] predict_alt_row1 =
        predict_btb_addr1[ALT_INDEX_WIDTH-1:1];
    wire [ALT_TAG_WIDTH-1:0] predict_alt_tag =
        predict_btb_addr[BTB_LOCAL_ADDR_WIDTH-1:ALT_INDEX_WIDTH];
    wire [ALT_TAG_WIDTH-1:0] predict_alt_tag1 =
        predict_btb_addr1[BTB_LOCAL_ADDR_WIDTH-1:ALT_INDEX_WIDTH];

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
    wire train_alt_bank = train_btb_addr[0];
    wire [ALT_ROW_WIDTH-1:0] train_alt_row =
        train_btb_addr[ALT_INDEX_WIDTH-1:1];
    wire [ALT_TAG_WIDTH-1:0] train_alt_tag =
        train_btb_addr[BTB_LOCAL_ADDR_WIDTH-1:ALT_INDEX_WIDTH];

    wire [BTB_ROW_WIDTH-1:0] btb_read_row0 =
        predict_btb_bank ? predict_btb_row1 : predict_btb_row;
    wire [BTB_ROW_WIDTH-1:0] btb_read_row1 =
        predict_btb_bank ? predict_btb_row : predict_btb_row1;
    wire [BHT_ROW_WIDTH-1:0] bht_read_row0 =
        predict_bht_bank ? predict_bht_row1 : predict_bht_row;
    wire [BHT_ROW_WIDTH-1:0] bht_read_row1 =
        predict_bht_bank ? predict_bht_row : predict_bht_row1;

    logic [EPOCH_WIDTH-1:0] epoch_q;
    logic btb_clear_active_q;
    logic bht_clear_active_q;
    logic [BTB_ROW_WIDTH-1:0] btb_clear_row_q;
    logic [BHT_ROW_WIDTH-1:0] bht_clear_row_q;
    wire clear_active = btb_clear_active_q || bht_clear_active_q;
    wire predict_ready = rst_n && !invalidate_i && !clear_active;
    wire train_fire = train_i.valid && !invalidate_i && !clear_active;

    wire [1:0] conditional_next_counter = train_i.taken ?
        ((train_i.counter == 2'b11) ? train_i.counter : train_i.counter + 2'b01) :
        ((train_i.counter == 2'b00) ? train_i.counter : train_i.counter - 2'b01);
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

    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata0;
    wire [BTB_MEM_DATA_WIDTH-1:0] btb_mem_rdata1;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata0;
    wire [BHT_MEM_DATA_WIDTH-1:0] bht_mem_rdata1;

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

    logic predict_btb_bank_q;
    logic predict_btb_bank1_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag_q;
    logic [BTB_TAG_WIDTH-1:0] predict_btb_tag1_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index_q;
    logic [BHT_INDEX_WIDTH-1:0] predict_bht_index1_q;
    logic predict_alt_bank_q;
    logic predict_alt_bank1_q;
    logic [ALT_ROW_WIDTH-1:0] predict_alt_row_q;
    logic [ALT_ROW_WIDTH-1:0] predict_alt_row1_q;
    logic [ALT_TAG_WIDTH-1:0] predict_alt_tag_q;
    logic [ALT_TAG_WIDTH-1:0] predict_alt_tag1_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            predict_btb_bank_q <= 1'b0;
            predict_btb_bank1_q <= 1'b1;
            predict_btb_tag_q <= '0;
            predict_btb_tag1_q <= '0;
            predict_bht_index_q <= '0;
            predict_bht_index1_q <= '0;
            predict_alt_bank_q <= 1'b0;
            predict_alt_bank1_q <= 1'b1;
            predict_alt_row_q <= '0;
            predict_alt_row1_q <= '0;
            predict_alt_tag_q <= '0;
            predict_alt_tag1_q <= '0;
        end else begin
            predict_btb_bank_q <= predict_btb_bank;
            predict_btb_bank1_q <= predict_btb_bank1;
            predict_btb_tag_q <= predict_btb_tag;
            predict_btb_tag1_q <= predict_btb_tag1;
            predict_bht_index_q <= predict_bht_index;
            predict_bht_index1_q <= predict_bht_index1;
            predict_alt_bank_q <= predict_alt_bank;
            predict_alt_bank1_q <= predict_alt_bank1;
            predict_alt_row_q <= predict_alt_row;
            predict_alt_row1_q <= predict_alt_row1;
            predict_alt_tag_q <= predict_alt_tag;
            predict_alt_tag1_q <= predict_alt_tag1;
        end
    end

    logic [ALT_DATA_WIDTH-1:0] alt_bank0_q [0:ALT_BANK_DEPTH-1];
    logic [ALT_DATA_WIDTH-1:0] alt_bank1_q [0:ALT_BANK_DEPTH-1];
    logic [ALT_BANK_DEPTH-1:0] alt_valid0_q;
    logic [ALT_BANK_DEPTH-1:0] alt_valid1_q;
    wire [ALT_DATA_WIDTH-1:0] alt_train_data = train_alt_bank ?
        alt_bank1_q[train_alt_row] : alt_bank0_q[train_alt_row];
    wire [ALT_TAG_WIDTH-1:0] alt_train_old_tag =
        alt_train_data[ALT_DATA_WIDTH-1:3];
    wire alt_train_old_taken = alt_train_data[2];
    wire [1:0] alt_train_old_conf = alt_train_data[1:0];
    wire alt_train_valid = train_alt_bank ? alt_valid1_q[train_alt_row] :
        alt_valid0_q[train_alt_row];
    wire alt_train_match = alt_train_valid &&
        (alt_train_old_tag == train_alt_tag);
    wire alt_train_alternates = alt_train_match &&
        (alt_train_old_taken != train_i.taken);
    wire [1:0] alt_train_next_conf = !alt_train_match ? 2'b00 :
        (alt_train_alternates ?
         ((alt_train_old_conf == 2'b11) ? 2'b11 : alt_train_old_conf + 1'b1) :
         ((alt_train_old_conf == 2'b00) ? 2'b00 : alt_train_old_conf - 1'b1));
    wire [ALT_DATA_WIDTH-1:0] alt_train_next_data =
        {train_alt_tag, train_i.taken, alt_train_next_conf};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alt_valid0_q <= '0;
            alt_valid1_q <= '0;
        end else if (invalidate_i) begin
            alt_valid0_q <= '0;
            alt_valid1_q <= '0;
        end else if (train_fire && train_i.conditional) begin
            if (train_alt_bank) begin
                alt_bank1_q[train_alt_row] <= alt_train_next_data;
                alt_valid1_q[train_alt_row] <= 1'b1;
            end else begin
                alt_bank0_q[train_alt_row] <= alt_train_next_data;
                alt_valid0_q[train_alt_row] <= 1'b1;
            end
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

    wire [ALT_DATA_WIDTH-1:0] lane0_alt_data = predict_alt_bank_q ?
        alt_bank1_q[predict_alt_row_q] : alt_bank0_q[predict_alt_row_q];
    wire [ALT_DATA_WIDTH-1:0] lane1_alt_data = predict_alt_bank1_q ?
        alt_bank1_q[predict_alt_row1_q] : alt_bank0_q[predict_alt_row1_q];
    wire lane0_alt_valid = predict_alt_bank_q ?
        alt_valid1_q[predict_alt_row_q] : alt_valid0_q[predict_alt_row_q];
    wire lane1_alt_valid = predict_alt_bank1_q ?
        alt_valid1_q[predict_alt_row1_q] : alt_valid0_q[predict_alt_row1_q];
    wire [ALT_TAG_WIDTH-1:0] lane0_alt_tag =
        lane0_alt_data[ALT_DATA_WIDTH-1:3];
    wire [ALT_TAG_WIDTH-1:0] lane1_alt_tag =
        lane1_alt_data[ALT_DATA_WIDTH-1:3];
    wire lane0_alt_use = lane0_alt_valid &&
        (lane0_alt_tag == predict_alt_tag_q) && (&lane0_alt_data[1:0]);
    wire lane1_alt_use = lane1_alt_valid &&
        (lane1_alt_tag == predict_alt_tag1_q) && (&lane1_alt_data[1:0]);
    wire lane0_alt_taken = !lane0_alt_data[2];
    wire lane1_alt_taken = !lane1_alt_data[2];

    wire lane0_btb_hit = lane0_btb_valid && (lane0_btb_epoch == epoch_q) &&
        (lane0_btb_tag == predict_btb_tag_q);
    wire lane1_btb_hit = lane1_btb_valid && (lane1_btb_epoch == epoch_q) &&
        (lane1_btb_tag == predict_btb_tag1_q);

    assign predict_hit_o = predict_ready && lane0_btb_hit;
    assign predict_counter_o = predict_ready ? lane0_bht_counter : 2'b01;
    assign predict_taken_o = predict_hit_o &&
        (lane0_alt_use ? lane0_alt_taken : predict_counter_o[1]);
    assign predict_target_o = lane0_btb_target;
    assign predict_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(predict_bht_index_q);

    assign predict1_hit_o = predict_ready && lane1_btb_hit;
    assign predict1_counter_o = predict_ready ? lane1_bht_counter : 2'b01;
    assign predict1_taken_o = predict1_hit_o &&
        (lane1_alt_use ? lane1_alt_taken : predict1_counter_o[1]);
    assign predict1_target_o = lane1_btb_target;
    assign predict1_bht_index_o = ydrasil_pkg::BP_BHT_INDEX_WIDTH'(predict_bht_index1_q);

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n)
            assert (predict_pc_i[2] != predict_pc1_i[2])
                else $fatal(1, "predictor lanes must address opposite parity banks");
    end
`endif

endmodule
