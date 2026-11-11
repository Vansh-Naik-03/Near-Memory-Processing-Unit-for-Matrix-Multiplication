# Near-Memory Processing Unit (NMPU) for Matrix Multiplication

**Final Year Engineering Project | Semester 7 & 8**  
**Architecture:** Near-Memory Processing (NMP) Unit for Matrix Multiplication  
**Target ASIC Flow:** Cadence Genus (Synthesis) -> Cadence Innovus (P&R -> GDSII) -> Cadence Tempus (STA) -> Cadence Voltus (Power)

---

## 1. Directory & File Structure

```text
nmpu_matmul/
├── rtl/
│   ├── pe.v                 # Processing Element (Reg A, Reg B, Signed Multiplier, Adder, Accumulator Reg)
│   ├── accumulator_tree.v   # Balanced Binary Adder/Accumulator Tree
│   ├── pe_array.v           # Parallel PE Array Core with Vector Dot-Product Merging
│   ├── sram_bank.v          # Synchronous Near-Memory SRAM Bank (for SRAM A, B, and C)
│   ├── fsm_controller.v     # Autonomous NMPU FSM with (i, j, k) Address Generation
│   └── nmpu_top.v           # Top-Level NMPU Module (SRAM Banks + PE + FSM + Host Bus)
│
├── tb/
│   ├── tb_pe.v              # Unit testbench for Processing Element
│   ├── tb_accumulator_tree.v# Unit testbench for Accumulator Tree
│   ├── tb_pe_array.v        # Unit testbench for PE Array
│   ├── tb_sram_bank.v       # Unit testbench for SRAM Bank
│   ├── tb_fsm_controller.v  # Unit testbench for FSM Controller
│   └── tb_nmpu_top.v        # Full-System End-to-End Self-Checking Testbench
│
└── sim/
    ├── golden_model.py      # Python reference model generating signed matrices & hex vectors
    ├── verify_cycle_accurate.py # Bit-accurate & cycle-accurate hardware emulator
    ├── modelsim_run.do      # Automated simulation DO script for ModelSim / QuestaSim
    └── test_vectors/        # Generated hex test vectors ($readmemh compatible)
        ├── a_data.hex       # Input Matrix A (8-bit signed hex)
        ├── b_data.hex       # Input Matrix B (8-bit signed hex)
        └── c_expected.hex   # Golden Matrix C (24-bit signed hex)
```

---

## 2. Key Architecture Specifications

| Parameter | Specification | Hardware Rationale |
|:---|:---|:---|
| **Matrix Dimensions** | 4 x 4 (N = 4) | Scalable to 8x8, 16x16 via Verilog `parameter N` |
| **Input Data Precision** | 8-bit Signed Two's Complement | Dynamic range -128 to +127 |
| **Accumulator Precision** | 24-bit Signed Full Precision | Eliminates overflow: worst-case 4x4 dot-product sum |
| **Reset Convention** | `rst_n` (Active-Low Asynchronous) | Standard cell ASIC library convention |
| **Memory Architecture** | 3 Independent On-Chip SRAM Banks | SRAM A (input), SRAM B (input), SRAM C (output) |
| **Bus Elimination** | Zero External Bus Latency | Direct parallel data paths between SRAM and PEs |
| **Control Logic** | 5-State Autonomous FSM | No instruction fetch/decode/AXI overhead |
| **Total Latency** | 177 Clock Cycles (1.77 µs @ 100 MHz)| ~11 cycles per matrix element |

---

## 3. How to Run Verification

### A. Python Golden Model & Verification
```bash
cd sim
python golden_model.py
python verify_cycle_accurate.py
```

### B. ModelSim / QuestaSim Simulation
Launch ModelSim, change directory to `sim/`, and execute:
```tcl
do modelsim_run.do
```

### C. Individual Unit Tests
Compile and run any part individually:
- Processing Element: `vlog ../rtl/pe.v tb_pe.v` -> `vsim -c tb_pe -do "run -all; quit"`
- Accumulator Tree: `vlog ../rtl/accumulator_tree.v tb_accumulator_tree.v` -> `vsim -c tb_accumulator_tree -do "run -all; quit"`
- PE Array: `vlog ../rtl/pe.v ../rtl/accumulator_tree.v ../rtl/pe_array.v tb_pe_array.v` -> `vsim -c tb_pe_array -do "run -all; quit"`
- SRAM Bank: `vlog ../rtl/sram_bank.v tb_sram_bank.v` -> `vsim -c tb_sram_bank -do "run -all; quit"`
- FSM Controller: `vlog ../rtl/fsm_controller.v tb_fsm_controller.v` -> `vsim -c tb_fsm_controller -do "run -all; quit"`
- Full Top-Level: `vlog ../rtl/*.v tb_nmpu_top.v` -> `vsim -c tb_nmpu_top -do "run -all; quit"`
