

// CSR寄存器模块
module ydrasil_registers_csr 
import ydrasil_pkg::*;
(

    input wire clk,
    input wire rst_n,
	    input wire [1:0] instret_inc_i,

    // form ex
    input wire                          ex_csr_wen_i,     // ex模块写寄存器标志
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    id_csr_raddr_i,  // ex模块读寄存器地址
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    ex_csr_waddr_i,  // ex模块写寄存器地址
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]   ex_csr_data_i,   // ex模块写寄存器数据

    // from clint
    input wire                          clint_csr_we_i,     // clint模块写寄存器标志
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    clint_csr_raddr_i,  // clint模块读寄存器地址
    input wire [ydrasil_pkg::CSR_ADDR_WIDTH-1:0]    clint_csr_waddr_i,  // clint模块写寄存器地址
    input wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0]   clint_csr_data_i,   // clint模块写寄存器数据

    output wire global_int_en_o,  // 全局中断使能标志

    // to clint
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_clint_data_o,      // clint模块读寄存器数据
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_clint_mtvec,   // mtvec
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_clint_mepc,    // mepc
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_clint_mstatus, // mstatus

    // to ex
    output wire [ydrasil_pkg::REGS_DATA_WIDTH-1:0] csr_ex_data_o  // ex模块读寄存器数据

);

    localparam logic [31:0] MISA_RV32_IM = 32'h4000_1100;

    reg  [ydrasil_pkg::DOUBLE_REGS_WIDTH-1:0] cycle;
    reg  [ydrasil_pkg::DOUBLE_REGS_WIDTH-1:0] instret;
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

    assign global_int_en_o   = (mstatus[3] == 1'b1) ? 1'b1 : 1'b0;


    assign csr_clint_mtvec   = mtvec;
    assign csr_clint_mepc    = mepc;
    assign csr_clint_mstatus = mstatus;

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
            ydrasil_pkg::CSR_MSTATUS:       csr_ex_read_value = mstatus;
            ydrasil_pkg::CSR_MSCRATCH:      csr_ex_read_value = mscratch;
            ydrasil_pkg::CSR_MIP:           csr_ex_read_value = mip;
            ydrasil_pkg::CSR_MTVAL:         csr_ex_read_value = mtval;
            ydrasil_pkg::CSR_MCOUNTEREN:    csr_ex_read_value = mcounteren;
            ydrasil_pkg::CSR_MCOUNTINHIBIT: csr_ex_read_value = mcountinhibit;
            ydrasil_pkg::CSR_MISA:          csr_ex_read_value = MISA_RV32_IM;
            ydrasil_pkg::CSR_MVENDORID,
            ydrasil_pkg::CSR_MARCHID,
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
            ydrasil_pkg::CSR_MSTATUS:       csr_clint_read_value = mstatus;
            ydrasil_pkg::CSR_MSCRATCH:      csr_clint_read_value = mscratch;
            ydrasil_pkg::CSR_MIP:           csr_clint_read_value = mip;
            ydrasil_pkg::CSR_MTVAL:         csr_clint_read_value = mtval;
            ydrasil_pkg::CSR_MCOUNTEREN:    csr_clint_read_value = mcounteren;
            ydrasil_pkg::CSR_MCOUNTINHIBIT: csr_clint_read_value = mcountinhibit;
            ydrasil_pkg::CSR_MISA:          csr_clint_read_value = MISA_RV32_IM;
            ydrasil_pkg::CSR_MVENDORID,
            ydrasil_pkg::CSR_MARCHID,
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
        end else begin
            if (mcycle_we) begin
                cycle[31:0] <= csr_write_data;
            end else if (mcycleh_we) begin
                cycle[63:32] <= csr_write_data;
            end else if (!mcountinhibit[0]) begin
                cycle <= cycle + 1'b1;
            end

            if (minstret_we) begin
                instret[31:0] <= csr_write_data;
            end else if (minstreth_we) begin
                instret[63:32] <= csr_write_data;
	            end else if ((instret_inc_i != 2'b00) && !mcountinhibit[2]) begin
	                instret <= instret + {{(ydrasil_pkg::DOUBLE_REGS_WIDTH-2){1'b0}}, instret_inc_i};
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
                    default: begin
                    end
                endcase
            end
        end
    end

    // ex模块读CSR寄存器
    assign csr_ex_data_o = ex_csr_forward ?
        ex_csr_write_read_value :
        csr_ex_read_value;

    // clint模块读CSR寄存器
    assign csr_clint_data_o = clint_csr_forward ?
        clint_csr_write_read_value :
        csr_clint_read_value;

endmodule
