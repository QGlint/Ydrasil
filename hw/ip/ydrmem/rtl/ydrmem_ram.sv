
// 通用RAM模块 - 参数化设计
module ydrmem_ram #(
    parameter ADDR_WIDTH = 16,  // 地址宽度参数
    parameter DATA_WIDTH = 32  // 数据宽度参数
) (
    input wire clk,
    input wire                  en_i,      // 使能信号
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

    wire [ADDR_WIDTH-1:0] word_addr;
    assign word_addr = addr_i;

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
        if (en_i) begin
            data_o <= mem_r[word_addr];
        end else begin
            data_o <= 0; // 不使能时输出0，或者保持之前的值
        end
    end

endmodule
