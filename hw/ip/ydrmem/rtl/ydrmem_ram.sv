
// 通用RAM模块 - 参数化设计
module ydrmem_ram #(
    parameter ADDR_WIDTH = 16,  // 地址宽度参数
    parameter DATA_WIDTH = 32,  // 数据宽度参数
    parameter INIT_MEM = 1,  // 是否初始化内存，1表示初始化，0表示不初始化
    parameter INIT_FILE = "/media/5/Projects/RISC-V/tinyriscv/tools/prog.mem"  // 初始化文件路径
) (
    input wire clk,
    input wire rst_n,

    input wire                  we_i,       // write enable
    input wire [           3:0] we_mask_i,  // 字节写入掩码 (byte write enable)
    input wire [ADDR_WIDTH-1:0] addr_i,     // addr
    input wire [DATA_WIDTH-1:0] data_i,     // write data

    output reg [DATA_WIDTH-1:0] data_o  // read data
);

    // 字节地址到字地址转换的偏移量（每个字4字节，需要右移2位）
    // localparam ADDR_OFFSET = 2;

    // 自动计算深度 = 2^(ADDR_WIDTH - ADDR_OFFSET)，因为是按字寻址
    localparam DEPTH = (1 << (ADDR_WIDTH));

    // 使用计算出的深度定义存储器
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_r[0:DEPTH-1];

    task automatic load_mem_file;
        string candidates [0:4];
        int fd;
        int idx;
        begin
            candidates[0] = INIT_FILE;
            candidates[1] = {"../", INIT_FILE};
            candidates[2] = {"../../", INIT_FILE};
            candidates[3] = {"../../../", INIT_FILE};
            candidates[4] = {"../../../../", INIT_FILE};

            for (idx = 0; idx < 5; idx = idx + 1) begin
                fd = $fopen(candidates[idx], "r");
                if (fd != 0) begin
                    $fclose(fd);
                    $display("[ydrmem_ram] load mem from: %s", candidates[idx]);
                    $readmemh(candidates[idx], mem_r);
                    return;
                end
            end

            $warning("$readmem file not found: %s", INIT_FILE);
        end
    endtask

    initial begin
        if (INIT_MEM) begin
            load_mem_file();
        end
    end

    wire [ADDR_WIDT-1:0] word_addr;
    assign word_addr = addr_i[ADDR_WIDTH-1:0];

    // 写入逻辑
    always @(posedge clk) begin
        if (we_i) begin
            // 根据掩码对每个字节单独处理
            if (we_mask_i[0]) mem_r[word_addr][7:0] <= data_i[7:0];
            if (we_mask_i[1]) mem_r[word_addr][15:8] <= data_i[15:8];
            if (we_mask_i[2]) mem_r[word_addr][23:16] <= data_i[23:16];
            if (we_mask_i[3]) mem_r[word_addr][31:24] <= data_i[31:24];
        end
    end

    // 同步读取逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            data_o <= {DATA_WIDTH{1'b0}};
        end else begin
            data_o <= mem_r[word_addr];
        end
    end

endmodule
