#ifndef CLINT_H
#define CLINT_H

#ifdef __cplusplus
extern "C"
{
#endif

#include "platform.h"

    typedef struct
    {
        __IOM uint32_t MSIP;              /*!< Offset: 0x000 (R/W)  System Timer SW interrupt Register */
        __IOM uint32_t RESERVED0[0xFFF];  /*!< Offset: 0x008 - 0x3FFC Reserved */
        __IOM uint64_t MTIMECMP;          /*!< Offset: 0x4000 (R/W)  System Timer compare Value 64bits Register */
        __IOM uint32_t RESERVED1[0x1FFC]; /*!< Offset: 0x4008 - 0xBFF4 Reserved */
        __IOM uint64_t MTIME;             /*!< Offset: 0xBFF8 (R/W)  System Timer load Value 64bits Register */
    } CLINT_Type;

// Timer control and status register definitions
#define CLINT_MSIP_MSIP_POS 0U                           // Systick timer MSIP: MSIP bit position
#define CLINT_MSIP_MSIP_MSK (1UL << CLINT_MSIP_MSIP_POS) // Systick timer MSIP: MSIP mask

#define CLINT_MTIMER_MSK (0xFFFFFFFFFFFFFFFFULL)    // Systick timer MTIMER value mask
#define CLINT_MTIMERCMP_MSK (0xFFFFFFFFFFFFFFFFULL) // Systick timer MTIMERCMP value mask
#define CLINT_MSIP_MSK (0xFFFFFFFFUL)               // Systick timer MSIP value mask

// System timer memory mapping of device
#define CLINT ((CLINT_Type *)ALIOTH_CLINT_BASE) // Systick configuration struct

    __STATIC_FORCEINLINE void CLINT_SetLoadValue(uint64_t value)
    {
        CLINT->MTIME = value;
    }

    /**
     * \brief  Get system timer load value
     * \details
     * This function get the system timer current value in MTIMER register.
     * \return  current value(64bit) of system timer MTIMER register.
     * \remarks
     * - Load value is 64bits wide.
     * - \ref CLINT_SetLoadValue
     */
    __STATIC_FORCEINLINE uint64_t CLINT_GetLoadValue(void)
    {
        return CLINT->MTIME;
    }

    /**
     * \brief  Set system timer compare value
     * \details
     * This function set the system Timer compare value in MTIMERCMP register.
     * \param [in]  value   compare value to set system timer MTIMERCMP register.
     * \remarks
     * - Compare value is 64bits wide.
     * - If compare value is larger than current value timer interrupt generate.
     * - Modify the load value or compare value less to clear the interrupt.
     * - \ref CLINT_GetCompareValue
     */
    __STATIC_FORCEINLINE void CLINT_SetCompareValue(uint64_t value)
    {
        CLINT->MTIMECMP = value;
    }

    /**
     * \brief  Get system timer compare value
     * \details
     * This function get the system timer compare value in MTIMERCMP register.
     * \return  compare value of system timer MTIMERCMP register.
     * \remarks
     * - Compare value is 64bits wide.
     * - \ref CLINT_SetCompareValue
     */
    __STATIC_FORCEINLINE uint64_t CLINT_GetCompareValue(void)
    {
        return CLINT->MTIMECMP;
    }

    /**
     * \brief  Trigger or set software interrupt via system timer
     * \details
     * This function set the system timer MSIP bit in MSIP register.
     * \remarks
     * - Set system timer MSIP bit and generate a SW interrupt.
     * - \ref CLINT_ClearSWIRQ
     * - \ref CLINT_GetMsipValue
     */
    __STATIC_FORCEINLINE void CLINT_SetSWIRQ(void)
    {
        CLINT->MSIP |= CLINT_MSIP_MSIP_MSK;
    }

    /**
     * \brief  Clear system timer software interrupt pending request
     * \details
     * This function clear the system timer MSIP bit in MSIP register.
     * \remarks
     * - Clear system timer MSIP bit in MSIP register to clear the software interrupt pending.
     * - \ref CLINT_SetSWIRQ
     * - \ref CLINT_GetMsipValue
     */
    __STATIC_FORCEINLINE void CLINT_ClearSWIRQ(void)
    {
        CLINT->MSIP &= ~CLINT_MSIP_MSIP_MSK;
    }

    /**
     * \brief  Get system timer MSIP register value
     * \details
     * This function get the system timer MSIP register value.
     * \return    Value of Timer MSIP register.
     * \remarks
     * - Bit0 is SW interrupt flag.
     *   Bit0 is 1 then SW interrupt set. Bit0 is 0 then SW interrupt clear.
     * - \ref CLINT_SetSWIRQ
     * - \ref CLINT_ClearSWIRQ
     */
    __STATIC_FORCEINLINE uint32_t CLINT_GetMsipValue(void)
    {
        return (uint32_t)(CLINT->MSIP & CLINT_MSIP_MSK);
    }

    /**
     * \brief  Set system timer MSIP register value
     * \details
     * This function set the system timer MSIP register value.
     * \param [in]  msip   value to set MSIP register
     */
    __STATIC_FORCEINLINE void CLINT_SetMsipValue(uint32_t msip)
    {
        CLINT->MSIP = (msip & CLINT_MSIP_MSK);
    }

    /**
     * \brief   System Tick Configuration
     * \details Initializes the System Timer and its non-vector interrupt, and starts the System Tick Timer.
     *
     *  In our default implementation, the timer counter will be set to zero, and it will start a timer compare non-vector interrupt
     *  when it matchs the ticks user set, during the timer interrupt user should reload the system tick using \ref SysTick_Reload function
     *  or similar function written by user, so it can produce period timer interrupt.
     * \param [in]  ticks  Number of ticks between two interrupts.
     * \return          0  Function succeeded.
     * \return          1  Function failed.
     * \sa
     * - \ref CLINT_SetCompareValue; CLINT_SetLoadValue
     */
    __STATIC_INLINE uint32_t SysTick_Config(uint64_t ticks)
    {
        CLINT_SetLoadValue(0);
        CLINT_SetCompareValue(ticks);
        __enable_timer_irq();
        return (0UL);
    }

    /**
     * \brief   System Tick Reload
     * \details Reload the System Timer Tick when the MTIMECMP reached TIME value
     *
     * \param [in]  ticks  Number of ticks between two interrupts.
     * \return          0  Function succeeded.
     * \return          1  Function failed.
     * \sa
     * - \ref CLINT_SetCompareValue
     * - \ref CLINT_SetLoadValue
     */
    __STATIC_FORCEINLINE uint32_t SysTick_Reload(uint64_t ticks)
    {
        uint64_t cur_ticks = CLINT->MTIME;
        uint64_t reload_ticks = ticks + cur_ticks;

        if (__USUALLY(reload_ticks > cur_ticks))
        {
            CLINT->MTIMECMP = reload_ticks;
        }
        else
        {
            /* When added the ticks value, then the MTIMERCMP < TIMER,
             * which means the MTIMERCMP is overflowed,
             * so we need to reset the counter to zero */
            CLINT->MTIME = 0;
            CLINT->MTIMECMP = ticks;
        }

        return (0UL);
    }

#ifdef __cplusplus
}
#endif

#endif // CLINT_H