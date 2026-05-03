# Architecture_DSP — RGB 5×5 Convolution Engine: Full DSP Microarchitecture Reference

> **Project**: convolution_fpga  
> **Target**: Xilinx Zynq-7000 (xc7z020clg400-1)  
> **Revision**: 2026-04-23  
> **Verified**: 5/5 kernels PASS (identity5, gaussian5, sharpen5, emboss5, laplacian5)

---

## 1. System-Level Architecture

![Architecture Block Diagram](architecture_dsp_diagram.png)

### 1.1 Design Goal

A **streaming, runtime-programmable 5×5 RGB convolution engine** that processes one 24-bit RGB pixel per clock cycle. The design targets real-time image filtering for camera pipelines (Intel RealSense D455 → Zynq FPGA → processed output).

### 1.2 Top-Level Block Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        top_convolution.sv                          │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │ line_buffer_4 │──▶│              │──▶│    mac_array_25x3     │    │
│  │ (Window Gen)  │   │    5×5       │   │  (3-stage pipeline)   │    │
│  │              │   │   Window     │   │                      │    │
│  └──────┬───────┘   │   600-bit    │   │  S1: 25×3 Multiplies │    │
│         │           └──────────────┘   │  S2: Grouped Partial  │    │
│  pixel_in (24b)                        │      Sums (4 groups)  │    │
│  valid_in          ┌──────────────┐   │  S3: Merge + Shift    │    │
│                    │kernel_loader │──▶│      + Saturate       │    │
│                    │ (25 coeffs)  │   └──────────┬───────────┘    │
│                    └──────┬───────┘              │                │
│                           │               pixel_out (24b)         │
│                    wr_en/addr/data         valid_out               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────┐    ┌──────────────────────────────────┐
│ axi_lite_kernel_ctrl.sv  │───▶│  axi_stream_conv_wrapper.sv      │
│ (Register Map Control)   │    │  (AXI-S Input/Output Wrapper)    │
│ 0x00: CTRL               │    │  s_axis ──▶ core ──▶ m_axis     │
│ 0x04: KERNEL_ADDR        │    │  tready/tvalid flow control      │
│ 0x08: KERNEL_DATA        │    │  overflow_flag                    │
│ 0x0C: COMMIT             │    └──────────────────────────────────┘
│ 0x10: STATUS             │
└──────────────────────────┘
```

### 1.3 Key Design Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `IMAGE_WIDTH` | 640 (default) | Horizontal resolution for line buffer depth |
| `DATA_W` | 24 | RGB888 pixel width (8 bits per channel) |
| `COEFF_W` | 16 | Signed coefficient width (Q8.8 fixed-point) |
| `KSIZE` | 5 | Kernel dimension (5×5) |
| `KERNEL_Q` | 8 | Fractional bits for fixed-point normalization |
| `TAPS` | 25 | Total kernel coefficients (KSIZE²) |

---

## 2. Module-Level Microarchitecture

### 2.1 Line Buffer — `line_buffer_4.sv`

**Purpose**: Convert incoming raster-scan pixel stream into a sliding 5×5 window.

#### Architecture

```
               pixel_in (24b)
                    │
        ┌───────────▼───────────┐
        │   line0[0..W-1]       │  ← Current line BRAM (newest)
        │   line1[0..W-1]       │  ← 1 line delayed
        │   line2[0..W-1]       │  ← 2 lines delayed
        │   line3[0..W-1]       │  ← 3 lines delayed
        └───────────┬───────────┘
                    │ p0, p1, p2, p3 (read before write)
                    ▼
        ┌───────────────────────┐
        │  sr0[0..4] ◀── p3    │  ← Row 0 shift register (oldest)
        │  sr1[0..4] ◀── p2    │  ← Row 1 shift register
        │  sr2[0..4] ◀── p1    │  ← Row 2 shift register
        │  sr3[0..4] ◀── p0    │  ← Row 3 shift register
        │  sr4[0..4] ◀── pixel │  ← Row 4 shift register (newest)
        └───────────┬───────────┘
                    │
              window_flat (600-bit)
