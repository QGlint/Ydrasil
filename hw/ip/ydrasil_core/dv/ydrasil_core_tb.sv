`timescale 1ns/1ns

parameter longint time_end = 100000; 

module ydrasil_core_tb
(
`ifdef VERILATOR_CC
    input clk,
    input rst_n
`endif

);
string itcmfile;
string dtcmfile;
// ITCM 访问路径
`define ITCM u_dut.u_ydrasil_mems.u_itcm.u_irom
`define DTCM u_dut.u_ydrasil_mems.u_dtcm.u_dram

longint time_out;
longint sv_timeout;
logic [31:0] riscv_tohost_addr;
logic        riscv_tohost_addr_valid;
logic [31:0] riscv_write_tohost_addr;
logic        riscv_write_tohost_addr_valid;
logic [31:0] store_watch_lo;
logic [31:0] store_watch_hi;
logic        store_watch_valid;
initial begin
    if ($value$plusargs("itcmfile=%s", itcmfile)) begin
      $display("Loading memory from %s", itcmfile);
      $readmemh(itcmfile, `ITCM.mem_r);
    end else begin
      $display("No itcmfile provided");
    end

    if ($value$plusargs("dtcmfile=%s", dtcmfile)) begin
      $display("Loading memory from %s", dtcmfile);
      $readmemh(dtcmfile, `DTCM.mem_r);
    end else begin
      $display("No dtcmfile provided");
    end

    if ($value$plusargs("sv_timeout=%d", time_out))begin
        sv_timeout = time_out;
    end else begin
        sv_timeout = time_end;
    end

    if ($value$plusargs("tohost_addr=%h", riscv_tohost_addr)) begin
        riscv_tohost_addr_valid = 1'b1;
        $display("[TB] riscv-tests tohost_addr=0x%08h", riscv_tohost_addr);
    end else begin
        riscv_tohost_addr_valid = 1'b0;
        riscv_tohost_addr = 32'b0;
    end

    if ($value$plusargs("write_tohost_addr=%h", riscv_write_tohost_addr)) begin
        riscv_write_tohost_addr_valid = 1'b1;
        $display("[TB] riscv-tests write_tohost_addr=0x%08h", riscv_write_tohost_addr);
    end else begin
        riscv_write_tohost_addr_valid = 1'b0;
        riscv_write_tohost_addr = 32'b0;
    end

    if ($value$plusargs("store_watch_lo=%h", store_watch_lo) &&
        $value$plusargs("store_watch_hi=%h", store_watch_hi)) begin
        store_watch_valid = 1'b1;
        $display("[TB] store_watch lo=0x%08h hi=0x%08h", store_watch_lo, store_watch_hi);
    end else begin
        store_watch_valid = 1'b0;
        store_watch_lo = 32'b0;
        store_watch_hi = 32'b0;
    end
end



`ifndef VERILATOR_CC
	logic        clk;
	logic        rst_n;
`endif

	logic [31:0] perip_addr;
	logic        perip_wen;
	logic [3:0]  perip_mask;
	logic [31:0] perip_wdata;
	logic [31:0] perip_rdata;

    // 通用寄存器访问 - 仅用于错误信息显示
    wire [31:0] x3 = u_dut.u_ydrasil_registers.registers[3];
    // PC 监控
    wire [31:0] pc = u_dut.u_ydrasil_if_stage.pc_ff;
    wire [31:0] csr_instret = u_dut.u_ydrasil_registers_csr.instret[31:0];
    wire [31:0] csr_cyclel = u_dut.u_ydrasil_registers_csr.cycle[31:0];
    wire [31:0] riscv_write_tohost_store_pc = riscv_write_tohost_addr + 32'd4;
    wire        tohost_pc_accept =
        riscv_write_tohost_addr_valid &&
        u_dut.if_id_valid && !u_dut.stall_id && !u_dut.flush_id &&
        (u_dut.if_id_pc == riscv_write_tohost_store_pc);

    integer           r;
    reg     [8*300:1] testcase;

    // 计算ITCM的深度和字节大小
    localparam ITCM_DEPTH = (1 << (ydrasil_pkg::ITCM_ADDR_WIDTH));  // ITCM中的字数
    localparam ITCM_BYTE_SIZE = ITCM_DEPTH * 4;  // 总字节数

    // 创建与ITCM容量相同的临时字节数组
    reg [7:0] prog_mem[0:ITCM_BYTE_SIZE-1];
    integer i;

    // 添加PC监控变量
    reg [31:0] pc_write_to_host_cnt;
    reg [31:0] pc_write_to_host_cycle;
    reg [31:0] riscv_tohost_value;
    wire  [31:0] cycle_count = csr_cyclel;
    reg pc_write_to_host_flag;
    reg [31:0] last_pc;
    logic [31:0] riscv_last_store_issue_pc;
    logic        riscv_last_store_issue_valid;
    wire         riscv_store_issue =
        u_dut.ex_accept_valid &&
        u_dut.operator_type[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
        !u_dut.interrupt &&
        !u_dut.flush_ex;
    wire riscv_tohost_write =
        riscv_tohost_addr_valid &&
        perip_wen &&
        (&perip_mask) &&
        (perip_addr == riscv_tohost_addr) &&
        perip_wdata[0];
    wire riscv_tohost_write_from_write_tohost =
        riscv_tohost_write &&
        riscv_write_tohost_addr_valid &&
        riscv_last_store_issue_valid &&
        (riscv_last_store_issue_pc == riscv_write_tohost_store_pc);

`ifndef SYNTHESIS
    wire [31:0] store_watch_addr_lo = u_dut.dtcm_addr;
    wire [31:0] store_watch_addr_hi = u_dut.dtcm_addr + 32'd3;
    wire        store_watch_hit =
        store_watch_valid && u_dut.dtcm_we &&
        (store_watch_addr_lo <= store_watch_hi) &&
        (store_watch_addr_hi >= store_watch_lo);

    always_ff @(posedge clk) begin
        if (rst_n && store_watch_hit) begin
            $display("STORE_WATCH_HIT: addr=0x%08h data=0x%08h mask=0x%1h pc=0x%08h issue_pc=0x%08h",
                u_dut.dtcm_addr,
                u_dut.dtcm_wdata,
                u_dut.dtcm_wmask,
                pc,
                riscv_last_store_issue_pc);
            $fatal(1, "store watch hit");
        end
    end
`endif

    // 添加指令计数和IPC计算相关变量
    wire [31:0] instruction_count = csr_instret; // Use CSR instret as the retired instruction count.
    real ipc;
    real bp_accuracy;

`ifndef SYNTHESIS
    wire [31:0] dbg_bp_predict_pc;
    wire        dbg_bp_predict_hit;
    wire        dbg_bp_predict_taken;
    wire [31:0] dbg_bp_predict_target;
    wire [1:0]  dbg_bp_predict_counter;
    wire        dbg_bp_resolve_valid;
    wire [31:0] dbg_bp_resolve_pc;
    wire        dbg_bp_actual_taken;
    wire [31:0] dbg_bp_actual_target;
    wire [31:0] dbg_bp_actual_next_pc;
    wire        dbg_bp_pred_hit;
    wire        dbg_bp_pred_taken;
    wire [31:0] dbg_bp_pred_target;
    wire [1:0]  dbg_bp_pred_counter;
    wire        dbg_bp_pred_l0_taken;
    wire [31:0] dbg_bp_pred_next_pc;
    wire        dbg_bp_mispredict;

    wire bp_branch_valid = dbg_bp_resolve_valid;
    wire bp_pred_hit = dbg_bp_pred_hit;
    wire bp_pred_taken = dbg_bp_pred_hit & dbg_bp_pred_taken;
    wire bp_actual_taken = dbg_bp_actual_taken;
    wire bp_mispredict = dbg_bp_mispredict;
    wire bp_dir_mispredict = bp_pred_taken ^ bp_actual_taken;
    wire bp_target_mispredict =
        bp_actual_taken & bp_pred_taken & (dbg_bp_pred_target != dbg_bp_actual_target);
    wire bp_btb_miss_taken = bp_actual_taken & !dbg_bp_pred_hit;
    wire bp_correct_taken =
        bp_actual_taken & bp_pred_taken & (dbg_bp_pred_target == dbg_bp_actual_target);
    wire bp_correct_not_taken = !bp_actual_taken & !bp_pred_taken;
`else
    wire bp_branch_valid = 1'b0;
    wire bp_pred_hit = 1'b0;
    wire bp_pred_taken = 1'b0;
    wire bp_actual_taken = 1'b0;
    wire bp_mispredict = 1'b0;
    wire bp_dir_mispredict = 1'b0;
    wire bp_target_mispredict = 1'b0;
    wire bp_btb_miss_taken = 1'b0;
    wire bp_correct_taken = 1'b0;
    wire bp_correct_not_taken = 1'b0;
`endif
`ifndef SYNTHESIS
    bit bp_trace_en;
    bit bp_fetch_trace_en;
`endif
    reg [31:0] bp_branch_count;
    reg [31:0] bp_hit_count;
    reg [31:0] bp_taken_count;
    reg [31:0] bp_actual_taken_count;
    reg [31:0] bp_actual_not_taken_count;
    reg [31:0] bp_mispredict_count;
    reg [31:0] bp_dir_mispredict_count;
    reg [31:0] bp_target_mispredict_count;
    reg [31:0] bp_btb_miss_taken_count;
    reg [31:0] bp_correct_taken_count;
    reg [31:0] bp_correct_not_taken_count;
    reg [31:0] stall_scoreboard_count;
    reg [31:0] stall_lsu_struct_count;
    reg [31:0] stall_wb_backpressure_count;
    reg [31:0] stall_clint_count;
    reg [31:0] stall_mul_count;
    reg [31:0] sb_rs1_pending_count;
    reg [31:0] sb_rs2_pending_count;
    reg [31:0] sb_rd_waw_count;
    reg [31:0] sb_issue_rs1_hzd_count;
    reg [31:0] sb_issue_rs2_hzd_count;
    reg [31:0] sb_issue_rd_hzd_count;
    reg [31:0] sb_load_use_count;
    reg [31:0] sb_alu_use_count;
    reg [31:0] sb_mul_div_use_count;
    reg [31:0] sb_branch_src_wait_count;
    reg [31:0] sb_store_addr_wait_count;
    reg [31:0] sb_store_data_wait_count;
    reg [31:0] fe_pred_taken_redirect_count;
    reg [31:0] fe_correct_taken_redirect_count;
    reg [31:0] fe_correct_taken_bubble_count;
    reg [31:0] fe_correct_taken_l0_count;
    reg [31:0] fe_correct_taken_sync_count;
    reg [31:0] fe_correct_taken_zero_bubble_count;
    reg [31:0] fe_wrong_dir_flush_count;
    reg [31:0] sb_raw_alu_ready_next_count;
    reg [31:0] sb_raw_load_wait_count;
    reg [31:0] sb_raw_mul_wait_count;
    reg [31:0] sb_raw_wb_wait_count;
    reg [31:0] sb_waw_only_count;
    reg [31:0] sb_branch_wait_raw_class_count;
    reg [31:0] sb_store_addr_raw_class_count;
    reg [31:0] sb_store_data_raw_class_count;
    reg [31:0] sb_can_bypass_with_ready_issue_count;
    reg [31:0] sb_must_stall_in_order_count;
    reg [31:0] p4a_alu_stable_slot_hit_count;
    reg [31:0] p4a_rs1_stable_bypass_count;
    reg [31:0] p4a_rs2_stable_bypass_count;
    reg [31:0] p4a_raw_ready_next_count;
    reg [31:0] p4b_wb_buf_valid_count;
    reg [31:0] p4b_rs1_pending_hit_count;
    reg [31:0] p4b_rs2_pending_hit_count;
    reg [31:0] p4b_id_wait_rs1_hit_count;
    reg [31:0] p4b_id_wait_rs2_hit_count;
    reg [31:0] p4c_branch_ready_next_bypass_count;
    reg [31:0] p4c_branch_rs1_ready_next_bypass_count;
    reg [31:0] p4c_branch_rs2_ready_next_bypass_count;

	ydrasil_core u_dut (
		.clk      (clk),
		.rst_n    (rst_n),
		.perip_addr (perip_addr),
		.perip_wen  (perip_wen),
		.perip_mask (perip_mask),
		.perip_wdata(perip_wdata),
		.perip_rdata(perip_rdata)
`ifndef SYNTHESIS
        ,.dbg_bp_predict_pc_o(dbg_bp_predict_pc)
        ,.dbg_bp_predict_hit_o(dbg_bp_predict_hit)
        ,.dbg_bp_predict_taken_o(dbg_bp_predict_taken)
        ,.dbg_bp_predict_target_o(dbg_bp_predict_target)
        ,.dbg_bp_predict_counter_o(dbg_bp_predict_counter)
        ,.dbg_bp_resolve_valid_o(dbg_bp_resolve_valid)
        ,.dbg_bp_resolve_pc_o(dbg_bp_resolve_pc)
        ,.dbg_bp_actual_taken_o(dbg_bp_actual_taken)
        ,.dbg_bp_actual_target_o(dbg_bp_actual_target)
        ,.dbg_bp_actual_next_pc_o(dbg_bp_actual_next_pc)
        ,.dbg_bp_pred_hit_o(dbg_bp_pred_hit)
        ,.dbg_bp_pred_taken_o(dbg_bp_pred_taken)
        ,.dbg_bp_pred_target_o(dbg_bp_pred_target)
        ,.dbg_bp_pred_counter_o(dbg_bp_pred_counter)
        ,.dbg_bp_pred_l0_taken_o(dbg_bp_pred_l0_taken)
        ,.dbg_bp_pred_next_pc_o(dbg_bp_pred_next_pc)
        ,.dbg_bp_mispredict_o(dbg_bp_mispredict)
`endif
	);

`ifndef SYNTHESIS
    initial begin
        bp_trace_en = $test$plusargs("bp_trace");
        bp_fetch_trace_en = $test$plusargs("bp_fetch_trace");
    end
`endif

`ifndef VERILATOR_CC
	initial begin
		clk = 1'b0;
		forever #10 clk = ~clk;
	end

	initial begin
		rst_n = 1'b0;
		repeat (10) @(posedge clk);
		rst_n = 1'b1;
	end
`endif

	wire rst;
	assign rst = ~rst_n;

	always_ff @(posedge clk) begin
        if($time >= sv_timeout) begin
            $display("[TB] timeout reached, finish simulation");
            $display("[TB] timeout pc=0x%08h cycle=%0d instret=%0d", pc, cycle_count, instruction_count);
            $display("[TB] stall scoreboard=%0b lsu_struct=%0b clint=%0b wb=%0b stall_if=%0b stall_id=%0b bubble_id=%0b id_ex_valid=%0b",
                     u_dut.scoreboard_stall,
                     u_dut.lsu_struct_stall,
                     u_dut.clint_stall,
                     u_dut.wb_backpressure,
                     u_dut.stall_if,
                     u_dut.stall_id,
                     u_dut.bubble_id,
                     u_dut.id_ex_valid);
            $display("[TB] id_ctrl rs1=%0d ren1=%0b pend1=%0b rs2=%0d ren2=%0b pend2=%0b rd=%0d wen=%0b pend_rd=%0b lsu_req=%0b lsu_busy=%0b",
                     u_dut.id_ctrl_rs1_addr,
                     u_dut.id_ctrl_rs1_ren,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rs1_addr],
                     u_dut.id_ctrl_rs2_addr,
                     u_dut.id_ctrl_rs2_ren,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rs2_addr],
                     u_dut.id_ctrl_rd_addr,
                     u_dut.id_ctrl_rd_wen,
                     u_dut.gpr_pending_for_hazard[u_dut.id_ctrl_rd_addr],
                     u_dut.id_ctrl_lsu_req,
                     u_dut.lsu_ctrl_busy);
            $display("[TB] pending=0x%08h clear=0x%08h issue=0x%08h ex_accept=%0b id_rd_issue=%0b rf_wen=%0b rf_waddr=%0d alu_wen=%0b alu_waddr=%0d lsu_wen=%0b lsu_waddr=%0d mul_wen=%0b mul_waddr=%0d",
                     u_dut.gpr_pending_q,
                     u_dut.gpr_pending_clear_mask,
                     u_dut.gpr_pending_issue_mask,
                     u_dut.ex_accept_valid,
                     u_dut.id_ex_rd_issue,
                     u_dut.rf_wen_rd,
                     u_dut.rf_waddr_rd,
                     u_dut.alu_rf_wen_rd,
                     u_dut.alu_rf_waddr_rd,
                     u_dut.lsu_rf_wen_rd,
                     u_dut.lsu_rf_waddr_rd,
                     u_dut.mul_rf_wen_rd,
                     u_dut.mul_rf_waddr_rd);
            $display("[TB] if_id pc=0x%08h instr=0x%08h valid=%0b flush_if=%0b flush_id=%0b flush_ex=%0b interrupt=%0b branch_jump=%0b target=0x%08h",
                     u_dut.if_id_pc,
                     u_dut.if_id_instr,
                     u_dut.if_id_valid,
                     u_dut.flush_if,
                     u_dut.flush_id,
                     u_dut.flush_ex,
                     u_dut.interrupt,
                     u_dut.branch_jump,
                     u_dut.branch_target);
            $display("[TB] rn occ=%0d head=%0d tail=%0d ctrl_block=%0b commit_ready=%0b commit_valid=%0b alloc_valid=%0b alloc_rd=%0d alloc_pdst=%0d free=%0d",
                     u_dut.rn_real_rob_occ_q,
                     u_dut.rn_real_rob_head_q,
                     u_dut.rn_real_rob_tail_q,
                     u_dut.rn_real_ctrl_block,
                     u_dut.rn_real_commit0_ready,
                     u_dut.rn_real_commit0_valid,
                     u_dut.rn_real_alloc0_valid,
                     u_dut.rn_alloc_rd_addr,
                     u_dut.rn_real_alloc0_pdst,
                     u_dut.rn_real_free_count_q);
            $display("[TB] clint csr_state=0x%02h int_state=0x%01h we=%0b waddr=0x%03h wdata=0x%08h mtvec=0x%08h mepc=0x%08h mcause=0x%08h",
                     u_dut.u_clint.csr_state,
                     u_dut.u_clint.int_state,
                     u_dut.clint_csr_we,
                     u_dut.clint_csr_waddr,
                     u_dut.clint_csr_wdata,
                     u_dut.csr_clint_mtvec,
                     u_dut.csr_clint_mepc,
                     u_dut.u_ydrasil_registers_csr.mcause);
            $finish;
        end
        if(sim_done) begin
            print_perf_metrics();
            $finish; 
        end
	end

    // 周期计数器 - 保持同步实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_pc           <= 32'b0;
            bp_branch_count <= 32'b0;
            bp_hit_count <= 32'b0;
            bp_taken_count <= 32'b0;
            bp_actual_taken_count <= 32'b0;
            bp_actual_not_taken_count <= 32'b0;
            bp_mispredict_count <= 32'b0;
            bp_dir_mispredict_count <= 32'b0;
            bp_target_mispredict_count <= 32'b0;
            bp_btb_miss_taken_count <= 32'b0;
            bp_correct_taken_count <= 32'b0;
            bp_correct_not_taken_count <= 32'b0;
            stall_scoreboard_count <= 32'b0;
            stall_lsu_struct_count <= 32'b0;
            stall_wb_backpressure_count <= 32'b0;
            stall_clint_count <= 32'b0;
            stall_mul_count <= 32'b0;
            sb_rs1_pending_count <= 32'b0;
            sb_rs2_pending_count <= 32'b0;
            sb_rd_waw_count <= 32'b0;
            sb_issue_rs1_hzd_count <= 32'b0;
            sb_issue_rs2_hzd_count <= 32'b0;
            sb_issue_rd_hzd_count <= 32'b0;
            sb_load_use_count <= 32'b0;
            sb_alu_use_count <= 32'b0;
            sb_mul_div_use_count <= 32'b0;
            sb_branch_src_wait_count <= 32'b0;
            sb_store_addr_wait_count <= 32'b0;
            sb_store_data_wait_count <= 32'b0;
            fe_pred_taken_redirect_count <= 32'b0;
            fe_correct_taken_redirect_count <= 32'b0;
            fe_correct_taken_bubble_count <= 32'b0;
            fe_correct_taken_l0_count <= 32'b0;
            fe_correct_taken_sync_count <= 32'b0;
            fe_correct_taken_zero_bubble_count <= 32'b0;
            fe_wrong_dir_flush_count <= 32'b0;
            sb_raw_alu_ready_next_count <= 32'b0;
            sb_raw_load_wait_count <= 32'b0;
            sb_raw_mul_wait_count <= 32'b0;
            sb_raw_wb_wait_count <= 32'b0;
            sb_waw_only_count <= 32'b0;
            sb_branch_wait_raw_class_count <= 32'b0;
            sb_store_addr_raw_class_count <= 32'b0;
            sb_store_data_raw_class_count <= 32'b0;
            sb_can_bypass_with_ready_issue_count <= 32'b0;
            sb_must_stall_in_order_count <= 32'b0;
            p4a_alu_stable_slot_hit_count <= 32'b0;
            p4a_rs1_stable_bypass_count <= 32'b0;
            p4a_rs2_stable_bypass_count <= 32'b0;
            p4a_raw_ready_next_count <= 32'b0;
            p4b_wb_buf_valid_count <= 32'b0;
            p4b_rs1_pending_hit_count <= 32'b0;
            p4b_rs2_pending_hit_count <= 32'b0;
            p4b_id_wait_rs1_hit_count <= 32'b0;
            p4b_id_wait_rs2_hit_count <= 32'b0;
            p4c_branch_ready_next_bypass_count <= 32'b0;
            p4c_branch_rs1_ready_next_bypass_count <= 32'b0;
            p4c_branch_rs2_ready_next_bypass_count <= 32'b0;
        end else begin
            last_pc     <= pc;
            if (bp_branch_valid) begin
                bp_branch_count <= bp_branch_count + 1;
                bp_hit_count <= bp_hit_count + (bp_pred_hit ? 32'd1 : 32'd0);
                bp_taken_count <= bp_taken_count + (bp_pred_taken ? 32'd1 : 32'd0);
                bp_actual_taken_count <= bp_actual_taken_count + (bp_actual_taken ? 32'd1 : 32'd0);
                bp_actual_not_taken_count <= bp_actual_not_taken_count + (!bp_actual_taken ? 32'd1 : 32'd0);
                bp_mispredict_count <= bp_mispredict_count + (bp_mispredict ? 32'd1 : 32'd0);
                bp_dir_mispredict_count <= bp_dir_mispredict_count + (bp_dir_mispredict ? 32'd1 : 32'd0);
                bp_target_mispredict_count <= bp_target_mispredict_count + (bp_target_mispredict ? 32'd1 : 32'd0);
                bp_btb_miss_taken_count <= bp_btb_miss_taken_count + (bp_btb_miss_taken ? 32'd1 : 32'd0);
                bp_correct_taken_count <= bp_correct_taken_count + (bp_correct_taken ? 32'd1 : 32'd0);
                bp_correct_not_taken_count <= bp_correct_not_taken_count + (bp_correct_not_taken ? 32'd1 : 32'd0);
                fe_correct_taken_redirect_count <= fe_correct_taken_redirect_count + (bp_correct_taken ? 32'd1 : 32'd0);
                fe_correct_taken_l0_count <= fe_correct_taken_l0_count +
                    ((bp_correct_taken && dbg_bp_pred_l0_taken) ? 32'd1 : 32'd0);
                fe_correct_taken_sync_count <= fe_correct_taken_sync_count +
                    ((bp_correct_taken && !dbg_bp_pred_l0_taken) ? 32'd1 : 32'd0);
                fe_correct_taken_bubble_count <= fe_correct_taken_bubble_count +
                    ((bp_correct_taken && !dbg_bp_pred_l0_taken) ? 32'd1 : 32'd0);
                fe_correct_taken_zero_bubble_count <= fe_correct_taken_zero_bubble_count +
                    ((bp_correct_taken && dbg_bp_pred_l0_taken) ? 32'd1 : 32'd0);
                fe_wrong_dir_flush_count <= fe_wrong_dir_flush_count + (bp_dir_mispredict ? 32'd1 : 32'd0);
