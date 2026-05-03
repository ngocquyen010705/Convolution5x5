# Simulation Guide

## Dependencies
- Icarus Verilog (iverilog)
- GTKWave
- Python 3 + numpy

## Generate a 16x16 test frame
From workspace root:

```bash
python python/synthetic_frames.py --out hex --count 1 --width 16 --height 16
```

This creates `hex/test_frame_0.hex` used by `tb/tb_convolution.sv`.

## Baseline run
From workspace root:

```bash
.\scripts\run_sim.ps1
```

Outputs:
- `../sim/sim.vvp`
- `../sim/dump.vcd`
- `../sim/tb_out.hex`

For the current 16x16, KSIZE=5 testbench, `tb_out.hex` must contain exactly 144 lines.

## View waveform
```bash
gtkwave ../sim/dump.vcd
```

## Notes
- The current testbench is self-checking: PASS requires valid_count=144, mismatch=0, unknown=0.
- Use `docs/waveform_checklist.md` to determine if waveform behavior is correct.

## Prepare kernel + expected vectors
Before running simulation, generate files consumed by testbench:

```bash
python python/prepare_case.py --in_hex hex/test_frame_0.hex --width 16 --height 16 --kernel identity5 --kernel_out sim/kernel.hex --expected_out sim/expected.hex
```

Supported kernels: `identity5`, `gaussian5`, `sharpen5`, `emboss5`, `laplacian5`.

## Full regression (all kernels)
From workspace root:

```bash
.\\scripts\\run_regression.ps1
```

This runs all kernels, and saves per-case artifacts:
- `sim/tb_out_<kernel>.hex`
- `sim/expected_<kernel>.hex`
