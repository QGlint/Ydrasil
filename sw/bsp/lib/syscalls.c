#include <stddef.h>
#include <stdint.h>

#include "sim_ctrl.h"

extern char _end;
extern char _heap_end;

int _write(int fd, const void *buf, int len)
{
    const char *p = (const char *)buf;
    (void)fd;

    for (int i = 0; i < len; i++) {
        *(volatile uint32_t *)SIM_STDOUT_REG = (uint8_t)p[i];
    }

    return len;
}

void *_sbrk(int incr)
{
    static char *heap;
    char *prev;

    if (heap == NULL) {
        heap = &_end;
    }

    prev = heap;
    if (heap + incr > &_heap_end) {
        return (void *)-1;
    }

    heap += incr;
    return prev;
}

void _exit(int code)
{
    (void)code;
    sim_end();
    while (1) {
    }
}

int _close(int fd)
{
    (void)fd;
    return -1;
}

int _fstat(int fd, void *st)
{
    (void)fd;
    (void)st;
    return 0;
}

int _isatty(int fd)
{
    (void)fd;
    return 1;
}

int _lseek(int fd, int ptr, int dir)
{
    (void)fd;
    (void)ptr;
    (void)dir;
    return 0;
}

int _read(int fd, void *buf, int len)
{
    (void)fd;
    (void)buf;
    (void)len;
    return 0;
}
