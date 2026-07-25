package ydrasil_apb_pkg;
    localparam int APB_ADDR_WIDTH = 32;
    localparam int APB_DATA_WIDTH = 32;
    localparam int APB_STRB_WIDTH = APB_DATA_WIDTH / 8;

    typedef struct packed {
        logic                      psel;
        logic                      penable;
        logic                      pwrite;
        logic [APB_ADDR_WIDTH-1:0] paddr;
        logic [APB_DATA_WIDTH-1:0] pwdata;
        logic [APB_STRB_WIDTH-1:0] pstrb;
        logic [2:0]                pprot;
    } ydrasil_apb_req_pkt_t;

    typedef struct packed {
        logic                      pready;
        logic [APB_DATA_WIDTH-1:0] prdata;
        logic                      pslverr;
    } ydrasil_apb_rsp_pkt_t;
endpackage
