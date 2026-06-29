#ifndef __GCC_DEFS_H__
#define __GCC_DEFS_H__

#include <stdint.h>
#include "encoding.h"

#ifdef __cplusplus
extern "C"
{
#endif

/* Ignore some GCC warnings */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wunused-parameter"

/* Fallback for __has_builtin */
#ifndef __has_builtin
#define __has_builtin(x) (0)
#endif

/* Compiler specific defines */
/** \brief Pass information from the compiler to the assembler. */
#ifndef __ASM
#define __ASM __asm
#endif

/** \brief Recommend that function should be inlined by the compiler. */
#ifndef __INLINE
#define __INLINE inline
#endif

/** \brief Define a static function that may be inlined by the compiler. */
#ifndef __STATIC_INLINE
#define __STATIC_INLINE static inline
#endif

/** \brief Define a static function that should always be inlined by the compiler. */
#ifndef __STATIC_FORCEINLINE
#define __STATIC_FORCEINLINE __attribute__((always_inline)) static inline
#endif

/** \brief Inform the compiler that a function does not return. */
#ifndef __NO_RETURN
#define __NO_RETURN __attribute__((__noreturn__))
#endif

/** \brief Inform that a variable shall be retained in executable image. */
#ifndef __USED
#define __USED __attribute__((used))
#endif

/** \brief Mark a function or variable as weak, allowing it to be overridden. */
#ifndef __WEAK
#define __WEAK __attribute__((weak))
#endif

/** \brief Specify the vector size of the variable, measured in bytes. */
#ifndef __VECTOR_SIZE
#define __VECTOR_SIZE(x) __attribute__((vector_size(x)))
#endif

/** \brief Request smallest possible alignment. */
#ifndef __PACKED
#define __PACKED __attribute__((packed, aligned(1)))
#endif

/** \brief Request smallest possible alignment for a structure. */
#ifndef __PACKED_STRUCT
#define __PACKED_STRUCT struct __attribute__((packed, aligned(1)))
#endif

/** \brief Request smallest possible alignment for a union. */
#ifndef __PACKED_UNION
#define __PACKED_UNION union __attribute__((packed, aligned(1)))
#endif

#ifndef __UNALIGNED_UINT16_WRITE
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpacked"
#pragma GCC diagnostic ignored "-Wattributes"
  /** \brief Packed struct for unaligned uint16_t write access */
  __PACKED_STRUCT T_UINT16_WRITE
  {
    uint16_t v;
  };
#pragma GCC diagnostic pop
/** \brief Pointer for unaligned write of a uint16_t variable. */
#define __UNALIGNED_UINT16_WRITE(addr, val) (void)((((struct T_UINT16_WRITE *)(void *)(addr))->v) = (val))
#endif

#ifndef __UNALIGNED_UINT16_READ
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpacked"
#pragma GCC diagnostic ignored "-Wattributes"
  /** \brief Packed struct for unaligned uint16_t read access */
  __PACKED_STRUCT T_UINT16_READ
  {
    uint16_t v;
  };
#pragma GCC diagnostic pop
/** \brief Pointer for unaligned read of a uint16_t variable. */
#define __UNALIGNED_UINT16_READ(addr) (((const struct T_UINT16_READ *)(const void *)(addr))->v)
#endif

#ifndef __UNALIGNED_UINT32_WRITE
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpacked"
#pragma GCC diagnostic ignored "-Wattributes"
  /** \brief Packed struct for unaligned uint32_t write access */
  __PACKED_STRUCT T_UINT32_WRITE
  {
    uint32_t v;
  };
#pragma GCC diagnostic pop
/** \brief Pointer for unaligned write of a uint32_t variable. */
#define __UNALIGNED_UINT32_WRITE(addr, val) (void)((((struct T_UINT32_WRITE *)(void *)(addr))->v) = (val))
#endif

#ifndef __UNALIGNED_UINT32_READ
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpacked"
#pragma GCC diagnostic ignored "-Wattributes"
  /** \brief Packed struct for unaligned uint32_t read access */
  __PACKED_STRUCT T_UINT32_READ
  {
    uint32_t v;
  };
#pragma GCC diagnostic pop
/** \brief Pointer for unaligned read of a uint32_t variable. */
#define __UNALIGNED_UINT32_READ(addr) (((const struct T_UINT32_READ *)(const void *)(addr))->v)
#endif

/** \brief Minimum `x` bytes alignment for a variable. */
#ifndef __ALIGNED
#define __ALIGNED(x) __attribute__((aligned(x)))
#endif

/** \brief Restrict pointer qualifier to enable additional optimizations. */
#ifndef __RESTRICT
#define __RESTRICT __restrict
#endif

/** \brief Barrier to prevent compiler from reordering instructions. */
#ifndef __COMPILER_BARRIER
#define __COMPILER_BARRIER() __ASM volatile("" :: : "memory")
#endif

/** \brief Provide the compiler with branch prediction information, the branch is usually true. */
#ifndef __USUALLY
#define __USUALLY(exp) __builtin_expect((exp), 1)
#endif

/** \brief Provide the compiler with branch prediction information, the branch is rarely true. */
#ifndef __RARELY
#define __RARELY(exp) __builtin_expect((exp), 0)
#endif

/** \brief Use this attribute to indicate that the specified function is an interrupt handler. */
#ifndef __INTERRUPT
#define __INTERRUPT
#endif

/* IO definitions (access restrictions to peripheral registers) */
/** \brief Defines 'read only' permissions */
#ifdef __cplusplus
#define __I volatile
#else
#define __I volatile const
#endif
/** \brief Defines 'write only' permissions */
#define __O volatile
/** \brief Defines 'read / write' permissions */
#define __IO volatile

/* Following defines should be used for structure members */
/** \brief Defines 'read only' structure member permissions */
#define __IM volatile const
/** \brief Defines 'write only' structure member permissions */
#define __OM volatile
/** \brief Defines 'read/write' structure member permissions */
#define __IOM volatile

/**
 * \brief   Mask and shift a bit field value for use in a register bit range.
 * \details Use _VAL2FLD macro to shift and mask a bit field value for register assignment.
 *
 * Example:
 * PLIC->CFG = _VAL2FLD(CFG_FIELD, 3);
 * \param[in] field  Name of the bit field
 * \param[in] value  Value of the bit field, type uint32_t
 * \return           Masked and shifted value
 */
#define _VAL2FLD(field, value) (((uint32_t)(value) << field##_Pos) & field##_Msk)

/**
 * \brief   Mask and shift a register value to extract a bit field value.
 * \details Use _FLD2VAL macro to extract a bit field value from a register value.
 *
 * Example:
 * val = _FLD2VAL(CFG_FIELD, PLIC->CFG);
 * \param[in] field  Name of the bit field
 * \param[in] value  Register value, type uint32_t
 * \return           Extracted bit field value
 */
#define _FLD2VAL(field, value) (((uint32_t)(value) & field##_Msk) >> field##_Pos)

#ifdef __cplusplus
}
#endif
#endif /* __GCC_DEFS_H__ */