```

#### Storage Details

| Resource | Count | Width | Total Bits |
|----------|-------|-------|------------|
| Line BRAM | 4 | 24 × 640 | 61,440 |
| Shift Registers | 5 × 5 | 24 | 600 |
| Counters | 2 (x_count, y_count) | 16 | 32 |

#### Valid Logic

- `valid_out` asserts when `x_count >= 4` AND `y_count >= 4`
- This implements a **"valid-only" border policy** — no padding; first valid output at pixel position (4,4) in the input frame
- For an input frame of W×H, the output stream contains **(W−4) × (H−4)** valid pixels

#### Read-Before-Write Pattern

Lines 51–54 use **blocking assignments** inside the `always_ff` block to read `p0`–`p3` from the line BRAMs before the non-blocking writes update them. This ensures the read captures the previous value stored at `x_count`, enabling the 4-line delay chain to work correctly:

```systemverilog
p0 = line0[x_count];   // blocking read (old value)
p1 = line1[x_count];
p2 = line2[x_count];
p3 = line3[x_count];

line3[x_count] <= line2[x_count];  // non-blocking write (shift chain)
line2[x_count] <= line1[x_count];
line1[x_count] <= line0[x_count];
line0[x_count] <= pixel_in;        // newest pixel enters line0
```

#### Window Output Packing

The 5×5 window is packed into a flat vector `[DATA_W * KSIZE * KSIZE - 1 : 0]` = 600 bits:
- `window_flat[(row*5 + col)*24 +: 24]` = pixel at `(row, col)` in the window
- Row 0 (`sr0`) = oldest row (top of window)
- Row 4 (`sr4`) = newest row (bottom of window, current input line)

---

### 2.2 Kernel Loader — `kernel_loader.sv`

**Purpose**: Store and flatten 25 signed 16-bit coefficients for runtime programmability.

#### Architecture

```
    wr_en ──┐    wr_addr (5b) ──┐    wr_data (16b signed) ──┐
            │                    │                            │
            ▼                    ▼                            ▼
    ┌─────────────────────────────────────────────┐
    │  coeff_mem[0..24]  (25 × 16-bit signed)     │
    │                                               │
    │  Reset default: coeff_mem[12] = 1 <<< 8 = 256 │
    │  (All others = 0 → identity kernel)           │
    └──────────────────────┬──────────────────────┘
                           │
                    kernel_flat (400-bit)
```

#### Reset Behavior

On reset, the kernel defaults to **identity**: center tap `coeff_mem[12] = 256` (which is `1.0` in Q8 representation), all others zero. This ensures the system passes through pixels unmodified until a new kernel is loaded.

#### Coefficient Format

- **Signed Q8.8 fixed-point**: 8 integer bits + 8 fractional bits
- Range: −128.0 to +127.99609375
- Resolution: 1/256 ≈ 0.00390625

---

### 2.3 MAC Array — `mac_array_25x3.sv`

**Purpose**: Compute the convolution sum for all 3 RGB channels using a 3-stage pipelined datapath.

This is the **computational heart of the DSP engine**.

#### 6-Stage Optimized Pipeline Architecture

> **Optimization note**: The original 4-stage pipeline had a ~24.5 ns critical path that limited Fmax to 40 MHz. The redesigned 6-stage pipeline breaks both bottleneck paths (output stage AND reduction tree) down to ~8–12 ns each, targeting **100+ MHz**.

```
 STAGE 0 (Comb)        STAGE 1 (Reg)           STAGE 2 (Reg)          STAGE 3 (Reg)
 ┌─────────────┐      ┌────────────────┐      ┌────────────────┐     ┌────────────────┐
 │25 Multiplies│─reg─▶│ 8 Sub-Group    │─reg─▶│ 4 Group Merges │─reg▶│ 2-Way Lo/Hi   │
 │  per channel│      │ Partial Sums   │      │ (pair merges)  │     │ Merge          │
 │ 75 products │      │ 4+3,3+3,3+3,   │      │ grp[i] = sub_a │     │ half[0]=g0+g1 │
 │ 9b × 16b    │      │ 3+3 balanced   │      │       + sub_b  │     │ half[1]=g2+g3 │
 └─────────────┘      └────────────────┘      └────────────────┘     └────────────────┘

 STAGE 4 (Reg)                    STAGE 5 (Reg)
 ┌───────────────────────┐      ┌──────────────────────┐
 │ Final merge + shift   │─reg─▶│ Saturate + Pack      │
 │ acc = half0 + half1   │      │ sat_u8(nr) → [0,255] │
 │ nr = acc >>> KERNEL_Q │      │ pixel_out={b8,g8,r8} │
 └───────────────────────┘      └──────────────────────┘
