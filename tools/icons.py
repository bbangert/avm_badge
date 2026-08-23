#!/usr/bin/env python3
"""Convert the source PNG icons into raw rgba8888 for AtomGL.

AtomGL accepts exactly one image format, rgba8888, and its draw loop takes a
no-blend fast path only when a pixel's alpha is 0xFF (dcs_lcd_draw.c:79). A
pixel with alpha 0 ends the current span early and forces a fresh O(items)
scan for the next one. The panel background is black, so every pixel is
emitted fully opaque and composited onto black rather than left transparent.

The source art is black-or-colour on an opaque white background with
anti-aliased edges. Keying out pure white alone would leave light halos, so
the white component is removed per pixel instead:

  greyscale art  ->  255 - P          (black on white becomes white on black)
  colour art     ->  P - min(R,G,B)   (removes white, keeps hue)

Greyscale is detected per file: if every pixel has R == G == B the art is
monochrome and gets inverted, otherwise it keeps its colour.

Output goes to firmware/assets/icons/<name>@<w>x<h>.rgba, named by meaning
rather than by colour so the firmware never has to know that the square is
red. Badge.Icons globs that directory at compile time.

Usage: python3 firmware/tools/icons.py [--check]
  --check  report what would change without writing
"""

import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "icons")
OUT = os.path.join(ROOT, "firmware", "assets", "icons")

# Source art is named for how it looks; the firmware wants what it means.
RENAME = {
    "red-rectangle": "square",
    "orange-triangle": "triangle",
    "yellow-cross": "cross",
    "green-circle": "circle",
    "blue-clover": "clover",
    "purple-diamond": "diamond",
}


def decode_png(path):
    """Decode a non-interlaced 8-bit RGBA PNG to (width, height, pixels)."""
    blob = open(path, "rb").read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    pos, idat, header = 8, b"", None
    while pos < len(blob):
        (length,) = struct.unpack(">I", blob[pos : pos + 4])
        kind = blob[pos + 4 : pos + 8]
        data = blob[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            idat += data
        pos += 12 + length

    width, height, depth, colour, _comp, _filt, interlace = header
    if (depth, colour, interlace) != (8, 6, 0):
        raise ValueError(
            f"{path}: need 8-bit RGBA non-interlaced, got depth={depth} "
            f"colour_type={colour} interlace={interlace}"
        )

    raw = zlib.decompress(idat)
    bpp, stride = 4, width * 4
    out, prev, pos = bytearray(), bytearray(stride), 0

    for _ in range(height):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride

        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = prev[i]
            upleft = prev[i - bpp] if i >= bpp else 0

            if filter_type == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                pa, pb, pc = abs(up - upleft), abs(left - upleft), abs(left + up - 2 * upleft)
                if pa <= pb and pa <= pc:
                    pred = left
                elif pb <= pc:
                    pred = up
                else:
                    pred = upleft
                line[i] = (line[i] + pred) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"{path}: unknown filter {filter_type}")

        out += line
        prev = line

    return width, height, bytes(out)


def is_greyscale(pixels):
    return all(
        pixels[i] == pixels[i + 1] == pixels[i + 2] for i in range(0, len(pixels), 4)
    )


def to_rgba8888(pixels, greyscale):
    """Composite onto black, opaque everywhere."""
    out = bytearray(len(pixels))

    for i in range(0, len(pixels), 4):
        r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]

        if greyscale:
            r, g, b = 255 - r, 255 - g, 255 - b
        else:
            white = min(r, g, b)
            r, g, b = r - white, g - white, b - white

        out[i], out[i + 1], out[i + 2], out[i + 3] = r, g, b, 0xFF

    return bytes(out)


def main():
    check = "--check" in sys.argv

    if not os.path.isdir(SRC):
        sys.exit(f"no source directory: {SRC}")

    if not check:
        os.makedirs(OUT, exist_ok=True)

    sources = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    if not sources:
        sys.exit(f"no PNGs in {SRC}")

    written, total = [], 0

    for filename in sources:
        stem = filename[:-4]
        name = RENAME.get(stem, stem).replace("-", "_")

        width, height, pixels = decode_png(os.path.join(SRC, filename))
        greyscale = is_greyscale(pixels)
        data = to_rgba8888(pixels, greyscale)

        assert len(data) == width * height * 4

        target = os.path.join(OUT, f"{name}@{width}x{height}.rgba")
        mode = "invert" if greyscale else "colour"
        total += len(data)

        if check:
            state = "same" if _same(target, data) else "differs"
            print(f"{filename:24} -> {os.path.basename(target):26} {mode:6} {state}")
        else:
            with open(target, "wb") as handle:
                handle.write(data)
            written.append(os.path.basename(target))
            print(f"{filename:24} -> {os.path.basename(target):26} {mode:6} {len(data):6} bytes")

    print(f"\n{len(sources)} icons, {total} bytes total")

    if not check:
        _prune(written)


def _same(path, data):
    return os.path.exists(path) and open(path, "rb").read() == data


def _prune(written):
    """Drop outputs whose source PNG is gone, so a rename cannot leave a stale icon."""
    for stale in sorted(set(os.listdir(OUT)) - set(written)):
        if stale.endswith(".rgba"):
            os.remove(os.path.join(OUT, stale))
            print(f"removed stale {stale}")


if __name__ == "__main__":
    main()
