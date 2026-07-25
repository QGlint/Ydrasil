`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg   
);
    import ydrasil_pkg::*;

    // IROM
    logic [31:0] pc;
    // logic [11:0] inst_addr;
    logic [31:0] instruction;

    ydrasil_axi_lite_m2s_pkt_t axi_m2s;
    ydrasil_axi_lite_s2m_pkt_t axi_s2m;
    ydrasil_irq_pkt_t irq;

    // 16KB = 2^12 * 32bit
    // assign inst_addr = pc[13:2];

    ydrasil_core Core_cpu (
        .clk              (w_cpu_clk),
        .rst_n            (~w_clk_rst),

        // // Interface to IROM
        // .irom_addr          (pc),             
        // .irom_data          (instruction),   

        .axi_m2s_o          (axi_m2s),
        .axi_s2m_i          (axi_s2m),
        .irq_i              (irq)
    );

    // IROM Mem_IROM (
    //     .a          (inst_addr),
    //     .spo        (instruction)
    // );
    
    ydrasil_mmio_subsystem u_mmio_subsystem (
        .clk                (w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst_n              (~w_clk_rst),
        .axi_m2s_i          (axi_m2s),
        .axi_s2m_o          (axi_s2m),
        .external_irq_i     (1'b0),
        .irq_o              (irq),
        .virtual_sw_input   (virtual_sw),
        .virtual_key_input  (virtual_key),
        .virtual_seg_output (virtual_seg),
        .virtual_led_output (virtual_led)
    );

endmodule
