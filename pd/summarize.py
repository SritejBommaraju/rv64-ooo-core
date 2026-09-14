#!/usr/bin/env python3
# Parses per-block *_synth.log / *_sta.txt / *_synth.status / *_synth.time into out/summary.txt.
import re
import sys
import os


def parse_synth(log_path):
    """Return (cells, area_um2, seq_pct) from the yosys `stat -liberty` block, or (None,)*3."""
    if not os.path.exists(log_path):
        return None, None, None
    text = open(log_path, errors="replace").read()
    m = re.search(r"^\s*(\d+)\s+([\d.eE+\-]+)\s+cells\s*$", text, re.M)
    cells = int(m.group(1)) if m else None
    m = re.search(r"Chip area for module.*?:\s*([\d.eE+\-]+)", text)
    area = float(m.group(1)) if m else None
    m = re.search(r"of which used for sequential elements:\s*[\d.eE+\-]+\s*\(([\d.]+)%\)", text)
    seq_pct = float(m.group(1)) if m else None
    return cells, area, seq_pct


def parse_sta(sta_path):
    """Return (startpoint, endpoint, arrival_ns, wns_ns) from an OpenSTA report, or (None,)*4."""
    if not os.path.exists(sta_path):
        return None, None, None, None
    text = open(sta_path, errors="replace").read()
    m = re.search(r"^Startpoint:\s*(\S+)", text, re.M)
    start = m.group(1) if m else None
    m = re.search(r"^Endpoint:\s*(\S+)", text, re.M)
    end = m.group(1) if m else None
    m = re.search(r"^\s*([\d.\-]+)\s+data arrival time\s*$", text, re.M)
    arrival = float(m.group(1)) if m else None
    m = re.search(r"^wns max\s+([\-\d.]+)", text, re.M)
    wns = float(m.group(1)) if m else None
    return start, end, arrival, wns


def fmax_mhz(arrival, wns, period=10.0):
    if wns is None or arrival is None:
        return None
    if wns < 0:
        # violating: fmax bounded by period - wns (i.e. period must grow to (period - wns))
        return 1000.0 / (period - wns)
    # met: use data arrival + assumed setup margin (period - wns == arrival + setup)
    setup = period - wns - arrival
    return 1000.0 / (arrival + setup)


def main():
    out_dir = sys.argv[1]
    blocks = sys.argv[2].split()

    rows = []
    for b in blocks:
        status_path = os.path.join(out_dir, f"{b}_synth.status")
        status = open(status_path).read().strip() if os.path.exists(status_path) else "ERROR"
        time_path = os.path.join(out_dir, f"{b}_synth.time")
        wall_s = open(time_path).read().strip() if os.path.exists(time_path) else "?"

        cells, area, seq_pct = parse_synth(os.path.join(out_dir, f"{b}_synth.log"))
        start, end, arrival, wns = parse_sta(os.path.join(out_dir, f"{b}_sta.txt"))
        fmax = fmax_mhz(arrival, wns)

        if status == "OK" and cells is None:
            status = "ERROR"  # yosys "succeeded" but stats never printed -- treat as error

        rows.append({
            "block": b, "status": status, "wall_s": wall_s,
            "cells": cells, "area": area, "seq_pct": seq_pct,
            "path": f"{start} -> {end}" if start and end else "n/a",
            "arrival": arrival, "wns": wns, "fmax": fmax,
        })

    def fmt(v, spec="{:.2f}"):
        return spec.format(v) if isinstance(v, (int, float)) else "n/a"

    lines = []
    header = f"{'block':<18}{'status':<9}{'cells':>8}{'area um^2':>14}{'seq%':>7}{'path':<48}{'arr ns':>9}{'WNS ns':>9}{'fmax MHz':>10}{'wall s':>8}"
    lines.append(header)
    lines.append("-" * len(header))
    for r in rows:
        lines.append(
            f"{r['block']:<18}{r['status']:<9}{fmt(r['cells'], '{:d}') if r['cells'] else 'n/a':>8}"
            f"{fmt(r['area']):>14}{fmt(r['seq_pct']):>7}{r['path']:<48}"
            f"{fmt(r['arrival']):>9}{fmt(r['wns']):>9}{fmt(r['fmax']):>10}{r['wall_s']:>8}"
        )

    summary = "\n".join(lines) + "\n"
    with open(os.path.join(out_dir, "summary.txt"), "w") as f:
        f.write(summary)
    print(summary)


if __name__ == "__main__":
    main()
