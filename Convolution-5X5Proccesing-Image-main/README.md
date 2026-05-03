# Streaming RGB 5x5 Convolution Engine (100MHz / Full HD)

A high-performance, parameterizable 5x5 RGB Convolution IP core designed for FPGAs (specifically targetted for Zynq-7020). This engine utilizes a **6-stage balanced pipeline architecture** to achieve a **100MHz** clock frequency, enabling real-time processing of **Full HD (1080p)** video streams.

![Hardware Architecture](./docs/architecture_latex_sample.png)

## Key Features

- **100MHz Fmax:** Achieved on Zynq-7020 through deep pipelining (WNS: +1.049ns).
- **Full HD Support:** Parameterizable `IMAGE_WIDTH` supports 1920x1080 and beyond.
- **6-Stage MAC Pipeline:** Balanced adder tree for low-latency, high-speed computation.
- **AXI-Stream Interface:** 24-bit RGB input/output for easy system integration.
- **AXI-Lite Control:** Dynamic kernel coefficient loading and status monitoring.
- **Saturating Arithmetic:** Fixed-point logic (Q8 default) with saturation clamping [0-255].
- **Multi-Channel Processing:** R, G, and B channels processed in parallel.

## Tech Stack

- **HDL:** SystemVerilog
- **FPGA Toolchain:** Vivado 2023.2
- **Target Device:** Xilinx Zynq-7020 (xc7z020clg400-1)
- **Verification:** Icarus Verilog, Vivado XSim
- **Documentation:** LaTeX (TikZ), Mermaid.js

## Performance Metrics

| Metric | Result |
| :--- | :--- |
| **Clock Frequency** | 100 MHz |
| **Throughput** | 100 Million Pixels/sec |
| **WNS (Worst Negative Slack)** | +1.049 ns |
| **WHS (Worst Hold Slack)** | +0.049 ns |
| **Latency** | 6 Cycles (MAC) + 2 Cycles (LB) |
| **Utilization (Zynq-7020)** | ~5% LUTs, 4 BRAM Tiles (at 1920 width) |

## Project Structure

```text
├── src/                # Optimized SystemVerilog RTL modules
│   ├── top_convolution.sv  # Top-level wrapper
│   ├── mac_array_25x3.sv   # 6-stage 5x5 MAC pipeline
│   ├── line_buffer_4.sv    # BRAM-based line storage
│   └── kernel_loader.sv    # AXI-Lite kernel management
├── tb/                 # Verification testbenches
├── scripts/            # PowerShell automation (Sim, Vivado Sweep, Benchmarks)
├── docs/               # Technical reports, Architecture diagrams (LaTeX/PDF)
└── captures/           # Verification outputs (Processed images, CSV reports)
```

## Getting Started

### 1. Prerequisites

- **Vivado 2023.2** (or newer)
- **Icarus Verilog** (for quick simulation)
- **PowerShell 7.0+** (for running scripts)

### 2. Run Functional Simulation

To verify the arithmetic correctness against the Python golden model for all 5 standard kernels (Gaussian, Sharpen, etc.):

```powershell
.\scripts\run_regression.ps1
```

### 3. Run Vivado Synthesis & Timing Closure

To verify timing closure at 100MHz for Full HD resolution:

```powershell
# Set IMAGE_WIDTH=1920 in src/top_convolution.sv
# Then run the synthesis script
E:\Vivado\2023.2\bin\vivado.bat -mode batch -source vivado_project/run_synth.tcl
```

## Architecture Details

The system is organized into three primary layers:

1.  **Line Buffer:** Stores 4 lines of incoming pixels using BRAM to provide a sliding 5x5 window to the processor.
2.  **Kernel Loader:** An AXI-Lite interface allows the host CPU to dynamically update the 25 coefficients (16-bit signed).
3.  **MAC Array (6-Stage):**
    -   **Stage 1:** 25 Parallel Multipliers (16-bit x 8-bit).
    -   **Stage 2-4:** Balanced Adder Tree for Sub-group sums.
    -   **Stage 5:** Channel Merge and Normalization (Right Shift).
    -   **Stage 6:** Saturation clamping to 8-bit unsigned.

## Verification Results

The design has been verified using a regression suite of 5 kernels. All tests returned a `PASS` status, confirming bit-exact matching between RTL and the software reference.

| Kernel Name | Status | Power (W) |
| :--- | :--- | :--- |
| Identity | PASS | 0.082 |
| Gaussian 5x5 | PASS | 0.088 |
| Sharpen 5x5 | PASS | 0.091 |
| Emboss 5x5 | PASS | 0.089 |
| Laplacian 5x5 | PASS | 0.092 |

---

## Technical Report

For a detailed breakdown of the mathematical model, pipeline stages, and implementation results, see the [Final Technical Report (PDF)](./docs/Report_Convolution_FPGA.pdf).
