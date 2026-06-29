#ifndef _SIM_CTRL_H_
#define _SIM_CTRL_H_

#define SIM_END_REG     0x80200040
#define SIM_STDOUT_REG  0x80200060
#define SIM_DUMP_REG    0x80200064

void sim_ctrl_init();
void sim_end();
void sim_dump_enable(uint8_t en);

#endif
