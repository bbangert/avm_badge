#!/usr/bin/env python3
"""Check that build artifacts fit the partitions they are flashed to."""
import csv, os, sys

FLASH = 0x400000

def parse_size(s):
    s = s.strip()
    mult = {"K": 1024, "M": 1024 * 1024}.get(s[-1].upper(), 1)
    return int(s[:-1], 0) * mult if mult > 1 else int(s, 0)

def main(argv):
    if len(argv) < 2:
        sys.exit("usage: check_partitions.py <partitions.csv> [label=path ...]")
    artifacts = dict(a.split("=", 1) for a in argv[2:])
    parts, bad = [], False

    with open(argv[1]) as fh:
        for row in csv.reader(fh):
            if not row or row[0].strip().startswith("#"):
                continue
            name = row[0].strip()
            parts.append((name, parse_size(row[3]), parse_size(row[4])))

    print(f"{'partition':<12}{'offset':>10}{'size':>10}{'used':>10}{'free':>10}  ")
    for name, off, size in parts:
        used = os.path.getsize(artifacts[name]) if name in artifacts else None
        shown = f"{used:,}" if used is not None else "-"
        free = f"{size - used:,}" if used is not None else "-"
        print(f"{name:<12}{hex(off):>10}{size:>10,}{shown:>10}{free:>10}")
        if used is not None and used > size:
            print(f"ERROR: {name} overflows by {used - size:,} bytes", file=sys.stderr)
            bad = True

    ordered = sorted(parts, key=lambda p: p[1])
    for (n1, o1, s1), (n2, o2, _) in zip(ordered, ordered[1:]):
        if o1 + s1 > o2:
            print(f"ERROR: {n1} overlaps {n2}", file=sys.stderr)
            bad = True

    end = max(o + s for _, o, s in parts)
    print(f"\nhighest end {hex(end)}, unallocated tail {FLASH - end:,} bytes")
    if end > FLASH:
        print(f"ERROR: table runs {end - FLASH:,} bytes past 4MB", file=sys.stderr)
        bad = True
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
