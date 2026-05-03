# RTL REPORT - Design Integrity and Verification

## 1. Core Modules
- line_buffer_4.sv: builds 5x5 window and valid gating.
- kernel_loader.sv: runtime kernel storage and write interface.
- mac_array_25x3.sv: pipelined MAC for RGB channels.
- top_convolution.sv: integration of window + kernel + MAC.
- axi_stream_conv_wrapper.sv: stream bridge and output buffering.
- axi_lite_kernel_ctrl.sv: register map and kernel write commit logic.

## 2. Key Fixes Landed
- AXI-Lite AW/W race handling corrected to support same-cycle and split transaction ordering.
- Fixed-point scaling aligned around KERNEL_Q=8 for correct gaussian brightness preservation.
- MAC pipeline upgraded for timing closure using staged products and balanced accumulation.

## 3. Pipeline Notes (Current)
- MAC now includes multi-stage internal datapath.
- Valid path includes additional internal delay stages versus early baseline.
- Architecture and waveform expectation documents must be read with current valid latency assumptions.

## 4. Regression Coverage (Current Mandatory Set)
- identity5: PASS.
- gaussian5: PASS.
- sharpen5: PASS.
- emboss5: PASS.
- laplacian5: PASS.

## 5. Outstanding Test Gaps
- reset-mid-frame robustness.
- randomized valid-gap / backpressure stress.
- saturation-heavy corner vectors.
- larger deterministic stress suites for long streams.

## 6. Interface Risk Summary
- AXI stream overflow signaling exists, but stress verification depth should be increased.
- AXI-Lite control path is stable for known write-order corner cases; additional randomized protocol checks are still recommended.

## 7. Evidence Pack to Include in Seminar
- Regression summary logs.
- One waveform snapshot per critical checklist item:
  - valid alignment.
  - center tap scaling check.
  - saturation behavior.
- Timing summary table (pass/fail by period).
