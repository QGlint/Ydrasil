#include <verilated.h>
#include <cstdlib>
#include <cstdio>

#ifndef TB_NAME
#error "Please define TB_NAME (e.g. -D TB_NAME=gearbox_68_to_80_tb)"
#endif

// ---------------- Wave select ----------------
#define CONFIG_FST_WAVE_TRACE 0

#if CONFIG_FST_WAVE_TRACE
#include <verilated_fst_c.h>
VerilatedFstC *tfp = new VerilatedFstC;
#else
#include <verilated_vcd_c.h>
VerilatedVcdC *tfp = new VerilatedVcdC;
#endif

// ---------------- Macro utils ----------------
#define _STR(x) #x
#define STR(x) _STR(x)

#define _CAT(a,b) a##b
#define CAT(a,b) _CAT(a,b)

#define TB_CLASS_NAME CAT(V, TB_NAME)
#define TB_HEADER_FILE STR(TB_CLASS_NAME.h)

#include TB_HEADER_FILE

// ---------------- Time ----------------
vluint64_t max_cycles = 10000000;

#ifdef VERILATOR_CC
vluint64_t tick = 0;
#endif

// ------------------------------------------------
int main(int argc, char **argv) {

    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    TB_CLASS_NAME *tb = new TB_CLASS_NAME;

    tb->trace(tfp, 99);
#if CONFIG_FST_WAVE_TRACE
    tfp->open("tb_top.fst");
#else
    tfp->open("tb_top.vcd");
#endif

#ifdef VERILATOR_CC
    // ---------------- Reset phase ----------------
    tb->clk   = 0;
    tb->rst_n = 0;

    for (int i = 0; i < 20; i++) {
        tb->eval();
        tfp->dump(tick++);
        tb->eval();
        tfp->dump(tick++);
    }

    tb->rst_n = 1;

    // ---------------- Main simulation ----------------
    while (!Verilated::gotFinish() && !tb->tb_done && Verilated::time() < max_cycles) {
        tb->clk = !tb->clk;   
        tb->eval();
        tfp->dump(tick++);
        tfp->dump(tick++);
    }
#else
    // ---------------- 纯sv仿真 ----------------
    while (!Verilated::gotFinish() && Verilated::time() < max_cycles) {
        // 1. 评估一次电路
        tb->eval();
        // 2. 记录当前时间点波形
        tfp->dump(Verilated::time());
        // 3. 时间推进 1 tick
        Verilated::timeInc(1);
    }
    if (Verilated::time() >= max_cycles) {
        VL_PRINTF("Timeout: simulation stopped\n");
    }

#endif
    // ---------------- Finish ----------------
    tfp->close();
    delete tb;
    delete tfp;
    return 0;
}
