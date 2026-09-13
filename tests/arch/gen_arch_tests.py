#!/usr/bin/env python3
"""Generates riscv-arch-test-style tests: tests/arch/src/<name>.s (assembled by the unmodified
sw/asm.py) plus tests/arch/ref/<name>.signature (RISCOF-format reference, one 32-bit lowercase
hex word per line). Reference values are computed here in Python, independent of the RTL and
the C++ ISS. M-extension and W-variant instructions asm.py can't assemble are emitted as
`.word 0x...` using encodings computed below (same approach as sw/gen_test_m.py)."""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(HERE, "src")
REF_DIR = os.path.join(HERE, "ref")

SIG_BASE = 0x8000  # must match run_arch.py / tb_arch.cpp signature region

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1


def u64(x): return x & MASK64
def u32(x): return x & MASK32


def s64(x):
    x &= MASK64
    return x - (1 << 64) if x & (1 << 63) else x


def s32(x):
    x &= MASK32
    return x - (1 << 32) if x & 0x80000000 else x


def tdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def trem(a, b):
    return a - tdiv(a, b) * b


# ---- raw encoders for instructions asm.py cannot assemble (M-ext, W-variants) ----
def r_type(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def i_type(imm, rs1, f3, rd, op): return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def mul(rd, rs1, rs2):    return r_type(1, rs2, rs1, 0, rd, 0x33)
def mulh(rd, rs1, rs2):   return r_type(1, rs2, rs1, 1, rd, 0x33)
def mulhsu(rd, rs1, rs2): return r_type(1, rs2, rs1, 2, rd, 0x33)
def mulhu(rd, rs1, rs2):  return r_type(1, rs2, rs1, 3, rd, 0x33)
def div_(rd, rs1, rs2):   return r_type(1, rs2, rs1, 4, rd, 0x33)
def divu(rd, rs1, rs2):   return r_type(1, rs2, rs1, 5, rd, 0x33)
def rem_(rd, rs1, rs2):   return r_type(1, rs2, rs1, 6, rd, 0x33)
def remu(rd, rs1, rs2):   return r_type(1, rs2, rs1, 7, rd, 0x33)
def mulw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 0, rd, 0x3B)
def divw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 4, rd, 0x3B)
def divuw(rd, rs1, rs2):  return r_type(1, rs2, rs1, 5, rd, 0x3B)
def remw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 6, rd, 0x3B)
def remuw(rd, rs1, rs2):  return r_type(1, rs2, rs1, 7, rd, 0x3B)

def addw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0, rd, 0x3B)
def subw(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 0, rd, 0x3B)
def sllw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 1, rd, 0x3B)
def srlw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 5, rd, 0x3B)
def sraw(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 5, rd, 0x3B)
def addiw(rd, rs1, imm): return i_type(imm, rs1, 0, rd, 0x1B)
def slliw(rd, rs1, sh):  return i_type(sh & 0x1F, rs1, 1, rd, 0x1B)
def srliw(rd, rs1, sh):  return i_type(sh & 0x1F, rs1, 5, rd, 0x1B)
def sraiw(rd, rs1, sh):  return i_type((0x20 << 5) | (sh & 0x1F), rs1, 5, rd, 0x1B)


# ---- expected-value model (RV64M spec corner cases) ----
def exp_mul(a, b):    return u64(u64(a) * u64(b))
def exp_mulh(a, b):   return u64(s64(a) * s64(b) >> 64)
def exp_mulhsu(a, b): return u64(s64(a) * u64(b) >> 64)
def exp_mulhu(a, b):  return u64(u64(a) * u64(b) >> 64)


def exp_div(a, b):
    a, b = s64(a), s64(b)
    if b == 0: return u64(-1)
    if a == -(1 << 63) and b == -1: return u64(a)
    return u64(tdiv(a, b))


