#ifndef YDRASIL_ATK_MS601M_H
#define YDRASIL_ATK_MS601M_H

#include <stdint.h>

struct ms601m_attitude
{
    int32_t roll_tenth_degree;
    int32_t pitch_tenth_degree;
    int32_t yaw_tenth_degree;
};

int ms601m_read_attitude(struct ms601m_attitude *attitude,
                         uint32_t timeout_ms);

#endif
