import argparse
from pathlib import Path

import numpy as np

KERNELS = {
    "identity5": np.array(
        [
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
            [0, 0, 256, 0, 0],
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
        ],
        dtype=np.int32,
    ),
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
            [0, -16, -16, -16, 0],
            [-16, 32, -64, 32, -16],
            [-16, -64, 320, -64, -16],
            [-16, 32, -64, 32, -16],
            [0, -16, -16, -16, 0],
        ],
        dtype=np.int32,
    ),
    "emboss5": np.array(
        [
            [-32, -16, 0, 16, 32],
            [-16, 0, 16, 32, 16],
            [0, 16, 32, 16, 0],
            [16, 32, 16, 0, -16],
            [32, 16, 0, -16, -32],
        ],
        dtype=np.int32,
    ),
    "laplacian5": np.array(
        [
            [0, 0, -16, 0, 0],
            [0, -16, -32, -16, 0],
            [-16, -32, 256, -32, -16],
            [0, -16, -32, -16, 0],
            [0, 0, -16, 0, 0],
        ],
        dtype=np.int32,
    ),
}


def read_hex_rgb(path: Path, width: int, height: int) -> np.ndarray:
    pixels = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            s = line.strip()
            if len(s) != 6:
                continue
            pixels.append((int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)))
    arr = np.array(pixels, dtype=np.uint8)
    return arr.reshape(height, width, 3)


def write_kernel_hex(path: Path, kernel: np.ndarray) -> None:
    flat = kernel.reshape(-1)
    with path.open("w", encoding="ascii") as f:
        for v in flat:
            twos = int(v) & 0xFFFF
            f.write(f"{twos:04x}\n")


def sat_u8(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v


def compute_expected_stream(frame: np.ndarray, kernel: np.ndarray, norm_shift: int = 8) -> np.ndarray:
    h, w, _ = frame.shape
    out_words = []

    for y in range(4, h):
        for x in range(4, w):
            win = frame[y - 4 : y + 1, x - 4 : x + 1, :].astype(np.int32)
            acc = np.sum(win * kernel[:, :, None], axis=(0, 1))
            r = sat_u8(int(acc[0]) >> norm_shift)
            g = sat_u8(int(acc[1]) >> norm_shift)
            b = sat_u8(int(acc[2]) >> norm_shift)
            out_words.append((r << 16) | (g << 8) | b)

    return np.array(out_words, dtype=np.uint32)


def write_expected_hex(path: Path, words: np.ndarray) -> None:
    with path.open("w", encoding="ascii") as f:
        for w in words:
            f.write(f"{int(w):06x}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare kernel and expected stream for RTL testbench")
    parser.add_argument("--in_hex", required=True)
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--kernel", choices=KERNELS.keys(), default="identity5")
    parser.add_argument("--kernel_out", default="sim/kernel.hex")
    parser.add_argument("--expected_out", default="sim/expected.hex")
    args = parser.parse_args()

    frame = read_hex_rgb(Path(args.in_hex), args.width, args.height)
    kernel = KERNELS[args.kernel]

    kernel_out = Path(args.kernel_out)
    expected_out = Path(args.expected_out)
    kernel_out.parent.mkdir(parents=True, exist_ok=True)
    expected_out.parent.mkdir(parents=True, exist_ok=True)

    write_kernel_hex(kernel_out, kernel)
    expected = compute_expected_stream(frame, kernel)
    write_expected_hex(expected_out, expected)

    print(f"Prepared case kernel={args.kernel}")
    print(f"Kernel file: {kernel_out}")
    print(f"Expected file: {expected_out} ({expected.size} samples)")


if __name__ == "__main__":
    main()
