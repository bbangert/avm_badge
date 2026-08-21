#!/usr/bin/env python3
"""Convert a TTF/OTF font to the uFont IFF binary format used by AtomGL.

Container sizes (FORM length, record sizes) are big-endian; every payload
struct inside is little-endian packed, matching ufontlib.c/ufontlib.h.

Usage:
    fontconvert.py FONT.ttf SIZE OUT.uf [--mode mono|normal] [--verify]
    fontconvert.py --verify-only OUT.uf [--dump-char C]
"""
import argparse
import struct

FIRST_CP = 32
LAST_CP = 126


def align4(n):
    return (n + 3) & ~3


def rasterize_glyph(face, cp, mode):
    import freetype

    if mode == "mono":
        flags = freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_MONO
    else:
        flags = freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_NORMAL

    face.load_char(chr(cp), flags)
    slot = face.glyph
    bitmap = slot.bitmap
    width, height = bitmap.width, bitmap.rows
    advance_x = slot.advance.x >> 6
    left = slot.bitmap_left
    top = slot.bitmap_top

    nibbles = [0] * (width * height)
    buf = bytes(bitmap.buffer)
    pitch = bitmap.pitch

    if mode == "mono":
        for y in range(height):
            row = buf[y * pitch:(y + 1) * pitch]
            for x in range(width):
                byte = row[x // 8]
                bit = (byte >> (7 - (x % 8))) & 1
                nibbles[y * width + x] = 15 if bit else 0
    else:
        for y in range(height):
            row = buf[y * pitch:(y + 1) * pitch]
            for x in range(width):
                nibbles[y * width + x] = row[x] >> 4

    return {
        "width": width,
        "height": height,
        "advance_x": advance_x,
        "left": left,
        "top": top,
        "nibbles": nibbles,
    }


def pack_bitmap(glyph):
    width, height = glyph["width"], glyph["height"]
    byte_width = width // 2 + width % 2
    out = bytearray(byte_width * height)
    nibbles = glyph["nibbles"]
    for y in range(height):
        for x in range(width):
            v = nibbles[y * width + x] & 0xF
            idx = y * byte_width + x // 2
            if x % 2 == 0:
                out[idx] = (out[idx] & 0xF0) | v
            else:
                out[idx] = (out[idx] & 0x0F) | (v << 4)
    return bytes(out)


def build_iff_record(name, payload):
    assert len(name) == 4
    header = name.encode("ascii") + struct.pack(">I", len(payload))
    body = header + payload
    pad = align4(len(body)) - len(body)
    return body + b"\x00" * pad


def convert(ttf_path, size, mode):
    import freetype

    face = freetype.Face(ttf_path)
    face.set_pixel_sizes(0, size)
    metrics = face.size

    glyphs = []
    for cp in range(FIRST_CP, LAST_CP + 1):
        glyphs.append(rasterize_glyph(face, cp, mode))

    # Hinted pixel fonts can render glyphs taller than the font's own
    # metrics.height/ascender claim, so derive line spacing from the actual
    # rasterized extents (not just face.size) or rows collide.
    rendered = [g for g in glyphs if g["height"] > 0]
    max_top = max((g["top"] for g in rendered), default=metrics.ascender >> 6)
    max_below_baseline = max(
        (max(0, g["height"] - g["top"]) for g in rendered), default=0
    )

    ascender = max(metrics.ascender >> 6, max_top)
    metrics_descender = -(metrics.descender >> 6) if metrics.descender < 0 else 0
    descender = max(metrics_descender, max_below_baseline)
    # Leading between rows, on top of the minimum that avoids glyph
    # collision: proportional to size, with a floor so small fonts still
    # get a visible gap.
    line_gap = max(2, round(size * 0.2))
    advance_y = ascender + descender + line_gap

    bitmap_blob = bytearray()
    glyph_records = []
    for g in glyphs:
        packed = pack_bitmap(g)
        offset = len(bitmap_blob)
        bitmap_blob += packed
        glyph_records.append(
            struct.pack(
                "<HHHhhII",
                g["width"],
                g["height"],
                g["advance_x"],
                g["left"],
                g["top"],
                0,  # compressed_size, unused (uncompressed)
                offset,
            )
        )

    uFH0 = struct.pack("<IBHHH", 1, 0, advance_y, ascender, descender)
    uFP0 = b"".join(glyph_records)
    uFI0 = struct.pack("<III", FIRST_CP, LAST_CP, 0)
    uFB0 = bytes(bitmap_blob)

    records = (
        build_iff_record("uFH0", uFH0)
        + build_iff_record("uFP0", uFP0)
        + build_iff_record("uFI0", uFI0)
        + build_iff_record("uFB0", uFB0)
    )

    body = b"FORM" + b"\x00\x00\x00\x00" + b"uFL0" + records
    total_size = len(body)
    body = b"FORM" + struct.pack(">I", total_size) + b"uFL0" + records
    assert len(body) == total_size

    return body


def parse_iff(data):
    """Re-parse the file the way ufont_parse() does. Returns dict of records."""
    if len(data) < 12:
        raise ValueError("file too short")
    if data[0:4] != b"FORM":
        raise ValueError("missing FORM magic")
    if data[8:12] != b"uFL0":
        raise ValueError("missing uFL0 magic")

    file_size = struct.unpack(">I", data[4:8])[0]
    if len(data) < file_size:
        raise ValueError(
            f"buffer ({len(data)}) smaller than declared file_size ({file_size})"
        )

    pos = 12
    records = {}
    while pos < file_size:
        if pos + 8 > file_size:
            raise ValueError("record header runs past file_size")
        name = data[pos:pos + 4]
        size = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        payload = data[pos + 8:pos + 8 + size]
        if len(payload) != size:
            raise ValueError(f"record {name} payload truncated")
        records[name] = payload
        pos += align4(size + 8)

    return records, file_size


def verify(data, dump_char=None):
    records, file_size = parse_iff(data)

    required = [b"uFH0", b"uFP0", b"uFI0", b"uFB0"]
    missing = [r for r in required if r not in records]
    if missing:
        raise ValueError(f"missing records: {missing}")

    interval_count, compressed, advance_y, ascender, descender = struct.unpack(
        "<IBHHH", records[b"uFH0"]
    )
    print(
        f"uFH0: interval_count={interval_count} compressed={compressed} "
        f"advance_y={advance_y} ascender={ascender} descender={descender}"
    )

    glyph_bytes = records[b"uFP0"]
    n_glyphs = len(glyph_bytes) // 18
    if len(glyph_bytes) % 18 != 0:
        raise ValueError("uFP0 payload not a multiple of 18 bytes")

    glyphs = []
    for i in range(n_glyphs):
        rec = glyph_bytes[i * 18:(i + 1) * 18]
        width, height, advance_x, left, top, compressed_size, data_offset = (
            struct.unpack("<HHHhhII", rec)
        )
        glyphs.append(
            dict(
                width=width,
                height=height,
                advance_x=advance_x,
                left=left,
                top=top,
                compressed_size=compressed_size,
                data_offset=data_offset,
            )
        )

    bitmap_blob = records[b"uFB0"]
    for i, g in enumerate(glyphs):
        byte_width = g["width"] // 2 + g["width"] % 2
        size = byte_width * g["height"]
        end = g["data_offset"] + size
        if end > len(bitmap_blob):
            raise ValueError(
                f"glyph {i} data_offset {g['data_offset']} + size {size} "
                f"({end}) exceeds uFB0 blob length {len(bitmap_blob)}"
            )

    intervals_bytes = records[b"uFI0"]
    n_intervals = len(intervals_bytes) // 12
    if len(intervals_bytes) % 12 != 0:
        raise ValueError("uFI0 payload not a multiple of 12 bytes")
    if n_intervals != interval_count:
        raise ValueError(
            f"interval_count {interval_count} does not match uFI0 record "
            f"length ({n_intervals} intervals)"
        )

    intervals = []
    for i in range(n_intervals):
        rec = intervals_bytes[i * 12:(i + 1) * 12]
        first, last, offset = struct.unpack("<III", rec)
        intervals.append((first, last, offset))
        print(f"uFI0[{i}]: first={first} last={last} offset={offset}")

    print(f"uFP0: {n_glyphs} glyphs, uFB0: {len(bitmap_blob)} bytes")
    print(f"file_size (declared)={file_size} actual={len(data)}")

    if dump_char is not None:
        cp = ord(dump_char)
        idx = None
        for first, last, offset in intervals:
            if first <= cp <= last:
                idx = offset + (cp - first)
                break
        if idx is None:
            print(f"code point {cp} ({dump_char!r}) not covered by any interval")
        else:
            g = glyphs[idx]
            byte_width = g["width"] // 2 + g["width"] % 2
            off = g["data_offset"]
            size = byte_width * g["height"]
            bm = bitmap_blob[off:off + size]
            print(
                f"glyph {dump_char!r}: {g['width']}x{g['height']} "
                f"advance_x={g['advance_x']} left={g['left']} top={g['top']}"
            )
            chars = " .:-=+*#%@"
            for y in range(g["height"]):
                row_chars = []
                for x in range(g["width"]):
                    byte = bm[y * byte_width + x // 2]
                    nib = (byte & 0xF) if x % 2 == 0 else (byte >> 4)
                    row_chars.append(chars[min(nib, 9)] if nib else " ")
                print("".join(row_chars))

    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("ttf", nargs="?", help="path to TTF/OTF font")
    ap.add_argument("size", nargs="?", type=int, help="pixel size to rasterize at")
    ap.add_argument("out", nargs="?", help="output .uf path")
    ap.add_argument(
        "--mode", choices=["mono", "normal"], default="mono",
        help="mono = 1-bit crisp render mapped to 0/15; normal = antialiased, coverage>>4 (default: mono)",
    )
    ap.add_argument("--verify", action="store_true", help="re-parse the output after writing and report")
    ap.add_argument("--verify-only", metavar="UF_FILE", help="only verify an existing .uf file, no conversion")
    ap.add_argument("--dump-char", default="A", help="character to dump as ASCII art during verify (default: A)")
    args = ap.parse_args()

    if args.verify_only:
        with open(args.verify_only, "rb") as f:
            data = f.read()
        verify(data, dump_char=args.dump_char)
        return

    if not (args.ttf and args.size and args.out):
        ap.error("ttf, size, and out are required unless --verify-only is given")

    data = convert(args.ttf, args.size, args.mode)
    with open(args.out, "wb") as f:
        f.write(data)
    print(f"wrote {args.out}: {len(data)} bytes (mode={args.mode}, size={args.size}px)")

    if args.verify:
        verify(data, dump_char=args.dump_char)


if __name__ == "__main__":
    main()
