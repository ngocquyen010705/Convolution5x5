import argparse
import csv
import json
import hashlib
import re
import shutil
import statistics
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np


def read_hex_rgb(path: Path, width: int, height: int) -> np.ndarray:
    vals = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            s = line.strip()
            if len(s) != 6:
                continue
            vals.append((int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)))
    arr = np.array(vals, dtype=np.uint8)
    return arr.reshape(height, width, 3)


def read_tb_stream(path: Path) -> np.ndarray:
    words = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            s = line.strip()
            if len(s) != 6:
                continue
            words.append((int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)))
    return np.array(words, dtype=np.uint8)


def write_hex_rgb(path: Path, frame: np.ndarray) -> None:
    with path.open("w", encoding="ascii") as f:
        for p in frame.reshape(-1, 3):
            f.write(f"{int(p[0]):02x}{int(p[1]):02x}{int(p[2]):02x}\n")


def reconstruct_frame_from_stream(stream: np.ndarray, width: int, height: int, ksize: int = 5) -> np.ndarray:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    idx = 0
    for y in range(ksize - 1, height):
        for x in range(ksize - 1, width):
            if idx < len(stream):
                frame[y, x, :] = stream[idx]
                idx += 1
    return frame


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return proc


def sha1_file(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def parse_sim_time_ps(stdout: str) -> int:
    m = re.search(r"\$finish called at\s+(\d+)\s+\(1ps\)", stdout)
    if not m:
        return -1
    return int(m.group(1))


def parse_tb_metrics(stdout: str) -> dict:
    pass_match = re.search(r"TB PASS:\s+valid_count=(\d+)\s+expected=(\d+)", stdout)
    if pass_match:
        valid_count = int(pass_match.group(1))
        expected_count = int(pass_match.group(2))
        return {
            "tb_status": "PASS",
            "tb_valid_count": valid_count,
            "tb_expected_count": expected_count,
            "tb_mismatch_count": 0,
            "tb_unknown_count": 0,
            "tb_exp_rd_ptr": expected_count,
            "tb_exp_wr_ptr": expected_count,
        }

    fail_match = re.search(
        r"TB FAIL:\s+valid_count=(\d+)\s+expected=(\d+)\s+mismatch=(\d+)\s+unknown=(\d+)\s+exp_rd=(\d+)\s+exp_wr=(\d+)",
        stdout,
    )
    if fail_match:
        return {
            "tb_status": "FAIL",
            "tb_valid_count": int(fail_match.group(1)),
            "tb_expected_count": int(fail_match.group(2)),
            "tb_mismatch_count": int(fail_match.group(3)),
            "tb_unknown_count": int(fail_match.group(4)),
            "tb_exp_rd_ptr": int(fail_match.group(5)),
            "tb_exp_wr_ptr": int(fail_match.group(6)),
        }

    return {
        "tb_status": "UNKNOWN",
        "tb_valid_count": -1,
        "tb_expected_count": -1,
        "tb_mismatch_count": -1,
        "tb_unknown_count": -1,
        "tb_exp_rd_ptr": -1,
        "tb_exp_wr_ptr": -1,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Process captured hex frames using RTL simulation")
    parser.add_argument("--workspace", default=".")
    parser.add_argument("--in_dir", required=True, help="Directory containing frame_*.hex feed files")
    parser.add_argument("--out_dir", required=True, help="Output directory for RTL processed artifacts")
    parser.add_argument("--kernel", required=True, choices=["identity5", "gaussian5", "sharpen5", "emboss5", "laplacian5"])
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--python_exe", default="C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe")
    parser.add_argument("--report_json", default="", help="Optional benchmark JSON output path")
    parser.add_argument("--report_csv", default="", help="Optional benchmark CSV output path")
    args = parser.parse_args()

    ws = Path(args.workspace).resolve()
    in_dir = (ws / args.in_dir).resolve()
    out_dir = (ws / args.out_dir).resolve()

    processed_dir = out_dir / "processed"
    hex_out_dir = out_dir / "hex_out"
    processed_dir.mkdir(parents=True, exist_ok=True)
    hex_out_dir.mkdir(parents=True, exist_ok=True)

    frame_files = sorted(in_dir.glob("frame_*.hex"))
    if not frame_files:
        raise RuntimeError(f"No frame hex files found in {in_dir}")

    hex_target = ws / "hex" / "test_frame_0.hex"
    sim_kernel = ws / "sim" / "kernel.hex"
    sim_expected = ws / "sim" / "expected.hex"
    sim_out = ws / "sim" / "tb_out.hex"

    expected_valid = (args.width - 4) * (args.height - 4)
    per_frame = []

    # Compile once for the selected frame dimensions, then run repeatedly.
    run_cmd(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts/run_sim.ps1",
            "-Width",
            str(args.width),
            "-Height",
            str(args.height),
            "-CompileOnly",
        ],
        ws,
    )

    for ff in frame_files:
        shutil.copyfile(ff, hex_target)

        run_cmd(
            [
                args.python_exe,
                "python/prepare_case.py",
                "--in_hex",
                "hex/test_frame_0.hex",
                "--width",
                str(args.width),
                "--height",
                str(args.height),
                "--kernel",
                args.kernel,
                "--kernel_out",
                str(sim_kernel.relative_to(ws)).replace("\\", "/"),
                "--expected_out",
                str(sim_expected.relative_to(ws)).replace("\\", "/"),
            ],
            ws,
        )

        t0 = time.perf_counter()
        sim_proc = run_cmd(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "scripts/run_sim.ps1",
                "-RunOnly",
            ],
            ws,
        )
        wall_ms = (time.perf_counter() - t0) * 1000.0
        sim_log = sim_proc.stdout + "\n" + sim_proc.stderr
        sim_ps = parse_sim_time_ps(sim_log)
        tb_metrics = parse_tb_metrics(sim_log)

        stream = read_tb_stream(sim_out)
        out_frame = reconstruct_frame_from_stream(stream, args.width, args.height)

        stem = ff.stem
        out_hex_file = hex_out_dir / f"{stem}.hex"
        write_hex_rgb(out_hex_file, out_frame)
        cv2.imwrite(str(processed_dir / f"{stem}.png"), cv2.cvtColor(out_frame, cv2.COLOR_RGB2BGR))

        per_frame.append(
            {
                "frame": stem,
                "valid_samples": int(len(stream)),
                "expected_valid": int(expected_valid),
                "sim_time_ps": int(sim_ps),
                "sim_wall_ms": float(wall_ms),
                "out_hex_sha1": sha1_file(out_hex_file),
                "tb_status": tb_metrics["tb_status"],
                "tb_valid_count": tb_metrics["tb_valid_count"],
                "tb_expected_count": tb_metrics["tb_expected_count"],
                "tb_mismatch_count": tb_metrics["tb_mismatch_count"],
                "tb_unknown_count": tb_metrics["tb_unknown_count"],
                "tb_exp_rd_ptr": tb_metrics["tb_exp_rd_ptr"],
                "tb_exp_wr_ptr": tb_metrics["tb_exp_wr_ptr"],
            }
        )

    wall_values = [x["sim_wall_ms"] for x in per_frame]
    if wall_values:
        sorted_wall = sorted(wall_values)
        p95_idx = int(round(0.95 * (len(sorted_wall) - 1)))
        p95_val = sorted_wall[p95_idx]
    else:
        p95_val = 0.0

    report = {
        "kernel": args.kernel,
        "width": args.width,
        "height": args.height,
        "frames": len(per_frame),
        "expected_valid_per_frame": expected_valid,
        "pixels_per_frame": int(args.width * args.height),
        "sim_wall_ms_mean": statistics.mean(wall_values) if wall_values else 0.0,
        "sim_wall_ms_p95": p95_val,
        "sim_wall_ms_min": min(wall_values) if wall_values else 0.0,
        "sim_wall_ms_max": max(wall_values) if wall_values else 0.0,
        "sim_fps_mean": (1000.0 / statistics.mean(wall_values)) if wall_values else 0.0,
        "sim_mpixels_per_sec_mean": ((args.width * args.height) / statistics.mean(wall_values) / 1000.0) if wall_values else 0.0,
        "all_tb_pass": all(x["tb_status"] == "PASS" for x in per_frame),
        "tb_failed_frames": [x["frame"] for x in per_frame if x["tb_status"] != "PASS"],
        "per_frame": per_frame,
    }

    report_json = Path(args.report_json) if args.report_json else (out_dir / f"rtl_benchmark_{args.kernel}.json")
    report_csv = Path(args.report_csv) if args.report_csv else (out_dir / f"rtl_benchmark_{args.kernel}.csv")
    if not report_json.is_absolute():
        report_json = ws / report_json
    if not report_csv.is_absolute():
        report_csv = ws / report_csv
    report_json.parent.mkdir(parents=True, exist_ok=True)
    report_csv.parent.mkdir(parents=True, exist_ok=True)

    with report_json.open("w", encoding="ascii") as f:
        json.dump(report, f, indent=2)

    with report_csv.open("w", encoding="ascii", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "frame",
                "valid_samples",
                "expected_valid",
                "sim_time_ps",
                "sim_wall_ms",
                "out_hex_sha1",
                "tb_status",
                "tb_valid_count",
                "tb_expected_count",
                "tb_mismatch_count",
                "tb_unknown_count",
                "tb_exp_rd_ptr",
                "tb_exp_wr_ptr",
            ],
        )
        writer.writeheader()
        writer.writerows(per_frame)

    print(f"RTL processing completed for {len(frame_files)} frame(s), kernel={args.kernel}")
    print(f"Processed output: {processed_dir}")
    print(f"Hex output: {hex_out_dir}")
    print(f"Benchmark JSON: {report_json}")
    print(f"Benchmark CSV: {report_csv}")


if __name__ == "__main__":
    main()
