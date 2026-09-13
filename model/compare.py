#!/usr/bin/env python3
# Diffs RTL testbench final register state against the ISS golden model for the same program.
import subprocess
import sys
import tempfile
import os

def run_dump(cmd, dump_path):
    subprocess.run(cmd, check=False)
    with open(dump_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    return {l.split()[0]: l.split()[1] for l in lines}

def main():
    if len(sys.argv) < 2:
        print("usage: compare.py <program.bin>")
        return 1
    prog = sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    with tempfile.TemporaryDirectory() as td:
        rtl_dump = os.path.join(td, "rtl.regs")
        iss_dump = os.path.join(td, "iss.regs")

        rtl_bin = os.path.join(repo_root, "sim", "obj_dir", "Vtop")
        iss_bin = os.path.join(script_dir, "iss")

        rtl_regs = run_dump([rtl_bin, prog, "--dump-regs", rtl_dump], rtl_dump)
        iss_regs = run_dump([iss_bin, prog, "--dump-regs", iss_dump], iss_dump)

    keys = [f"x{i}" for i in range(32)] + ["pc"]
    mismatches = [k for k in keys if rtl_regs.get(k) != iss_regs.get(k)]

    if not mismatches:
        print("MATCH")
        return 0

    print(f"{'reg':<6}{'rtl':<20}{'iss':<20}")
    for k in mismatches:
        print(f"{k:<6}{rtl_regs.get(k, '-'):<20}{iss_regs.get(k, '-'):<20}")
    return 1

if __name__ == "__main__":
    sys.exit(main())
