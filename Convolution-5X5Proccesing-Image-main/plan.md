# PLAN CHI TIET DO AN: RGB 5x5 CONVOLUTION ENGINE (ZYNQ + D455)

## 1. Muc tieu va pham vi
- Xay dung pipeline 5x5 RGB convolution co kernel nap runtime.
- Hoan tat luong: camera Intel RealSense D455 -> stream du lieu -> xu ly -> xuat anh truoc/sau.
- Duy tri bo test regression cho RTL va doi chieu output.
- Chot duoc tai lieu tong ket cho seminar (demo + report + so lieu).

Nguyen tac bat buoc:
- Python chi capture/feed/automation.
- Convolution phai do RTL thuc hien (simulation hoac FPGA), khong duoc xu ly bang Python.

## 2. Trang thai hien tai (2026-03-18)

## Da hoan thanh
- RTL baseline da co: line buffer 5x5, kernel loader, MAC 25x3, top integration.
- Testbench self-check da co va da regression 5 kernel PASS.
- Pipeline D455 da chay that:
  - Stream lien tuc tren may hien tai.
  - Da luu anh raw + feed_rgb + hex_in.
  - Da xu ly ra processed + hex_out bang RTL simulation tu hex_in.
- Skeleton Vivado da co (create project, run synth/impl, constraints mau).
- Da co benchmark sim/frame cho full 640x480 (N frame) va xuat JSON/CSV report.
- Da tao AXI wrapper skeleton: src/axi_stream_conv_wrapper.sv, src/axi_lite_kernel_ctrl.sv.

## Ket qua chay that gan nhat
- D455 stream (8s/kernel):
  - gaussian5: 88 frame, ~10.02 fps
  - sharpen5: 92 frame, ~10.48 fps
  - laplacian5: 90 frame, ~10.21 fps
- RTL regression:
  - identity5, gaussian5, sharpen5, emboss5, laplacian5: PASS
  - valid_count = 144/144 moi case (test 16x16)
- Benchmark campaign 640x480:
  - gaussian5: report da tao (sim_wall_ms_mean, p95, fps proxy)
  - sharpen5: report da tao (sim_wall_ms_mean, p95, fps proxy)
- Vivado synth/impl batch da chay xong:
  - Vong dau @125MHz: WNS=-40.656 ns, TNS=-2294.210 ns (chua dat)
  - Vong toi uu bring-up @20MHz (pipeline MAC + constraint moi):
    - Timing post-route: WNS=+22.577 ns, TNS=0.000 ns (dat)
    - Utilization post-route: LUT=930 (1.75%), FF=203 (0.19%), BRAM Tile=1 (0.71%), DSP=78 (35.45%)
    - Power post-route (co VCD): Total=0.127W, Dynamic=0.022W, Static=0.105W
    - Luu y: confidence van low vi activity net match 0% (3/6256)