`ifndef SYNTHESIS
                if (bp_trace_en) begin
                    $display("BP_TRACE: cycle=%0d pc=0x%08h pred_hit=%0b pred_taken=%0b actual_taken=%0b pred_target=0x%08h actual_target=0x%08h pred_next=0x%08h actual_next=0x%08h counter=%0d mispredict=%0b dir_mispredict=%0b target_mispredict=%0b",
                        cycle_count,
                        dbg_bp_resolve_pc,
                        dbg_bp_pred_hit,
                        bp_pred_taken,
                        dbg_bp_actual_taken,
                        dbg_bp_pred_target,
                        dbg_bp_actual_target,
                        dbg_bp_pred_next_pc,
                        dbg_bp_actual_next_pc,
                        dbg_bp_pred_counter,
                        dbg_bp_mispredict,
                        bp_dir_mispredict,
                        bp_target_mispredict);
                end
`endif
            end
`ifndef SYNTHESIS
            if (bp_fetch_trace_en && dbg_bp_predict_hit) begin
                $display("BP_FETCH_TRACE: cycle=%0d pc=0x%08h hit=%0b taken=%0b target=0x%08h counter=%0d",
                    cycle_count,
                    dbg_bp_predict_pc,
                    dbg_bp_predict_hit,
                    dbg_bp_predict_taken,
                    dbg_bp_predict_target,
                    dbg_bp_predict_counter);
            end
`endif
            stall_scoreboard_count <= stall_scoreboard_count +
                (u_dut.scoreboard_stall ? 32'd1 : 32'd0);
            stall_lsu_struct_count <= stall_lsu_struct_count +
                (u_dut.lsu_struct_stall ? 32'd1 : 32'd0);
            stall_wb_backpressure_count <= stall_wb_backpressure_count +
                (u_dut.wb_backpressure ? 32'd1 : 32'd0);
            stall_clint_count <= stall_clint_count +
                (u_dut.clint_stall ? 32'd1 : 32'd0);
            stall_mul_count <= stall_mul_count +
                (u_dut.ex_mul_stall ? 32'd1 : 32'd0);
            sb_rs1_pending_count <= sb_rs1_pending_count +
                (u_dut.rs1_pending_stall_eff ? 32'd1 : 32'd0);
            sb_rs2_pending_count <= sb_rs2_pending_count +
                (u_dut.rs2_pending_stall_eff ? 32'd1 : 32'd0);
            sb_rd_waw_count <= sb_rd_waw_count +
                (u_dut.rd_waw_stall ? 32'd1 : 32'd0);
            sb_issue_rs1_hzd_count <= sb_issue_rs1_hzd_count +
                (u_dut.rs1_issue_hzd ? 32'd1 : 32'd0);
            sb_issue_rs2_hzd_count <= sb_issue_rs2_hzd_count +
                (u_dut.rs2_issue_hzd ? 32'd1 : 32'd0);
            sb_issue_rd_hzd_count <= sb_issue_rd_hzd_count +
                (u_dut.rd_issue_hzd ? 32'd1 : 32'd0);
            sb_load_use_count <= sb_load_use_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_alu_use_count <= sb_alu_use_count +
                ((u_dut.issue_alu_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_mul_div_use_count <= sb_mul_div_use_count +
                ((u_dut.issue_mul_div_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_branch_src_wait_count <= sb_branch_src_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            sb_store_addr_wait_count <= sb_store_addr_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs1_pending_stall_eff | u_dut.rs1_issue_hzd)) ? 32'd1 : 32'd0);
            sb_store_data_wait_count <= sb_store_data_wait_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs2_pending_stall_eff | u_dut.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            fe_pred_taken_redirect_count <= fe_pred_taken_redirect_count +
                (u_dut.u_ydrasil_if_stage.bp_predict_redirect ? 32'd1 : 32'd0);
            sb_raw_alu_ready_next_count <= sb_raw_alu_ready_next_count +
                ((u_dut.rs1_issue_alu_ready_next | u_dut.rs2_issue_alu_ready_next) ? 32'd1 : 32'd0);
            p4a_alu_stable_slot_hit_count <= p4a_alu_stable_slot_hit_count +
                (u_dut.issue_alu_stable_slot_hit ? 32'd1 : 32'd0);
            p4a_rs1_stable_bypass_count <= p4a_rs1_stable_bypass_count +
                (u_dut.rs1_issue_alu_stable_bypass ? 32'd1 : 32'd0);
            p4a_rs2_stable_bypass_count <= p4a_rs2_stable_bypass_count +
                (u_dut.rs2_issue_alu_stable_bypass ? 32'd1 : 32'd0);
            p4a_raw_ready_next_count <= p4a_raw_ready_next_count +
                ((u_dut.rs1_issue_alu_ready_next_raw | u_dut.rs2_issue_alu_ready_next_raw) ? 32'd1 : 32'd0);
            p4b_wb_buf_valid_count <= p4b_wb_buf_valid_count +
                (u_dut.wb_buf_fwd_valid ? 32'd1 : 32'd0);
            p4b_rs1_pending_hit_count <= p4b_rs1_pending_hit_count +
                ((u_dut.wb_buf_fwd_valid &&
                  u_dut.id_ctrl_rs1_ren &&
                  (u_dut.id_ctrl_rs1_addr != '0) &&
                  u_dut.gpr_pending_q[u_dut.id_ctrl_rs1_addr] &&
                  (u_dut.id_ctrl_rs1_addr == u_dut.wb_buf_fwd_addr)) ? 32'd1 : 32'd0);
            p4b_rs2_pending_hit_count <= p4b_rs2_pending_hit_count +
                ((u_dut.wb_buf_fwd_valid &&
                  u_dut.id_ctrl_rs2_ren &&
                  (u_dut.id_ctrl_rs2_addr != '0) &&
                  u_dut.gpr_pending_q[u_dut.id_ctrl_rs2_addr] &&
                  (u_dut.id_ctrl_rs2_addr == u_dut.wb_buf_fwd_addr)) ? 32'd1 : 32'd0);
            p4b_id_wait_rs1_hit_count <= p4b_id_wait_rs1_hit_count +
                ((u_dut.u_ydrasil_id_stage.issue_wait_rs1_ff &&
                  !u_dut.wb_hzd_valid_q &&
                  u_dut.u_ydrasil_id_stage.rs1_wb_fwd) ? 32'd1 : 32'd0);
            p4b_id_wait_rs2_hit_count <= p4b_id_wait_rs2_hit_count +
                ((u_dut.u_ydrasil_id_stage.issue_wait_rs2_ff &&
                  !u_dut.wb_hzd_valid_q &&
                  u_dut.u_ydrasil_id_stage.rs2_wb_fwd) ? 32'd1 : 32'd0);
            p4c_branch_ready_next_bypass_count <= p4c_branch_ready_next_bypass_count +
                ((u_dut.rs1_branch_ready_next_bypass |
                  u_dut.rs2_branch_ready_next_bypass) ? 32'd1 : 32'd0);
            p4c_branch_rs1_ready_next_bypass_count <= p4c_branch_rs1_ready_next_bypass_count +
                (u_dut.rs1_branch_ready_next_bypass ? 32'd1 : 32'd0);
            p4c_branch_rs2_ready_next_bypass_count <= p4c_branch_rs2_ready_next_bypass_count +
                (u_dut.rs2_branch_ready_next_bypass ? 32'd1 : 32'd0);
            sb_raw_load_wait_count <= sb_raw_load_wait_count +
                ((u_dut.issue_load_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_raw_mul_wait_count <= sb_raw_mul_wait_count +
                ((u_dut.issue_mul_div_producer & u_dut.issue_src_hzd) ? 32'd1 : 32'd0);
            sb_raw_wb_wait_count <= sb_raw_wb_wait_count +
                (((u_dut.rs1_pending_stall_eff | u_dut.rs2_pending_stall_eff) &&
                  !u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP] &&
                  !u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_LOAD] &&
                  !u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  !u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_MUL]) ? 32'd1 : 32'd0);
            sb_waw_only_count <= sb_waw_only_count +
                ((u_dut.rd_waw_stall &&
                  !(u_dut.rs1_pending_stall_eff | u_dut.rs2_pending_stall_eff |
                    u_dut.rs1_issue_hzd | u_dut.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            sb_branch_wait_raw_class_count <= sb_branch_wait_raw_class_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_BJP]) ? 32'd1 : 32'd0);
            sb_store_addr_raw_class_count <= sb_store_addr_raw_class_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs1_pending_stall_eff | u_dut.rs1_issue_hzd)) ? 32'd1 : 32'd0);
            sb_store_data_raw_class_count <= sb_store_data_raw_class_count +
                ((u_dut.scoreboard_stall &&
                  u_dut.u_ydrasil_id_stage.issue_operator_type_ff[ydrasil_pkg::OPERATOR_TYPE_STORE] &&
                  (u_dut.rs2_pending_stall_eff | u_dut.rs2_issue_hzd)) ? 32'd1 : 32'd0);
            sb_can_bypass_with_ready_issue_count <= sb_can_bypass_with_ready_issue_count +
                ((u_dut.scoreboard_stall && u_dut.u_ydrasil_id_stage.ri_slot1_ready) ? 32'd1 : 32'd0);
            sb_must_stall_in_order_count <= sb_must_stall_in_order_count +
                ((u_dut.scoreboard_stall && !u_dut.u_ydrasil_id_stage.ri_slot1_ready) ? 32'd1 : 32'd0);
        end
    end

    // PC监控逻辑：双取回时 tohost PC 可能来自 fetch queue slot1，
    // 因此按 IF/ID 接收的指令 PC 统计，而不是只看取指请求 PC。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_write_to_host_cnt   <= 32'b0;
            pc_write_to_host_flag  <= 1'b0;
            pc_write_to_host_cycle <= 32'b0;
        end else if (tohost_pc_accept) begin
            pc_write_to_host_cnt <= pc_write_to_host_cnt + 1'b1;
            if (pc_write_to_host_flag == 1'b0) begin
                pc_write_to_host_cycle <= cycle_count;
                pc_write_to_host_flag  <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            riscv_last_store_issue_pc <= 32'b0;
            riscv_last_store_issue_valid <= 1'b0;
        end else if (riscv_store_issue) begin
            riscv_last_store_issue_pc <= u_dut.id_instr_addr;
            riscv_last_store_issue_valid <= 1'b1;
        end
    end

    // 测试用例解析与ITCM加载
    initial begin
        if ($value$plusargs("itcm_init=%s", testcase)) begin
            display_testcase_name();
            $display("");

            $readmemh({testcase, ".verilog"}, prog_mem);
            for (i = 0; i < ITCM_DEPTH; i = i + 1) begin
                `ITCM.mem_r[i] = {prog_mem[i*4+3], prog_mem[i*4+2], prog_mem[i*4+1], prog_mem[i*4+0]};
            end
            $display("Successfully loaded instructions to ITCM");
            $display("ITCM 0x00: %h", `ITCM.mem_r[0]);
            $display("ITCM 0x01: %h", `ITCM.mem_r[1]);
            $display("ITCM 0x02: %h", `ITCM.mem_r[2]);
            $display("ITCM 0x03: %h", `ITCM.mem_r[3]);
            $display("ITCM 0x04: %h", `ITCM.mem_r[4]);
        end else begin
            $display("No itcm_init defined, use default ITCM init.");
        end
    end

	initial begin
		$monitor("[TB] time=%0t, rst_n=%b, LED=0x%08h, seg_wdata=0x%08h",
			$time, rst_n, LED, seg_wdata);
	end

	initial begin
		if(pc == 32'h800001b4) begin
			$display("PC = 0x800001b4,time = %0t", $time);
		end
	end


	localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
	localparam SEG_ADDR  = 32'h8020_0020;  // seg
	localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
	localparam CNT_ADDR  = 32'h8020_0050;  // counter
	localparam SIM_STDOUT_ADDR = 32'h8020_0060;
	localparam SIM_DUMP_ADDR   = 32'h8020_0064;

	logic [31:0] LED;
	logic [31:0] seg_wdata, cnt_rdata, mmio_rdata, dram_rdata;
	logic sim_done;
	logic sim_dump_en;
	logic [39:0] seg_output;
	string sim_stdout_line;

	task automatic sim_stdout_putc(input logic [7:0] ch);
		string one_char;
		begin
			if (ch == 8'h0a) begin
				$display("COREMARK_UART: %s", sim_stdout_line);
				sim_stdout_line = "";
			end else if (ch != 8'h0d) begin
				one_char = " ";
				one_char.putc(0, ch);
				if (sim_stdout_line.len() < 512) begin
					sim_stdout_line = {sim_stdout_line, one_char};
				end
			end
		end
	endtask

	// we don't care perip_mask in LED, SEG, SW & KEY, only care in DRAM
	// write process
	always_ff @(posedge clk) begin
		if (rst) begin
			LED <= 32'h0;
			seg_wdata <= 32'h0;
			sim_done <= 1'b0;
			sim_dump_en <= 1'b0;
			sim_stdout_line = "";
		end else if (perip_wen) begin
			case (perip_addr)
				LED_ADDR: begin
					LED <= perip_wdata;
					sim_done <= (perip_wdata != 32'h0);
				end
				SEG_ADDR:   seg_wdata <= perip_wdata;
				SIM_STDOUT_ADDR: begin
					$write("%c", perip_wdata[7:0]);
					sim_stdout_putc(perip_wdata[7:0]);
				end
				SIM_DUMP_ADDR: sim_dump_en <= perip_wdata[0];
			endcase
		end
	end

	wire [31:0] virtual_led_output;
	wire [39:0] virtual_seg_output;
	wire [63:0] virtual_sw_input = 0;
	wire [7:0]  virtual_key_input = 0;

    // read process: in one cycle
    always_comb begin
        if (~perip_wen) begin
            case (perip_addr)
                SW0_ADDR:  mmio_rdata = virtual_sw_input[31:0];
                SW1_ADDR:  mmio_rdata = virtual_sw_input[63:32];
                KEY_ADDR:  mmio_rdata = {24'd0, virtual_key_input};
                SEG_ADDR:  mmio_rdata = seg_wdata;
                default:   mmio_rdata = 32'hDEAD_BEEF;
            endcase
        end else begin
            mmio_rdata = 32'h0;
        end
    end

    // seg driver
  
    assign seg_output[7]  = 0;
    assign seg_output[17] = 0;
    assign seg_output[27] = 0;
    assign seg_output[37] = 0;
    

    // dram rw
    // dram_driver dram_driver_inst (
    //     .clk				(clk),
    //     .perip_addr			(perip_addr[17:0]),
    //     .perip_wdata		(perip_wdata),
    //     .perip_mask			(perip_mask),
    //     .dram_wen 			(perip_wen & (perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END)),
    //     .perip_rdata		(dram_rdata)
    // );

    // counter rw
    // counter counter_inst (
    //     .clk				(cnt_clk),
    //     .rst                (rst),
    //     .perip_wdata		(perip_wdata),
    //     .cnt_wen 			(perip_wen & (perip_addr == CNT_ADDR)),
    //     .perip_rdata		(cnt_rdata)
    // );

	wire cnt_wen ;
	assign cnt_wen = perip_wen & (perip_addr == CNT_ADDR);

    reg [31:0] mmio_rdata_reg;
    reg [31:0] back_rdata;
    always_ff @(posedge clk) begin
        mmio_rdata_reg <= back_rdata;
    end
    assign perip_rdata = mmio_rdata_reg;
    assign back_rdata = {32{perip_addr == SW0_ADDR}} & mmio_rdata |
                        {32{perip_addr == SW1_ADDR}} & mmio_rdata |
                        {32{perip_addr == KEY_ADDR}} & mmio_rdata |
                        {32{perip_addr == SEG_ADDR}} & mmio_rdata |
                        // {32{perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END}} & dram_rdata |
                        {32{perip_addr == CNT_ADDR}} & cnt_rdata;
    


    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;
    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic start;


    always_ff @(posedge clk) begin
        if (rst) begin
            start <= 0;
        end else if (cnt_wen & perip_wdata == 32'h8000_0000) begin
            start <= 1;
        end else if (cnt_wen & perip_wdata == 32'hFFFF_FFFF) begin
            start <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt_1ms <= 0;
        end else if (start) begin
            if (cnt_1ms == 49999) begin
                cnt_1ms <= 0;
            end else begin
                cnt_1ms <= cnt_1ms + 1;
            end
        end else begin
            cnt_1ms <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt_ms <= 0;
        end else if (start && cnt_1ms == 49999) begin
            cnt_ms <= cnt_ms + 1;
        end
    end

    assign cnt_rdata = cnt_ms;

    // riscv-tests official pass/fail protocol writes an odd value to tohost:
    // 1 means PASS, and any other odd value is an encoded FAIL code.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            riscv_tohost_value <= 32'b0;
        end else if (riscv_tohost_write) begin
            riscv_tohost_value <= perip_wdata;
            ipc = (instruction_count > 0 && cycle_count > 0) ? (instruction_count * 1.0) / cycle_count : 0.0;
            bp_accuracy = (bp_branch_count > 0) ?
                ((bp_branch_count - bp_mispredict_count) * 100.0) / bp_branch_count : 0.0;

            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~ Test Result Summary ~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $write("~TESTCASE: ");
            display_testcase_name();
            $display("~");
            $display("~~~~~~~~~~~~~~Total cycle_count value: %d ~~~~~~~~~~~~~", cycle_count);
            $display("~~~~~The test ending reached at cycle: %d ~~~~~~~~~~~~~", cycle_count);
            $display("~~~~~~~~~~Total instructions executed: %d ~~~~~~~~~~~~~", instruction_count);
            $display("~~~~~~~~~~~~~~~~~~ IPC value: %.4f ~~~~~~~~~~~~~~~~~~", ipc);
            $display("~~~~ Branch predictor: branches=%0d hits=%0d predicted_taken=%0d mispredicts=%0d accuracy=%.2f%% ~~~~",
                bp_branch_count, bp_hit_count, bp_taken_count, bp_mispredict_count, bp_accuracy);
            $display("~~~~ BP detail: actual_taken=%0d not_taken=%0d dir_mispredict=%0d target_mispredict=%0d btb_miss_taken=%0d correct_taken=%0d correct_not_taken=%0d ~~~~",
                bp_actual_taken_count,
                bp_actual_not_taken_count,
                bp_dir_mispredict_count,
                bp_target_mispredict_count,
                bp_btb_miss_taken_count,
                bp_correct_taken_count,
                bp_correct_not_taken_count);
            $display("~~~~~~~~~~~~~~~The final x3 Reg value: %d ~~~~~~~~~~~~~", x3);
            $display("~~~~~~~~~~~~~~~RISCV tohost value: 0x%08h ~~~~~~~~~~~~~", perip_wdata);
            $display("RISCV_TEST_TOHOST_WRITE: addr=0x%08h data=0x%08h mask=0x%1h pc=0x%08h write_tohost_store_pc=0x%08h last_store_pc=0x%08h from_write_tohost=%0d",
                perip_addr,
                perip_wdata,
                perip_mask,
                pc,
                riscv_write_tohost_store_pc,
                riscv_last_store_issue_pc,
                riscv_tohost_write_from_write_tohost);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

            if ((perip_wdata == 32'h1) && riscv_tohost_write_from_write_tohost) begin
                $display("RISCV_TEST_PASS: tohost=0x%08h", perip_wdata);
                $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            end else begin
                $display("RISCV_TEST_FAIL: tohost=0x%08h from_write_tohost=%0d", perip_wdata, riscv_tohost_write_from_write_tohost);
                $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
                $display("fail tohost = 0x%08h", perip_wdata);
                for (r = 0; r < 32; r = r + 1) $display("x%2d = 0x%x", r, u_dut.u_ydrasil_registers.registers[r]);
            end
            print_perf_metrics();
            $finish;
        end
    end

    // 对pc_write_to_host_cnt的变化进行监控
    always @(pc_write_to_host_cnt) begin
        if (1'b0 && pc_write_to_host_cnt == 32'd8) begin
            ipc = (instruction_count > 0 && cycle_count > 0) ? (instruction_count * 1.0) / cycle_count : 0.0;
            bp_accuracy = (bp_branch_count > 0) ?
                ((bp_branch_count - bp_mispredict_count) * 100.0) / bp_branch_count : 0.0;

            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~ Test Result Summary ~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $write("~TESTCASE: ");
            display_testcase_name();
            $display("~");
            $display("~~~~~~~~~~~~~~Total cycle_count value: %d ~~~~~~~~~~~~~", cycle_count);
            $display("~~~~~The test ending reached at cycle: %d ~~~~~~~~~~~~~", pc_write_to_host_cycle);
            $display("~~~~~~~~~~Total instructions executed: %d ~~~~~~~~~~~~~", instruction_count);
            $display("~~~~~~~~~~~~~~~~~~ IPC value: %.4f ~~~~~~~~~~~~~~~~~~", ipc);
            $display("~~~~ Branch predictor: branches=%0d hits=%0d predicted_taken=%0d mispredicts=%0d accuracy=%.2f%% ~~~~",
                bp_branch_count, bp_hit_count, bp_taken_count, bp_mispredict_count, bp_accuracy);
            $display("~~~~ BP detail: actual_taken=%0d not_taken=%0d dir_mispredict=%0d target_mispredict=%0d btb_miss_taken=%0d correct_taken=%0d correct_not_taken=%0d ~~~~",
                bp_actual_taken_count,
                bp_actual_not_taken_count,
                bp_dir_mispredict_count,
                bp_target_mispredict_count,
                bp_btb_miss_taken_count,
                bp_correct_taken_count,
                bp_correct_not_taken_count);
            $display("~~~~~~~~~~~~~~~The final x3 Reg value: %d ~~~~~~~~~~~~~", x3);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

            if (x3 == 1) begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
                $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
                $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
                $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
                $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                $display("fail testnum = %2d", x3);
                for (r = 0; r < 32; r = r + 1) $display("x%2d = 0x%x", r, u_dut.u_ydrasil_registers.registers[r]);
            end
            print_perf_metrics();
            $finish;
        end
    end

    task automatic print_perf_metrics;
        real perf_ipc;
        real perf_bp_accuracy;
        real perf_cycles_real;
        begin
            perf_ipc = (instruction_count > 0 && cycle_count > 0) ?
                (instruction_count * 1.0) / cycle_count : 0.0;
            perf_bp_accuracy = (bp_branch_count > 0) ?
                ((bp_branch_count - bp_mispredict_count) * 100.0) / bp_branch_count : 0.0;
            perf_cycles_real = (cycle_count > 0) ? (cycle_count * 1.0) : 1.0;

            $display("PERF_METRIC: CYCLES=%-d INSTS=%-d IPC=%.4f",
                cycle_count, instruction_count, perf_ipc);
            $display("PERF_CSR_INSTRET: CSR_INSTRET_DELTA0=%-d CSR_INSTRET_DELTA1=%-d CSR_INSTRET_DELTA2=%-d CSR_INSTRET_TOTAL_DELTA=%-d CSR_INSTRET_READ_VALUE=%-d",
                u_dut.u_ydrasil_registers_csr.perf_csr_instret_delta0,
                u_dut.u_ydrasil_registers_csr.perf_csr_instret_delta1,
                u_dut.u_ydrasil_registers_csr.perf_csr_instret_delta2,
                u_dut.u_ydrasil_registers_csr.perf_csr_instret_total_delta,
                instruction_count);
            $display("PERF_RATIO: IPC=%.4f SCOREBOARD_CYC_PCT=%.4f SB_RAW_WB_WAIT_CYC_PCT=%.4f SB_BRANCH_WAIT_RAW_CYC_PCT=%.4f SB_RAW_LOAD_WAIT_CYC_PCT=%.4f RI_SLOT1_FIRE_BLOCKED_BY_WB_ORDER_CYC_PCT=%.4f",
                perf_ipc,
                (stall_scoreboard_count * 100.0) / perf_cycles_real,
                (sb_raw_wb_wait_count * 100.0) / perf_cycles_real,
                (sb_branch_wait_raw_class_count * 100.0) / perf_cycles_real,
                (sb_raw_load_wait_count * 100.0) / perf_cycles_real,
                (u_dut.u_ydrasil_id_stage.perf_ri_slot1_fire_blocked_by_wb_order * 100.0) / perf_cycles_real);
            $display("PERF_STALL: SCOREBOARD=%-d LSU_STRUCT=%-d WB_BACKPRESSURE=%-d CLINT=%-d MUL_DIV=%-d",
                stall_scoreboard_count,
                stall_lsu_struct_count,
                stall_wb_backpressure_count,
                stall_clint_count,
                stall_mul_count);
            $display("PERF_SCOREBOARD_DETAIL: RS1_PENDING=%-d RS2_PENDING=%-d RD_WAW=%-d ISSUE_RS1_HZD=%-d ISSUE_RS2_HZD=%-d ISSUE_RD_HZD=%-d LOAD_USE=%-d ALU_USE=%-d MUL_DIV_USE=%-d BRANCH_SRC_WAIT=%-d STORE_ADDR_WAIT=%-d STORE_DATA_WAIT=%-d",
                sb_rs1_pending_count,
                sb_rs2_pending_count,
                sb_rd_waw_count,
                sb_issue_rs1_hzd_count,
                sb_issue_rs2_hzd_count,
                sb_issue_rd_hzd_count,
                sb_load_use_count,
                sb_alu_use_count,
                sb_mul_div_use_count,
                sb_branch_src_wait_count,
                sb_store_addr_wait_count,
                sb_store_data_wait_count);
            $display("PERF_SCOREBOARD_CLASS: SB_RAW_ALU_READY_NEXT=%-d SB_RAW_LOAD_WAIT=%-d SB_RAW_MUL_WAIT=%-d SB_RAW_WB_WAIT=%-d SB_WAW_ONLY=%-d SB_BRANCH_WAIT_RAW=%-d SB_STORE_ADDR_RAW=%-d SB_STORE_DATA_RAW=%-d SB_CAN_BYPASS_WITH_READY_ISSUE=%-d SB_MUST_STALL_IN_ORDER=%-d",
                sb_raw_alu_ready_next_count,
                sb_raw_load_wait_count,
                sb_raw_mul_wait_count,
                sb_raw_wb_wait_count,
                sb_waw_only_count,
                sb_branch_wait_raw_class_count,
                sb_store_addr_raw_class_count,
                sb_store_data_raw_class_count,
                sb_can_bypass_with_ready_issue_count,
                sb_must_stall_in_order_count);
            $display("PERF_PHASE4A_ALU_STABLE: RAW_READY_NEXT=%-d STABLE_SLOT_HIT=%-d RS1_BYPASS=%-d RS2_BYPASS=%-d",
                p4a_raw_ready_next_count,
                p4a_alu_stable_slot_hit_count,
                p4a_rs1_stable_bypass_count,
                p4a_rs2_stable_bypass_count);
            $display("PERF_PHASE4B_WB_BUF: VALID=%-d RS1_PENDING_HIT=%-d RS2_PENDING_HIT=%-d ID_WAIT_RS1_HIT=%-d ID_WAIT_RS2_HIT=%-d",
                p4b_wb_buf_valid_count,
                p4b_rs1_pending_hit_count,
                p4b_rs2_pending_hit_count,
                p4b_id_wait_rs1_hit_count,
                p4b_id_wait_rs2_hit_count);
            $display("PERF_PHASE4C_BRANCH_BYPASS: READY_NEXT=%-d RS1_READY_NEXT=%-d RS2_READY_NEXT=%-d",
                p4c_branch_ready_next_bypass_count,
                p4c_branch_rs1_ready_next_bypass_count,
                p4c_branch_rs2_ready_next_bypass_count);
            $display("PERF_FRONTEND: PRED_TAKEN_REDIRECT=%-d CORRECT_TAKEN_TOTAL=%-d CORRECT_TAKEN_L0=%-d CORRECT_TAKEN_SYNC=%-d CORRECT_TAKEN_SYNC_BUBBLE=%-d CORRECT_TAKEN_ZERO_BUBBLE=%-d WRONG_DIR_FLUSH=%-d BTB_MISS_TAKEN=%-d FETCH_Q_FULL=%-d FETCH_Q_EMPTY=%-d FETCH_Q_PUSH=%-d FETCH_Q_POP=%-d DECODE_BLOCKED_BY_UOPQ=%-d SYNC_BP_TAKEN_BUBBLE=%-d L0_HIT=%-d L0_TAKEN=%-d",
                fe_pred_taken_redirect_count,
                fe_correct_taken_redirect_count,
                fe_correct_taken_l0_count,
                fe_correct_taken_sync_count,
                fe_correct_taken_bubble_count,
                fe_correct_taken_zero_bubble_count,
                fe_wrong_dir_flush_count,
                bp_btb_miss_taken_count,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_full,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_empty,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_push,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_pop,
                u_dut.u_ydrasil_if_stage.perf_decode_blocked_by_uopq,
                u_dut.u_ydrasil_if_stage.perf_sync_bp_taken_bubble,
                u_dut.u_ydrasil_if_stage.perf_l0_hit,
                u_dut.u_ydrasil_if_stage.perf_l0_taken);
            $display("PERF_FETCHQ: FQ_OCC_0=%-d FQ_OCC_1=%-d FQ_OCC_2=%-d FQ_OCC_3=%-d FQ_OCC_4=%-d FQ_PUSH=%-d FQ_POP=%-d FQ_FLUSH_DROP=%-d FQ_FULL_BLOCK_REQ=%-d FQ_BACKEND_STALL_POP=%-d FQ_EMPTY_ID_BUBBLE=%-d FQ_SYNC_REDIRECT_FLUSH=%-d FQ_EX_REDIRECT_FLUSH=%-d",
                u_dut.u_ydrasil_if_stage.perf_fq_occ_0,
                u_dut.u_ydrasil_if_stage.perf_fq_occ_1,
                u_dut.u_ydrasil_if_stage.perf_fq_occ_2,
                u_dut.u_ydrasil_if_stage.perf_fq_occ_3,
                u_dut.u_ydrasil_if_stage.perf_fq_occ_4,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_push,
                u_dut.u_ydrasil_if_stage.perf_fetch_q_pop,
                u_dut.u_ydrasil_if_stage.perf_fq_flush_drop,
                u_dut.u_ydrasil_if_stage.perf_fq_full_block_req,
                u_dut.u_ydrasil_if_stage.perf_fq_backend_stall_pop,
                u_dut.u_ydrasil_if_stage.perf_fq_empty_id_bubble,
                u_dut.u_ydrasil_if_stage.perf_fq_sync_redirect_flush,
                u_dut.u_ydrasil_if_stage.perf_fq_ex_redirect_flush);
            $display("PERF_FETCH2: FETCH2_REQ=%-d FETCH2_VALID2=%-d FETCH2_VALID1_ONLY=%-d FETCH2_ALIGN_BLOCK=%-d FETCH2_REDIRECT_KILL_SLOT1=%-d FETCH2_IROM_STALL=%-d",
                u_dut.u_ydrasil_if_stage.perf_fetch2_req,
                u_dut.u_ydrasil_if_stage.perf_fetch2_valid2,
                u_dut.u_ydrasil_if_stage.perf_fetch2_valid1_only,
                u_dut.u_ydrasil_if_stage.perf_fetch2_align_block,
                u_dut.u_ydrasil_if_stage.perf_fetch2_redirect_kill_slot1,
                u_dut.u_ydrasil_if_stage.perf_fetch2_irom_stall);
            $display("PERF_L0: L0_LOOKUP=%-d L0_HIT=%-d L0_TAKEN=%-d L0_CORRECT_TAKEN=%-d L0_WRONG_TAKEN=%-d L0_TRAIN_TAKEN=%-d L0_TRAIN_NOT_TAKEN=%-d L0_COUNTER_INC=%-d L0_COUNTER_DEC=%-d",
                u_dut.u_ydrasil_if_stage.perf_l0_lookup,
                u_dut.u_ydrasil_if_stage.perf_l0_hit,
                u_dut.u_ydrasil_if_stage.perf_l0_taken,
                u_dut.u_ydrasil_if_stage.perf_l0_correct_taken,
                u_dut.u_ydrasil_if_stage.perf_l0_wrong_taken,
                u_dut.u_ydrasil_if_stage.perf_l0_train_taken,
                u_dut.u_ydrasil_if_stage.perf_l0_train_not_taken,
                u_dut.u_ydrasil_if_stage.perf_l0_counter_inc,
                u_dut.u_ydrasil_if_stage.perf_l0_counter_dec);
            $display("PERF_ID: ID_DECODE_VALID=%-d ID_ISSUE_ACCEPT=%-d ID_ISSUE_FIRE=%-d ID_ISSUE_SLOT_VALID=%-d ID_ISSUE_NO_FIRE=%-d ID_ISSUE_WAIT_BLOCK=%-d ID_WAIT_RS1=%-d ID_WAIT_RS2=%-d ID_WAIT_ALU_READY_NEXT_RS1=%-d ID_WAIT_ALU_READY_NEXT_RS2=%-d ID_WAIT_LSU_FWD_RS1=%-d ID_WAIT_LSU_FWD_RS2=%-d ID_WAIT_WB_FWD_RS1=%-d ID_WAIT_WB_FWD_RS2=%-d ID_SKID_VALID=%-d ID_SKID_FILL=%-d ID_SKID_DRAIN=%-d ID_SKID_FULL_STALL=%-d ID_FRONTEND_STALL=%-d",
                u_dut.u_ydrasil_id_stage.perf_id_decode_valid,
                u_dut.u_ydrasil_id_stage.perf_id_issue_accept,
                u_dut.u_ydrasil_id_stage.perf_id_issue_fire,
                u_dut.u_ydrasil_id_stage.perf_id_issue_slot_valid,
                u_dut.u_ydrasil_id_stage.perf_id_issue_no_fire,
                u_dut.u_ydrasil_id_stage.perf_id_issue_wait_block,
                u_dut.u_ydrasil_id_stage.perf_id_wait_rs1,
                u_dut.u_ydrasil_id_stage.perf_id_wait_rs2,
                u_dut.u_ydrasil_id_stage.perf_id_wait_alu_ready_next_rs1,
                u_dut.u_ydrasil_id_stage.perf_id_wait_alu_ready_next_rs2,
                u_dut.u_ydrasil_id_stage.perf_id_wait_lsu_fwd_rs1,
                u_dut.u_ydrasil_id_stage.perf_id_wait_lsu_fwd_rs2,
                u_dut.u_ydrasil_id_stage.perf_id_wait_wb_fwd_rs1,
                u_dut.u_ydrasil_id_stage.perf_id_wait_wb_fwd_rs2,
                u_dut.u_ydrasil_id_stage.perf_id_skid_valid,
                u_dut.u_ydrasil_id_stage.perf_id_skid_fill,
                u_dut.u_ydrasil_id_stage.perf_id_skid_drain,
                u_dut.u_ydrasil_id_stage.perf_id_skid_full_stall,
                u_dut.u_ydrasil_id_stage.perf_id_frontend_stall);
            $display("PERF_READY_ISSUE: RI_SLOT0_VALID=%-d RI_SLOT1_VALID=%-d RI_SLOT0_READY=%-d RI_SLOT1_READY=%-d RI_FIRE_SLOT0=%-d RI_FIRE_SLOT1_BYPASS=%-d RI_SLOT1_BLOCK_RAW=%-d RI_SLOT1_BLOCK_WAW=%-d RI_SLOT1_BLOCK_CTRL=%-d RI_SLOT1_BLOCK_MEM=%-d RI_SLOT1_BLOCK_UNSUPPORTED=%-d RI_SLOT1_READY_WHEN_SLOT0_BLOCKED=%-d RI_SLOT1_READY_WHEN_SLOT0_READY=%-d RI_SLOT1_FIRE_BLOCKED_BY_SINGLE_ISSUE=%-d RI_SLOT1_FIRE_BLOCKED_BY_OPERAND_PORT=%-d RI_SLOT1_FIRE_BLOCKED_BY_WB_ORDER=%-d RI_BYPASS_FLUSH_KILLED=%-d",
                u_dut.u_ydrasil_id_stage.perf_ri_slot0_valid,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_valid,
                u_dut.u_ydrasil_id_stage.perf_ri_slot0_ready,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_ready,
                u_dut.u_ydrasil_id_stage.perf_ri_fire_slot0,
                u_dut.u_ydrasil_id_stage.perf_ri_fire_slot1_bypass,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_block_raw,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_block_waw,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_block_ctrl,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_block_mem,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_block_unsupported,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_ready_when_slot0_blocked,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_ready_when_slot0_ready,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_fire_blocked_by_single_issue,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_fire_blocked_by_operand_port,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_fire_blocked_by_wb_order,
                u_dut.u_ydrasil_id_stage.perf_ri_bypass_flush_killed);
            $display("PERF_ALU_RESOURCE: ALU0_ISSUE=%-d ALU1_ISSUE_CANDIDATE=%-d ALU1_BLOCKED_NO_PORT=%-d ALU1_BLOCKED_WB_PORT=%-d ALU1_BLOCKED_RF_PORT=%-d ALU1_BLOCKED_FORWARD_PORT=%-d",
                u_dut.u_ydrasil_id_stage.perf_ri_fire_slot0,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_ready_when_slot0_ready,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_fire_blocked_by_single_issue,
                32'd0,
                32'd0,
                32'd0);
            $display("PERF_ALU_RATIO: ALU0_ISSUE_CYC_PCT=%.4f ALU1_ISSUE_CYC_PCT=%.4f DI_PAIR_CYC_PCT=%.4f PIPE1_BLOCKED_P0_FIRE_CYC_PCT=%.4f",
                (u_dut.u_ydrasil_id_stage.perf_di_pipe0_fire * 100.0) / perf_cycles_real,
                (u_dut.u_ydrasil_id_stage.perf_di_pipe1_fire * 100.0) / perf_cycles_real,
                (u_dut.u_ydrasil_id_stage.perf_di_pair_fire * 100.0) / perf_cycles_real,
                (u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_when_p0_blocked * 100.0) / perf_cycles_real);
            $display("PERF_DUAL_SHADOW: DS_CYCLES=%-d DS_PIPE0_VALID=%-d DS_PIPE0_READY=%-d DS_PIPE1_VALID=%-d DS_PIPE1_SIMPLE_ALU=%-d DS_SAFE_CANDIDATE=%-d DS_SAFE_WHEN_PIPE0_READY=%-d DS_SAFE_WHEN_PIPE0_BLOCKED=%-d DS_BLOCK_PIPE1_UNSUPPORTED=%-d DS_BLOCK_RAW_PIPE0=%-d DS_BLOCK_WAW_PIPE0=%-d DS_BLOCK_PENDING_RS1=%-d DS_BLOCK_PENDING_RS2=%-d DS_BLOCK_CTRL=%-d DS_BLOCK_MEM=%-d DS_BLOCK_CSR_SYS=%-d DS_BLOCK_FLUSH=%-d DS_BLOCK_WB_PORT=%-d DS_BLOCK_FORWARD_COMPLEX=%-d",
                u_dut.u_ydrasil_id_stage.perf_ds_cycles,
                u_dut.u_ydrasil_id_stage.perf_ds_pipe0_valid,
                u_dut.u_ydrasil_id_stage.perf_ds_pipe0_ready,
                u_dut.u_ydrasil_id_stage.perf_ds_pipe1_valid,
                u_dut.u_ydrasil_id_stage.perf_ds_pipe1_simple_alu,
                u_dut.u_ydrasil_id_stage.perf_ds_safe_candidate,
                u_dut.u_ydrasil_id_stage.perf_ds_safe_when_pipe0_ready,
                u_dut.u_ydrasil_id_stage.perf_ds_safe_when_pipe0_blocked,
                u_dut.u_ydrasil_id_stage.perf_ds_block_pipe1_unsupported,
                u_dut.u_ydrasil_id_stage.perf_ds_block_raw_pipe0,
                u_dut.u_ydrasil_id_stage.perf_ds_block_waw_pipe0,
                u_dut.u_ydrasil_id_stage.perf_ds_block_pending_rs1,
                u_dut.u_ydrasil_id_stage.perf_ds_block_pending_rs2,
                u_dut.u_ydrasil_id_stage.perf_ds_block_ctrl,
                u_dut.u_ydrasil_id_stage.perf_ds_block_mem,
                u_dut.u_ydrasil_id_stage.perf_ds_block_csr_sys,
                u_dut.u_ydrasil_id_stage.perf_ds_block_flush,
                u_dut.u_ydrasil_id_stage.perf_ds_block_wb_port,
                u_dut.u_ydrasil_id_stage.perf_ds_block_forward_complex);
            $display("PERF_PAIR_SHADOW: P1SH_VALID_CYCLES=%-d P1SH_SIMPLE_ALU=%-d P1SH_SAFE_CAND=%-d P1SH_BLOCK_RAW_PAIR0=%-d P1SH_BLOCK_WAW_PAIR0=%-d P1SH_BLOCK_PENDING_RS=%-d P1SH_BLOCK_CTRL_MEM=%-d",
                u_dut.u_ydrasil_id_stage.perf_p1sh_valid_cycles,
                u_dut.u_ydrasil_id_stage.perf_p1sh_simple_alu,
                u_dut.u_ydrasil_id_stage.perf_p1sh_safe_cand,
                u_dut.u_ydrasil_id_stage.perf_p1sh_block_raw_pair0,
                u_dut.u_ydrasil_id_stage.perf_p1sh_block_waw_pair0,
                u_dut.u_ydrasil_id_stage.perf_p1sh_block_pending_rs,
                u_dut.u_ydrasil_id_stage.perf_p1sh_block_ctrl_mem);
            $display("PERF_UOPQ_SHADOW: UOPQ_OCC_0=%-d UOPQ_OCC_1=%-d UOPQ_OCC_2=%-d UOPQ_OCC_3=%-d UOPQ_OCC_4=%-d UOPQ_P1_SAFE_1=%-d UOPQ_P1_SAFE_2=%-d UOPQ_P1_SAFE_3=%-d UOPQ_BLOCK_OLDER_CTRL_MEM=%-d UOPQ_BLOCK_RAW_OLDER=%-d UOPQ_BLOCK_WAW_OLDER=%-d",
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_0,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_1,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_2,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_3,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_4,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_safe_1,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_safe_2,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_safe_3,
                u_dut.u_ydrasil_id_stage.perf_uopq_block_older_ctrl_mem,
                u_dut.u_ydrasil_id_stage.perf_uopq_block_raw_older,
                u_dut.u_ydrasil_id_stage.perf_uopq_block_waw_older);
            $display("PERF_UOPQ_ISSUE: UOPQ_P1_FIRE_FROM_1=%-d UOPQ_P1_FIRE_FROM_2=%-d UOPQ_P1_FIRE_FROM_3=%-d UOPQ_P1_FIRE_WHEN_P0_READY=%-d UOPQ_P1_FIRE_WHEN_P0_BLOCKED=%-d UOPQ_P1_BLOCK_OLDER_CTRL_MEM=%-d UOPQ_P1_BLOCK_RAW_OLDER=%-d UOPQ_P1_BLOCK_WAW_OLDER=%-d UOPQ_P1_BLOCK_COMMIT_ORDER=%-d",
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_from_1,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_from_2,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_from_3,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_when_p0_ready,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_when_p0_blocked,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_older_ctrl_mem,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_raw_older,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_waw_older,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_commit_order);
            $display("PERF_RENAME_SHADOW: RN_SHADOW_RAW_WB_CAN_REMOVE=%-d RN_SHADOW_WAW_CAN_REMOVE=%-d RN_SHADOW_WAR_CAN_REMOVE=%-d RN_SHADOW_PIPE1_WHEN_P0_BLOCKED_CAN_FIRE=%-d RN_SHADOW_FREE_PREG_MIN=%-d",
                u_dut.perf_rn_shadow_raw_wb_can_remove,
                u_dut.perf_rn_shadow_waw_can_remove,
                u_dut.perf_rn_shadow_war_can_remove,
                u_dut.u_ydrasil_id_stage.perf_ri_slot1_ready_when_slot0_blocked,
                u_dut.perf_rn_free_min);
            $display("PERF_RENAME_SHADOW_SPLIT: RAW_WB_CAN_REMOVE_ALU_READY=%-d RAW_WB_CAN_REMOVE_P1_READY=%-d RAW_WB_CAN_REMOVE_LSU_READY=%-d RAW_WB_CAN_REMOVE_MUL_READY=%-d RAW_WB_FALSE_POSITIVE=%-d",
                u_dut.perf_raw_wb_can_remove_alu_ready,
                u_dut.perf_raw_wb_can_remove_p1_ready,
                u_dut.perf_raw_wb_can_remove_lsu_ready,
                u_dut.perf_raw_wb_can_remove_mul_ready,
                u_dut.perf_raw_wb_false_positive);
            $display("PERF_RENAME: RN_ALLOC0=%-d RN_ALLOC1=%-d RN_COMMIT=%-d RN_FREE=%-d RN_FREE_MIN=%-d RN_FULL_STALL=%-d RN_FLUSH_RESTORE=%-d RN_SAME_CYCLE_RAW=%-d RN_SAME_CYCLE_WAW=%-d RN_X0_NO_ALLOC=%-d RN_FULL_STALL_CYC_PCT=%.4f",
                u_dut.perf_rn_alloc0,
                u_dut.perf_rn_alloc1,
                u_dut.perf_rn_commit,
                u_dut.perf_rn_free,
                u_dut.perf_rn_free_min,
                u_dut.perf_rn_full_stall,
                u_dut.perf_rn_flush_restore,
                u_dut.perf_rn_same_cycle_raw,
                u_dut.perf_rn_same_cycle_waw,
                u_dut.perf_rn_x0_no_alloc,
                (u_dut.perf_rn_full_stall * 100.0) / perf_cycles_real);
            $display("PERF_RENAME_STALL: RN_FULL_STALL_FREELIST=%-d RN_FULL_STALL_ROB=%-d",
                u_dut.perf_rn_full_stall_freelist,
                u_dut.perf_rn_full_stall_rob);
            $display("PERF_PRF: PRF_RD0=%-d PRF_RD1=%-d PRF_RD2=%-d PRF_RD3=%-d PRF_WR0=%-d PRF_WR1=%-d PRF_BYPASS_RD0=%-d PRF_BYPASS_RD1=%-d PRF_BYPASS_RD2=%-d PRF_BYPASS_RD3=%-d PRF_BYPASS_USE_CYC_PCT=%.4f",
                u_dut.perf_prf_rd0,
                u_dut.perf_prf_rd1,
                u_dut.perf_prf_rd2,
                u_dut.perf_prf_rd3,
                u_dut.perf_prf_wr0,
                u_dut.perf_prf_wr1,
                u_dut.perf_prf_bypass_rd0,
                u_dut.perf_prf_bypass_rd1,
                u_dut.perf_prf_bypass_rd2,
                u_dut.perf_prf_bypass_rd3,
                ((u_dut.perf_prf_bypass_rd0 + u_dut.perf_prf_bypass_rd1 +
                  u_dut.perf_prf_bypass_rd2 + u_dut.perf_prf_bypass_rd3) * 100.0) / perf_cycles_real);
            $display("PERF_ISSUEQ: IQ_OCC_0=%-d IQ_OCC_1=%-d IQ_OCC_2=%-d IQ_OCC_3=%-d IQ_OCC_4=%-d IQ_FULL_STALL=%-d IQ_WAKEUP_RS1=%-d IQ_WAKEUP_RS2=%-d IQ_PIPE0_FIRE=%-d IQ_PIPE1_FIRE=%-d IQ_PIPE1_FIRE_WHEN_PIPE0_BLOCKED=%-d IQ_PIPE1_BLOCK_OLDER_CTRL_MEM=%-d IQ_PIPE1_BLOCK_NOT_READY=%-d IQ_FULL_STALL_CYC_PCT=%.4f PIPE1_WHEN_P0_BLOCKED_CYC_PCT=%.4f",
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_0,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_1,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_2,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_3,
                u_dut.u_ydrasil_id_stage.perf_uopq_occ_4,
                32'd0,
                32'd0,
                32'd0,
                u_dut.u_ydrasil_id_stage.perf_di_pipe0_fire,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_fire,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_when_p0_blocked,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_older_ctrl_mem,
                u_dut.u_ydrasil_id_stage.perf_uopq_p1_block_raw_older,
                0.0,
                (u_dut.u_ydrasil_id_stage.perf_uopq_p1_fire_when_p0_blocked * 100.0) / perf_cycles_real);
            $display("PERF_ROB: ROB_OCC_0=%-d ROB_OCC_1=%-d ROB_OCC_2=%-d ROB_OCC_3=%-d ROB_OCC_4P=%-d ROB_FULL_STALL=%-d ROB_COMMIT0=%-d ROB_COMMIT1=%-d ROB_HEAD_NOT_READY=%-d ROB_FULL_STALL_CYC_PCT=%.4f",
                u_dut.perf_rob_occ_0,
                u_dut.perf_rob_occ_1,
                u_dut.perf_rob_occ_2,
                u_dut.perf_rob_occ_3,
                u_dut.perf_rob_occ_4p,
                u_dut.perf_rob_full_stall,
                u_dut.perf_rob_commit0,
                u_dut.perf_rob_commit1,
                u_dut.perf_rob_head_not_ready,
                (u_dut.perf_rob_full_stall * 100.0) / perf_cycles_real);
            $display("PERF_ROB_HEAD_SPLIT: ROB_HEAD_WAIT_ALU=%-d ROB_HEAD_WAIT_LSU=%-d ROB_HEAD_WAIT_MUL=%-d ROB_HEAD_WAIT_FLUSH_LOST=%-d",
                u_dut.perf_rob_head_wait_alu,
                u_dut.perf_rob_head_wait_lsu,
                u_dut.perf_rob_head_wait_mul,
                u_dut.perf_rob_head_wait_flush_lost);
            $display("PERF_COMMIT_SHELL: COMMIT_SHELL_ALLOC=%-d COMMIT_SHELL_READY=%-d COMMIT_SHELL_RETIRE=%-d COMMIT_SHELL_HEAD_WAIT=%-d COMMIT_SHELL_FLUSH_SQUASH=%-d",
                u_dut.u_ydrasil_commit_trace.perf_commit_shell_alloc,
                u_dut.u_ydrasil_commit_trace.perf_commit_shell_ready,
                u_dut.u_ydrasil_commit_trace.perf_commit_shell_retire,
                u_dut.u_ydrasil_commit_trace.perf_commit_shell_head_wait,
                u_dut.u_ydrasil_commit_trace.perf_commit_shell_flush_squash);
            $display("PERF_DUAL_ISSUE: DI_PIPE0_FIRE=%-d DI_PIPE1_FIRE=%-d DI_PAIR_FIRE=%-d DI_PAIR_SIMPLE_ALU=%-d DI_PIPE1_KILLED_FLUSH=%-d DI_PIPE1_BLOCK_STALL_RECHECK=%-d DI_PIPE1_BLOCK_RESBUF_FULL=%-d DI_PIPE1_BLOCK_ALU_FIFO_FULL=%-d DI_PIPE1_BLOCK_PENDING_RECHECK=%-d DI_PIPE1_BLOCK_TIMING_GUARD=%-d",
                u_dut.u_ydrasil_id_stage.perf_di_pipe0_fire,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_fire,
                u_dut.u_ydrasil_id_stage.perf_di_pair_fire,
                u_dut.u_ydrasil_id_stage.perf_di_pair_simple_alu,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_killed_flush,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_block_stall_recheck,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_block_resbuf_full,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_block_alu_fifo_full,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_block_pending_recheck,
                u_dut.u_ydrasil_id_stage.perf_di_pipe1_block_timing_guard);
            $display("PERF_PIPE1_WB: P1_WB_ENQUEUE=%-d P1_WB_DEQUEUE=%-d P1_WB_DIRECT=%-d P1_WB_WAIT_CYCLES=%-d P1_WB_MAX_OCC=%-d P1_WB_ORDER_FIX=%-d",
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_enqueue,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_dequeue,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_direct,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_wait_cycles,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_max_occ,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_order_fix);
            $display("PERF_DUAL_GAIN: CYCLES_WITH_PAIR_FIRE=%-d EXTRA_INSTRET_PIPE1=%-d PIPE1_USEFUL_COMMIT=%-d PIPE1_SQUASHED=%-d",
                u_dut.u_ydrasil_id_stage.perf_dual_cycles_with_pair_fire,
                u_dut.u_ydrasil_id_stage.perf_dual_extra_instret_pipe1,
                u_dut.u_ydrasil_wb_stage.perf_p1_wb_dequeue,
                u_dut.u_ydrasil_id_stage.perf_dual_pipe1_squashed);
            $display("PERF_BRANCH: BRANCHES=%-d HITS=%-d PRED_TAKEN=%-d MISPRED=%-d ACC=%.2f",
                bp_branch_count, bp_hit_count, bp_taken_count, bp_mispredict_count, perf_bp_accuracy);
            $display("PERF_BP_ACC: ACC=%.2f", perf_bp_accuracy);
            $display("PERF_BP_DETAIL: TAKEN=%-d NOT_TAKEN=%-d DIR_MISPRED=%-d TARGET_MISPRED=%-d BTB_MISS_TAKEN=%-d CORRECT_TAKEN=%-d CORRECT_NOT_TAKEN=%-d",
                bp_actual_taken_count,
                bp_actual_not_taken_count,
                bp_dir_mispredict_count,
                bp_target_mispredict_count,
                bp_btb_miss_taken_count,
                bp_correct_taken_count,
                bp_correct_not_taken_count);
        end
    endtask

    // 添加一个任务来显示处理过的testcase名称
    task automatic display_testcase_name;
        integer i;
        reg [7:0] ch;
        reg printing;

        printing = 0;
        for (i = 300; i >= 1; i = i - 1) begin
            ch = testcase[i*8-:8];
            if (!printing && ch != " " && ch != 8'h00 && ch != 8'h20) begin
                printing = 1;
            end
            if (printing && (ch == 8'h00 || ch == 8'h0A)) begin
                printing = 0;
                break;
            end
            if (printing && ch >= 8'h20) begin
                $write("%c", ch);
            end
        end
    endtask



	initial begin
`ifdef VERILATOR_SV
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`elsif IVERILOG_VCD
		$dumpfile("ydrasil_core_tb.vcd");
		$dumpvars(0, ydrasil_core_tb);
`endif
	end

endmodule
