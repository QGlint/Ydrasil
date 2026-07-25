# APB and Interrupt Verification Plan

## Scope

This plan verifies the path from the core memory request packet through
AXI4-Lite and the asynchronous AXI-to-APB bridge, plus the machine-mode
interrupt path used by RT-Thread. The FPU is outside this change and remains
covered by the existing FPU tests.

The production clock path is:

```text
CPU/AXI clock -> asynchronous AXI-to-APB bridge -> cnt_clk APB domain
cnt_clk CLINT/peripherals -> IRQ synchronizer -> CPU/AXI clock domain
```

AXI, APB, CDC, bridge, demultiplexer, and CLINT RTL are owned by
`ydrasil_utils`. Core RTL only consumes AXI and synchronized interrupt inputs.
The board-specific MMIO composition and display/counter devices remain under
`jyd_fpga`.

The core integration testbench compiles and instantiates those real
`jyd_fpga` MMIO/peripheral modules. It does not replace them with a behavioral
MMIO model, so changes to the production bridge, counter, display, or address
decode remain visible to the full regression.

## Bus cases

| Area | Required checks |
| --- | --- |
| AXI write | AW before W, W before AW, independent ready, held valid, B response |
| AXI read | AR handshake, held R response, returned data |
| APB protocol | setup then access, stable address/control, multi-cycle PREADY wait |
| Clock crossing | slower APB clock, non-aligned edges, one request/response per toggle |
| CDC payload | request payload remains stable until the APB response returns |
| CDC reset | both domains return idle without a phantom request or response |
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

## IRQ clock-domain cases

| Area | Required checks |
| --- | --- |
| Assertion | APB-domain software, timer, and external IRQs assert in the CPU domain after synchronizer latency |
| Deassertion | cleared APB-domain IRQs deassert in the CPU domain after synchronizer latency |
| Stability | no pulse is generated for an IRQ level that remains inactive |
| Reset | synchronized IRQ outputs are inactive throughout reset release |

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
