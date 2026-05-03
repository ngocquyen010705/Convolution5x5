import argparse
from pathlib import Path

import numpy as np


def generate_frame(width: int, height: int, index: int) -> np.ndarray:
    y = np.arange(height, dtype=np.uint16)[:, None]
    x = np.arange(width, dtype=np.uint16)[None, :]

    r = np.broadcast_to((x + index * 7) & 0xFF, (height, width))
    g = np.broadcast_to((y + index * 13) & 0xFF, (height, width))
    b = ((x // 2 + y // 3 + index * 19) & 0xFF)
    return np.stack([r, g, b], axis=-1).astype(np.uint8)


def write_hex_rgb(frame: np.ndarray, path: Path) -> None:
    with path.open("w", encoding="ascii") as f:
        for pix in frame.reshape(-1, 3):
            f.write(f"{pix[0]:02x}{pix[1]:02x}{pix[2]:02x}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate synthetic RGB frames as hex streams")
    parser.add_argument("--out", default="../hex", help="Output directory")
    parser.add_argument("--count", type=int, default=10, help="Number of frames")
    parser.add_argument("--width", type=int, default=640, help="Frame width")
    parser.add_argument("--height", type=int, default=480, help="Frame height")
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for i in range(args.count):
        frame = generate_frame(args.width, args.height, i)
        write_hex_rgb(frame, out_dir / f"test_frame_{i}.hex")

    print(f"Generated {args.count} frames in {out_dir}")


if __name__ == "__main__":
    main()
