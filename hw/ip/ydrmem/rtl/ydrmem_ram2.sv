module ydrmem_ram2#(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter string INIT_FILE = "",
    parameter string READ_MODE = "READ_FIRST" // "READ_FIRST", "WRITE_FIRST", "NO_CHANGE"
)(
    input wire clk,
    input wire rst_n,
    input wire en_a,
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire [DATA_WIDTH-1:0] wdata_a,
    input wire we_a,
    input wire [3:0] we_mask_a,
    output wire [DATA_WIDTH-1:0] rdata_a,
    input wire en_b,
    input wire [ADDR_WIDTH-1:0] addr_b,
    input wire [DATA_WIDTH-1:0] wdata_b,
    input wire we_b,
    input wire [3:0] we_mask_b,
    output wire [DATA_WIDTH-1:0] rdata_b
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    wire [DATA_WIDTH-1:0] rdata_a_read_first;
    wire [DATA_WIDTH-1:0] rdata_b_read_first;
    wire [DATA_WIDTH-1:0] rdata_a_write_first;
    wire [DATA_WIDTH-1:0] rdata_b_write_first;
    wire [DATA_WIDTH-1:0] rdata_a_n;
    wire [DATA_WIDTH-1:0] rdata_b_n;

    wire [DATA_WIDTH-1:0] rdata_a_no_change;
    wire [DATA_WIDTH-1:0] rdata_b_no_change;
    wire                  write_a_fire;
    wire                  write_b_fire;

    /* verilator tracing_off */
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_r[0:DEPTH-1];
    /* verilator tracing_on */

    reg [DATA_WIDTH-1:0] rdata_a_ff;
    reg [DATA_WIDTH-1:0] rdata_b_ff;

    assign rdata_a = rdata_a_ff;
    assign rdata_b = rdata_b_ff;
    assign write_a_fire = en_a && we_a;
    assign write_b_fire = en_b && we_b;

    assign rdata_a_n = (READ_MODE == "READ_FIRST") ? rdata_a_read_first : (READ_MODE == "WRITE_FIRST") ? rdata_a_write_first : (READ_MODE == "NO_CHANGE") ? rdata_a_no_change : mem_r[addr_a];
    assign rdata_b_n = (READ_MODE == "READ_FIRST") ? rdata_b_read_first : (READ_MODE == "WRITE_FIRST") ? rdata_b_write_first : (READ_MODE == "NO_CHANGE") ? rdata_b_no_change : mem_r[addr_b];

    assign rdata_a_read_first = mem_r[addr_a];
    assign rdata_b_read_first = mem_r[addr_b];

    assign rdata_a_write_first = write_a_fire ? {
        we_mask_a[3] ? wdata_a[31:24] : mem_r[addr_a][31:24],
        we_mask_a[2] ? wdata_a[23:16] : mem_r[addr_a][23:16],
        we_mask_a[1] ? wdata_a[15:8]  : mem_r[addr_a][15:8],
        we_mask_a[0] ? wdata_a[7:0]   : mem_r[addr_a][7:0]
    } : mem_r[addr_a];
    assign rdata_b_write_first = write_b_fire ? {
        we_mask_b[3] ? wdata_b[31:24] : mem_r[addr_b][31:24],
        we_mask_b[2] ? wdata_b[23:16] : mem_r[addr_b][23:16],
        we_mask_b[1] ? wdata_b[15:8]  : mem_r[addr_b][15:8],
        we_mask_b[0] ? wdata_b[7:0]   : mem_r[addr_b][7:0]
    } : mem_r[addr_b];

    assign rdata_a_no_change = rdata_a_ff;
    assign rdata_b_no_change = rdata_b_ff;

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem_r);
        end
    end

    always @(posedge clk) begin
        if (write_a_fire) begin
            if (we_mask_a[0]) mem_r[addr_a][7:0] <= wdata_a[7:0];
            if (we_mask_a[1]) mem_r[addr_a][15:8] <= wdata_a[15:8];
            if (we_mask_a[2]) mem_r[addr_a][23:16] <= wdata_a[23:16];
            if (we_mask_a[3]) mem_r[addr_a][31:24] <= wdata_a[31:24];
        end
        if (write_b_fire) begin
            if (we_mask_b[0]) mem_r[addr_b][7:0] <= wdata_b[7:0];
            if (we_mask_b[1]) mem_r[addr_b][15:8] <= wdata_b[15:8];
            if (we_mask_b[2]) mem_r[addr_b][23:16] <= wdata_b[23:16];
            if (we_mask_b[3]) mem_r[addr_b][31:24] <= wdata_b[31:24];
        end
    end

    // Port A
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_a_ff <= 0;
        end else if (en_a) begin
            rdata_a_ff <= rdata_a_n;
        end
    end

    // Port B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_b_ff <= 0;
        end else if (en_b) begin
            rdata_b_ff <= rdata_b_n;
        end
    end
    
endmodule 
