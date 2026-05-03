# Vivado Pre-board Speed Sweep Summary

Command used:

```powershell
.\scripts\sweep_clock_with_saif.ps1 -PeriodsNs @(50.0,40.0,35.0,30.0,25.0) -FrameHex .\hex\test_frame_0.hex -Kernel gaussian5 -Width 640 -Height 480 -SaifOut .\sim\activity.saif
```

| Period (ns) | Freq (MHz) | WNS (ns) | TNS (ns) | Status | Power Confidence |
|---:|---:|---:|---:|---|---|
| 50.0 | 20.0 | 22.577 | 0.000 | PASS | Medium |
| 40.0 | 25.0 | 12.577 | 0.000 | PASS | Medium |
| 35.0 | 28.571 | 7.451 | 0.000 | PASS | Medium |
| 30.0 | 33.333 | 2.577 | 0.000 | PASS | Medium |
| 25.0 | 40.0 | -1.060 | -121.329 | FAIL | Medium |

Practical clean pre-board point: up to ~33.3 MHz.
