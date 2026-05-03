# Performance - Current Baseline and Roadmap

## 1. Current Measured Status
- Regression status: PASS for identity5, gaussian5, sharpen5, emboss5, laplacian5.
- Timing closure status:
  - 40.000 MHz (25.000 ns): PASS.
  - 50.000 MHz (20.000 ns): FAIL.
  - 59.999 MHz (16.667 ns): FAIL.
- Power flow status: SAIF-based flow available; confidence must be improved by better activity matching.

## 2. Reproducible Benchmark Principle
Always benchmark using stable captured input frames under captures/benchmark instead of mutable smoke/regression frame files.

## 3. Recommended Benchmark Matrix
- Resolutions: 160x120, 320x240, 640x480.
- Kernels: gaussian5, sharpen5, laplacian5 (optionally identity5 as sanity reference).
- Metrics:
  - Functional: mismatch_count, unknown_count, valid_count.
  - Timing: WNS/TNS/Fmax-equivalent pass point.
  - Throughput proxy: frames/s and MP/s.
  - Power: total, dynamic, static with SAIF confidence.

## 4. SW vs HW Comparison Plan
- SW baseline:
  - Python OpenCV or NumPy 5x5 convolution on same frame set.
- HW/RTL baseline:
  - Existing RTL simulation flow with identical inputs and kernels.
- Output:
  - CSV and markdown table with speedup and quality parity checks.

## 5. Next Optimization Priority
1. Interface hardening first (Gate F), because unstable AXI behavior invalidates benchmark trust.
2. SAIF confidence uplift (activity match and realistic stimulus).
3. Timing stretch beyond 40 MHz using targeted critical path reduction.

## 6. Timing Closure Methods (Research-Backed)
- AMD UltraFast flow focus:
  - Run methodology checks early and at each phase.
  - Keep constraints clean and ordered.
  - Apply physically-aware optimization only after clean functional/timing context.
- Datapath tactics:
  - Maintain balanced adder trees and short fanout on valid/control.
  - Keep register boundaries near high-fanout cones.

## 7. AXI Throughput/Backpressure Methods (Research-Backed)
- Use register-slice/skid-buffer strategy on long or high-fanout handshake paths.
- Add bounded buffering around stream boundaries where sink stall can occur.
- Validate with randomized backpressure scenarios, not only deterministic tests.

## 8. Definition of Done for Performance Signoff
- 40 MHz remains clean across reproducible reruns.
- At least one higher point (>=45 MHz or 50 MHz) demonstrates stable trend or closure.
- SAIF confidence >= Medium with explainable stimulus coverage.
- No functional regression across full kernel set.