```

#### Pipeline Timing

| Stage | Clock | Operation | Width | Max Comb Depth |
|-------|-------|-----------|-------|----------------|
| S0→S1 | comb→reg | 25 multiplies per channel (75 total) | 32-bit | 1 multiply (~3 ns via DSP48) |
| S1→S2 | comb→reg | 8 sub-group balanced sums (max 4 inputs) | 48-bit | 2 additions (~6–8 ns) |
| S2→S3 | comb→reg | 4 group pair merges (2 inputs each) | 48-bit | 1 addition (~4 ns) |
| S3→S4 | comb→reg | 2-way lo/hi merge (2 inputs each) | 48-bit | 1 addition (~4 ns) |
| S4→S5 | comb→reg | Final merge + arithmetic shift | 48-bit | 1 add + shift (~5 ns) |
| S5→S6 | comb→reg | Saturate (compare+mux) + pack | 48→8 bit | Comparison (~3 ns) |

**Total pipeline latency**: `valid_in` to `valid_out` = **6 clock cycles**
**Estimated max combinational path**: ~8 ns (Stage S1→S2) → **theoretical Fmax ~120 MHz**

#### Balanced Binary Reduction Tree

The 25 taps are first split into 8 sub-groups (balanced binary tree), then merged in pairs:

| Sub-Group | Taps | Count | Tree Depth |
|-----------|------|-------|------------|
| Sub 0a | [0, 1, 2, 3] | 4 | 2 additions |
| Sub 0b | [4, 5, 6] | 3 | 2 additions |
| Sub 1a | [7, 8, 9] | 3 | 2 additions |
| Sub 1b | [10, 11, 12] | 3 | 2 additions |
| Sub 2a | [13, 14, 15] | 3 | 2 additions |
| Sub 2b | [16, 17, 18] | 3 | 2 additions |
| Sub 3a | [19, 20, 21] | 3 | 2 additions |
| Sub 3b | [22, 23, 24] | 3 | 2 additions |

Then merged hierarchically:
- **Stage 3**: `grp[i] = sub_a[i] + sub_b[i]` → 4 group results (1 add each)
- **Stage 4**: `half[0] = grp[0] + grp[1]`, `half[1] = grp[2] + grp[3]` (1 add each)
- **Stage 5**: `acc = half[0] + half[1]` + normalize (1 add + shift)

This balanced tree ensures max combinational depth per stage is **2 additions** (~6–8 ns), well within 10 ns target for 100 MHz.

#### Channel Extraction

```systemverilog
px_r = window_flat[(i * 24) +: 8];        // bits [7:0]   of pixel i
px_g = window_flat[(i * 24) + 8 +: 8];    // bits [15:8]  of pixel i
px_b = window_flat[(i * 24) + 16 +: 8];   // bits [23:16] of pixel i
```

> **Note**: The variable names `px_r`/`px_g`/`px_b` correspond to bit positions, not necessarily R/G/B in the image domain. However, because the golden model and the testbench both interpret the hex format consistently (byte 0 = bits[7:0], byte 1 = bits[15:8], byte 2 = bits[23:16]), the computation is **functionally correct** regardless of channel naming.

#### Saturation Logic

```systemverilog
function automatic [7:0] sat_u8(input logic signed [47:0] val);
    if (val < 0)       sat_u8 = 8'd0;
    else if (val > 255) sat_u8 = 8'd255;
    else                sat_u8 = val[7:0];
endfunction
```

This clamps each channel to the unsigned [0, 255] range after the arithmetic right shift, preventing wrap-around artifacts visible as bright speckles on dark backgrounds.

---

### 2.4 Top Convolution — `top_convolution.sv`

**Purpose**: Integration wrapper connecting the three core modules.

```
                      kernel_wr_en/addr/data
                              │
                    ┌─────────▼─────────┐
                    │   kernel_loader    │
                    │   (25 × 16b)      │
                    └─────────┬─────────┘
                              │ kernel_flat (400b)
                              │
   in_valid ──┐     ┌─────────▼─────────┐
   in_pixel ──┼────▶│   line_buffer_4   │
              │     │   (4-line + 5×SR) │
              │     └─────────┬─────────┘
              │               │ window_flat (600b), lb_valid
              │     ┌─────────▼─────────┐
              │     │   mac_array_25x3  │──▶ out_valid
              │     │   (3-ch pipeline) │──▶ out_pixel (24b)
              │     └───────────────────┘
              │
         clk, rst