## Artifact da tao
- captures/d455/gaussian5/raw + processed + hex_in + hex_out
- captures/d455/sharpen5/raw + processed + hex_in + hex_out
- captures/d455/laplacian5/raw + processed + hex_in + hex_out
- captures/d455/*/feed_rgb (anh feed vao RTL simulation)
- sim/tb_out_<kernel>.hex va sim/expected_<kernel>.hex
- captures/d455/campaign640/campaign_summary.json
- captures/d455/campaign640/rtl_benchmark_<kernel>.json/.csv
- tb/tb_axi_stream_conv_wrapper.sv
- src/axi_stream_conv_wrapper.sv
- src/axi_lite_kernel_ctrl.sv

## 3. Research tom tat (cho phase camera + FPGA)

## 3.1 Tham khao camera va Python wrapper
Nguon tham khao chinh:
- librealsense Python examples:
  - wrappers/python/examples/opencv_viewer_example.py
  - wrappers/python/examples/align-depth2color.py
  - wrappers/python/examples/frame_queue_example.py

Ket luan ap dung:
- Dung rs.pipeline + rs.config + enable_stream(color, BGR8) la luong co ban on dinh.
- Dung wait_for_frames() theo vong lap cho stream lien tuc.
- Neu can toc do cao hon, uu tien frame queue/multi-thread va giam tan suat ghi file.

## 3.2 Tham khao phan cung so va DSP
Nguon tham khao chinh:
- AMD/Xilinx UG479 (DSP48E1)
- AMD/Xilinx UG902 (synthesis flow)

Ket luan ap dung:
- MAC 25 tap RGB can uu tien pipeline ro rang truoc khi day fmax.
- Gate quan trong cho phase synth: WNS > 0, thong ke DSP/BRAM/Fmax, sau do moi chot throughput.

## 4. Ke hoach phase chi tiet tu hien tai den final

## Phase A - Camera capture/feed + RTL output (DA XONG)
Muc tieu:
- Stream D455 lien tuc, xuat feed cho RTL, va xuat anh sau xu ly tu RTL.
Deliverable:
- Script stream camera: python/d455_stream_process.py
- Script xu ly feed bang RTL simulation: python/rtl_process_hex_frames.py
- Script orchestration: scripts/run_live_multi_kernel_demo.ps1
- Output frame bundles trong captures/d455/*
Tieu chi pass:
- Co anh raw, feed_rgb, processed cung frame index.
- Co hex_in va hex_out cung frame index.

## Phase B - RTL regression toan bo kernel (DA XONG)
Muc tieu:
- Xac nhan tinh dung RTL voi bo kernel bat buoc.
Deliverable:
- scripts/run_regression.ps1
- python/prepare_case.py (tao kernel.hex va expected.hex)
Tieu chi pass:
- 5/5 kernel PASS.
- Moi case co 144 output line cho test 16x16.

## Phase C - Test case mo rong can lam tiep (CAN THUC HIEN)
Muc tieu:
- Tang do tin cay truoc khi vao synth/hardware demo.
Cong viec:
1. Them test case reset giua frame.
2. Them test case valid gap/back-pressure.
3. Them test case overflow/saturation voi kernel am/duong lon.
4. Them test 32x32 va 640x480 synthetic profile.
Deliverable:
- File testbench mo rong trong tb/.
- Bao cao pass/fail theo tung case.
Gate pass:
- Khong X/Z khi out_valid=1.
- mismatch_count=0 voi expected stream.

Trang thai cap nhat:
- Dang can bo sung bo test reset-mid-frame, valid-gap, saturation-stress de dat gate C day du.

## Phase D - Synthesis va timing closure (CAN THUC HIEN)
Muc tieu:
- Dat gate ky thuat >=250 MP/s (muc thuc dung), huong toi 300 MP/s.
Cong viec:
1. Chay vivado_project/project_create.tcl.
2. Chay vivado_project/run_synth.tcl.
3. Phan tich report: timing_post_route.rpt, util_post_route.rpt, power_post_route.rpt.
4. Toi uu: bo sung pipeline stage neu can, can bang resource.
Deliverable:
- report timing/resource/power.
Gate pass:
- WNS > 0.
- Co cong thuc throughput ro rang theo freq x pixel_per_clock.

Trang thai cap nhat:
- Bring-up timing da dat o 40 MHz.
- Can sweep them de tim muc tan so timing-clean cao nhat truoc board.
- Flow SAIF da on dinh, confidence power hien tai la Medium.

## Phase E - Hardware integration realtime (CAN THUC HIEN)
Muc tieu:
- Chay duoc duong camera -> FPGA -> output hien thi/ghi ket qua.
Cong viec:
1. Chon giao tiep runtime kernel (AXI-Lite/UART).
2. Hoan tat wrapper stream input/output.
3. Dong bo format pixel va toc do truyen.
4. Chay demo switch kernel realtime.
Deliverable:
- Video demo truc tiep.
- Log thoi gian va fps he thong.
Gate pass:
- Chuyen kernel khong vo frame.
- He thong chay on dinh trong thoi gian demo.

Trang thai cap nhat:
- Chua len board runtime.
- Da co tai lieu runbook day du de vao board: docs/board_streaming_guide.md.

## Phase F - Bao cao va chot seminar (CAN THUC HIEN)
Muc tieu:
- Chot slide + report day du ky thuat.
Noi dung bat buoc:
1. Kien truc 5x5 va dataflow.
2. Ket qua camera stream truoc/sau.
3. Ket qua regression va waveform checklist.
4. Ket qua synthesis/timing/resource.
5. Bai hoc kinh nghiem va huong mo rong.

## 5. Lenh chay chuan (runbook)

## Camera stream + xuat anh
- scripts/run_live_multi_kernel_demo.ps1

## Chay 1 kernel camera ngắn
- C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/d455_stream_process.py --width 640 --height 480 --fps 30 --feed_width 16 --feed_height 16 --duration_sec 5 --max_frames 150 --save_every 10 --out_dir captures/d455/smoke
- C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe python/rtl_process_hex_frames.py --workspace . --in_dir captures/d455/smoke/hex_in --out_dir captures/d455/smoke --kernel gaussian5 --width 16 --height 16 --python_exe C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe

## Regression RTL
- scripts/run_regression.ps1

## Dem so dong output testbench
- (Get-Content .\sim\tb_out.hex | Measure-Object -Line).Lines

## 6. KPI va gate chap nhan
- Functional:
  - 5 kernel regression PASS.
  - testbench self-check mismatch=0, unknown=0.
- Camera pipeline:
  - Co cap anh before/after cho moi kernel da chay.
  - Co hex input/output frame theo index.
- Synthesis:
  - WNS > 0.
  - Co bang resource DSP/BRAM.
- Demo:
  - Trinh dien switch kernel voi luong du lieu thuc te.

## 7. Rui ro va giam thieu
- FPS camera software thap khi ghi file nhieu:
  - Giam save_every, tach thread ghi file, uu tien xử ly tren FPGA.
- Sai lech mapping output giua software va RTL:
  - Giu nguyen quy tac valid window x>=4, y>=4 trong script expected.
- Timing fail sau synth:
  - Tang pipeline stage, don gian hoa duong valid/control, toi uu ranh gioi module.

## 8. Cong viec tiep theo ngay lap tuc (48h)
1. Them 3 test case mo rong: reset-mid-frame, valid-gap, saturation-stress.
2. Chay sweep SAIF o nhieu period de chon muc board clock an toan va co bien timing.
3. Nang AXI wrapper tu skeleton len handshake day du, ket noi DMA trong block design.

## 9. Xu ly loi path trong flow Vivado (bat buoc)
Muc tieu:
- Neu xuat hien `The system cannot find the path specified.` thi script phai dung ngay va khong tiep tuc ket qua dang ngo.

Da thuc hien:
- scripts/run_power_with_saif.ps1 va scripts/sweep_clock_with_saif.ps1 da co che do strict.
- Co co che:
  1. Bat chuoi loi path trong output Vivado.
  2. Dung ngay run hien tai.
  3. Thu 1 lan auto-repair bang regenerate project.
  4. Neu van loi, throw va in log path cu the.

Log kiem tra:
- vivado_project/reports/vivado_power_with_saif.log
- vivado_project/reports/vivado_sweep_<period>ns.log
- vivado_project/reports/vivado_path_repair.log

## 10. Ke hoach chot truoc khi dua len board
Phai PASS cac gate sau:
1. Gate A (functional regression): PASS 5/5 kernel.
2. Gate B (D455 data-path): du artifact raw/feed/processed/hex_in/hex_out theo frame index.
3. Gate C (stress): reset-mid-frame, valid-gap, saturation.
4. Gate D (timing/resource): timing-clean o board clock du kien.
5. Gate E (power): SAIF applied, confidence toi thieu Medium.
6. Gate F (interface): AXI stream/lite test co backpressure PASS.

Tai lieu bat buoc:
- docs/pre_board_verification_plan.md
- docs/board_streaming_guide.md
- docs/saif_power_flow.md

## 11. Delta implementation (2026-03-18, Muc A local)
- Da them luong 1 lenh de tao demo xem output va bao cao pass/fail:
  - scripts/run_live_multi_kernel_demo.ps1
- Da them tool tao video side-by-side input/output:
  - python/build_side_by_side_video.py
- Da them tool signoff local:
  - python/signoff_level_a.py
- Da nang report frame-level trong RTL processing:
  - python/rtl_process_hex_frames.py (tb_status, mismatch, unknown, valid counters)
- Artifact demo local da tao tren bo capture benchmark:
  - captures/d455/benchmark640/preview_side_by_side.mp4
  - captures/d455/benchmark640/level_a_signoff.md
  - captures/d455/benchmark640/level_a_signoff.json
