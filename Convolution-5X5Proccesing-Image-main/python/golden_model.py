import argparse
from pathlib import Path

import numpy as np


KERNELS = {
    "gaussian5": np.array(
        [
            [1, 4, 6, 4, 1],
            [4, 16, 24, 16, 4],
            [6, 24, 36, 24, 6],
            [4, 16, 24, 16, 4],
            [1, 4, 6, 4, 1],
        ],
        dtype=np.int32,
    ),
    "sharpen5": np.array(
        [
            [0, -1, -1, -1, 0],
            [-1, 2, -4, 2, -1],
            [-1, -4, 20, -4, -1],
            [-1, 2, -4, 2, -1],
            [0, -1, -1, -1, 0],
        ],
        dtype=np.int32,
    ),
    "laplacian5": np.array(
        [
            [0, 0, -1, 0, 0],
            [0, -1, -2, -1, 0],
            [-1, -2, 16, -2, -1],
            [0, -1, -2, -1, 0],
            [0, 0, -1, 0, 0],
        ],
        dtype=np.int32,
    ),
}


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    if mse == 0:
        return 99.0
    return 10.0 * np.log10((255.0 * 255.0) / mse)


def conv2d_rgb(frame: np.ndarray, kernel: np.ndarray, norm: int) -> np.ndarray:
    h, w, _ = frame.shape
    k = kernel.shape[0]
    pad = k // 2
    padded = np.pad(frame, ((pad, pad), (pad, pad), (0, 0)), mode="constant")

    out = np.zeros_like(frame, dtype=np.int32)
    for y in range(h):
        for x in range(w):
            win = padded[y : y + k, x : x + k, :].astype(np.int32)
            out[y, x, 0] = np.sum(win[:, :, 0] * kernel)
            out[y, x, 1] = np.sum(win[:, :, 1] * kernel)
            out[y, x, 2] = np.sum(win[:, :, 2] * kernel)

    out = out >> norm
    return np.clip(out, 0, 255).astype(np.uint8)


def read_hex_rgb(path: Path, width: int, height: int) -> np.ndarray:
    values = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            s = line.strip()
            if len(s) != 6:
                continue
            values.append([int(s[0:2], 16), int(s[1*2:2*2], 16), int(s[2*2:3*2], 16)])
    arr = np.array(values, dtype=np.uint8)
    return arr.reshape(height, width, 3)


def write_hex_rgb(path: Path, frame: np.ndarray) -> None:
    with path.open("w", encoding="ascii") as f:
        for p in frame.reshape(-1, 3):
            f.write(f"{p[0]:02x}{p[1]:02x}{p[2]:02x}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="5x5 RGB golden model")
    parser.add_argument("--in_hex", required=True, help="Input hex file")
    parser.add_argument("--out_hex", required=True, help="Output hex file")
    parser.add_argument("--kernel", default="gaussian5", choices=KERNELS.keys())
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--norm", type=int, default=8, help="Right shift for normalization")
    args = parser.parse_args()

    inp = read_hex_rgb(Path(args.in_hex), args.width, args.height)
    out = conv2d_rgb(inp, KERNELS[args.kernel], args.norm)
    write_hex_rgb(Path(args.out_hex), out)

    score = psnr(inp, out)
    print(f"Kernel={args.kernel}, PSNR(input,output)={score:.3f} dB")


if __name__ == "__main__":
    main()