```

**Parameters propagated**: IMAGE_WIDTH, DATA_W, COEFF_W, KSIZE, KERNEL_Q

---

### 2.5 AXI-Stream Wrapper — `axi_stream_conv_wrapper.sv`

**Purpose**: Wraps the convolution core with AXI4-Stream input/output interfaces.

#### Flow Control

```
s_axis_tready = (~out_buf_valid) | m_axis_tready
```

This is a **conservative back-pressure scheme**:
- Accept new input if the output buffer is empty OR the downstream sink is ready
- Prevents data loss by stalling the input when output cannot drain

#### Overflow Protection

If the core emits `core_out_valid` but the output buffer is full AND the sink is not ready, the `overflow_flag` latches high. This is a **sticky error flag** that persists until reset, enabling system-level error detection.

#### Signal Mapping

| AXI-Stream Signal | Internal Signal |
|---|---|
| `s_axis_tvalid & s_axis_tready` | `in_valid` to core |
| `s_axis_tdata` | `in_pixel` to core |
| `m_axis_tvalid` | `out_buf_valid` |
| `m_axis_tdata` | `out_buf_data` |

---

### 2.6 AXI-Lite Kernel Control — `axi_lite_kernel_ctrl.sv`

**Purpose**: Runtime kernel coefficient programming via AXI4-Lite register writes.

#### Register Map

| Offset | Name | Width | Access | Description |
|--------|------|-------|--------|-------------|
| 0x00 | CTRL | 32 | RW | Control register (reserved) |
| 0x04 | KERNEL_ADDR | 32 | WO | Coefficient index [4:0] (0–24) |
| 0x08 | KERNEL_DATA | 32 | WO | Coefficient value [15:0] (signed Q8.8) |
| 0x0C | COMMIT | 32 | WO | Write bit[0]=1 to commit coefficient |
| 0x10 | STATUS | 32 | RO | bit[0] = overflow_flag from wrapper |

#### Write Transaction Protocol

1. Write coefficient index to `0x04`
2. Write coefficient value to `0x08`
3. Write `0x01` to `0x0C` → generates single-cycle `kernel_wr_en` pulse

The controller handles both **same-cycle AW+W** and **split AW/W** transactions by latching the write address when `s_axil_awvalid` arrives and using it when `s_axil_wvalid` follows.

#### Bounds Check

Addresses beyond the valid range (≥25) are silently ignored:
```systemverilog
if (s_axil_wdata[7:0] < TAPS) begin
    kernel_wr_addr <= s_axil_wdata[$clog2(KSIZE*KSIZE)-1:0];
end
```

---

## 3. Fixed-Point Numeric System

### 3.1 Number Representation

| Signal | Format | Bits | Range |
|--------|--------|------|-------|
| Pixel channel | Unsigned integer | 8 | [0, 255] |
| Coefficient | Signed Q8.8 | 16 | [−128.0, +127.996] |
| Product | Signed | 32 | [−32,640, +32,513] |
| Partial accumulator | Signed | 48 | ±2⁴⁷ (overflow-safe) |
| Normalized result | Signed | 48 | After `>>>8` shift |
| Output channel | Unsigned (saturated) | 8 | [0, 255] |

### 3.2 Accumulator Sizing Proof

Worst-case accumulation: all 25 taps at maximum magnitude.

```
max_product = 255 × 127 = 32,385  (positive)
min_product = 255 × (−128) = −32,640  (negative)

max_acc = 25 × 32,385 = 809,625     → fits in 20 bits unsigned
min_acc = 25 × (−32,640) = −816,000  → fits in 21 bits signed

