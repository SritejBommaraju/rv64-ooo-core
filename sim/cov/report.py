#!/usr/bin/env python3
# Parses Verilator --coverage-user output (coverage.dat). Each data line is
#   C '<\x01key\x02value>...' <count>
# a run of \x01-prefixed field names each followed by \x02 and its value
# (f=file, l=line, n=col, page=page, o=cover-property name, h=hier path, ...).
# We key on the 'o' field, which holds the cover label (cov_<NAME>) verbatim.
import argparse
import re
import sys

LINE_RE = re.compile(r"^C '(.*)' (\d+)\s*$")
FIELD_RE = re.compile(r"\x01([a-z]+)\x02([^\x01]*)")


def parse(path):
    points = {}
    with open(path) as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            key, count = m.group(1), int(m.group(2))
            fields = dict(FIELD_RE.findall(key))
            label = fields.get("o", "")
            if not label.startswith("cov_"):
                continue
            points[label] = points.get(label, 0) + count
    return points


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("coverage_dat")
    ap.add_argument("--min-percent", type=float, default=0.0)
    args = ap.parse_args()

    points = parse(args.coverage_dat)
    if not points:
        print(f"no cov_* points found in {args.coverage_dat}")
        return 1

    hit = 0
    for label in sorted(points):
        count = points[label]
        status = "HIT" if count > 0 else "UNHIT"
        if count > 0:
            hit += 1
        print(f"{status:6s} {label:24s} {count}")

    total = len(points)
    pct = 100.0 * hit / total
    print(f"covered: {hit}/{total} ({pct:.1f}%)")
    return 0 if pct >= args.min_percent else 1


if __name__ == "__main__":
    sys.exit(main())
