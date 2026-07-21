#define BOUNDARY_NAME "exception_stress"
#include "boundary.h"

#define TRAP_ROUNDS 128u

static volatile uint32_t trap_count;
static volatile uint32_t observed_mcause[TRAP_ROUNDS];
static volatile uint32_t observed_mepc[TRAP_ROUNDS];
static volatile uint32_t observed_mstatus[TRAP_ROUNDS];
static volatile uint32_t expected_mepc[TRAP_ROUNDS];
static volatile uint32_t load_source = 0x10203040u;

__attribute__((naked)) static void stress_trap_handler(void)
{
    asm volatile(
        "la t0, trap_count\n"
        "lw t1, 0(t0)\n"
        "slli t2, t1, 2\n"
        "la t3, observed_mcause\n"
        "add t3, t3, t2\n"
        "csrr t4, mcause\n"
        "sw t4, 0(t3)\n"
        "la t3, observed_mepc\n"
        "add t3, t3, t2\n"
        "csrr t4, mepc\n"
        "sw t4, 0(t3)\n"
        "la t3, observed_mstatus\n"
        "add t3, t3, t2\n"
        "csrr t4, mstatus\n"
        "sw t4, 0(t3)\n"
        "addi t1, t1, 1\n"
        "sw t1, 0(t0)\n"
        "csrr t4, mepc\n"
        "addi t4, t4, 4\n"
        "csrw mepc, t4\n"
        "mret\n");
}

static void prepare_status(uint32_t mie)
{
    uint32_t mask = (1u << 3) | (1u << 7);
    uint32_t value = mie ? (1u << 3) : (1u << 7);

    asm volatile("csrc mstatus, %0\ncsrs mstatus, %1"
                 :: "r"(mask), "r"(value) : "memory");
}

int main(void)
{
    uint32_t handler = (uint32_t)(uintptr_t)stress_trap_handler;
    uint32_t scratch = 1;
    uint32_t status;

    asm volatile("csrw mtvec, %0" :: "r"(handler));

    for (uint32_t i = 0; i < TRAP_ROUNDS; i++) {
        uint32_t mie = i & 1u;
        prepare_status(mie);

        switch (i & 3u) {
        case 0:
            asm volatile("addi %0, %0, 3" : "+r"(scratch));
            break;
        case 1:
            asm volatile("lw %0, 0(%1)\naddi %0, %0, 1"
                         : "=&r"(scratch) : "r"(&load_source) : "memory");
            break;
        case 2:
            asm volatile("li t0, 81\nli t1, 9\ndiv %0, t0, t1"
                         : "=r"(scratch) :: "t0", "t1");
            break;
        default:
            asm volatile(
                "li t0, 1\n"
                "beq t0, t0, 1f\n"
                "li %0, 0\n"
                "1: addi %0, t0, 1"
                : "=r"(scratch) :: "t0");
            break;
        }

        asm volatile(
            "la t0, 1f\n"
            "slli t1, %1, 2\n"
            "la t2, expected_mepc\n"
            "add t2, t2, t1\n"
            "sw t0, 0(t2)\n"
            "1: ecall"
            :: "r"(scratch), "r"(i) : "t0", "t1", "t2", "t3", "t4", "memory");

        asm volatile("csrr %0, mstatus" : "=r"(status));
        CHECK_EQ("mret_mie", status & (1u << 3), mie << 3);
        CHECK_EQ("mret_mpie", status & (1u << 7), 1u << 7);
        asm volatile("csrr %0, mtvec" : "=r"(status));
        CHECK_EQ("mtvec_preserved", status, handler);
    }

    CHECK_EQ("trap_count", trap_count, TRAP_ROUNDS);
    for (uint32_t i = 0; i < TRAP_ROUNDS; i++) {
        uint32_t mie = i & 1u;
        CHECK_EQ("mcause_sequence", observed_mcause[i], 11);
        CHECK_EQ("mepc_sequence", observed_mepc[i], expected_mepc[i]);
        CHECK_EQ("handler_mie", observed_mstatus[i] & (1u << 3), 0);
        CHECK_EQ("handler_mpie", observed_mstatus[i] & (1u << 7), mie << 7);
    }

    boundary_finish();
}
