#include <verilated.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <iostream>
#ifndef TB_NAME
#error "Please define TB_NAME (e.g. -D TB_NAME=gearbox_68_to_80_tb)"
#endif

// ---------------- Wave select ----------------
#define CONFIG_FST_WAVE_TRACE 0
#ifdef VERILATOR_TRACE
#if CONFIG_FST_WAVE_TRACE
#include <verilated_fst_c.h>
VerilatedFstC *tfp = new VerilatedFstC;
#else
#include <verilated_vcd_c.h>
VerilatedVcdC *tfp = new VerilatedVcdC;
#endif
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
// vluint64_t max_cycles = 10000000;

#ifdef VERILATOR_CC
vluint64_t tick = 0;
#endif

// ------------------------------------------------
int main(int argc, char **argv) {

    Verilated::commandArgs(argc, argv);


    TB_CLASS_NAME *tb = new TB_CLASS_NAME;
    // check if trace is enabled
    int trace_en = 0;
    for (int i = 0; i < argc; i++)
    {
        if (strcmp(argv[i], "+trace") == 0)
            trace_en = 1;
        if (strcmp(argv[i], "--trace") == 0)
            trace_en = 1;
    }

    if (trace_en)
    {
        std::cout << "Trace is enabled.\n";
    }
    else
    {
        std::cout << "Trace is disabled.\n";
    }

#ifdef VERILATOR_TRACE
        Verilated::traceEverOn(true);
        tb->trace(tfp, 99);
#if CONFIG_FST_WAVE_TRACE
        tfp->open("tb_top.fst");
#else
        tfp->open("tb_top.vcd");
#endif
#endif

    // ---------------- Reset phase ----------------
    tb->clk   = 0;
    tb->rst_n = 0;

    for (int i = 0; i < 20; i++) {
        tb->clk = !tb->clk;  
        tb->eval();

#ifdef VERILATOR_TRACE
            tfp->dump(tick);
#endif
    tick++;        
    Verilated::timeInc(1);
        tb->eval();

#ifdef VERILATOR_TRACE
            tfp->dump(tick);
#endif
    tick++;        
    Verilated::timeInc(1);
    }

    tb->rst_n = 1;

    // ---------------- Main simulation ----------------
    while (!Verilated::gotFinish() ) {
        tb->clk = !tb->clk;   
        tb->eval();
#ifdef VERILATOR_TRACE
            tfp->dump(tick);
#endif
        Verilated::timeInc(1);
        tb->eval();
        tick++; 
#ifdef VERILATOR_TRACE
            tfp->dump(tick);
#endif
        tick++;
        Verilated::timeInc(1);

    }

    // ---------------- Finish ----------------


    std::cout << "Simulation finished at time " << Verilated::time() << " ticks.\n";
    #ifdef VERILATOR_TRACE
        tfp->close();
    delete tfp;
    #endif
    delete tb;
    return 0;
}
