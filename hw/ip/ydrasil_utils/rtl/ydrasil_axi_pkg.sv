package ydrasil_axi_pkg;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

    typedef struct packed {
        logic                      awvalid;
        logic [AXI_ADDR_WIDTH-1:0] awaddr;
        logic [2:0]                awprot;
        logic                      wvalid;
        logic [AXI_DATA_WIDTH-1:0] wdata;
        logic [AXI_STRB_WIDTH-1:0] wstrb;
        logic                      bready;
        logic                      arvalid;
        logic [AXI_ADDR_WIDTH-1:0] araddr;
        logic [2:0]                arprot;
        logic                      rready;
    } ydrasil_axi_lite_m2s_pkt_t;

    typedef struct packed {
        logic                      awready;
        logic                      wready;
        logic                      bvalid;
        logic [1:0]                bresp;
        logic                      arready;
        logic                      rvalid;
        logic [AXI_DATA_WIDTH-1:0] rdata;
        logic [1:0]                rresp;
    } ydrasil_axi_lite_s2m_pkt_t;
endpackage