48-bit accumulator capacity: ±140,737,488,355,327
Margin: >170 million × headroom
```

The 48-bit accumulator is vastly oversized for this application but aligns with Xilinx DSP48E1 native precision, avoiding any truncation logic.

### 3.3 Normalization: Arithmetic Right Shift

```systemverilog
nr = acc_r >>> KERNEL_Q;   // arithmetic (sign-extending) right shift by 8
```

Using `>>>` (arithmetic shift) instead of `>>` (logical shift) preserves the sign bit for kernels that produce negative intermediate results (e.g., Laplacian, Sharpen). The subsequent `sat_u8()` clamps negative results to 0.

### 3.4 Kernel Coefficient Design Rules

| Kernel Type | Sum of Coefficients | Q8 Scaling | Expected Output |
|-------------|-------------------|------------|-----------------|
| Identity | 256 | ×1.0 | Pixel passthrough |
| Gaussian (blur) | 256 | ×1.0 | Smooth, same brightness |
| Sharpen | 0 (approx) | N/A | Edges enhanced |
| Laplacian (edge) | 0 | N/A | Edge map (mostly dark) |
| Emboss | 0 (approx) | N/A | Relief effect |

**Rule**: For brightness-preserving kernels, coefficient sum must equal `2^KERNEL_Q = 256`.

---

## 4. Xilinx DSP48E1 Mapping Strategy

### 4.1 DSP48E1 Primitive Overview

The Zynq-7020 contains **220 DSP48E1 slices**, each providing:
- 25×18 multiplier → 48-bit product
- 48-bit accumulator with cascade chain
- Pre-adder for coefficient optimization

### 4.2 Resource Mapping

Each `pixel_channel × coefficient` multiply maps to one DSP48E1:

| Per Channel | DSP Slices | Notes |
|-------------|-----------|-------|
| 25 multiplies | 25 | 9-bit unsigned × 16-bit signed fits 25×18 |
| 3 channels | × 3 | R, G, B independent |
| **Total** | **75** | 34.1% of xc7z020 capacity |

Actual synthesis result: **78 DSP slices** (minor overhead from synthesis tool inference).

### 4.3 Reduction Tree (CLB Logic)

The grouped partial sums and final merge stages use CLB fabric (LUTs + FFs) rather than DSP cascade chains, because:
1. The 4-group reduction pattern doesn't align with DSP48E1 cascade topology
2. 48-bit additions in CLB logic are fast enough at the target frequency (40 MHz)
3. This leaves DSP cascade chains available for future pipeline extensions

### 4.4 Synthesis Results Summary (Pre-Optimization @ 40 MHz)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUT | 930 | 53,200 | 1.75% |
| FF | 203 | 106,400 | 0.19% |
| DSP48E1 | 78 | 220 | 35.45% |
| BRAM (18Kb) | 1 | 140 | 0.71% |

### 4.5 Timing History

#### Before Optimization (4-stage pipeline)

| Clock Target | Period | WNS | TNS | Status |
|-------------|--------|-----|-----|--------|
| 40 MHz | 25.000 ns | +0.460 ns | 0.000 ns | ✅ PASS |
| 50 MHz | 20.000 ns | −4.540 ns | −653.446 ns | ❌ FAIL |
| 60 MHz | 16.667 ns | −7.873 ns | −1133.350 ns | ❌ FAIL |

**Critical path**: ~24.5 ns — combinational cone spanning 7-input adder tree AND output merge+shift+saturate.

#### After Optimization (6-stage pipeline)

| Clock Target | Period | WNS | TNS | Status |
|-------------|--------|-----|-----|--------|
| 100 MHz | 10.000 ns | +1.228 ns | 0.000 ns | ✅ PASS |

| Resource | Actual | Notes |
|----------|-----------|-------|
| FF | ~491 (+288) | 0.46% utilization — still very low |
| LUT | ~930 | Unchanged (same logic, just re-partitioned) |
| DSP48E1 | 78 | Unchanged |
| **Max comb path** | **~8.7 ns** | **Inferred from WNS +1.228ns @ 10ns** |
| **Target Fmax** | **100+ MHz** | **Vivado post-route confirmed** |

**Actual timing at 100 MHz (10 ns period)**: WNS = +1.228 ns (comfortable margin).

---

## 5. Pipeline Timing Diagram

```
Clock     │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │ 7  │ 8  │ 9  │ 10 │ ...
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_in  │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ...
pixel_in  │ P0 │ P1 │ P2 │ P3 │ P4 │ P5 │ P6 │ P7 │ P8 │ P9 │ ...
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
lb_valid  │    │    │    │    │ ██ │ ██ │ ██ │ ██ │ ██ │ ██ │ ...
          │    │    │    │    │(after warm-up)
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_s1  │    │    │    │    │    │ ██ │ ██ │ ██ │ ██ │ ██ │ ...
(multiply)│    │    │    │    │    │    │    │    │    │    │
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_s2  │    │    │    │    │    │    │ ██ │ ██ │ ██ │ ██ │ ...
(sub-grps)│    │    │    │    │    │    │    │    │    │    │
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_s3  │    │    │    │    │    │    │    │ ██ │ ██ │ ██ │ ...
(grp merge)│   │    │    │    │    │    │    │    │    │    │
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_s4  │    │    │    │    │    │    │    │    │ ██ │ ██ │ ...
(lo/hi)   │    │    │    │    │    │    │    │    │    │    │
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_s5  │    │    │    │    │    │    │    │    │    │ ██ │ ...
(norm)    │    │    │    │    │    │    │    │    │    │    │
──────────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────
valid_out │    │    │    │    │    │    │    │    │    │    │ ██
pixel_out │    │    │    │    │    │    │    │    │    │    │ Q0
          │    │    │    │    │    │    │    │    │    │    │
          │◀───────────── 6-cycle MAC pipeline ────────────▶│
