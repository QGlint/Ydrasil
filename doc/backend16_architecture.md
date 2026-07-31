# Ydrasil 16-entry dual-issue backend

## Goals

- RV32IM/Zicsr/Zifencei, 64-bit fetch, two decode, two dispatch, two issue,
  and two in-order retire.
- A 16-entry out-of-order window for the first FPGA implementation.  Window
  depth is a package parameter so 32 and 48 entries can be evaluated later
  without changing module contracts.
- Preserve or improve IPC relative to the pre-refactor 0.7 IPC baseline while
  closing 200 MHz on xc7k325t-2.
- No combinational fetch-count to issue-slot path, completion to current-cycle
  select path, or selected-slot to frontend-ready path.

## Pipeline

```text
F0/F1  fetch request and dual-word response
F2     fetch queue
D0     dual decode
R0     rename, ROB allocation, architectural RF snapshot
Q0     banked issue enqueue and event wakeup
Q1     registered bank select and operand read
E0     ALU0/ALU1, BRU, AGU, MUL/DIV/CSR
W0     tagged completion and local bypass
C0     two-wide in-order retirement
```

Latency and throughput are separated.  R0 and Q0 are elastic; they may add
latency to an isolated instruction but do not reduce two-wide throughput.
Single-cycle ALU results provide a tagged E0-to-Q1 bypass for dependent chains.

## Modules

### `ydrasil_rename_rob`

- Owns the 16-entry ROB, speculative RAT, result-ready bitmap, result value
  array, allocation tags, retirement, and branch recovery.
- A source is represented by `{used, tag_valid, physical_tag}`.  Destination
  tags are ROB/physical slots with an epoch bit.
- All completion lanes write one value array.  Result class is execution
  metadata, not a separate value store.
- Commit clears a RAT entry only when it still names the retiring tag.
- Mispredict keeps entries through the resolved branch and rebuilds the RAT
  from surviving ROB entries.  This removes four wide RAT snapshots and their
  dispatch/redirect fanout.
- Reset applies to valid/ready/pointer state.  Payload arrays are not reset.

### `ydrasil_issue_window`

- 16 entries arranged as four banks of four slots.  Dispatch lane 0 and lane 1
  use separate bank candidates, so two inserts never share a write port.
- Slot scheduling metadata is stored separately from execution payload.
- Each operand has a ready bit and a physical tag.  Registered completion
  events update ready/value state; no completion data drives the current-cycle
  selector.
- An epoch-checked architectural-RF fallback covers the dispatch/completion
  boundary: if a producer has already retired before its one-cycle event was
  observed by a newly allocated entry, the entry reads the committed value
  through its ordinary RF port.  This is not a CAM or a result crossbar.
- Each bank produces one local oldest-ready candidate.  A second registered
  arbitration level chooses at most two compatible execution ports.
- Selection consumes registered credits.  Reclaimed slots update next-cycle
  credits and cannot feed frontend ready in the same cycle.
- Serial, CSR, SYSTEM, fence and control-flow operations issue only at ROB head.

### `ydrasil_backend`

- Connects decode packets, architectural RF read data, rename/ROB, issue,
  completion, branch recovery and commit.
- Exposes only elastic ready/valid channels to frontend and execution.
- Owns dispatch pairing rules and completion-event registration.

### Execution and LSU

- Lane 0 supports ALU/shift/branch/LSU/MUL/DIV/CSR/SYSTEM.
- Lane 1 supports ALU/shift and branch where resource conflicts permit.
- The LSU request queue and store buffer are both eight entries.  Request and
  store payload RAMs have no asynchronous reset; only pointers and valid/count
  state reset.
- Store-to-load forwarding stays local to the LSU and is not an issue selector
  input.
- MMIO has one non-cancellable request state and retires only after its AXI
  response.  Its response latency is unconstrained; DTCM responses retain the
  fixed one-cycle metadata path.

## Recovery and precise state

- Retirement is always in ROB order, at most two adjacent entries per cycle.
- Exceptions and interrupts flush all speculative backend state.
- A branch redirect invalidates only younger ROB and issue entries by tag age.
- Stores are issued only when non-speculative (the corresponding ROB entry is
  at the head), preserving precise memory state without a speculative store
  rollback path in this first 16-entry implementation.

## Timing ownership

| Path | Register boundary |
| --- | --- |
| fetch/decode to backend | decode skid register |
| rename/RAT to issue | renamed dispatch register |
| slot wakeup to select | registered ready bitmap |
| local select to execute | registered issue/execute packet |
| completion to consumers | registered event plus ALU bypass tag |
| redirect to RAT rebuild | recovery register |
| LSU to issue capacity | registered LSU credit/status |

## Verification gates

1. Verilator compile and directed boundary/ISA tests.
2. CoreMark and `coe_loop5`; IPC must not regress below 0.70.
3. `make coverage_quick`.
4. `make coverage_all`.
5. `make synf`; use the generated deduplicated timing groups to inspect all
   remaining path families, not only WNS.
