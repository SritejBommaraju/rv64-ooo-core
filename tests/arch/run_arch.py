#!/usr/bin/env python3
"""Builds a DUT sim dir, assembles every tests/arch/src/*.s with the unmodified sw/asm.py, runs each
through the Verilator TB, and diffs the dumped signature against tests/arch/ref/*.signature —
mirroring riscv-arch-test/RISCOF's compile-run-diff flow. --dut selects the core top under test:
'inorder' (default) builds/runs sim/arch, 'ooo' builds/runs sim/ooo_core against the identical CLI."""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC_DIR = os.path.join(HERE, "src")
REF_DIR = os.path.join(HERE, "ref")
ASM_PY = os.path.join(ROOT, "sw", "asm.py")
BUILD_DIR = os.path.join(HERE, "build")

DUTS = {
    "inorder": {"dir": os.path.join(ROOT, "sim", "arch"), "exe": "Vtop"},
    "ooo": {"dir": os.path.join(ROOT, "sim", "ooo_core"), "exe": "Vooo_top"},
}

SIG_BASE = 0x8000
FAIL_MARKER = "# EXPECT: FAIL"


def build_tb(dut, sim_dir):
    if not os.path.exists(os.path.join(sim_dir, "Makefile")):
        rel = os.path.relpath(sim_dir, ROOT).replace(os.sep, "/")
        sys.exit(f"DUT {dut}: {rel} not present")
    r = subprocess.run(["make", "build"], cwd=sim_dir, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        sys.exit(f"{sim_dir} build failed")


def load_ref(path):
    with open(path) as f:
        lines = [l.rstrip("\n") for l in f if l.strip() != ""]
    expect_fail = bool(lines) and lines[0] == FAIL_MARKER
    if expect_fail:
        lines = lines[1:]
    return expect_fail, lines


def assemble(src_path, bin_path):
    r = subprocess.run([sys.executable, ASM_PY, src_path, "-o", bin_path], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        return False
    return True


def run_tb(exe, bin_path, sig_out, num_words):
    sig_end = SIG_BASE + 4 * num_words
    return subprocess.run([exe, bin_path, "--sig-begin", f"{SIG_BASE:#x}",
                            "--sig-end", f"{sig_end:#x}", "--sig-out", sig_out],
                           capture_output=True, text=True)


def diff_signatures(got_words, ref_words):
    n = min(len(got_words), len(ref_words))
    for i in range(n):
        if got_words[i] != ref_words[i]:
            return i
    if len(got_words) != len(ref_words):
        return n
    return None


def main():
    ap = argparse.ArgumentParser(description="Run the arch-test corpus against a selectable DUT")
    ap.add_argument("--dut", choices=sorted(DUTS), default="inorder", help="core top under test")
    ap.add_argument("--only", help="run only the test with this name")
    ap.add_argument("--keep-going", action="store_true", help="don't stop early on a build/assemble error")
    args = ap.parse_args()

    dut = DUTS[args.dut]
    sim_dir, exe_name = dut["dir"], dut["exe"]
    build_tb(args.dut, sim_dir)
    exe = os.path.join(sim_dir, "obj_dir", exe_name)
    os.makedirs(BUILD_DIR, exist_ok=True)

    names = sorted(n[:-2] for n in os.listdir(SRC_DIR) if n.endswith(".s"))
    if args.only:
        if args.only not in names:
            sys.exit(f"no such test: {args.only}")
        names = [args.only]
    rows = []
    any_unexpected = False

    for name in names:
        src_path = os.path.join(SRC_DIR, f"{name}.s")
        ref_path = os.path.join(REF_DIR, f"{name}.signature")
        if not os.path.exists(ref_path):
            rows.append((name, 0, "FAIL", "missing reference", False))
            any_unexpected = True
            if not args.keep_going:
                break
            continue

        expect_fail, ref_words = load_ref(ref_path)
        bin_path = os.path.join(BUILD_DIR, f"{name}.bin")
        sig_path = os.path.join(BUILD_DIR, f"{name}.signature")

        if not assemble(src_path, bin_path):
            rows.append((name, len(ref_words), "FAIL", "assemble error", False))
            any_unexpected = True
            if not args.keep_going:
                break
            continue

        r = run_tb(exe, bin_path, sig_path, len(ref_words))
        if r.returncode != 0 and "PASS" not in r.stdout:
            rows.append((name, len(ref_words), "FAIL", "sim did not halt (PASS)", False))
            if not expect_fail:
                any_unexpected = True
                if not args.keep_going:
                    break
            continue

        with open(sig_path) as f:
            got_words = [l.strip() for l in f if l.strip()]

        mismatch = diff_signatures(got_words, ref_words)
        passed = mismatch is None
        as_expected = passed if not expect_fail else not passed

        status = "PASS" if passed else "FAIL"
        detail = "-" if passed else f"word[{mismatch}]: got {got_words[mismatch] if mismatch < len(got_words) else '<missing>'} want {ref_words[mismatch] if mismatch < len(ref_words) else '<missing>'}"
        if expect_fail:
            status += " (expected-fail)" if not passed else " (UNEXPECTED PASS)"
        rows.append((name, len(ref_words), status, detail, as_expected))
        if not as_expected:
            any_unexpected = True
            if not args.keep_going:
                break

    name_w = max(len(r[0]) for r in rows) + 2
    print(f"DUT: {args.dut}")
    print(f"{'test'.ljust(name_w)}{'words':>7}  {'result':<24}detail")
    print("-" * (name_w + 7 + 2 + 24 + 20))
    for name, words, status, detail, _ in rows:
        print(f"{name.ljust(name_w)}{words:>7}  {status:<24}{detail}")

    if any_unexpected:
        print("\nFAILED: one or more tests had an unexpected outcome")
        sys.exit(1)
    print("\nall tests as expected")
    sys.exit(0)


if __name__ == "__main__":
    main()
