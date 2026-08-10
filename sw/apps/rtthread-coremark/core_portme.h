#ifndef YDRASIL_RTTHREAD_CORE_PORTME_H
#define YDRASIL_RTTHREAD_CORE_PORTME_H

#include <rtthread.h>

#ifndef HAS_FLOAT
#define HAS_FLOAT  0
#endif
#define HAS_TIME_H 0
#define USE_CLOCK  0
#define HAS_STDIO  0
#define HAS_PRINTF 0

#ifdef __GNUC__
#define COMPILER_VERSION "GCC " __VERSION__
#else
#define COMPILER_VERSION "unknown"
#endif
#define COMPILER_FLAGS FLAGS_STR
#define MEM_LOCATION   "STATIC"

typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef unsigned long long ee_u64;
typedef ee_u32         ee_ptr_int;
typedef unsigned int   ee_size_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

#define align_mem(pointer) \
    (void *)(4U + (((ee_ptr_int)(pointer) - 1U) & ~3U))

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

#define CORETIMETYPE ee_u64
typedef ee_u64 CORE_TICKS;

extern ee_u32 default_num_contexts;

typedef struct
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *port, int *argc, char *argv[]);
void portable_fini(core_portable *port);

#define ee_printf rt_kprintf

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && \
    !defined(VALIDATION_RUN)
#if TOTAL_DATA_SIZE == 1200
#define PROFILE_RUN 1
#elif TOTAL_DATA_SIZE == 2000
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

#endif
