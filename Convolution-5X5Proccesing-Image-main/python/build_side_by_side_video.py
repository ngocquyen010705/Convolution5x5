import argparse
from pathlib import Path

import cv2
import numpy as np


def list_stems(folder: Path, suffix: str) -> set[str]:
    return {p.stem for p in folder.glob(f"*{suffix}")}


def main() -> None:
    parser = argparse.ArgumentParser(description="Build side-by-side input/output preview video")
    parser.add_argument("--raw_dir", required=True)
    parser.add_argument("--processed_dir", required=True)
    parser.add_argument("--output_video", required=True)
    parser.add_argument("--fps", type=float, default=10.0)
    parser.add_argument("--label", default="RTL 5x5 Convolution")
    parser.add_argument("--match_raw_size", action="store_true", help="Resize processed frame to raw frame size")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir).resolve()
    processed_dir = Path(args.processed_dir).resolve()
    output_video = Path(args.output_video).resolve()
    output_video.parent.mkdir(parents=True, exist_ok=True)

    stems = sorted(list_stems(raw_dir, ".png") & list_stems(processed_dir, ".png"))
    if not stems:
        raise RuntimeError("No matching frame stems found between raw_dir and processed_dir")

    first_raw = cv2.imread(str(raw_dir / f"{stems[0]}.png"), cv2.IMREAD_COLOR)
    first_proc = cv2.imread(str(processed_dir / f"{stems[0]}.png"), cv2.IMREAD_COLOR)
    if first_raw is None or first_proc is None:
        raise RuntimeError("Failed to read first pair of frames")

    if args.match_raw_size:
        target_h = first_raw.shape[0]
        target_w = first_raw.shape[1]
    else:
        target_h = max(first_raw.shape[0], first_proc.shape[0])
        target_w = first_proc.shape[1]

    h = target_h
    w = first_raw.shape[1] + target_w

    fourcc = int.from_bytes(b"mp4v", "little")
    writer = cv2.VideoWriter(str(output_video), fourcc, args.fps, (w, h))
    if not writer.isOpened():
        raise RuntimeError(f"Could not open video writer for {output_video}")

    try:
        for idx, stem in enumerate(stems):
            raw = cv2.imread(str(raw_dir / f"{stem}.png"), cv2.IMREAD_COLOR)
            proc = cv2.imread(str(processed_dir / f"{stem}.png"), cv2.IMREAD_COLOR)
            if raw is None or proc is None:
                continue

            if raw.shape[0] != h or raw.shape[1] != first_raw.shape[1]:
                raw = cv2.resize(raw, (first_raw.shape[1], h), interpolation=cv2.INTER_AREA)

            if args.match_raw_size:
                proc = cv2.resize(proc, (target_w, target_h), interpolation=cv2.INTER_LINEAR)
            elif proc.shape[0] != h:
                proc = cv2.resize(proc, (proc.shape[1], h), interpolation=cv2.INTER_AREA)

            frame = np.hstack([raw, proc])
            cv2.putText(frame, "Input", (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (40, 220, 40), 2, cv2.LINE_AA)
            cv2.putText(
                frame,
                "RTL Output",
                (raw.shape[1] + 12, 28),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (40, 220, 40),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                frame,
                f"{args.label} | frame={stem} | idx={idx}",
                (12, h - 16),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (255, 255, 255),
                2,
                cv2.LINE_AA,
            )
            writer.write(frame)
    finally:
        writer.release()

    print(f"Side-by-side video generated: {output_video}")
    print(f"Frames written: {len(stems)}")


if __name__ == "__main__":
    main()
