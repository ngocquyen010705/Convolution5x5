import argparse
import json
import subprocess
from pathlib import Path


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")
    return proc


def load_json(path: Path) -> dict:
    with path.open("r", encoding="ascii") as f:
        return json.load(f)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run multi-kernel RTL benchmark campaign")
    parser.add_argument("--workspace", default=".")
    parser.add_argument("--capture_dir", default="captures/d455/campaign640")
    parser.add_argument("--frames", type=int, default=3)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--python_exe", default="C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe")
    parser.add_argument("--kernels", nargs="+", default=["gaussian5", "sharpen5", "laplacian5"])
    args = parser.parse_args()

    ws = Path(args.workspace).resolve()
    capture_dir = (ws / args.capture_dir).resolve()
    capture_dir.mkdir(parents=True, exist_ok=True)

    # 1) Capture/feed N full-resolution frames once.
    run_cmd(
        [
            args.python_exe,
            "python/d455_stream_process.py",
            "--width",
            str(args.width),
            "--height",
            str(args.height),
            "--fps",
            str(args.fps),
            "--feed_width",
            str(args.width),
            "--feed_height",
            str(args.height),
            "--duration_sec",
            "0",
            "--max_frames",
            str(args.frames),
            "--save_every",
            "1",
            "--out_dir",
            str(capture_dir.relative_to(ws)).replace("\\", "/"),
        ],
        ws,
    )

    summary = []

    # 2) Process same captured frame set for each kernel via RTL simulation.
    for k in args.kernels:
        run_cmd(
            [
                args.python_exe,
                "python/rtl_process_hex_frames.py",
                "--workspace",
                ".",
                "--in_dir",
                str((capture_dir / "hex_in").relative_to(ws)).replace("\\", "/"),
                "--out_dir",
                str(capture_dir.relative_to(ws)).replace("\\", "/"),
                "--kernel",
                k,
                "--width",
                str(args.width),
                "--height",
                str(args.height),
                "--python_exe",
                args.python_exe,
                "--report_json",
                str((capture_dir / f"rtl_benchmark_{k}.json").relative_to(ws)).replace("\\", "/"),
                "--report_csv",
                str((capture_dir / f"rtl_benchmark_{k}.csv").relative_to(ws)).replace("\\", "/"),
            ],
            ws,
        )

        rep = load_json(capture_dir / f"rtl_benchmark_{k}.json")
        summary.append(
            {
                "kernel": k,
                "frames": rep["frames"],
                "sim_wall_ms_mean": rep["sim_wall_ms_mean"],
                "sim_wall_ms_p95": rep["sim_wall_ms_p95"],
                "sim_fps_mean": rep["sim_fps_mean"],
                "sim_mpixels_per_sec_mean": rep["sim_mpixels_per_sec_mean"],
            }
        )

    final = {
        "width": args.width,
        "height": args.height,
        "frames": args.frames,
        "kernels": args.kernels,
        "summary": summary,
    }

    out_json = capture_dir / "campaign_summary.json"
    with out_json.open("w", encoding="ascii") as f:
        json.dump(final, f, indent=2)

    print(f"Campaign done. Summary: {out_json}")
    for row in summary:
        print(
            f"{row['kernel']}: frames={row['frames']} mean_ms={row['sim_wall_ms_mean']:.2f} "
            f"p95_ms={row['sim_wall_ms_p95']:.2f} sim_fps={row['sim_fps_mean']:.4f} MP/s={row['sim_mpixels_per_sec_mean']:.4f}"
        )


if __name__ == "__main__":
    main()
