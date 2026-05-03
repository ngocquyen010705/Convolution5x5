# DESIGN HARDWARE - Implementation Strategy

## 1. Hardware Architecture Summary
- Streaming RGB888 convolution pipeline with runtime kernel programmability.
- 5x5 line-buffered window generator feeding pipelined MAC datapath.
- AXI-Lite control plane for kernel update and status.
- AXI-Stream data plane for frame processing integration.

## 2. Dataflow
1. Input RGB stream enters line buffer.
2. 5x5 window + valid asserted after warm-up.
3. MAC pipeline computes per-channel convolution.
4. Shift by KERNEL_Q then saturate to 8-bit.
5. Output stream forwarded through wrapper buffer logic.

## 3. Timing-Critical Zones
- Product and adder tree depth in MAC datapath.
- valid/ready fanout and control coupling around wrapper.
- Long combinational cones across module boundaries.

## 4. Practical Hardening Actions
- Keep stage boundaries explicit and balanced in MAC arithmetic.
- Isolate handshake paths with register-slice/spill or skid buffering when needed.
- Avoid mixed control/data combinational dependencies across interfaces.
- Keep XDC constraints minimal, ordered, and reviewable.

## 5. AXI Hardening Checklist
- Randomized sink backpressure on stream output.
- Burst-like traffic behavior emulation for sustained valid toggling.
- AW/W ordering perturbation on AXI-Lite writes.
- Overflow and recovery semantics clearly defined and asserted.

## 6. Power Methodology
- Generate SAIF from realistic frame traffic.
- Verify SAIF hierarchy mapping and net-match ratio.
- Report total, dynamic, static and confidence category.
- Re-run after each timing optimization that alters toggle behavior.

## 7. Bring-Up Readiness Criteria
- Timing clean at selected board clock.
- Functional gates A-F satisfied.
- Documented runbook with one-command reproducibility.
- Fixed list of known limitations for demo transparency.

## 8. External Method References (Applied)
- AMD UltraFast methodology (UG949): staged methodology checks and early closure discipline.
- AMD design analysis (UG906): report-driven closure loops.
- AMD constraints methodology (UG903): constraint ordering and context correctness.
- AXI infrastructure guidance (PG085): buffering and stream path decoupling strategies.
- Open-source practice (verilog-axi, verilog-axis, wb2axip, pulp-platform/axi): skid/register-slice usage and randomized backpressure tests.