```

**Throughput**: 1 pixel/clock sustained (after warm-up) — unchanged  
**Latency**: 6 clock cycles from `valid_in` to `valid_out` in MAC (was 4)  
**Warm-up**: (KSIZE−1) lines × IMAGE_WIDTH + (KSIZE−1) pixels = 4×640 + 4 = 2564 cycles  
**Max combinational depth per stage**: 2 additions (~8 ns) — **down from ~24.5 ns**

---

## 6. Verification Methodology

### 6.1 Golden Model (`python/prepare_case.py`)

The golden model computes the expected output using identical fixed-point arithmetic:

```python
acc[ch] = sum(window_pixel[r,c,ch] * kernel[r,c]) for all (r,c) in 5×5
result[ch] = clamp(acc[ch] >> KERNEL_Q, 0, 255)
```

Key property: the golden model uses Python `int` arithmetic (arbitrary precision), matches RTL 48-bit accumulation exactly.

### 6.2 Self-Checking Testbench (`tb/tb_convolution.sv`)

The testbench:
1. Loads input frame from `hex/test_frame_0.hex`
2. Loads expected output from `sim/expected.hex`
3. Loads kernel coefficients from `sim/kernel.hex`
4. Streams pixels through DUT one per clock
5. Compares each `out_valid`+`out_pixel` against expected
6. Reports: `valid_count`, `mismatch_count`, `unknown_count` (X/Z detection)

**Pass criteria**: `valid_count == (W−4)×(H−4)`, `mismatch_count == 0`, `unknown_count == 0`

### 6.3 Regression Test Matrix

| Kernel | Coefficients Sum | Test Size | Expected Outputs | Status |
|--------|-----------------|-----------|-----------------|--------|
| identity5 | 256 | 16×16 | 144 | ✅ PASS |
| gaussian5 | 256 | 16×16 | 144 | ✅ PASS |
| sharpen5 | 0 | 16×16 | 144 | ✅ PASS |
| emboss5 | ~0 | 16×16 | 144 | ✅ PASS |
| laplacian5 | 0 | 16×16 | 144 | ✅ PASS |

### 6.4 Manual Arithmetic Verification

**Identity kernel at pixel (4,4)**:
- Window center = `frame[2,2]` = `[2, 2, 1]`
- `acc = [2×256, 2×256, 1×256] = [512, 512, 256]`
- `>>8 = [2, 2, 1]`
- Output = `020201` ✅ (matches RTL)

**Sharpen kernel at pixel (4,4)**:
- Accumulation across all 25 taps with sharpen coefficients
- `acc = [0, 0, -48]`
- `>>8 = [0, 0, -1]`
- `clamp(-1, 0, 255) = 0`
- Output = `000000` ✅ (matches RTL)

---

## 7. AXI Interface Specifications

### 7.1 AXI4-Stream Data Path

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `s_axis_tvalid` | Input | 1 | Input data valid |
| `s_axis_tready` | Output | 1 | Ready to accept |
| `s_axis_tdata` | Input | 24 | RGB pixel data |
| `m_axis_tvalid` | Output | 1 | Output data valid |
| `m_axis_tready` | Input | 1 | Downstream ready |
| `m_axis_tdata` | Output | 24 | Filtered pixel data |

### 7.2 AXI4-Lite Control Plane

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `s_axil_awaddr` | Input | 6 | Write address |
| `s_axil_awvalid` | Input | 1 | Write address valid |
| `s_axil_awready` | Output | 1 | Always 1 |
| `s_axil_wdata` | Input | 32 | Write data |
| `s_axil_wstrb` | Input | 4 | Byte strobes (unused) |
| `s_axil_wvalid` | Input | 1 | Write data valid |
| `s_axil_wready` | Output | 1 | Always 1 |
| `s_axil_bresp` | Output | 2 | Always OKAY |
| `s_axil_bvalid` | Output | 1 | Write response valid |
| `s_axil_bready` | Input | 1 | Response accepted |
| `s_axil_araddr` | Input | 6 | Read address |
| `s_axil_arvalid` | Input | 1 | Read address valid |
| `s_axil_arready` | Output | 1 | Always 1 |
| `s_axil_rdata` | Output | 32 | Read data |
| `s_axil_rresp` | Output | 2 | Always OKAY |
| `s_axil_rvalid` | Output | 1 | Read data valid |
| `s_axil_rready` | Input | 1 | Read accepted |

---

## 8. Power Analysis

### 8.1 SAIF-Based Methodology

Power estimation uses Switching Activity Interchange Format (SAIF) generated from RTL simulation with realistic frame data (640×480 Gaussian-filtered frames from D455 camera).

### 8.2 Power Results (40 MHz, Post-Route)

| Category | Power (W) |
|----------|-----------|
| Dynamic | 0.022 |
| Static (quiescent) | 0.105 |
| **Total** | **0.127** |

### 8.3 Confidence Level

Current confidence: **Medium** (SAIF net match ratio ~0% due to hierarchy mapping; needs improvement with `set_switching_activity` fallback).

---

## 9. Known Limitations & Future Work

### 9.1 Current Limitations

1. **Max verified clock**: 100 MHz (10.0 ns period). WNS = +1.228 ns.
2. **No padding mode**: Border pixels are dropped (valid-only policy).
3. **Single-pixel throughput**: No spatial parallelism across multiple pixels per clock.
4. **Fixed kernel size**: Hardcoded 5×5; no runtime kernel size selection.
5. **No TLAST support**: AXI-Stream wrapper lacks frame boundary signaling.

### 9.2 Optimization Paths

| Improvement | Impact | Effort |
|-------------|--------|--------|
| Register-slice on MAC output cone | +10–20 MHz Fmax | Low |
| DSP48E1 cascade chain for reduction | −20% LUT, +Fmax | Medium |
| Dual-pixel-per-clock datapath | 2× throughput | High |
| Configurable kernel size (3×3/5×5/7×7) | Flexibility | High |
| Zero-padding border mode | Full-size output | Medium |
| TLAST frame boundary support | DMA compatibility | Low |

---

## 10. File Inventory

### 10.1 RTL Source (`src/`)

| File | Lines | Purpose |
|------|-------|---------|
| `top_convolution.sv` | 65 | Top integration module |
| `line_buffer_4.sv` | 99 | 5×5 window generator |
| `kernel_loader.sv` | 37 | Runtime coefficient storage |
| `mac_array_25x3.sv` | 237 | 3-channel pipelined MAC |
| `axi_stream_conv_wrapper.sv` | 85 | AXI-Stream wrapper |
| `axi_lite_kernel_ctrl.sv` | 128 | AXI-Lite control |
| `defines.sv` | 10 | Global defines |

### 10.2 Testbench (`tb/`)

| File | Purpose |
|------|---------|
| `tb_convolution.sv` | Self-checking regression testbench |
| `tb_axi_stream_conv_wrapper.sv` | AXI wrapper functional test |
| `tb_activity_saif.sv` | SAIF power activity capture |

### 10.3 Python Utilities (`python/`)

| File | Purpose |
|------|---------|
| `prepare_case.py` | Generate kernel.hex + expected.hex |
| `golden_model.py` | Reference convolution with PSNR |
| `synthetic_frames.py` | Generate deterministic test frames |
| `d455_stream_process.py` | D455 camera capture pipeline |
| `rtl_process_hex_frames.py` | Batch RTL simulation processing |
| `benchmark_campaign.py` | Multi-kernel benchmark orchestration |
| `build_side_by_side_video.py` | Input/output comparison video |
| `build_multi_kernel_comparison_video.py` | Multi-kernel comparison video |
| `signoff_level_a.py` | Level-A verification signoff |
| `generate_architecture_ppt.py` | Architecture slide deck |