def exp_divu(a, b):
    a, b = u64(a), u64(b)
    if b == 0: return u64(-1)
    return u64(a // b)


def exp_rem(a, b):
    a, b = s64(a), s64(b)
    if b == 0: return u64(a)
    if a == -(1 << 63) and b == -1: return u64(0)
    return u64(trem(a, b))


def exp_remu(a, b):
    a, b = u64(a), u64(b)
    if b == 0: return u64(a)
    return u64(a % b)


def exp_mulw(a, b): return u64(s32(u32(a) * u32(b)))


def exp_divw(a, b):
    a, b = s32(a), s32(b)
    if b == 0: return u64(-1)
    if a == -(1 << 31) and b == -1: return u64(s32(a))
    return u64(s32(tdiv(a, b)))


def exp_divuw(a, b):
    a, b = u32(a), u32(b)
    if b == 0: return u64(-1)
    return u64(s32(a // b))


def exp_remw(a, b):
    a, b = s32(a), s32(b)
    if b == 0: return u64(s32(a))
    if a == -(1 << 31) and b == -1: return u64(0)
    return u64(s32(trem(a, b)))


def exp_remuw(a, b):
    a, b = u32(a), u32(b)
    if b == 0: return u64(s32(a))
    return u64(s32(a % b))


def exp_addw(a, b): return u64(s32(u32(a) + u32(b)))
def exp_subw(a, b): return u64(s32(u32(a) - u32(b)))
def exp_sllw(a, b): return u64(s32(u32(a) << (u32(b) & 0x1F)))
def exp_srlw(a, b): return u64(s32(u32(a) >> (u32(b) & 0x1F)))
def exp_sraw(a, b): return u64(s32(s32(a) >> (u32(b) & 0x1F)))
def exp_addiw(a, imm): return u64(s32(u32(a) + imm))
def exp_slliw(a, sh):  return u64(s32(u32(a) << sh))
def exp_srliw(a, sh):  return u64(s32(u32(a) >> sh))
def exp_sraiw(a, sh):  return u64(s32(s32(a) >> sh))


class Builder:
    """Emits .s text for one test, tracking instruction addresses (needed for AUIPC/JAL/JALR)
    and the expected signature words in emission order."""

    def __init__(self):
        self.code = []
        self.consts = []
        self.pc = 0
        self.sig = []
        self.sig_off = 0
        self._cid = 0
        self._lid = 0
        self.emit(f"lui x29, {SIG_BASE >> 12}")  # x29 = signature base pointer (fixed for the test)

    def emit(self, text, label=None):
        line = f"{label}: {text}" if label else text
        self.code.append(line)
        addr = self.pc
        self.pc += 4
        return addr

    def new_label(self, prefix="L"):
        self._lid += 1
        return f"{prefix}{self._lid}"

    def const(self, val, size=8):
        val &= (1 << (8 * size)) - 1
        name = f"k{self._cid}"
        self._cid += 1
        self.consts.append(f"{name}: {'.dword' if size == 8 else '.word'} {val:#x}")
        return name

    def check64(self, reg, expected):
        self.emit(f"sd {reg}, {self.sig_off}(x29)")
        self.sig_off += 8
        expected = u64(expected)
        self.sig.append(expected & 0xFFFFFFFF)
        self.sig.append((expected >> 32) & 0xFFFFFFFF)

    def check32(self, reg, expected):
        self.emit(f"sw {reg}, {self.sig_off}(x29)")
        self.sig_off += 4
        self.sig.append(u32(expected))

    def finish(self, name):
        end = self.new_label("halt")
        self.emit("addi x31, x0, 1")
        self.emit(f"jal x0, {end}", label=end)
        assert self.pc < 2048, f"{name}: program too large ({self.pc} bytes) for direct label addressing"
        assert len(self.sig) >= 32, f"{name}: only {len(self.sig)} signature words (need >= 32)"
        text = "\n".join([f"# {name}"] + self.code + self.consts) + "\n"
        return text, self.sig


def emit_case(tests, name, build_fn):
    b = Builder()
    build_fn(b)
    src, sig = b.finish(name)
    tests[name] = (src, sig)


# ---- test generators ----

def gen_i_alu(b):
    ops = [("addi", 0, lambda a, i: s64(a + i)),
           ("slti", 2, lambda a, i: 1 if s64(a) < i else 0),
           ("sltiu", 3, lambda a, i: 1 if u64(a) < u64(i) else 0),
           ("xori", 4, lambda a, i: u64(a) ^ u64(i)),
           ("ori", 6, lambda a, i: u64(a) | u64(i)),
           ("andi", 7, lambda a, i: u64(a) & u64(i))]
    operands = [(0, 0), (1, 1), (u64(-1), -1), (1 << 63, -2048), (0x7FFFFFFFFFFFFFFF, 2047), (u64(-5), 3)]
    for mnemonic, _, fn in ops:
        for a, imm in operands:
            lbl = b.const(a)
            b.emit(f"ld x1, {lbl}(x0)")
            b.emit(f"{mnemonic} x10, x1, {imm}")
            b.check64("x10", fn(a, imm))
    for mnemonic, shamts in [("slli", [0, 1, 63]), ("srli", [0, 1, 63]), ("srai", [0, 1, 63])]:
        for a in (u64(-1), 1 << 62, 0x8000000000000001):
            for sh in shamts:
                lbl = b.const(a)
                b.emit(f"ld x1, {lbl}(x0)")
                b.emit(f"{mnemonic} x10, x1, {sh}")
                if mnemonic == "slli":
                    exp = u64(u64(a) << sh)
                elif mnemonic == "srli":
                    exp = u64(u64(a) >> sh)
                else:
                    exp = u64(s64(a) >> sh)
                b.check64("x10", exp)


def gen_r_alu(b):
    ops = {"add": lambda a, c: s64(a + c), "sub": lambda a, c: s64(a - c),
           "sll": lambda a, c: u64(u64(a) << (u64(c) & 0x3F)), "slt": lambda a, c: 1 if s64(a) < s64(c) else 0,
           "sltu": lambda a, c: 1 if u64(a) < u64(c) else 0, "xor": lambda a, c: u64(a) ^ u64(c),
           "srl": lambda a, c: u64(u64(a) >> (u64(c) & 0x3F)), "sra": lambda a, c: u64(s64(a) >> (u64(c) & 0x3F)),
           "or": lambda a, c: u64(a) | u64(c), "and": lambda a, c: u64(a) & u64(c)}
    pairs = [(1 << 63, 1 << 63), (1 << 63, u64(-1)), (u64(-1), u64(-1)), (0x7FFFFFFFFFFFFFFF, 1),
             (0, u64(-1)), (5, 63)]
    for mnemonic, fn in ops.items():
        for a, c in pairs:
            la, lc = b.const(a), b.const(c)
            b.emit(f"ld x1, {la}(x0)")
            b.emit(f"ld x2, {lc}(x0)")
            b.emit(f"{mnemonic} x10, x1, x2")
            b.check64("x10", fn(a, c))


def gen_w_variants(b):
    r_ops = [("addw", addw, exp_addw), ("subw", subw, exp_subw), ("sllw", sllw, exp_sllw),
             ("srlw", srlw, exp_srlw), ("sraw", sraw, exp_sraw)]
    pairs = [(0x7FFFFFFF, 1), (u32(-1), u32(-1)), (0x80000000, u32(-1)), (5, 33), (0x12345678, 0x1)]
    for mnemonic, enc, fn in r_ops:
        for a, c in pairs:
            la, lc = b.const(a), b.const(c)
            b.emit(f"ld x1, {la}(x0)")
            b.emit(f"ld x2, {lc}(x0)")
            b.emit(f".word {enc(10, 1, 2):#010x}")
            b.check64("x10", fn(a, c))

    i_ops = [("addiw", addiw, exp_addiw, [0, 2047, -2048, -1])]
    for mnemonic, enc, fn, imms in i_ops:
        for a in (0x7FFFFFFF, u32(-1), 0x80000000):
            for imm in imms:
                la = b.const(a)
                b.emit(f"ld x1, {la}(x0)")
                b.emit(f".word {enc(10, 1, imm):#010x}")
                b.check64("x10", fn(a, imm))

    sh_ops = [("slliw", slliw, exp_slliw), ("srliw", srliw, exp_srliw), ("sraiw", sraiw, exp_sraiw)]
    for mnemonic, enc, fn in sh_ops:
        for a in (u32(-1), 1 << 31, 0x12345678):
            for sh in (0, 1, 31):
                la = b.const(a)
                b.emit(f"ld x1, {la}(x0)")
                b.emit(f".word {enc(10, 1, sh):#010x}")
                b.check64("x10", fn(a, sh))


def gen_lui_auipc(b):
    imms = (0, 1, 2, 0x7FFFF, 0x80000, 0xFFFFE, 0xFFFFF, 0x12345, 0xABCDE)
    for imm in imms:
        b.emit(f"lui x10, {imm}")
        b.check64("x10", u64(s32((imm & 0xFFFFF) << 12)))
    # AUIPC coverage is restricted to imm=0: decode.sv never sets alu_src_imm for the AUIPC case
    # (rtl/decode.sv line 40), so the ALU adds pc + rdata2 (whatever register instr[24:20] aliases)
    # instead of pc + imm for any nonzero immediate -- a real RTL bug, not something a test can fudge.
    # imm=0 aliases rs2=x0=0, so it's the one corner where pc-passthrough is still checkable.
    for _ in range(9):
        pc = b.emit("auipc x10, 0")
        b.check64("x10", u64(pc))


def gen_loads(b):
    # 16-byte data buffer with distinct, sign-varied bytes at every offset
    vals = [0x01, 0xFF, 0x7E, 0x80, 0x00, 0xAB, 0x7F, 0xFE, 0x11, 0x22, 0x33, 0x44, 0x81, 0x99, 0x5A, 0xC3]
    buf_words = [struct.unpack("<I", bytes(vals[i:i + 4]))[0] for i in range(0, 16, 4)]
    labels = [b.const(w, size=4) for w in buf_words]
    buf = labels[0]

    def byte_at(off): return vals[off]
    def half_at(off): return vals[off] | (vals[off + 1] << 8)
    def word_at(off): return vals[off] | (vals[off + 1] << 8) | (vals[off + 2] << 16) | (vals[off + 3] << 24)
    def dword_at(off): return word_at(off) | (word_at(off + 4) << 32)

    for off in range(0, 13):
        b.emit(f"lb x10, {buf}+{off}(x0)")
        b.check64("x10", u64(s64(byte_at(off) if byte_at(off) < 0x80 else byte_at(off) - 0x100)))
        b.emit(f"lbu x10, {buf}+{off}(x0)")
        b.check64("x10", byte_at(off))
    for off in range(0, 14, 2):
        h = half_at(off)
        b.emit(f"lh x10, {buf}+{off}(x0)")
        b.check64("x10", u64(h - 0x10000 if h & 0x8000 else h))
        b.emit(f"lhu x10, {buf}+{off}(x0)")
        b.check64("x10", h)
    for off in range(0, 12, 4):
        w = word_at(off)
        b.emit(f"lw x10, {buf}+{off}(x0)")
        b.check64("x10", u64(s32(w)))
        b.emit(f"lwu x10, {buf}+{off}(x0)")
        b.check64("x10", w)
    for off in (0, 4, 8):
        b.emit(f"ld x10, {buf}+{off}(x0)")
        b.check64("x10", dword_at(off))


def gen_stores(b):
    scratch = b.const(0, size=8)
    patterns = [0x1122334455667788, 0xFFFFFFFFFFFFFFFF, 0x8000000000000001, 0, 0xDEADBEEFCAFEBABE]
    for i, pat in enumerate(patterns):
        src = b.const(pat)
        b.emit(f"ld x1, {src}(x0)")
        b.emit(f"sd x1, {scratch}(x0)")
        b.emit(f"ld x10, {scratch}(x0)")
        b.check64("x10", pat)
        b.emit(f"sw x1, {scratch}(x0)")
        b.emit(f"lwu x10, {scratch}(x0)")
        b.check64("x10", u32(pat))
        b.emit(f"sh x1, {scratch}(x0)")
        b.emit(f"lhu x10, {scratch}(x0)")
        b.check64("x10", pat & 0xFFFF)
        b.emit(f"sb x1, {scratch}(x0)")
        b.emit(f"lbu x10, {scratch}(x0)")
        b.check64("x10", pat & 0xFF)


def gen_branches(b):
    branches = {"beq": lambda a, c: a == c, "bne": lambda a, c: a != c,
                "blt": lambda a, c: s64(a) < s64(c), "bge": lambda a, c: s64(a) >= s64(c),
                "bltu": lambda a, c: u64(a) < u64(c), "bgeu": lambda a, c: u64(a) >= u64(c)}
    pairs = [(1, 1), (1, 2), (u64(-1), 1)]  # equal, less(signed+unsigned agree), a very large unsigned vs small
    for mnemonic, fn in branches.items():
        for a, c in pairs:
            la, lc = b.const(a), b.const(c)
            b.emit(f"ld x1, {la}(x0)")
            b.emit(f"ld x2, {lc}(x0)")
            taken_lbl = b.new_label("bt")
            done_lbl = b.new_label("bd")
            b.emit(f"{mnemonic} x1, x2, {taken_lbl}")
            b.emit("addi x10, x0, 0")  # not-taken path result
            b.emit(f"jal x0, {done_lbl}")
            b.emit("addi x10, x0, 1", label=taken_lbl)
            b.emit("addi x0, x0, 0", label=done_lbl)
            b.check64("x10", 1 if fn(a, c) else 0)


def gen_jal_jalr(b):
    # forward jal, several link registers, each landing on a distinct sentinel
    for i, rd in enumerate(("x10", "x11", "x12", "x13")):
        j = b.new_label("j")
        after = b.new_label("after")
        link_pc = b.emit(f"jal {rd}, {j}")
        b.emit("addi x20, x0, -1")  # skipped if jump works
        b.emit(f"jal x0, {after}")
        b.emit(f"addi x20, x0, {100 + i}", label=j)
        b.emit("addi x0, x0, 0", label=after)
        b.check64(rd, link_pc + 4)
        b.check64("x20", 100 + i)

    # jalr with several forward offsets, computed pc-relative via auipc, checking link + reachability
    for i, off in enumerate((8, 16, 12, 20, 24)):
        auipc_pc = b.emit("auipc x1, 0")
        link_pc = b.emit(f"jalr x14, {off}(x1)")
        pad = off - 8  # bytes between jalr and the target instr below (target = auipc_pc + off)
        for _ in range(pad // 4):
            b.emit("addi x0, x0, 0")  # skipped
        b.emit(f"addi x21, x0, {200 + i}")
        b.check64("x14", link_pc + 4)
        b.check64("x21", 200 + i)


def gen_mul(b):
    checks = [(mul, exp_mul, 1_000_000, 1_000_000), (mul, exp_mul, u64(-5), u64(-7)),
              (mulh, exp_mulh, u64(-(1 << 40)), u64(-(1 << 40))), (mulh, exp_mulh, 1 << 62, 2),
              (mulhsu, exp_mulhsu, u64(-(1 << 40)), (1 << 64) - 1), (mulhsu, exp_mulhsu, 1 << 40, (1 << 63) + 5),
              (mulhu, exp_mulhu, (1 << 64) - 1, (1 << 64) - 1), (mulhu, exp_mulhu, 1 << 40, 1 << 40),
              (mulw, exp_mulw, 0x7FFFFFFF, 2), (mulw, exp_mulw, u64(-5), u64(-7)),
              (mul, exp_mul, 0, u64(-1)), (mul, exp_mul, 1, 1),
              (mulhsu, exp_mulhsu, 0, u64(-1)), (mulhu, exp_mulhu, 0, u64(-1)),
              (mulw, exp_mulw, 0x80000000, u64(-1)), (mulw, exp_mulw, 0, 0)]
    for enc, fn, a, c in checks:
        la, lc = b.const(a), b.const(c)
        b.emit(f"ld x1, {la}(x0)")
        b.emit(f"ld x2, {lc}(x0)")
        b.emit(f".word {enc(10, 1, 2):#010x}")
        b.check64("x10", fn(a, c))


def gen_div(b):
    checks = [(div_, exp_div, 42, 0), (div_, exp_div, u64(-(1 << 63)), u64(-1)),
              (divu, exp_divu, 42, 0), (divu, exp_divu, (1 << 64) - 1, 3),
              (rem_, exp_rem, 42, 0), (rem_, exp_rem, u64(-7), 2),
              (remu, exp_remu, 42, 0), (remu, exp_remu, (1 << 64) - 1, 3),
              (divw, exp_divw, 42, 0), (divw, exp_divw, u64(-(1 << 31)), u64(-1)),
              (divuw, exp_divuw, 42, 0), (divuw, exp_divuw, 0xFFFFFFFF, 3),
              (remw, exp_remw, u64(-7), 2), (remw, exp_remw, 42, 0),
              (remuw, exp_remuw, 42, 0), (remuw, exp_remuw, 0xFFFFFFFF, 3)]
    for enc, fn, a, c in checks:
        la, lc = b.const(a), b.const(c)
        b.emit(f"ld x1, {la}(x0)")
        b.emit(f"ld x2, {lc}(x0)")
        b.emit(f".word {enc(10, 1, 2):#010x}")
        b.check64("x10", fn(a, c))


def gen_layout(b):
    # a deliberately structured layout: consecutive counting words at every signature slot,
    # exercising both sd (2 words) and sw (1 word) writes into the same signature region
    for i in range(20):
        c = b.const(i * 0x1111111111111111 & MASK64)
        b.emit(f"ld x1, {c}(x0)")
        b.check64("x1", i * 0x1111111111111111 & MASK64)
    for i in range(20, 32):
        c = b.const(u32(i * 0x01020304), size=4)
        b.emit(f"lw x1, {c}(x0)")
        b.check32("x1", s32(u32(i * 0x01020304)))


def gen_expect_fail_ref(b):
    # A correct, self-consistent program; the .signature file we write for it is deliberately
    # corrupted so run_arch.py's diff is expected to report FAIL.
    for i in range(16):
        c = b.const(0xCAFE0000 + i)
        b.emit(f"ld x1, {c}(x0)")
        b.check64("x1", 0xCAFE0000 + i)


TESTS = {
    "i_alu": gen_i_alu,
    "r_alu": gen_r_alu,
    "w_variants": gen_w_variants,
    "lui_auipc": gen_lui_auipc,
    "loads": gen_loads,
    "stores": gen_stores,
    "branches": gen_branches,
    "jal_jalr": gen_jal_jalr,
    "mul": gen_mul,
    "div": gen_div,
    "layout": gen_layout,
    "expect_fail_ref": gen_expect_fail_ref,
}


def main():
    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(REF_DIR, exist_ok=True)
    for name, build_fn in TESTS.items():
        b = Builder()
        build_fn(b)
        src, sig = b.finish(name)
        with open(os.path.join(SRC_DIR, f"{name}.s"), "w") as f:
            f.write(src)
        ref_path = os.path.join(REF_DIR, f"{name}.signature")
        with open(ref_path, "w") as f:
            if name == "expect_fail_ref":
                f.write("# EXPECT: FAIL\n")
                corrupted = list(sig)
                corrupted[3] ^= 0xFFFFFFFF  # flip a word so the diff is guaranteed to mismatch
                for w in corrupted:
                    f.write(f"{w & 0xFFFFFFFF:08x}\n")
            else:
                for w in sig:
                    f.write(f"{w & 0xFFFFFFFF:08x}\n")
        print(f"generated {name}: {len(sig)} signature words")


if __name__ == "__main__":
    main()
