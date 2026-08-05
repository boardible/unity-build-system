#!/usr/bin/env python3
"""Convert a raw RGBA32 frame captured by the `capture_frame_raw` Pipeline command into a PNG.

The engine deliberately does not encode PNGs: `ImageConversion.EncodeToPNG` would put the
compression cost and its allocations inside a process whose perf lane gates on `gcAllocatedMb`.
The Player writes raw bytes plus a JSON sidecar and this does the encoding outside.

Stdlib only — `zlib` and `struct`. That is not austerity for its own sake: Pillow is not installed
on this machine, `Scripts/` runs on bare `python3` with no venv, and the flat-frame analysis in
`probe_game_visuals.py` had to report `rendered-unverified` for exactly that reason. The analysis
here needs no third-party package, so it always runs.

    python3 Scripts/raw_frame_to_png.py <meta.json> [--output frame.png]
    python3 Scripts/raw_frame_to_png.py <meta.json> --analyse-only
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

# A frame that is a near-flat expanse of one colour is the signature of a game that did not render:
# an empty skybox, a black backbuffer, a scene that never booted. Distinguishing that from real
# content is the whole point of looking, so it is measured rather than eyeballed.
FLAT_FRAME_UNIQUE_COLOUR_CEILING = 24


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    """Write 8-bit RGBA rows as a PNG.

    PNG is a sequence of length-prefixed, CRC-suffixed chunks wrapping zlib-compressed scanlines,
    each prefixed with a filter byte. Filter 0 (None) keeps this simple and still compresses well,
    because zlib does the real work.
    """

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit, colour type 6 = RGBA
    raw = b"".join(b"\x00" + row for row in rows)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def load_rows(meta: dict, raw_path: Path) -> tuple[int, int, list[bytes]]:
    width, height = int(meta["width"]), int(meta["height"])
    stride = width * int(meta.get("bytesPerPixel", 4))
    data = raw_path.read_bytes()

    expected = stride * height
    if len(data) < expected:
        raise SystemExit(
            f"{raw_path.name} holds {len(data)} bytes but {width}x{height} RGBA32 needs {expected}. "
            "The capture was truncated."
        )

    rows = [data[y * stride:(y + 1) * stride] for y in range(height)]

    # Metal and OpenGL hand back bottom-up rows. Without this the frame is vertically mirrored,
    # which reads as a rendering bug instead of a row-order convention.
    if meta.get("originBottomLeft", True):
        rows.reverse()
    return width, height, rows


def analyse(width: int, height: int, rows: list[bytes]) -> dict:
    """Sample the frame for colour diversity without decoding every pixel.

    Sampling a grid rather than the whole buffer keeps this fast on a 1792x828 frame while still
    catching a uniformly empty one: a flat frame is flat everywhere, so a sparse sample finds it.
    """
    step_y = max(1, height // 64)
    step_x = max(1, width // 64)
    colours = set()
    opaque = 0
    sampled = 0

    for y in range(0, height, step_y):
        row = rows[y]
        for x in range(0, width, step_x):
            offset = x * 4
            pixel = row[offset:offset + 3]
            if len(pixel) < 3:
                continue
            colours.add(pixel)
            if row[offset + 3] > 8:
                opaque += 1
            sampled += 1

    return {
        "sampledPixels": sampled,
        "uniqueColours": len(colours),
        "opaqueFraction": round(opaque / sampled, 4) if sampled else 0.0,
        "looksFlat": len(colours) <= FLAT_FRAME_UNIQUE_COLOUR_CEILING,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("meta", help="The .json sidecar written beside the .raw capture.")
    parser.add_argument("--output", help="PNG path. Defaults to the raw file with a .png suffix.")
    parser.add_argument(
        "--analyse-only",
        action="store_true",
        help="Report the frame's colour diversity without writing a PNG.",
    )
    args = parser.parse_args(argv)

    meta_path = Path(args.meta)
    if not meta_path.exists():
        raise SystemExit(f"No such sidecar: {meta_path}")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

    raw_path = Path(meta.get("rawPath") or meta_path.with_suffix(".raw"))
    if not raw_path.exists():
        # The Player may have written to its own persistentDataPath while the sidecar travelled;
        # fall back to a sibling of the sidecar before giving up.
        sibling = meta_path.with_suffix(".raw")
        if sibling.exists():
            raw_path = sibling
        else:
            raise SystemExit(f"Raw frame not found at {raw_path} nor {sibling}")

    width, height, rows = load_rows(meta, raw_path)
    report = {
        "raw": str(raw_path),
        "width": width,
        "height": height,
        "graphicsDeviceType": meta.get("graphicsDeviceType"),
        "isBatchMode": meta.get("isBatchMode"),
        "usedAsyncReadback": meta.get("usedAsyncReadback"),
        **analyse(width, height, rows),
    }

    if not args.analyse_only:
        png_path = Path(args.output) if args.output else raw_path.with_suffix(".png")
        write_png(png_path, width, height, rows)
        report["png"] = str(png_path)

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
