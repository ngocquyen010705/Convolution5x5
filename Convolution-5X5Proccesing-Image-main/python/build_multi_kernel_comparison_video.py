import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def list_stems(folder: Path, suffix: str) -> set[str]:
    return {p.stem for p in folder.glob(f"*{suffix}")}


def read_signoff_status(capture_dir: Path) -> str:
    signoff = capture_dir / "level_a_signoff.json"
    if not signoff.exists():
        return "UNKNOWN"
    with signoff.open("r", encoding="ascii") as f:
        data = json.load(f)
    return str(data.get("final_status", "UNKNOWN"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build one combined video: input + 3 kernel outputs")
    parser.add_argument("--source_raw_dir", required=True)
    parser.add_argument("--gaussian_dir", required=True)
    parser.add_argument("--sharpen_dir", required=True)
    parser.add_argument("--laplacian_dir", required=True)
    parser.add_argument("--output_video", required=True)
    parser.add_argument("--fps", type=float, default=12.0)
    args = parser.parse_args()

    source_raw = Path(args.source_raw_dir).resolve()
    gaussian_proc = Path(args.gaussian_dir).resolve() / "processed"
    sharpen_proc = Path(args.sharpen_dir).resolve() / "processed"
    laplacian_proc = Path(args.laplacian_dir).resolve() / "processed"
    output_video = Path(args.output_video).resolve()
    output_video.parent.mkdir(parents=True, exist_ok=True)

    stems = sorted(
        list_stems(source_raw, ".png")
        & list_stems(gaussian_proc, ".png")
        & list_stems(sharpen_proc, ".png")
        & list_stems(laplacian_proc, ".png")
    )
    if not stems:
        raise RuntimeError("No common frame stems found across source and kernel outputs")

    raw0 = cv2.imread(str(source_raw / f"{stems[0]}.png"), cv2.IMREAD_COLOR)
    if raw0 is None:
        raise RuntimeError("Cannot read first raw frame")

    tile_h, tile_w = raw0.shape[0], raw0.shape[1]
    canvas_w = tile_w * 2
    canvas_h = tile_h * 2

    fourcc = int.from_bytes(b"mp4v", "little")
    writer = cv2.VideoWriter(str(output_video), fourcc, args.fps, (canvas_w, canvas_h))
    if not writer.isOpened():
        raise RuntimeError(f"Could not open video writer: {output_video}")

    status_gaussian = read_signoff_status(Path(args.gaussian_dir).resolve())
    status_sharpen = read_signoff_status(Path(args.sharpen_dir).resolve())
    status_laplacian = read_signoff_status(Path(args.laplacian_dir).resolve())

    try:
        for idx, stem in enumerate(stems):
            raw = cv2.imread(str(source_raw / f"{stem}.png"), cv2.IMREAD_COLOR)
            ga = cv2.imread(str(gaussian_proc / f"{stem}.png"), cv2.IMREAD_COLOR)
            sh = cv2.imread(str(sharpen_proc / f"{stem}.png"), cv2.IMREAD_COLOR)
            la = cv2.imread(str(laplacian_proc / f"{stem}.png"), cv2.IMREAD_COLOR)
            if raw is None or ga is None or sh is None or la is None:
                continue

            ga = cv2.resize(ga, (tile_w, tile_h), interpolation=cv2.INTER_LINEAR)
            sh = cv2.resize(sh, (tile_w, tile_h), interpolation=cv2.INTER_LINEAR)
            la = cv2.resize(la, (tile_w, tile_h), interpolation=cv2.INTER_LINEAR)

            top = np.hstack([raw, ga])
            bottom = np.hstack([sh, la])
            frame = np.vstack([top, bottom])

            cv2.putText(frame, "INPUT", (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.85, (40, 220, 40), 2, cv2.LINE_AA)
            cv2.putText(
                frame,
                f"GAUSSIAN5 ({status_gaussian})",
                (tile_w + 12, 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (40, 220, 40),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                f"SHARPEN5 ({status_sharpen})",
                (12, tile_h + 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (40, 220, 40),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                f"LAPLACIAN5 ({status_laplacian})",
                (tile_w + 12, tile_h + 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                (40, 220, 40),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                f"frame={stem} idx={idx}",
                (12, canvas_h - 16),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (255, 255, 255),
                2,
                cv2.LINE_AA,
            )
            writer.write(frame)
    finally:
        writer.release()

    print(f"Combined comparison video generated: {output_video}")
    print(f"Frames written: {len(stems)}")


if __name__ == "__main__":
    main()
