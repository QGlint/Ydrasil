

// CSR寄存器模块
module ydrasil_registers_csr 
import ydrasil_pkg::*;
(

    input wire clk,
    input wire rst_n,
    input wire [2:0] instret_inc_count_i,

    // form ex
    input wire                          ex_csr_wen_i,     // ex模块写寄存器标志
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    id_csr_raddr_i,  // ex模块读寄存器地址
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    ex_csr_waddr_i,  // ex模块写寄存器地址
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]   ex_csr_data_i,   // ex模块写寄存器数据

    input ydrasil_csr_write_pkt_t       trap_csr_write_i,
    input ydrasil_irq_pkt_t             irq_i,

	input wire                          fp_flags_valid_i,
	input wire [4:0]                    fp_flags_i,
	input wire                          fp_state_dirty_i,
	output wire [2:0]                   frm_o,
	output wire                         fp_enabled_o,

    output ydrasil_csr_trap_state_pkt_t trap_state_o,

    // to ex
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_ex_data_o  // ex模块读寄存器数据

);

    wire clint_csr_we_i = trap_csr_write_i.valid;
    wire [CSR_ADDR_WIDTH-1:0] clint_csr_raddr_i = '0;
    wire [CSR_ADDR_WIDTH-1:0] clint_csr_waddr_i = trap_csr_write_i.addr;
    wire [REGS_DATA_WIDTH-1:0] clint_csr_data_i = trap_csr_write_i.data;

`ifdef YDRASIL_ENABLE_FPU
    localparam logic [31:0] MISA_VALUE = 32'h4000_1122;
`else
    localparam logic [31:0] MISA_VALUE = 32'h4000_1102;
`endif

    reg  [ydrasil_pkg::DOUBLE_REGS_WIDTH-1:0] cycle;
    reg  [ydrasil_pkg::DOUBLE_REGS_WIDTH-1:0] instret;
    reg                         mcycle_low_write_pending;
    reg                         mcycle_low_write_carry;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mtvec;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mcause;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mepc;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mie;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mstatus;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mscratch;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mip;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mtval;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mcounteren;
    reg  [ydrasil_pkg::REGS_DATA_WIDTH-1:0] mcountinhibit;
    reg  [4:0] fflags;
    reg  [2:0] frm;
	wire [31:0] mstatus_read = {mstatus[14:13] == 2'b11, mstatus[30:0]};
	wire [31:0] mip_read = mip |
		({31'b0, irq_i.software} << 3) |
		({31'b0, irq_i.timer} << 7) |
		({31'b0, irq_i.external} << 11);

	assign frm_o = frm;
	assign fp_enabled_o = |mstatus[14:13];

    assign trap_state_o.mtvec = mtvec;
    assign trap_state_o.mepc = mepc;
    assign trap_state_o.mstatus = mstatus_read;
    assign trap_state_o.mie = mie;
    assign trap_state_o.mip = mip_read;

    reg ex_csr_addr_writeable;
    reg clint_csr_addr_writeable;
    reg [31:0] csr_ex_read_value;
    reg [31:0] csr_clint_read_value;

    wire [31:0] ex_csr_write_read_value =
        (ex_csr_waddr_i[11:0] == ydrasil_pkg::CSR_MCOUNTINHIBIT) ?
        {29'b0, ex_csr_data_i[2], 1'b0, ex_csr_data_i[0]} :
        ex_csr_data_i;
    wire [31:0] clint_csr_write_read_value =
        (clint_csr_waddr_i[11:0] == ydrasil_pkg::CSR_MCOUNTINHIBIT) ?
        {29'b0, clint_csr_data_i[2], 1'b0, clint_csr_data_i[0]} :
        clint_csr_data_i;

    always_comb begin
        ex_csr_addr_writeable = 1'b0;
        unique case (ex_csr_waddr_i[11:0])
            ydrasil_pkg::CSR_MTVEC,
            ydrasil_pkg::CSR_MCAUSE,
            ydrasil_pkg::CSR_MEPC,
            ydrasil_pkg::CSR_MIE,
            ydrasil_pkg::CSR_MSTATUS,
            ydrasil_pkg::CSR_MSCRATCH,
            ydrasil_pkg::CSR_MIP,
            ydrasil_pkg::CSR_MTVAL,
            ydrasil_pkg::CSR_MCOUNTEREN,
            ydrasil_pkg::CSR_MCOUNTINHIBIT,
            ydrasil_pkg::CSR_MCYCLE,
            ydrasil_pkg::CSR_MCYCLEH,
            ydrasil_pkg::CSR_MINSTRET,
            ydrasil_pkg::CSR_MINSTRETH:
                ex_csr_addr_writeable = 1'b1;
`ifdef YDRASIL_ENABLE_FPU
            ydrasil_pkg::CSR_FFLAGS,
            ydrasil_pkg::CSR_FRM,
            ydrasil_pkg::CSR_FCSR:
                ex_csr_addr_writeable = 1'b1;
