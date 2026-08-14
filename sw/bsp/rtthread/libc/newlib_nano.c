#include <errno.h>
#include <stddef.h>
#include <reent.h>

#include <rtthread.h>

static void newlib_set_nomem(struct _reent *reent)
{
    if (reent != RT_NULL)
    {
        reent->_errno = ENOMEM;
    }
}

void *_malloc_r(struct _reent *reent, size_t size)
{
    void *memory = rt_malloc(size);

    if (memory == RT_NULL)
    {
        newlib_set_nomem(reent);
    }

    return memory;
}

void *_realloc_r(struct _reent *reent, void *memory, size_t size)
{
    void *resized = rt_realloc(memory, size);

    if (resized == RT_NULL && size != 0U)
    {
        newlib_set_nomem(reent);
    }

    return resized;
}

void *_calloc_r(struct _reent *reent, size_t count, size_t size)
{
    void *memory = rt_calloc(count, size);

    if (memory == RT_NULL)
    {
        newlib_set_nomem(reent);
    }

    return memory;
}

void _free_r(struct _reent *reent, void *memory)
{
    (void)reent;
    rt_free(memory);
}
