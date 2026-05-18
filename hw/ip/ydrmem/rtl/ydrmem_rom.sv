module ydrmem_rom #(
    parameter ADDR_WIDTH = 16,  // 地址宽度参数
    parameter DATA_WIDTH = 32  // 数据宽度参数
) (
    input wire [ADDR_WIDTH-1:0] addr_i,     // addr
    output wire [DATA_WIDTH-1:0] data_o     // read data

);

    // 字节地址到字地址转换的偏移量（每个字4字节，需要右移2位）
    // localparam ADDR_OFFSET = 2;

    // 自动计算深度 = 2^(ADDR_WIDTH - ADDR_OFFSET)，因为是按字寻址
    localparam DEPTH = (1 << (ADDR_WIDTH));

    // 使用计算出的深度定义存储器
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_r[0:DEPTH-1];


    wire [ADDR_WIDTH-1:0] word_addr ;
    assign word_addr = addr_i;

    assign data_o = mem_r[word_addr];


endmodule
