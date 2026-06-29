#ifndef SYS_DEFS_H
#define SYS_DEFS_H

#ifdef __cplusplus
extern "C"
{
#endif

#ifdef __cplusplus
#include <cstdint>
#else
#include <stdint.h>
#include <stddef.h>
#endif

#include "xprintf.h"
#include "gcc_defs.h"

#ifndef SYSTEM_CLOCK
#define SYSTEM_CLOCK (242000000UL)
#endif

#ifndef SYSTEM_CLOCK_MHZ
#define SYSTEM_CLOCK_MHZ (242UL)
#endif

#define CPU_FREQ_HZ (SYSTEM_CLOCK)
#define CPU_FREQ_MHZ (SYSTEM_CLOCK_MHZ)

#define ALIOTH_PERIPH_BASE (0x84000000UL) /*!< Alioth APB Peripherals Base Address */
#define ALIOTH_CLINT_BASE (0x02000000UL)  /*!< Alioth CLINT Base Address */
#define ALIOTH_PLIC_BASE (0x0C000000UL)  /*!< Alioth PLIC Base Address */

/* Peripheral memory map */
#define PWM_BASE (ALIOTH_PERIPH_BASE + 0x00000)   /*!< (Timer) Base Address */
#define SPI0_BASE (ALIOTH_PERIPH_BASE + 0x01000)  /*!< (SPI0) Base Address */
#define I2C0_BASE (ALIOTH_PERIPH_BASE + 0x02000)  /*!< (I2C0) Base Address */
#define I2C1_BASE (ALIOTH_PERIPH_BASE + 0x03000)  /*!< (I2C1) Base Address */
#define UART0_BASE (ALIOTH_PERIPH_BASE + 0x04000) /*!< (UART0) Base Address */
#define UART1_BASE (ALIOTH_PERIPH_BASE + 0x05000) /*!< (UART1) Base Address */
#define GPIO0_BASE (ALIOTH_PERIPH_BASE + 0x06000) /*!< (GPIO0) Base Address */
#define GPIO1_BASE (ALIOTH_PERIPH_BASE + 0x07000) /*!< (GPIO1) Base Address */

    /**
     * @brief GPIO
     */
    typedef struct
    { /*!< GPIO Structure */
        __IOM uint32_t PADDIR;
        __IOM uint32_t PADIN;
        __IOM uint32_t PADOUT;
        __IOM uint32_t INTEN;
        __IOM uint32_t INTTYPE0;
        __IOM uint32_t INTTYPE1;
        __IOM uint32_t INTSTATUS;
        __IOM uint32_t IOFCFG;
    } GPIO_TypeDef;

    /**
     * @brief UART
     */
    typedef struct
    {
        union
        {
            __IOM uint32_t RBR;
            __IOM uint32_t DLL;
            __IOM uint32_t THR;
        };
        union
        {
            __IOM uint32_t DLM;
            __IOM uint32_t IER;
        };
        union
        {
            __IOM uint32_t IIR;
            __IOM uint32_t FCR;
        };
        __IOM uint32_t LCR;
        __IOM uint32_t MCR;
        __IOM uint32_t LSR;
        __IOM uint32_t MSR;
        __IOM uint32_t SCR;
    } UART_TypeDef;

    /**
     * @brief QSPI
     */
    typedef struct
    {
        __IOM uint32_t SCKDIV;
        __IOM uint32_t SCKMODE;
        __IOM uint32_t RESERVED0[2];
        __IOM uint32_t CSID;
        __IOM uint32_t CSDEF;
        __IOM uint32_t CSMODE;
        __IOM uint32_t RESERVED1[3];
        __IOM uint32_t DELAY0;
        __IOM uint32_t DELAY1;
        __IOM uint32_t RESERVED2[4];
        __IOM uint32_t FMT;
        __IOM uint32_t RESERVED3;
        __IOM uint32_t TXDATA;
        __IOM uint32_t RXDATA;
        __IOM uint32_t TXMARK;
        __IOM uint32_t RXMARK;
        __IOM uint32_t RESERVED4[2];
        __IOM uint32_t FCTRL;
        __IOM uint32_t FFMT;
        __IOM uint32_t RESERVED5[2];
        __IOM uint32_t IE;
        __IOM uint32_t IP;
    } QSPI_TypeDef;

    /**
     * @brief SPI
     */
    typedef struct
    {
        __IOM uint32_t STATUS;
        __IOM uint32_t CLKDIV;
        __IOM uint32_t SPICMD;
        __IOM uint32_t SPIADR;
        __IOM uint32_t SPILEN;
        __IOM uint32_t SPIDUM;
        __IOM uint32_t TXFIFO;
        __IOM uint32_t Pad;
        __IOM uint32_t RXFIFO;
        __IOM uint32_t INTCFG;
        __IOM uint32_t INTSTA;
    } SPI_TypeDef;

    /**
     * @brief I2C
     */
    typedef struct
    {
        __IOM uint32_t PRE;
        __IOM uint32_t CTR;
        __IOM uint32_t RX;
        __IOM uint32_t STATUS;
        __IOM uint32_t TX;
        __IOM uint32_t CMD;
    } I2C_TypeDef;

    /**
     * @brief PWM
     */
    typedef enum
    {
        PWM_TIMER0 = 0,
        PWM_TIMER1 = 1,
        PWM_TIMER2 = 2,
        PWM_TIMER3 = 3,
    } PwmTimerNum;

    typedef enum
    {
        PWM_TIMER_TH_CHANNEL0 = 0,
        PWM_TIMER_TH_CHANNEL1 = 1,
        PWM_TIMER_TH_CHANNEL2 = 2,
        PWM_TIMER_TH_CHANNEL3 = 3,
    } PwmTimerThChannel;

    enum
    {
        pwm_timer_event0 = 0,
        pwm_timer_event1,
        pwm_timer_event2,
        pwm_timer_event3,
    };

    typedef enum
    {
        PWM_TIMER_CMD_START = 0x01, /* Start counting */
        PWM_TIMER_CMD_STOP = 0x02,  /* Stop counting */
        PWM_TIMER_CMD_UPD = 0x04,   /* Update timer params */
        PWM_TIMER_CMD_RST = 0x08,   /* Reset counter value */
    } PwmCounterCmd;

    typedef struct
    {
        unsigned int SelectInputSource : 8; /* Select counting condition */
        unsigned int InputEnableIn : 3;     /* Define enable rules:
                                              000, always count (use clock)
                                              001 count when external input is 0
                                              010 count when external input is 1
                                              011 count on rising edge of external
                                              100 count on falling edge of external
                                              101 count on falling and on rising edge of external
                                              */
        unsigned int FllOrRTC : 1;          /* Clock input of counter is Fll or RTC */
        unsigned int IncThenDec : 1;        /* When counter reaches threshold count down if IncThenDec else return to 0 and ocunt up again */
        unsigned int Pad : 3;
        unsigned int PreScaler : 8; /* */
        unsigned int Pad2 : 8;
    } PwmCounterConfig;

    typedef struct
    {
        unsigned int chThreshold : 16; /* Threshold value for the channel of a counter */
        unsigned int chAction : 3;
        /* When counter reaches threshold:
            000: Set
            001: Toggle then next is Clear
            010: Set then Clear
            011: Toggle
            100: Clear
            101: Toggle then next is Set
            110: Clear then Set
        */
        unsigned int Pad : 13;
    } PwmChannelThConfig;

    typedef struct
    {
        unsigned int evt0_sel : 4;
        unsigned int evt1_sel : 4;
        unsigned int evt2_sel : 4;
        unsigned int evt3_sel : 4;
        unsigned int evt_en : 4;
        unsigned int pad : 12;
    } PwmTimerEvt;

    typedef union
    {
        PwmCounterConfig timerConf;
        unsigned int timerTh; /* Threshold value for the counter */
        PwmChannelThConfig ch_ThConfig;
        PwmTimerEvt timerEvt;
        unsigned int Raw;
    } pwm_timer;

// 全局重定向printf到xprintf
#define printf xprintf

#ifndef __RISCV_XLEN
#define __RISCV_XLEN 32
#endif /* __RISCV_XLEN */

#define SOC_TIMER_FREQ SYSTEM_CLOCK

#ifdef __cplusplus
}
#endif
#endif // SYS_DEFS_H