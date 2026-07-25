# APB and Interrupt Verification Plan

## Scope

This plan verifies the path from the core memory request packet through
AXI4-Lite and APB, plus the machine-mode interrupt path used by RT-Thread.
The FPU is outside this change and remains covered by the existing FPU tests.

## Bus cases

| Area | Required checks |
| --- | --- |
| AXI write | AW before W, W before AW, independent ready, held valid, B response |
| AXI read | AR handshake, held R response, returned data |
| APB protocol | setup then access, stable address/control, multi-cycle PREADY wait |
| Error path | APB PSLVERR maps to AXI SLVERR for reads and writes |
| Byte enables | AXI WSTRB maps to APB PSTRB; zero and partial strobes preserve bytes |
| Decode | CLINT and board peripheral windows select one slave; unmapped access errors |

## CLINT cases

| Register/behavior | Required checks |
| --- | --- |
| MSIP | set, clear, PSTRB masking, software IRQ output |
| MTIME | increment every clock, low/high access, 64-bit rollover |
| MTIMECMP | reset disabled value, low/high writes, threshold transition |
| Invalid address | PREADY completes and PSLVERR asserts |

## Trap cases

| Area | Required checks |
| --- | --- |
| Pending bits | IRQ inputs drive MIP.MSIP, MTIP and MEIP |
| Masking | MSTATUS.MIE and individual MIE bits both gate acceptance |
| Priority | MEI over MTI over MSI |
| Entry | backend drains, MEPC captures resume PC, MCAUSE interrupt bit/code |
| Status | MPIE receives MIE, MIE clears, MPP records machine mode |
| Vectoring | direct exceptions and vectored machine interrupts use MTVEC correctly |
| Return | MRET restores MIE from MPIE and redirects to MEPC |
| Precision | IRQ arrival during LSU/producer activity stalls new issue until idle |

## Regression entry points

- `make bus_irq_test`: compile and run the focused self-checking testbench.
- `make bus_irq_coverage`: run the same test with Verilator coverage output.
- `make coverage_all`: includes `bus_irq_coverage` before the merged report.
