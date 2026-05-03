# pyright: reportAttributeAccessIssue=false

import argparse
import time
from pathlib import Path

import cv2
import numpy as np
import pyrealsense2 as rs  # type: ignore[import]


def write_hex_rgb(path: Path, frame_rgb: np.ndarray) -> None:
    with path.open("w", encoding="ascii") as f:
        for p in frame_rgb.reshape(-1, 3):
            f.write(f"{int(p[0]):02x}{int(p[1]):02x}{int(p[2]):02x}\n")


def save_feed_bundle(base_dir: Path, frame_idx: int, raw_rgb: np.ndarray, feed_rgb: np.ndarray) -> None:
    raw_dir = base_dir / "raw"
    feed_dir = base_dir / "feed_rgb"
    hex_in_dir = base_dir / "hex_in"

    for d in (raw_dir, feed_dir, hex_in_dir):
        d.mkdir(parents=True, exist_ok=True)

    stem = f"frame_{frame_idx:06d}"
    cv2.imwrite(str(raw_dir / f"{stem}.png"), cv2.cvtColor(raw_rgb, cv2.COLOR_RGB2BGR))
    cv2.imwrite(str(feed_dir / f"{stem}.png"), cv2.cvtColor(feed_rgb, cv2.COLOR_RGB2BGR))
    write_hex_rgb(hex_in_dir / f"{stem}.hex", feed_rgb)


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture Intel RealSense D455 stream and export feed vectors for RTL")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--feed_width", type=int, default=0)
    parser.add_argument("--feed_height", type=int, default=0)
    parser.add_argument("--duration_sec", type=float, default=10.0)
    parser.add_argument("--max_frames", type=int, default=300)
    parser.add_argument("--save_every", type=int, default=10)
    parser.add_argument("--out_dir", default="captures/d455")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    feed_w = args.feed_width if args.feed_width > 0 else args.width
    feed_h = args.feed_height if args.feed_height > 0 else args.height

    pipeline_ctor = getattr(rs, "pipeline")
    config_ctor = getattr(rs, "config")
    stream_enum = getattr(rs, "stream")
    format_enum = getattr(rs, "format")

    pipeline = pipeline_ctor()
    config = config_ctor()
    config.enable_stream(getattr(stream_enum, "color"), args.width, args.height, getattr(format_enum, "bgr8"), args.fps)

    print("Starting D455 color stream (capture/feed only)...")
    profile = pipeline.start(config)
    _ = profile.get_device()

    frame_idx = 0
    saved_idx = 0
    start_t = time.time()

    try:
        while True:
            if args.max_frames > 0 and frame_idx >= args.max_frames:
                break
            if args.duration_sec > 0 and (time.time() - start_t) >= args.duration_sec:
                break

            frames = pipeline.wait_for_frames(timeout_ms=5000)
            color_frame = frames.get_color_frame()
            if not color_frame:
                continue

            bgr = np.asanyarray(color_frame.get_data())
            raw_rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

            if frame_idx % args.save_every == 0:
                if (feed_w != args.width) or (feed_h != args.height):
                    feed_rgb = cv2.resize(raw_rgb, (feed_w, feed_h), interpolation=cv2.INTER_AREA)
                else:
                    feed_rgb = raw_rgb
                save_feed_bundle(out_dir, frame_idx, raw_rgb, feed_rgb)
                saved_idx += 1

            frame_idx += 1

    finally:
        pipeline.stop()

    elapsed = max(time.time() - start_t, 1e-6)
    print(f"Done. Captured frames={frame_idx}, saved_feed_frames={saved_idx}, elapsed={elapsed:.2f}s, capture_fps={frame_idx/elapsed:.2f}")
    print(f"Output directory: {out_dir}")


if __name__ == "__main__":
    main()
