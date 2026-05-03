# Pre-board Verification Plan (Must Pass Before FPGA Bring-up)

## Scope
This checklist gates the project before loading bitstream on board.
Any FAIL blocks board bring-up.

## Gate A: RTL Functional Correctness
1. Run kernel regression (identity5, gaussian5, sharpen5, emboss5, laplacian5).
2. Verify each case has zero mismatch and zero unknown output sample.
3. Verify output sample count equals expected valid window count.

Commands:
```powershell
.\scripts\run_regression.ps1
```

Pass criteria:
- All kernels PASS.
- No X/Z at valid output cycles.

## Gate B: D455 Data-path Integrity
1. Capture stream from D455 and export `raw`, `feed_rgb`, `hex_in`.
2. Process `hex_in` by RTL simulation only (no software convolution).
3. Export `processed` and `hex_out` and check frame index alignment.

Commands:
```powershell
.\scripts\run_live_multi_kernel_demo.ps1 -CaptureRoot captures/d455/output_live -Width 640 -Height 480 -FeedWidth 320 -FeedHeight 240 -Frames 12 -Fps 30
```

Pass criteria:
- For each frame index, all artifacts exist:
  - raw image
  - feed_rgb image
  - processed image
  - hex_in
  - hex_out

## Gate C: Stress and Corner Cases
1. Reset mid-frame test.
2. Valid-gap test.
3. Saturation/overflow test with high-gain kernels.
4. Full-frame (640x480) test for multiple frames.

Pass criteria:
- Deterministic output, no protocol violation, no unknown states.

## Gate D: Timing and Resource
1. Run synth/impl at bring-up constraint.
2. Sweep to find highest timing-clean point.
3. Record WNS/TNS/utilization at each point.

Commands:
```powershell
.\scripts\sweep_clock_with_saif.ps1 -PeriodsNs @(30.0, 27.0, 25.0)
```

Pass criteria:
- Selected board clock target has WNS >= 0 and TNS = 0.
- Resource within acceptable envelope.

## Gate E: Power Confidence
1. Generate SAIF from D455 frame stream activity.
2. Run power report with SAIF annotation.
3. Confirm confidence level and net annotation ratio.

Commands:
```powershell
.\scripts\run_power_with_saif.ps1
```

Pass criteria:
- SAIF applied successfully.
- Confidence at least Medium for bring-up, target High for final signoff.

## Gate F: Interface/Integration Readiness
1. AXI stream wrapper handshake under backpressure.
2. AXI-lite kernel write/read behavior.
3. DMA-compatible framing assumptions documented.

Pass criteria:
- No data loss with randomized tready stalls.
- Register map and kernel update flow verified.

## Final Go/No-Go Rule
Go to board only when:
- Gate A to Gate D are PASS.
- Gate E is at least Medium with documented limitations.
- Gate F baseline tests PASS.
