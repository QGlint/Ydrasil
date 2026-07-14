#include <verilated.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <iostream>
#if VM_COVERAGE
#include <verilated_cov.h>
#endif
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

// #define DOUBLE_TICK

vluint64_t MAX_TIME = 10000; // 默认


// ------------------------------------------------
int main(int argc, char **argv) {

    Verilated::commandArgs(argc, argv);


    TB_CLASS_NAME *tb = new TB_CLASS_NAME;
    // check if trace is enabled
    int trace_en = 0;
    vluint64_t trace_start = 0;
    vluint64_t trace_stop = ~vluint64_t{0};
    const char *coverage_file = "coverage.dat";
    for (int i = 0; i < argc; i++)
    {
        if (strcmp(argv[i], "+trace") == 0)
            trace_en = 1;
        if (strcmp(argv[i], "--trace") == 0)
            trace_en = 1;
        if (sscanf(argv[i], "+cpp_timeout=%lu", &MAX_TIME) == 1)
            printf("C++ timeout set to %lu\n", MAX_TIME);
        if (sscanf(argv[i], "+trace_start=%lu", &trace_start) == 1)
            printf("Trace start set to %lu\n", trace_start);
        if (sscanf(argv[i], "+trace_stop=%lu", &trace_stop) == 1)
            printf("Trace stop set to %lu\n", trace_stop);
        if (strncmp(argv[i], "+coverage_file=", 15) == 0)
            coverage_file = argv[i] + 15;
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
    tb->clk   = 1;
    tb->rst_n = 0;

    for (int i = 0; i < 20; i++) {
        tb->clk = !tb->clk;  
        tb->eval();

#ifdef VERILATOR_TRACE
        if (trace_en && Verilated::time() > trace_start &&
            Verilated::time() < trace_stop)
            tfp->dump(Verilated::time());
#endif     
        Verilated::timeInc(1);

#ifdef DOUBLE_TICK

#ifdef VERILATOR_TRACE
            if (trace_en && Verilated::time() > trace_start &&
                Verilated::time() < trace_stop)
                tfp->dump(Verilated::time());
#endif
        Verilated::timeInc(1);
#endif
    }

    tb->rst_n = 1;

    // ---------------- Main simulation ----------------
    while ((!Verilated::gotFinish() )&&(Verilated::time() <= MAX_TIME)) {
        tb->clk = !tb->clk;   
        tb->eval();
#ifdef VERILATOR_TRACE
            if (trace_en && Verilated::time() > trace_start &&
                Verilated::time() < trace_stop)
                tfp->dump(Verilated::time());
#endif
        Verilated::timeInc(1);

#ifdef DOUBLE_TICK
        tb->eval();

#ifdef VERILATOR_TRACE
            if (trace_en && Verilated::time() > trace_start &&
                Verilated::time() < trace_stop)
                tfp->dump(Verilated::time());
#endif
        Verilated::timeInc(1);
#endif
    }

    // ---------------- Finish ----------------

    tb->final();
    std::cout << "Simulation finished at time " << Verilated::time() << " ticks.\n";
#if VM_COVERAGE
    VerilatedCov::write(coverage_file);
    std::cout << "Coverage data written to " << coverage_file << "\n";
#endif
    #ifdef VERILATOR_TRACE
        tfp->close();
    delete tfp;
    #endif
    delete tb;
    return 0;
}
