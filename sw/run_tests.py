#!/usr/bin/env python3
"""Assembles sw/tests/*.s, runs each against sim/obj_dir/Vtop, and reports PASS/FAIL.
Runs from any cwd. Exits non-zero if any test's outcome differs from expectation."""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SIM_DIR = REPO / "sim"
ASM = REPO / "sw" / "asm.py"
TESTS_DIR = REPO / "sw" / "tests"
BUILD_DIR = REPO / "sw" / "build"
VTOP = SIM_DIR / "obj_dir" / "Vtop"
TIMEOUT_S = 30


def expects_fail(src_path):
    with open(src_path) as f:
        first = f.readline()
    return "EXPECT: FAIL" in first


def run_one(src_path):
    BUILD_DIR.mkdir(exist_ok=True)
    bin_path = BUILD_DIR / (src_path.stem + ".bin")

    r = subprocess.run([sys.executable, str(ASM), str(src_path), "-o", str(bin_path)],
                        capture_output=True, text=True)
    if r.returncode != 0:
        return False, None, f"assemble error: {r.stderr.strip()}"

    try:
        r = subprocess.run([str(VTOP), str(bin_path)], capture_output=True, text=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return False, None, "sim timeout"

    m = re.search(r"PASS at cycle (\d+)", r.stdout)
    if m:
        return True, int(m.group(1)), None
    return False, None, r.stdout.strip() or "no PASS/FAIL output"


def main():
    print(f"building sim/obj_dir/Vtop ...")
    build = subprocess.run(["make", "-C", str(SIM_DIR), "obj_dir/Vtop"], capture_output=True, text=True)
    if build.returncode != 0:
        print(build.stdout)
        print(build.stderr, file=sys.stderr)
        print("build failed")
        return 1

    src_files = sorted(TESTS_DIR.glob("*.s"))
    if not src_files:
        print("no tests found in", TESTS_DIR)
        return 1

    rows = []
    all_ok = True
    for src in src_files:
        expect_fail = expects_fail(src)
        passed, cycles, note = run_one(src)
        as_expected = (passed and not expect_fail) or (not passed and expect_fail)
        all_ok &= as_expected
        rows.append((src.stem, passed, cycles, expect_fail, as_expected, note))

    name_w = max(len(r[0]) for r in rows) + 2
    print(f"\n{'test'.ljust(name_w)}{'result'.ljust(10)}{'cycles'.ljust(10)}{'status'}")
    for name, passed, cycles, expect_fail, as_expected, note in rows:
        result = "PASS" if passed else "FAIL"
        if expect_fail:
            result += " (expected-fail)"
        cyc = str(cycles) if cycles is not None else "-"
        status = "ok" if as_expected else f"UNEXPECTED ({note})" if note else "UNEXPECTED"
        print(f"{name.ljust(name_w)}{result.ljust(10)}{cyc.ljust(10)}{status}")

    print()
    if all_ok:
        print("all tests as expected")
        return 0
    print("one or more tests did not match their expectation")
    return 1


if __name__ == "__main__":
    sys.exit(main())
