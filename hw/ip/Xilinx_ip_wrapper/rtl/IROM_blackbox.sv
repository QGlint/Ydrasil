// OOC synthesis black box for the block-memory IP generated in the FPGA
// project.  The real IROM IP is supplied by Vivado in the full project; the
// pin-free milestone run only needs its interface to elaborate the core.
(* black_box *)
module IROM #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  wire                  clka,
    input  wire                  ena,
    input  wire [ADDR_WIDTH-1:0] addra,
    output wire [DATA_WIDTH-1:0] douta
);
endmodule
