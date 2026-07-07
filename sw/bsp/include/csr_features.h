#ifndef CSR_FEATURES_H
#define CSR_FEATURES_H

#ifdef __cplusplus
extern "C"
{
#endif

#include <stdint.h>
#include "encoding.h"
#include "sys_defs.h"

#define __STR(s)                #s
#define STRINGIFY(s)            __STR(s)

/** \brief Type of Control and Status Register(CSR), depends on the XLEN defined in RISC-V */
#if __RISCV_XLEN == 32
    typedef uint32_t rv_csr_t;
#elif __RISCV_XLEN == 64
typedef uint64_t rv_csr_t;
#else
typedef uint32_t rv_csr_t;
#endif

    /**
     * \brief  Union type to access MISA register.
     */
    typedef union
    {
        struct
        {
            rv_csr_t a : 1;          /*!< bit:     0  Atomic extension */
            rv_csr_t b : 1;          /*!< bit:     1  Tentatively reserved for Bit-Manipulation extension */
            rv_csr_t c : 1;          /*!< bit:     2  Compressed extension */
            rv_csr_t d : 1;          /*!< bit:     3  Double-precision floating-point extension */
            rv_csr_t e : 1;          /*!< bit:     4  RV32E base ISA */
            rv_csr_t f : 1;          /*!< bit:     5  Single-precision floating-point extension */
            rv_csr_t g : 1;          /*!< bit:     6  Additional standard extensions present */
            rv_csr_t h : 1;          /*!< bit:     7  Hypervisor extension */
            rv_csr_t i : 1;          /*!< bit:     8  RV32I/64I/128I base ISA */
            rv_csr_t j : 1;          /*!< bit:     9  Tentatively reserved for Dynamically Translated Languages extension */
            rv_csr_t _reserved1 : 1; /*!< bit:     10 Reserved  */
            rv_csr_t l : 1;          /*!< bit:     11 Tentatively reserved for Decimal Floating-Point extension  */
            rv_csr_t m : 1;          /*!< bit:     12 Integer Multiply/Divide extension */
            rv_csr_t n : 1;          /*!< bit:     13 User-level interrupts supported  */
            rv_csr_t _reserved2 : 1; /*!< bit:     14 Reserved  */
            rv_csr_t p : 1;          /*!< bit:     15 Tentatively reserved for Packed-SIMD extension  */
            rv_csr_t q : 1;          /*!< bit:     16 Quad-precision floating-point extension  */
            rv_csr_t _resreved3 : 1; /*!< bit:     17 Reserved  */
            rv_csr_t s : 1;          /*!< bit:     18 Supervisor mode implemented  */
            rv_csr_t t : 1;          /*!< bit:     19 Tentatively reserved for Transactional Memory extension  */
            rv_csr_t u : 1;          /*!< bit:     20 User mode implemented  */
            rv_csr_t v : 1;          /*!< bit:     21 Tentatively reserved for Vector extension  */
            rv_csr_t _reserved4 : 1; /*!< bit:     22 Reserved  */
            rv_csr_t x : 1;          /*!< bit:     23 Non-standard extensions present  */
#if defined(__RISCV_XLEN) && __RISCV_XLEN == 64
            rv_csr_t _reserved5 : 38; /*!< bit:     24..61 Reserved  */
            rv_csr_t mxl : 2;         /*!< bit:     62..63 Machine XLEN  */
#else
        rv_csr_t _reserved5 : 6; /*!< bit:     24..29 Reserved  */
        rv_csr_t mxl : 2;        /*!< bit:     30..31 Machine XLEN  */
#endif
        } b;        /*!< Structure used for bit  access */
        rv_csr_t d; /*!< Type      used for csr data access */
    } CSR_MISA_Type;

    /**
     * \brief  Union type to access MSTATUS configure register.
     */
    typedef union
    {
        struct
        {
#if defined(__RISCV_XLEN) && __RISCV_XLEN == 64
            rv_csr_t _reserved0 : 3;  /*!< bit:     0..2  Reserved */
            rv_csr_t mie : 1;         /*!< bit:     3  Machine mode interrupt enable flag */
            rv_csr_t _reserved1 : 3;  /*!< bit:     4..6  Reserved */
            rv_csr_t mpie : 1;        /*!< bit:     7  mirror of MIE flag */
            rv_csr_t _reserved2 : 3;  /*!< bit:     8..10  Reserved */
            rv_csr_t mpp : 2;         /*!< bit:     11..12 mirror of Privilege Mode */
            rv_csr_t fs : 2;          /*!< bit:     13..14 FS status flag */
            rv_csr_t xs : 2;          /*!< bit:     15..16 XS status flag */
            rv_csr_t mprv : 1;        /*!< bit:     Machine mode PMP */
            rv_csr_t _reserved3 : 14; /*!< bit:     18..31 Reserved */
            rv_csr_t uxl : 2;         /*!< bit:     32..33 user mode xlen */
            rv_csr_t _reserved6 : 29; /*!< bit:     34..62 Reserved  */
            rv_csr_t sd : 1;          /*!< bit:     Dirty status for XS or FS */
#else
        rv_csr_t _reserved0 : 1;  /*!< bit:     0  Reserved */
        rv_csr_t sie : 1;         /*!< bit:     1  supervisor interrupt enable flag */
        rv_csr_t _reserved1 : 1;  /*!< bit:     2  Reserved */
        rv_csr_t mie : 1;         /*!< bit:     3  Machine mode interrupt enable flag */
        rv_csr_t _reserved2 : 1;  /*!< bit:     4  Reserved */
        rv_csr_t spie : 1;        /*!< bit:     3  Supervisor Privilede mode interrupt enable flag */
        rv_csr_t _reserved3 : 1;  /*!< bit:     Reserved */
        rv_csr_t mpie : 1;        /*!< bit:     mirror of MIE flag */
        rv_csr_t _reserved4 : 3;  /*!< bit:     Reserved */
        rv_csr_t mpp : 2;         /*!< bit:     mirror of Privilege Mode */
        rv_csr_t fs : 2;          /*!< bit:     FS status flag */
        rv_csr_t xs : 2;          /*!< bit:     XS status flag */
        rv_csr_t mprv : 1;        /*!< bit:     Machine mode PMP */
        rv_csr_t sum : 1;         /*!< bit:     Supervisor Mode load and store protection */
        rv_csr_t _reserved6 : 12; /*!< bit:     19..30 Reserved  */
        rv_csr_t sd : 1;          /*!< bit:     Dirty status for XS or FS */
#endif
        } b;        /*!< Structure used for bit  access */
        rv_csr_t d; /*!< Type      used for csr data access */
    } CSR_MSTATUS_Type;

    /**
     * \brief  Union type to access MTVEC configure register.
     */
    typedef union
    {
        struct
        {
            rv_csr_t mode : 2; /*!< bit:     0..2   interrupt mode control */
#if defined(__RISCV_XLEN) && __RISCV_XLEN == 64
            rv_csr_t addr : 61; /*!< bit:     3..63  mtvec address */
#else
        rv_csr_t addr : 29; /*!< bit:     3..31  mtvec address */
#endif
        } b;        /*!< Structure used for bit  access */
        rv_csr_t d; /*!< Type      used for csr data access */
    } CSR_MTVEC_Type;

    /**
     * \brief  Union type to access MCAUSE configure register.
     */
    typedef union
    {
        struct
        {
            rv_csr_t exccode : 12;   /*!< bit:     11..0  exception or interrupt code */
            rv_csr_t _reserved0 : 4; /*!< bit:     15..12  Reserved */
            rv_csr_t mpil : 8;       /*!< bit:     23..16  Previous interrupt level */
            rv_csr_t _reserved1 : 3; /*!< bit:     26..24  Reserved */
            rv_csr_t mpie : 1;       /*!< bit:     27  Interrupt enable flag before enter interrupt */
            rv_csr_t mpp : 2;        /*!< bit:     29..28  Privilede mode flag before enter interrupt */
            rv_csr_t minhv : 1;      /*!< bit:     30  Machine interrupt vector table */
#if defined(__RISCV_XLEN) && __RISCV_XLEN == 64
            rv_csr_t _reserved2 : 32; /*!< bit:     31..62  Reserved */
            rv_csr_t interrupt : 1;   /*!< bit:     63  trap type. 0 means exception and 1 means interrupt */
#else
        rv_csr_t interrupt : 1; /*!< bit:     31  trap type. 0 means exception and 1 means interrupt */
#endif
        } b;        /*!< Structure used for bit  access */
        rv_csr_t d; /*!< Type      used for csr data access */
    } CSR_MCAUSE_Type;

    /**
     * \brief  Union type to access MCOUNTINHIBIT configure register.
     */
    typedef union
    {
        struct
        {
            rv_csr_t cy : 1;         /*!< bit:     0     1 means disable mcycle counter */
            rv_csr_t _reserved0 : 1; /*!< bit:     1     Reserved */
            rv_csr_t ir : 1;         /*!< bit:     2     1 means disable minstret counter */
#if defined(__RISCV_XLEN) && __RISCV_XLEN == 64
            rv_csr_t _reserved1 : 61; /*!< bit:     3..63 Reserved */
#else
        rv_csr_t _reserved1 : 29; /*!< bit:     3..31 Reserved */
#endif
        } b;        /*!< Structure used for bit  access */
        rv_csr_t d; /*!< Type      used for csr data access */
    } CSR_MCOUNTINHIBIT_Type;
    /** @} */ /* End of Doxygen Group Base_Registers */

#ifndef __ASSEMBLY__

/**
 * \brief CSR operation Macro for csrrw instruction.
 * \details
 * Read the content of csr register to __v,
 * then write content of val into csr register, then return __v
 * \param csr   CSR macro definition defined in
 *              \ref CSR_Registers, eg. \ref CSR_MSTATUS
 * \param val   value to store into the CSR register
 * \return the CSR register value before written
 */
#define __RV_CSR_SWAP(csr, val)                                                                \
    ({                                                                                         \
        register rv_csr_t __v = (unsigned long)(val);                                          \
        __ASM volatile("csrrw %0, " STRINGIFY(csr) ", %1" : "=r"(__v) : "rK"(__v) : "memory"); \
        __v;                                                                                   \
    })

/**
 * \brief CSR operation Macro for csrr instruction.
 * \details
 * Read the content of csr register to __v and return it
 * \param csr   CSR macro definition defined in
 *              \ref CSR_Registers, eg. \ref CSR_MSTATUS
 * \return the CSR register value
 */
#define __RV_CSR_READ(csr)                                                   \
    ({                                                                       \
        register rv_csr_t __v;                                               \
        __ASM volatile("csrr %0, " STRINGIFY(csr) : "=r"(__v) : : "memory"); \
        __v;                                                                 \
    })

/**
 * \brief CSR operation Macro for csrw instruction.
 * \details
 * Write the content of val to csr register
 * \param csr   CSR macro definition defined in
 *              \ref CSR_Registers, eg. \ref CSR_MSTATUS
 * \param val   value to store into the CSR register
 */
#define __RV_CSR_WRITE(csr, val)                                                \
    ({                                                                          \
        register rv_csr_t __v = (rv_csr_t)(val);                                \
        __ASM volatile("csrw " STRINGIFY(csr) ", %0" : : "rK"(__v) : "memory"); \
    })

/**
 * \brief CSR operation Macro for csrrs instruction.
 * \details
 * Read the content of csr register to __v,
 * then set csr register to be __v | val, then return __v
 * \param csr   CSR macro definition defined in
 *              \ref CSR_Registers, eg. \ref CSR_MSTATUS
 * \param val   Mask value to be used wih csrrs instruction
 * \return the CSR register value before written
 */
#define __RV_CSR_READ_SET(csr, val)                                                            \
    ({                                                                                         \
        register rv_csr_t __v = (rv_csr_t)(val);                                               \
        __ASM volatile("csrrs %0, " STRINGIFY(csr) ", %1" : "=r"(__v) : "rK"(__v) : "memory"); \
        __v;                                                                                   \
    })

/**
 * \brief CSR operation macro for csrs instruction.
 * \details
 * Set CSR register to csr_content | val
 * \param csr   CSR register name
 * \param val   Mask value for csrs instruction
 */
#define __RV_CSR_SET(csr, val)                                                  \
    ({                                                                          \
        register rv_csr_t __v = (rv_csr_t)(val);                                \
        __ASM volatile("csrs " STRINGIFY(csr) ", %0" : : "rK"(__v) : "memory"); \
    })

/**
 * \brief CSR operation macro for csrrc instruction.
 * \details
 * Read CSR register to __v, then set CSR to __v & ~val, return original value
 * \param csr   CSR register name
 * \param val   Mask value for csrrc instruction
 * \return Value of CSR before write
 */
#define __RV_CSR_READ_CLEAR(csr, val)                                                          \
    ({                                                                                         \
        register rv_csr_t __v = (rv_csr_t)(val);                                               \
        __ASM volatile("csrrc %0, " STRINGIFY(csr) ", %1" : "=r"(__v) : "rK"(__v) : "memory"); \
        __v;                                                                                   \
    })

/**
 * \brief CSR operation Macro for csrc instruction.
 * \details
 * Set csr register to be csr_content & ~val
 * \param csr   CSR macro definition defined in
 *              \ref CSR_Registers, eg. \ref CSR_MSTATUS
 * \param val   Mask value to be used wih csrc instruction
 */
#define __RV_CSR_CLEAR(csr, val)                                                \
    ({                                                                          \
        register rv_csr_t __v = (rv_csr_t)(val);                                \
        __ASM volatile("csrc " STRINGIFY(csr) ", %0" : : "rK"(__v) : "memory"); \
    })
#endif /* __ASSEMBLY__ */

    /**
     * \brief   Enable IRQ Interrupts
     * \details Enables IRQ interrupts by setting the MIE-bit in the MSTATUS Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __enable_irq(void)
    {
        __RV_CSR_SET(CSR_MSTATUS, MSTATUS_MIE);
    }

    /**
     * \brief   Disable IRQ Interrupts
     * \details Disables IRQ interrupts by clearing the MIE-bit in the MSTATUS Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __disable_irq(void)
    {
        __RV_CSR_CLEAR(CSR_MSTATUS, MSTATUS_MIE);
    }

    /**
     * \brief   Enable External IRQ Interrupts
     * \details Enables External IRQ interrupts by setting the MEIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __enable_ext_irq(void)
    {
        __RV_CSR_SET(CSR_MIE, MIE_MEIE);
    }

    /**
     * \brief   Disable External IRQ Interrupts
     * \details Disables External IRQ interrupts by clearing the MEIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __disable_ext_irq(void)
    {
        __RV_CSR_CLEAR(CSR_MIE, MIE_MEIE);
    }

    /**
     * \brief   Enable Timer IRQ Interrupts
     * \details Enables Timer IRQ interrupts by setting the MTIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __enable_timer_irq(void)
    {
        __RV_CSR_SET(CSR_MIE, MIE_MTIE);
    }

    /**
     * \brief   Disable Timer IRQ Interrupts
     * \details Disables Timer IRQ interrupts by clearing the MTIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __disable_timer_irq(void)
    {
        __RV_CSR_CLEAR(CSR_MIE, MIE_MTIE);
    }

    /**
     * \brief   Enable software IRQ Interrupts
     * \details Enables software IRQ interrupts by setting the MSIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __enable_sw_irq(void)
    {
        __RV_CSR_SET(CSR_MIE, MIE_MSIE);
    }

    /**
     * \brief   Disable software IRQ Interrupts
     * \details Disables software IRQ interrupts by clearing the MSIE-bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __disable_sw_irq(void)
    {
        __RV_CSR_CLEAR(CSR_MIE, MIE_MSIE);
    }

    /**
     * \brief   Disable Core IRQ Interrupt
     * \details Disable Core IRQ interrupt by clearing the irq bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __disable_core_irq(uint32_t irq)
    {
        __RV_CSR_CLEAR(CSR_MIE, 1 << irq);
    }

    /**
     * \brief   Enable Core IRQ Interrupt
     * \details Enable Core IRQ interrupt by setting the irq bit in the MIE Register.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __enable_core_irq(uint32_t irq)
    {
        __RV_CSR_SET(CSR_MIE, 1 << irq);
    }

    /**
     * \brief   Get Core IRQ Interrupt Pending status
     * \details Get Core IRQ interrupt pending status of irq bit.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE uint32_t __get_core_irq_pending(uint32_t irq)
    {
        return ((__RV_CSR_READ(CSR_MIP) >> irq) & 0x1);
    }

    /**
     * \brief   Clear Core IRQ Interrupt Pending status
     * \details Clear Core IRQ interrupt pending status of irq bit.
     * \remarks
     *          Can only be executed in Privileged modes.
     */
    __STATIC_FORCEINLINE void __clear_core_irq_pending(uint32_t irq)
    {
        __RV_CSR_SET(CSR_MIP, 1 << irq);
    }

    /**
     * \brief   Read whole 64 bits value of mcycle counter
     * \details This function will read the whole 64 bits of MCYCLE register
     * \return  The whole 64 bits value of MCYCLE
     * \remarks It will work for both RV32 and RV64 to get full 64bits value of MCYCLE
     */
    __STATIC_FORCEINLINE uint64_t __get_rv_cycle(void)
    {
#if __RISCV_XLEN == 32
        volatile uint32_t high0, low, high;
        uint64_t full;

        high0 = __RV_CSR_READ(CSR_MCYCLEH);
        low = __RV_CSR_READ(CSR_MCYCLE);
        high = __RV_CSR_READ(CSR_MCYCLEH);
        if (high0 != high)
        {
            low = __RV_CSR_READ(CSR_MCYCLE);
        }
        full = (((uint64_t)high) << 32) | low;
        return full;
#elif __RISCV_XLEN == 64
    return (uint64_t)__RV_CSR_READ(CSR_MCYCLE);
#else // TODO Need cover for XLEN=128 case in future
    return (uint64_t)__RV_CSR_READ(CSR_MCYCLE);
#endif
    }

    /**
     * \brief   Read whole 64 bits value of machine instruction-retired counter
     * \details This function will read the whole 64 bits of MINSTRET register
     * \return  The whole 64 bits value of MINSTRET
     * \remarks It will work for both RV32 and RV64 to get full 64bits value of MINSTRET
     */
    __STATIC_FORCEINLINE uint64_t __get_rv_instret(void)
    {
#if __RISCV_XLEN == 32
        volatile uint32_t high0, low, high;
        uint64_t full;

        high0 = __RV_CSR_READ(CSR_MINSTRETH);
        low = __RV_CSR_READ(CSR_MINSTRET);
        high = __RV_CSR_READ(CSR_MINSTRETH);
        if (high0 != high)
        {
            low = __RV_CSR_READ(CSR_MINSTRET);
        }
        full = (((uint64_t)high) << 32) | low;
        return full;
#elif __RISCV_XLEN == 64
    return (uint64_t)__RV_CSR_READ(CSR_MINSTRET);
#else // TODO Need cover for XLEN=128 case in future
    return (uint64_t)__RV_CSR_READ(CSR_MINSTRET);
#endif
    }

    /**
     * \brief   Read whole 64 bits value of real-time clock
     * \details This function will read the whole 64 bits of TIME register
     * \return  The whole 64 bits value of TIME CSR
     * \remarks It will work for both RV32 and RV64 to get full 64bits value of TIME
     * \attention only available when user mode available
     */
    __STATIC_FORCEINLINE uint64_t __get_rv_time(void)
    {
#if __RISCV_XLEN == 32
        volatile uint32_t high0, low, high;
        uint64_t full;

        high0 = __RV_CSR_READ(CSR_TIMEH);
        low = __RV_CSR_READ(CSR_TIME);
        high = __RV_CSR_READ(CSR_TIMEH);
        if (high0 != high)
        {
            low = __RV_CSR_READ(CSR_TIME);
        }
        full = (((uint64_t)high) << 32) | low;
        return full;
#elif __RISCV_XLEN == 64
    return (uint64_t)__RV_CSR_READ(CSR_TIME);
#else // TODO Need cover for XLEN=128 case in future
    return (uint64_t)__RV_CSR_READ(CSR_TIME);
#endif
    }

    /**
     * \brief   Enable MCYCLE counter
     * \details
     * Clear the CY bit of MCOUNTINHIBIT to 0 to enable MCYCLE Counter
     */
    __STATIC_FORCEINLINE void __enable_mcycle_counter(void)
    {
        __RV_CSR_CLEAR(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_CY);
    }

    /**
     * \brief   Disable MCYCLE counter
     * \details
     * Set the CY bit of MCOUNTINHIBIT to 1 to disable MCYCLE Counter
     */
    __STATIC_FORCEINLINE void __disable_mcycle_counter(void)
    {
        __RV_CSR_SET(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_CY);
    }

    /**
     * \brief   Enable MINSTRET counter
     * \details
     * Clear the IR bit of MCOUNTINHIBIT to 0 to enable MINSTRET Counter
     */
    __STATIC_FORCEINLINE void __enable_minstret_counter(void)
    {
        __RV_CSR_CLEAR(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_IR);
    }

    /**
     * \brief   Disable MINSTRET counter
     * \details
     * Set the IR bit of MCOUNTINHIBIT to 1 to disable MINSTRET Counter
     */
    __STATIC_FORCEINLINE void __disable_minstret_counter(void)
    {
        __RV_CSR_SET(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_IR);
    }

    /**
     * \brief   Enable MCYCLE & MINSTRET counter
     * \details
     * Clear the IR and CY bit of MCOUNTINHIBIT to 1 to enable MINSTRET & MCYCLE Counter
     */
    __STATIC_FORCEINLINE void __enable_all_counter(void)
    {
        __RV_CSR_CLEAR(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_IR | MCOUNTINHIBIT_CY);
    }

    /**
     * \brief   Disable MCYCLE & MINSTRET counter
     * \details
     * Set the IR and CY bit of MCOUNTINHIBIT to 1 to disable MINSTRET & MCYCLE Counter
     */
    __STATIC_FORCEINLINE void __disable_all_counter(void)
    {
        __RV_CSR_SET(CSR_MCOUNTINHIBIT, MCOUNTINHIBIT_IR | MCOUNTINHIBIT_CY);
    }

#ifdef __cplusplus
}
#endif

#endif // CSR_FEATURES_H