    module ydrmem_ram2#(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter string READ_MODE = "READ_FIRST" // "READ_FIRST", "WRITE_FIRST", "NO_CHANGE"
)(
    input wire clk,
    input wire rst_n,
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire [DATA_WIDTH-1:0] wdata_a,
    input wire we_a,
    output wire [DATA_WIDTH-1:0] rdata_a,
    input wire [ADDR_WIDTH-1:0] addr_b,
    input wire [DATA_WIDTH-1:0] wdata_b,
    input wire we_b,
    output wire [DATA_WIDTH-1:0] rdata_b
);

    wire [DATA_WIDTH-1:0] rdata_a_read_first;
    wire [DATA_WIDTH-1:0] rdata_b_read_first;
    wire [DATA_WIDTH-1:0] rdata_a_write_first;
    wire [DATA_WIDTH-1:0] rdata_b_write_first;
    wire [DATA_WIDTH-1:0] rdata_a_n;
    wire [DATA_WIDTH-1:0] rdata_b_n;

    wire [DATA_WIDTH-1:0] rdata_a_no_change;
    wire [DATA_WIDTH-1:0] rdata_b_no_change;

    reg [DATA_WIDTH-1:0] mem_r [(2**ADDR_WIDTH)-1:0];

    reg [DATA_WIDTH-1:0] rdata_a_ff;
    reg [DATA_WIDTH-1:0] rdata_b_ff;

    assign rdata_a = rdata_a_ff;
    assign rdata_b = rdata_b_ff;

    assign rdata_a_n = (READ_MODE == "READ_FIRST") ? rdata_a_read_first : (READ_MODE == "WRITE_FIRST") ? rdata_a_write_first : (READ_MODE == "NO_CHANGE") ? rdata_a_no_change : mem_r[addr_a];
    assign rdata_b_n = (READ_MODE == "READ_FIRST") ? rdata_b_read_first : (READ_MODE == "WRITE_FIRST") ? rdata_b_write_first : (READ_MODE == "NO_CHANGE") ? rdata_b_no_change : mem_r[addr_b];

    assign rdata_a_read_first = mem_r[addr_a];
    assign rdata_b_read_first = mem_r[addr_b];

    assign rdata_a_write_first = we_a ? wdata_a : mem_r[addr_a];
    assign rdata_b_write_first = we_b ? wdata_b : mem_r[addr_b];

    assign rdata_a_no_change = rdata_a_ff;
    assign rdata_b_no_change = rdata_b_ff;

    always @(posedge clk) begin
        if (we_a) begin
            mem_r[addr_a] <= wdata_a;
        end
        else if (we_b) begin
            mem_r[addr_b] <= wdata_b;
        end
    end

    // Port A
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_a_ff <= 0;
        end else begin
            rdata_a_ff <= rdata_a_n;
        end
    end

    // Port B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_b_ff <= 0;
        end else begin
            rdata_b_ff <= rdata_b_n;
        end
    end
    
endmodule 
