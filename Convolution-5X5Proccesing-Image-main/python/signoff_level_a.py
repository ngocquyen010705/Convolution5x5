import argparse
import json
from pathlib import Path


def stems_for(folder: Path, suffix: str) -> set[str]:
    return {p.stem for p in folder.glob(f"*{suffix}")}


def sorted_list(values: set[str]) -> list[str]:
    return sorted(values)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="ascii") as f:
        return json.load(f)


def detect_report(capture_dir: Path, kernel: str) -> Path:
    report = capture_dir / f"rtl_benchmark_{kernel}.json"
    if report.exists():
        return report

    candidates = sorted(capture_dir.glob("rtl_benchmark_*.json"))
    if len(candidates) == 1:
        return candidates[0]

    if not candidates:
        raise RuntimeError(f"No rtl_benchmark_*.json report found in {capture_dir}")

    names = ", ".join(str(p.name) for p in candidates)
    raise RuntimeError(f"Multiple benchmark reports found. Specify --kernel. Found: {names}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Level-A signoff report for D455 RTL simulation artifacts")
    parser.add_argument("--capture_dir", required=True, help="Capture folder containing raw/feed_rgb/processed/hex_in/hex_out")
    parser.add_argument("--kernel", default="gaussian5")
    parser.add_argument("--timing_period_ns", type=float, default=50.0)
    parser.add_argument("--timing_wns", type=float, default=22.577)
    parser.add_argument("--timing_tns", type=float, default=0.0)
    parser.add_argument("--out_json", default="")
    parser.add_argument("--out_md", default="")
    args = parser.parse_args()

    capture_dir = Path(args.capture_dir).resolve()
    raw_dir = capture_dir / "raw"
    feed_dir = capture_dir / "feed_rgb"
    processed_dir = capture_dir / "processed"
    hex_in_dir = capture_dir / "hex_in"
    hex_out_dir = capture_dir / "hex_out"

    for d in [raw_dir, feed_dir, processed_dir, hex_in_dir, hex_out_dir]:
        if not d.exists():
            raise RuntimeError(f"Missing required directory: {d}")

    stems_raw = stems_for(raw_dir, ".png")
    stems_feed = stems_for(feed_dir, ".png")
    stems_processed = stems_for(processed_dir, ".png")
    stems_hex_in = stems_for(hex_in_dir, ".hex")
    stems_hex_out = stems_for(hex_out_dir, ".hex")

    parity_ok = stems_raw == stems_feed == stems_processed == stems_hex_in == stems_hex_out
    common_stems = stems_raw & stems_feed & stems_processed & stems_hex_in & stems_hex_out

    report_path = detect_report(capture_dir, args.kernel)
    bench = load_json(report_path)
    per_frame = bench.get("per_frame", [])

    mismatches = 0
    unknowns = 0
    tb_failed = []
    valid_samples_ok = True

    for row in per_frame:
        mismatches += int(row.get("tb_mismatch_count", -1)) if int(row.get("tb_mismatch_count", -1)) >= 0 else 0
        unknowns += int(row.get("tb_unknown_count", -1)) if int(row.get("tb_unknown_count", -1)) >= 0 else 0
        if row.get("tb_status") != "PASS":
            tb_failed.append(str(row.get("frame", "unknown")))
        if int(row.get("valid_samples", -1)) != int(row.get("expected_valid", -2)):
            valid_samples_ok = False

    timing_ok = (args.timing_wns >= 0.0) and (abs(args.timing_tns) < 1e-9)
    tb_ok = bool(bench.get("all_tb_pass", False)) and len(tb_failed) == 0
    counters_ok = (mismatches == 0) and (unknowns == 0) and valid_samples_ok

    final_pass = parity_ok and tb_ok and counters_ok and timing_ok

    result = {
        "capture_dir": str(capture_dir),
        "kernel": bench.get("kernel", args.kernel),
        "frames_detected": len(common_stems),
        "frame_sets": {
            "raw_png": sorted_list(stems_raw),
            "feed_png": sorted_list(stems_feed),
            "processed_png": sorted_list(stems_processed),
            "hex_in": sorted_list(stems_hex_in),
            "hex_out": sorted_list(stems_hex_out),
        },
        "checks": {
            "parity_ok": parity_ok,
            "tb_ok": tb_ok,
            "counters_ok": counters_ok,
            "timing_ok": timing_ok,
        },
        "timing": {
            "period_ns": args.timing_period_ns,
            "wns_ns": args.timing_wns,
            "tns_ns": args.timing_tns,
        },
        "tb_metrics": {
            "all_tb_pass": bench.get("all_tb_pass", False),
            "tb_failed_frames": tb_failed,
            "mismatch_total": mismatches,
            "unknown_total": unknowns,
            "valid_samples_all_ok": valid_samples_ok,
        },
        "benchmark_report": str(report_path),
        "final_status": "PASS" if final_pass else "FAIL",
    }

    out_json = Path(args.out_json) if args.out_json else (capture_dir / "level_a_signoff.json")
    out_md = Path(args.out_md) if args.out_md else (capture_dir / "level_a_signoff.md")
    if not out_json.is_absolute():
        out_json = capture_dir / out_json
    if not out_md.is_absolute():
        out_md = capture_dir / out_md

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    with out_json.open("w", encoding="ascii") as f:
        json.dump(result, f, indent=2)

    lines = [
        "# Level-A Signoff Report",
        "",
        f"- Capture dir: {capture_dir}",
        f"- Kernel: {result['kernel']}",
        f"- Benchmark report: {report_path}",
        f"- Final status: {result['final_status']}",
        "",
        "## Checks",
        "",
        f"- Parity raw/feed/processed/hex_in/hex_out: {'PASS' if parity_ok else 'FAIL'}",
        f"- Testbench per-frame status: {'PASS' if tb_ok else 'FAIL'}",
        f"- Counter integrity (mismatch=0, unknown=0, valid count): {'PASS' if counters_ok else 'FAIL'}",
        f"- Timing baseline {args.timing_period_ns:.3f}ns (WNS={args.timing_wns:.3f}, TNS={args.timing_tns:.3f}): {'PASS' if timing_ok else 'FAIL'}",
        "",
        "## Metrics",
        "",
        f"- Frames detected: {len(common_stems)}",
        f"- Total mismatch count: {mismatches}",
        f"- Total unknown count: {unknowns}",
        f"- TB failed frames: {', '.join(tb_failed) if tb_failed else 'none'}",
    ]

    with out_md.open("w", encoding="ascii") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Signoff JSON: {out_json}")
    print(f"Signoff MD: {out_md}")
    print(f"Level-A final status: {result['final_status']}")


if __name__ == "__main__":
    main()
