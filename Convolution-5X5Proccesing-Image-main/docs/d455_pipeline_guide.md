# D455 Pipeline Guide

## Muc tieu
Huong dan chay Intel RealSense D455 stream lien tuc va xuat du lieu:
- Anh truoc xu ly (raw)
- Feed frame cho RTL (hex_in)
- Anh/hex sau xu ly duoc tao tu RTL simulation (processed, hex_out)

Luu y quan trong: Python KHONG lam convolution. Python chi capture/feed va goi RTL simulation.

## Script chinh
- python/d455_stream_process.py
- python/rtl_process_hex_frames.py
- scripts/run_live_multi_kernel_demo.ps1

## Chay nhanh 1 kernel
From workspace root:

```powershell
C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/d455_stream_process.py --width 640 --height 480 --fps 30 --feed_width 640 --feed_height 480 --duration_sec 3 --max_frames 1 --save_every 1 --out_dir captures/d455/smoke

C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/rtl_process_hex_frames.py --workspace . --in_dir captures/d455/smoke/hex_in --out_dir captures/d455/smoke --kernel gaussian5 --width 640 --height 480 --python_exe C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe
```

## Realtime multi-kernel (gaussian5 + sharpen5 + laplacian5)

Capture 1 lan tu D455, sau do xu ly va tao video preview cho tung kernel:

```powershell
.\scripts\run_live_multi_kernel_demo.ps1 -CaptureRoot captures/d455/output_live -Width 640 -Height 480 -FeedWidth 320 -FeedHeight 240 -Frames 12 -Fps 30
```

Mac dinh script se tu dong xoa folder trung gian va chi giu 1 output cuoi:
- `captures/d455/output_live/final/realtime_comparison_all_kernels.mp4`

Neu can giu file trung gian de debug:
```powershell
.\scripts\run_live_multi_kernel_demo.ps1 -CaptureRoot captures/d455/output_live -KeepIntermediates
```

Don dep generated files/log cu:
```powershell
.\scripts\clean_project_generated.ps1
```

Artifact chinh cho demo:
- `captures/d455/output_live/final/realtime_comparison_all_kernels.mp4`

## Benchmark N frame full 640x480 (sim/frame)
Vi du benchmark 2 frame tu camera va xuat report:

```powershell
C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/d455_stream_process.py --width 640 --height 480 --fps 30 --feed_width 640 --feed_height 480 --duration_sec 6 --max_frames 2 --save_every 1 --out_dir captures/d455/benchmark640

C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/rtl_process_hex_frames.py --workspace . --in_dir captures/d455/benchmark640/hex_in --out_dir captures/d455/benchmark640 --kernel gaussian5 --width 640 --height 480 --python_exe C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe
```

Report tao ra:
- captures/d455/benchmark640/rtl_benchmark_gaussian5.json
- captures/d455/benchmark640/rtl_benchmark_gaussian5.csv

## Thu muc output
Moi kernel co cau truc:
- captures/d455/<kernel>/raw
- captures/d455/<kernel>/feed_rgb
- captures/d455/<kernel>/processed
- captures/d455/<kernel>/hex_in
- captures/d455/<kernel>/hex_out

Voi luong Muc A, cung thu muc capture se co them:
- captures/d455/<capture>/preview_side_by_side.mp4
- captures/d455/<capture>/level_a_signoff.json
- captures/d455/<capture>/level_a_signoff.md

Ten file theo frame index, vi du:
- frame_000000.png
- frame_000010.png
- frame_000020.png

## Tieu chi pass can kiem
1. So file trong raw va processed phai bang nhau.
2. So file trong hex_in va hex_out phai bang nhau.
3. Cung frame index phai ton tai day du 4 file (raw/processed/hex_in/hex_out).
4. Sau khi chay xong pipeline, regression script bao 5/5 kernel PASS.

## Test case can thuc hien sau moi lan thay doi
1. identity5 regression
2. gaussian5 regression
3. sharpen5 regression
4. emboss5 regression
5. laplacian5 regression
6. D455 smoke stream 5s

## Luu y hieu nang
- Full 640x480 RTL simulation can be slow; this is expected in functional verification mode.
- Neu can fps cao hon:
  - giam so frame trong smoke test
  - dung on-board FPGA realtime path thay cho software simulation loop

## Tai lieu lien quan
- Pre-board verification gate: docs/pre_board_verification_plan.md
- Huong dan stream du lieu that tren board: docs/board_streaming_guide.md
- SAIF power flow: docs/saif_power_flow.md
