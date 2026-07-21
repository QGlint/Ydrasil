#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t count)
{
    unsigned char *out = (unsigned char *)dest;
    const unsigned char *in = (const unsigned char *)src;

    while (count-- != 0) {
        *out++ = *in++;
    }
    return dest;
}

void *memset(void *dest, int value, size_t count)
{
    unsigned char *out = (unsigned char *)dest;

    while (count-- != 0) {
        *out++ = (unsigned char)value;
    }
    return dest;
}
