#include "platform.h"
#include "xprintf.h"
#include "sim_ctrl.h"

void SystemBannerPrint(void)
{
#if defined(SDK_BANNER) && (SDK_BANNER == 1)
    printf("Alioth SDK Build Time: %s, %s\r\n", __DATE__, __TIME__);
    printf("CPU Frequency %lu Hz\r\n", SYSTEM_CLOCK);
#endif
}

void SystemInit(void)
{
#ifdef YDRASIL_SIM_CTRL
    sim_ctrl_init();
#elif defined(YDRASIL_CONTEST_FPGA)
    /* The contest UART is reserved for the digital-twin controller. */
#else
    // 初始化UART0，波特率115200
    uart_init((UART_TypeDef *)UART0_BASE, 115200);

    // 初始化xprintf重定向到UART
    xprintf_uart_init();
#endif

    // 打印基本信息
    SystemBannerPrint();
}

__STATIC_FORCEINLINE uint64_t get_timer_freq(void)
{
    return SOC_TIMER_FREQ;
}

uint32_t measure_cpu_freq(uint32_t n)
{
    uint32_t start_mcycle, delta_mcycle;
    uint32_t start_mtime, delta_mtime;
    uint64_t mtime_freq = get_timer_freq();

    // Don't start measuruing until we see an mtime tick
    uint32_t tmp = (uint32_t)CLINT_GetLoadValue();
    do {
        start_mtime = (uint32_t)CLINT_GetLoadValue();
        start_mcycle = __RV_CSR_READ(CSR_MCYCLE);
    } while (start_mtime == tmp);

    do {
        delta_mtime = (uint32_t)CLINT_GetLoadValue() - start_mtime;
        delta_mcycle = __RV_CSR_READ(CSR_MCYCLE) - start_mcycle;
    } while (delta_mtime < n);

    return (delta_mcycle / delta_mtime) * mtime_freq
           + ((delta_mcycle % delta_mtime) * mtime_freq) / delta_mtime;
}

uint32_t get_cpu_freq(void)
{
    uint32_t cpu_freq;

    // warm up
    measure_cpu_freq(1);
    // measure for real
    cpu_freq = measure_cpu_freq(100);

    return cpu_freq;
}

/**
 * \brief      delay a time in milliseconds
 * \details
 *             provide API for delay
 * \param[in]  count: count in milliseconds
 * \remarks
 */
void delay_1ms(uint32_t count)
{
    uint64_t start_cycle, delta_cycle;
    uint64_t delay_cycles = ((uint64_t)SYSTEM_CLOCK * count) / 1000;

    start_cycle = __RV_CSR_READ(CSR_MCYCLE);

    do {
        delta_cycle = __RV_CSR_READ(CSR_MCYCLE) - start_cycle;
    } while (delta_cycle < delay_cycles);
}