`endif
            default:
                ex_csr_addr_writeable = 1'b0;
        endcase
    end

    always_comb begin
        clint_csr_addr_writeable = 1'b0;
        unique case (clint_csr_waddr_i[11:0])
            ydrasil_pkg::CSR_MTVEC,
            ydrasil_pkg::CSR_MCAUSE,
            ydrasil_pkg::CSR_MEPC,
            ydrasil_pkg::CSR_MIE,
            ydrasil_pkg::CSR_MSTATUS,
            ydrasil_pkg::CSR_MSCRATCH,
            ydrasil_pkg::CSR_MIP,
            ydrasil_pkg::CSR_MTVAL,
            ydrasil_pkg::CSR_MCOUNTEREN,
            ydrasil_pkg::CSR_MCOUNTINHIBIT,
            ydrasil_pkg::CSR_MCYCLE,
            ydrasil_pkg::CSR_MCYCLEH,
            ydrasil_pkg::CSR_MINSTRET,
            ydrasil_pkg::CSR_MINSTRETH:
                clint_csr_addr_writeable = 1'b1;
            default:
                clint_csr_addr_writeable = 1'b0;
        endcase
    end

    wire ex_csr_write_effective =
        ex_csr_wen_i && ex_csr_addr_writeable;
    wire clint_csr_write_effective =
        clint_csr_we_i && clint_csr_addr_writeable;
    wire csr_write_en = ex_csr_write_effective | clint_csr_write_effective;
    wire [11:0] csr_write_addr =
        ex_csr_write_effective ? ex_csr_waddr_i[11:0] : clint_csr_waddr_i[11:0];
    wire [31:0] csr_write_data =
        ex_csr_write_effective ? ex_csr_data_i : clint_csr_data_i;
    wire [31:0] csr_write_mcountinhibit_data =
        {29'b0, csr_write_data[2], 1'b0, csr_write_data[0]};

    wire mcycle_we =
        csr_write_en && (csr_write_addr == ydrasil_pkg::CSR_MCYCLE);
    wire mcycleh_we =
        csr_write_en && (csr_write_addr == ydrasil_pkg::CSR_MCYCLEH);
    wire minstret_we =
        csr_write_en && (csr_write_addr == ydrasil_pkg::CSR_MINSTRET);
    wire minstreth_we =
        csr_write_en && (csr_write_addr == ydrasil_pkg::CSR_MINSTRETH);
    wire mcountinhibit_we =
        csr_write_en && (csr_write_addr == ydrasil_pkg::CSR_MCOUNTINHIBIT);
    wire cycle_inhibited = mcountinhibit_we ?
        csr_write_mcountinhibit_data[0] : mcountinhibit[0];
    wire instret_inhibited = mcountinhibit_we ?
        csr_write_mcountinhibit_data[2] : mcountinhibit[2];

    wire ex_csr_forward =
        ex_csr_write_effective && (ex_csr_waddr_i[11:0] == id_csr_raddr_i[11:0]);
    wire clint_csr_forward =
        clint_csr_write_effective && (clint_csr_waddr_i[11:0] == clint_csr_raddr_i[11:0]);

    always_comb begin
        unique case (id_csr_raddr_i[11:0])
            ydrasil_pkg::CSR_CYCLE,
            ydrasil_pkg::CSR_TIME,
            ydrasil_pkg::CSR_MCYCLE:
                csr_ex_read_value = cycle[31:0];
            ydrasil_pkg::CSR_CYCLEH,
            ydrasil_pkg::CSR_TIMEH,
            ydrasil_pkg::CSR_MCYCLEH:
                csr_ex_read_value = cycle[63:32];
            ydrasil_pkg::CSR_INSTRET,
            ydrasil_pkg::CSR_MINSTRET:
                csr_ex_read_value = instret[31:0];
            ydrasil_pkg::CSR_INSTRETH,
            ydrasil_pkg::CSR_MINSTRETH:
                csr_ex_read_value = instret[63:32];
            ydrasil_pkg::CSR_MTVEC:         csr_ex_read_value = mtvec;
            ydrasil_pkg::CSR_MCAUSE:        csr_ex_read_value = mcause;
            ydrasil_pkg::CSR_MEPC:          csr_ex_read_value = mepc;
            ydrasil_pkg::CSR_MIE:           csr_ex_read_value = mie;
            ydrasil_pkg::CSR_MSTATUS:       csr_ex_read_value = mstatus_read;
            ydrasil_pkg::CSR_MSCRATCH:      csr_ex_read_value = mscratch;
            ydrasil_pkg::CSR_MIP:           csr_ex_read_value = mip_read;
            ydrasil_pkg::CSR_MTVAL:         csr_ex_read_value = mtval;
            ydrasil_pkg::CSR_MCOUNTEREN:    csr_ex_read_value = mcounteren;
            ydrasil_pkg::CSR_MCOUNTINHIBIT: csr_ex_read_value = mcountinhibit;
            ydrasil_pkg::CSR_MISA:          csr_ex_read_value = MISA_VALUE;
`ifdef YDRASIL_ENABLE_FPU
            ydrasil_pkg::CSR_FFLAGS:        csr_ex_read_value = {27'b0, fflags};
            ydrasil_pkg::CSR_FRM:           csr_ex_read_value = {29'b0, frm};
            ydrasil_pkg::CSR_FCSR:          csr_ex_read_value = {24'b0, frm, fflags};
`endif
            ydrasil_pkg::CSR_MARCHID:
                csr_ex_read_value = ydrasil_pkg::MARCHID_VALUE;
            ydrasil_pkg::CSR_MVENDORID,
            ydrasil_pkg::CSR_MIMPID,
            ydrasil_pkg::CSR_MHARTID:
                csr_ex_read_value = 32'b0;
            default:
                csr_ex_read_value = 32'b0;
        endcase
    end

    always_comb begin
        unique case (clint_csr_raddr_i[11:0])
            ydrasil_pkg::CSR_CYCLE,
            ydrasil_pkg::CSR_TIME,
            ydrasil_pkg::CSR_MCYCLE:
                csr_clint_read_value = cycle[31:0];
            ydrasil_pkg::CSR_CYCLEH,
            ydrasil_pkg::CSR_TIMEH,
            ydrasil_pkg::CSR_MCYCLEH:
                csr_clint_read_value = cycle[63:32];
            ydrasil_pkg::CSR_INSTRET,
            ydrasil_pkg::CSR_MINSTRET:
                csr_clint_read_value = instret[31:0];
            ydrasil_pkg::CSR_INSTRETH,
            ydrasil_pkg::CSR_MINSTRETH:
                csr_clint_read_value = instret[63:32];
            ydrasil_pkg::CSR_MTVEC:         csr_clint_read_value = mtvec;
            ydrasil_pkg::CSR_MCAUSE:        csr_clint_read_value = mcause;
            ydrasil_pkg::CSR_MEPC:          csr_clint_read_value = mepc;
            ydrasil_pkg::CSR_MIE:           csr_clint_read_value = mie;
            ydrasil_pkg::CSR_MSTATUS:       csr_clint_read_value = mstatus_read;
            ydrasil_pkg::CSR_MSCRATCH:      csr_clint_read_value = mscratch;
            ydrasil_pkg::CSR_MIP:           csr_clint_read_value = mip_read;
            ydrasil_pkg::CSR_MTVAL:         csr_clint_read_value = mtval;
            ydrasil_pkg::CSR_MCOUNTEREN:    csr_clint_read_value = mcounteren;
            ydrasil_pkg::CSR_MCOUNTINHIBIT: csr_clint_read_value = mcountinhibit;
            ydrasil_pkg::CSR_MISA:          csr_clint_read_value = MISA_VALUE;
`ifdef YDRASIL_ENABLE_FPU
            ydrasil_pkg::CSR_FFLAGS:        csr_clint_read_value = {27'b0, fflags};
            ydrasil_pkg::CSR_FRM:           csr_clint_read_value = {29'b0, frm};
            ydrasil_pkg::CSR_FCSR:          csr_clint_read_value = {24'b0, frm, fflags};
`endif
            ydrasil_pkg::CSR_MARCHID:
                csr_clint_read_value = ydrasil_pkg::MARCHID_VALUE;
            ydrasil_pkg::CSR_MVENDORID,
            ydrasil_pkg::CSR_MIMPID,
            ydrasil_pkg::CSR_MHARTID:
                csr_clint_read_value = 32'b0;
            default:
                csr_clint_read_value = 32'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle         <= {ydrasil_pkg::DOUBLE_REGS_WIDTH{1'b0}};
            instret       <= {ydrasil_pkg::DOUBLE_REGS_WIDTH{1'b0}};
            mcycle_low_write_pending <= 1'b0;
            mcycle_low_write_carry <= 1'b0;
            mtvec         <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mcause        <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mepc          <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mie           <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mstatus       <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mscratch      <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mip           <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mtval         <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mcounteren    <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            mcountinhibit <= {ydrasil_pkg::REGS_DATA_WIDTH{1'b0}};
            fflags        <= 5'b0;
            frm           <= 3'b0;
        end else begin
            if (mcycle_we) begin
                cycle[31:0] <= csr_write_data;
                mcycle_low_write_pending <= 1'b1;
                mcycle_low_write_carry <= 1'b0;
            end else if (mcycleh_we) begin
                cycle[63:32] <= csr_write_data +
                    (mcycle_low_write_pending && mcycle_low_write_carry);
                mcycle_low_write_pending <= 1'b0;
                mcycle_low_write_carry <= 1'b0;
            end else if (!cycle_inhibited) begin
                cycle <= cycle + 1'b1;
                if (mcycle_low_write_pending && (cycle[31:0] == 32'hffff_ffff))
                    mcycle_low_write_carry <= 1'b1;
            end

            if (minstret_we) begin
                instret[31:0] <= csr_write_data;
            end else if (minstreth_we) begin
                instret[63:32] <= csr_write_data;
            end else if ((instret_inc_count_i != 2'b0) && !instret_inhibited) begin
                instret <= instret + instret_inc_count_i;
            end

            if (csr_write_en) begin
                case (csr_write_addr)
                    ydrasil_pkg::CSR_MTVEC:         mtvec         <= csr_write_data;
                    ydrasil_pkg::CSR_MCAUSE:        mcause        <= csr_write_data;
                    ydrasil_pkg::CSR_MEPC:          mepc          <= csr_write_data;
                    ydrasil_pkg::CSR_MIE:           mie           <= csr_write_data;
                    ydrasil_pkg::CSR_MSTATUS:       mstatus       <= csr_write_data;
                    ydrasil_pkg::CSR_MSCRATCH:      mscratch      <= csr_write_data;
                    ydrasil_pkg::CSR_MIP:           mip           <= csr_write_data;
                    ydrasil_pkg::CSR_MTVAL:         mtval         <= csr_write_data;
                    ydrasil_pkg::CSR_MCOUNTEREN:    mcounteren    <= csr_write_data;
                    ydrasil_pkg::CSR_MCOUNTINHIBIT: mcountinhibit <= csr_write_mcountinhibit_data;
`ifdef YDRASIL_ENABLE_FPU
                    ydrasil_pkg::CSR_FFLAGS: begin
                        fflags <= csr_write_data[4:0];
                        if (mstatus[14:13] != 2'b00) mstatus[14:13] <= 2'b11;
                    end
                    ydrasil_pkg::CSR_FRM: begin
                        frm <= csr_write_data[2:0];
                        if (mstatus[14:13] != 2'b00) mstatus[14:13] <= 2'b11;
                    end
                    ydrasil_pkg::CSR_FCSR: begin
                        frm <= csr_write_data[7:5];
                        fflags <= csr_write_data[4:0];
                        if (mstatus[14:13] != 2'b00) mstatus[14:13] <= 2'b11;
                    end
`endif
                    default: begin
                    end
                endcase
            end
`ifdef YDRASIL_ENABLE_FPU
            if (fp_flags_valid_i)
                fflags <= fflags | fp_flags_i;
            if (fp_state_dirty_i && (mstatus[14:13] != 2'b00))
                mstatus[14:13] <= 2'b11;
`endif
        end
    end

    // ex模块读CSR寄存器
    assign csr_ex_data_o = ex_csr_forward ?
        ex_csr_write_read_value :
        csr_ex_read_value;

endmodule
