# rv64-ooo-core

RV64IM out-of-order core with full verification stack.

## Status
Seed: single-issue in-order RV64I core, boots and runs instructions in Verilator sim.
Everything below is roadmap, not yet built.

## Roadmap
1. RV64I in-order core (this seed)
2. Add M extension, C extension, Zicsr, M-mode CSRs/traps
3. 2-wide fetch/decode, gshare/TAGE + BTB + RAS
4. Rename + physical regfile, ROB, issue queues
5. LSQ with store-to-load forwarding, precise exceptions, mispredict recovery
6. Tiny Cache L1D (non-blocking, MSHRs) + L1I, AXI4 to memory
7. UVM env: Spike lockstep scoreboard, SVA, functional coverage, SymbiYosys formal
8. Verilator lint clean, riscv-arch-test, CoreMark/Embench IPC
9. C++ cycle-approximate model validated vs RTL
10. LibreLane/IHP sg13g2: synth, STA, gate-level regression, GDS
11. LLM regression triage + coverage-driven test gen agent

## Build
```
cd sim
make run
```
