#!/usr/bin/env python3
"""Two-pass RV64I mini-assembler. stdlib only. See --selftest for a self-check."""
import argparse
import re
import struct
import sys

OP     = 0b0110011
OPIMM  = 0b0010011
LOAD   = 0b0000011
STORE  = 0b0100011
BRANCH = 0b1100011
LUI    = 0b0110111
AUIPC  = 0b0010111
JAL    = 0b1101111
JALR   = 0b1100111

REGS = {f"x{i}": i for i in range(32)}
REGS.update({
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "fp": 8,
    "s0": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
})

R_TYPE = {  # mnemonic -> (funct3, funct7)
    "add": (0, 0), "sub": (0, 0b0100000), "sll": (1, 0), "slt": (2, 0),
    "sltu": (3, 0), "xor": (4, 0), "srl": (5, 0), "sra": (5, 0b0100000),
    "or": (6, 0), "and": (7, 0),
}
I_ARITH = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
I_SHIFT = {"slli": (1, 0), "srli": (5, 0), "srai": (5, 0b010000)}  # (funct3, funct6)
LOADS = {"lb": 0, "lh": 1, "lw": 2, "ld": 3, "lbu": 4, "lhu": 5, "lwu": 6}
STORES = {"sb": 0, "sh": 1, "sw": 2, "sd": 3}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}

DIRECTIVES = {".word", ".dword", ".align", ".org"}


class AsmError(Exception):
    pass


def parse_int(tok):
    tok = tok.strip()
    neg = tok.startswith("-")
    if neg:
        tok = tok[1:]
    val = int(tok, 16) if tok.lower().startswith("0x") else int(tok, 10)
    return -val if neg else val


def parse_reg(tok):
    tok = tok.strip()
    if tok not in REGS:
        raise AsmError(f"unknown register '{tok}'")
    return REGS[tok]


def split_operands(s):
    return [t.strip() for t in s.split(",")] if s.strip() else []


def resolve(tok, labels):
    """A label, 'label+N'/'label-N', or a plain numeric literal."""
    tok = tok.strip()
    if tok in labels:
        return labels[tok]
    m = re.match(r"^(\w+)([+-]\w+)$", tok)
    if m and m.group(1) in labels:
        return labels[m.group(1)] + parse_int(m.group(2))
    return parse_int(tok)


def parse_mem_operand(tok):
    # "imm(reg)" -> (imm_str, reg_name)
    m = re.match(r"^([+\-\w]+)\((\w+)\)$", tok.strip())
    if not m:
        raise AsmError(f"expected 'imm(reg)', got '{tok}'")
    return m.group(1), m.group(2)


def rtype(f7, rs2, rs1, f3, rd, opcode):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def itype(imm, rs1, f3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def stype(imm, rs2, rs1, f3, opcode):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | opcode


def btype(imm, rs2, rs1, f3, opcode):
    imm &= 0x1FFF
    b12, b11, b10_5, b4_1 = (imm >> 12) & 1, (imm >> 11) & 1, (imm >> 5) & 0x3F, (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def utype(imm32, rd, opcode):
    return (imm32 & 0xFFFFF000) | (rd << 7) | opcode


def jtype(imm, rd, opcode):
    imm &= 0x1FFFFF
    b20, b19_12, b11, b10_1 = (imm >> 20) & 1, (imm >> 12) & 0xFF, (imm >> 11) & 1, (imm >> 1) & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode


def expand_pseudo(mnemonic, operand_str):
    """Rewrite a pseudo-instruction into a real one, or return (mnemonic, operand_str) unchanged."""
    ops = split_operands(operand_str)
    if mnemonic == "nop":
        return "addi", "x0,x0,0"
    if mnemonic == "mv":
        return "addi", f"{ops[0]},{ops[1]},0"
    if mnemonic == "j":
        return "jal", f"x0,{ops[0]}"
    if mnemonic == "li":
        imm = parse_int(ops[1])
        if not (-2048 <= imm <= 2047):
            raise AsmError(f"li: immediate {imm} out of 12-bit range")
        return "addi", f"{ops[0]},x0,{imm}"
    if mnemonic == "not":
        return "xori", f"{ops[0]},{ops[1]},-1"
    if mnemonic == "neg":
        return "sub", f"{ops[0]},x0,{ops[1]}"
    if mnemonic == "beqz":
        return "beq", f"{ops[0]},x0,{ops[1]}"
    if mnemonic == "bnez":
        return "bne", f"{ops[0]},x0,{ops[1]}"
    return mnemonic, operand_str


def encode_insn(mnemonic, operand_str, addr, labels):
    ops = split_operands(operand_str)

    if mnemonic in R_TYPE:
        rd, rs1, rs2 = parse_reg(ops[0]), parse_reg(ops[1]), parse_reg(ops[2])
        f3, f7 = R_TYPE[mnemonic]
        return rtype(f7, rs2, rs1, f3, rd, OP)

    if mnemonic in I_ARITH:
        rd, rs1 = parse_reg(ops[0]), parse_reg(ops[1])
        imm = parse_int(ops[2])
        if not (-2048 <= imm <= 2047):
            raise AsmError(f"{mnemonic}: immediate {imm} out of 12-bit range")
        return itype(imm, rs1, I_ARITH[mnemonic], rd, OPIMM)

    if mnemonic in I_SHIFT:
        rd, rs1 = parse_reg(ops[0]), parse_reg(ops[1])
        shamt = parse_int(ops[2])
        if not (0 <= shamt <= 63):
            raise AsmError(f"{mnemonic}: shift amount {shamt} out of range")
        f3, f6 = I_SHIFT[mnemonic]
        return itype((f6 << 6) | shamt, rs1, f3, rd, OPIMM)

    if mnemonic in LOADS:
        rd = parse_reg(ops[0])
        off_str, rs1_tok = parse_mem_operand(ops[1])
        rs1, imm = parse_reg(rs1_tok), resolve(off_str, labels)
        if not (-2048 <= imm <= 2047):
            raise AsmError(f"{mnemonic}: offset {imm} out of 12-bit range")
        return itype(imm, rs1, LOADS[mnemonic], rd, LOAD)

    if mnemonic in STORES:
        rs2 = parse_reg(ops[0])
        off_str, rs1_tok = parse_mem_operand(ops[1])
        rs1, imm = parse_reg(rs1_tok), resolve(off_str, labels)
        if not (-2048 <= imm <= 2047):
            raise AsmError(f"{mnemonic}: offset {imm} out of 12-bit range")
        return stype(imm, rs2, rs1, STORES[mnemonic], STORE)

    if mnemonic in BRANCHES:
        rs1, rs2 = parse_reg(ops[0]), parse_reg(ops[1])
        target = ops[2]
        offset = labels[target] - addr if target in labels else parse_int(target)
        if offset % 2 != 0:
            raise AsmError(f"{mnemonic}: misaligned target offset {offset}")
        if not (-4096 <= offset <= 4094):
            raise AsmError(f"{mnemonic}: target offset {offset} out of range")
        return btype(offset, rs2, rs1, BRANCHES[mnemonic], BRANCH)

    if mnemonic == "jal":
        rd = parse_reg(ops[0])
        target = ops[1]
        offset = labels[target] - addr if target in labels else parse_int(target)
        if offset % 2 != 0:
            raise AsmError(f"jal: misaligned target offset {offset}")
        if not (-1048576 <= offset <= 1048574):
            raise AsmError(f"jal: target offset {offset} out of range")
        return jtype(offset, rd, JAL)

    if mnemonic == "jalr":
        rd = parse_reg(ops[0])
        off_str, rs1_tok = parse_mem_operand(ops[1])
        rs1, imm = parse_reg(rs1_tok), resolve(off_str, labels)
        if not (-2048 <= imm <= 2047):
            raise AsmError(f"jalr: offset {imm} out of 12-bit range")
        return itype(imm, rs1, 0, rd, JALR)

    if mnemonic in ("lui", "auipc"):
        rd = parse_reg(ops[0])
        imm = parse_int(ops[1])
        if imm < 0:
            imm &= 0xFFFFF
        if imm > 0xFFFFF:
            raise AsmError(f"{mnemonic}: immediate {imm} out of 20-bit range")
        opcode = LUI if mnemonic == "lui" else AUIPC
        return utype(imm << 12, rd, opcode)

    raise AsmError(f"unknown mnemonic '{mnemonic}'")


def split_line(line):
    """Strip comments, split off an optional leading 'label:', return (label_or_None, rest)."""
    line = line.split("#", 1)[0].rstrip()
    if not line.strip():
        return None, ""
    label = None
    if ":" in line:
        idx = line.index(":")
        label = line[:idx].strip()
        line = line[idx + 1:]
    return label, line.strip()


def split_mnemonic(rest):
    parts = rest.split(None, 1)
    mnemonic = parts[0]
    operand_str = parts[1] if len(parts) > 1 else ""
    return mnemonic, operand_str


def assemble(source_lines):
    """Two-pass assemble. Returns bytes of the flat little-endian image."""
    labels = {}
    statements = []  # (kind, addr, mnemonic, operand_str)
    pc = 0

    # pass 1: addresses and labels
    for lineno, raw in enumerate(source_lines, 1):
        try:
            label, rest = split_line(raw)
            if label:
                if label in labels:
                    raise AsmError(f"duplicate label '{label}'")
                labels[label] = pc
            if not rest:
                continue
            mnemonic, operand_str = split_mnemonic(rest)
            if mnemonic == ".word":
                statements.append(("word", pc, None, operand_str))
                pc += 4
            elif mnemonic == ".dword":
                statements.append(("dword", pc, None, operand_str))
                pc += 8
            elif mnemonic == ".align":
                n = parse_int(operand_str)
                pc = (pc + n - 1) // n * n
                statements.append(("align", pc, None, None))
            elif mnemonic == ".org":
                pc = parse_int(operand_str)
                statements.append(("org", pc, None, None))
            else:
                mnemonic, operand_str = expand_pseudo(mnemonic, operand_str)
                statements.append(("insn", pc, mnemonic, operand_str))
                pc += 4
        except AsmError as e:
            raise AsmError(f"line {lineno}: {e}")

    # pass 2: encode
    buf = bytearray()

    def ensure(n):
        if len(buf) < n:
            buf.extend(b"\x00" * (n - len(buf)))

    for lineno, (kind, addr, mnemonic, operand_str) in enumerate(statements, 1):
        try:
            if kind in ("org", "align"):
                ensure(addr)
            elif kind == "word":
                val = labels[operand_str.strip()] if operand_str.strip() in labels else parse_int(operand_str)
                ensure(addr + 4)
                buf[addr:addr + 4] = struct.pack("<I", val & 0xFFFFFFFF)
            elif kind == "dword":
                val = labels[operand_str.strip()] if operand_str.strip() in labels else parse_int(operand_str)
                ensure(addr + 8)
                buf[addr:addr + 8] = struct.pack("<Q", val & 0xFFFFFFFFFFFFFFFF)
            elif kind == "insn":
                word = encode_insn(mnemonic, operand_str, addr, labels)
                ensure(addr + 4)
                buf[addr:addr + 4] = struct.pack("<I", word)
        except AsmError as e:
            raise AsmError(f"line {lineno}: {e}")

    return bytes(buf)


TEST1_SOURCE = """
addi x1, x0, 5
addi x2, x0, 7
add x3, x1, x2
addi x4, x0, 12
beq x3, x4, pass
addi x31, x0, 0
fail: jal x0, fail
pass: addi x31, x0, 1
loop: jal x0, loop
"""

TEST1_EXPECTED = [
    0x00500093, 0x00700113, 0x002081B3, 0x00C00213, 0x00418663,
    0x00000F93, 0x0000006F, 0x00100F93, 0x0000006F,
]

# Roundtrip source covering every real (non-pseudo) mnemonic, hand-verified against
# the RISC-V spec encoding tables (not against the RTL).
ROUNDTRIP_SOURCE = """
add x1, x2, x3
sub x1, x2, x3
sll x1, x2, x3
slt x1, x2, x3
sltu x1, x2, x3
xor x1, x2, x3
srl x1, x2, x3
sra x1, x2, x3
or x1, x2, x3
and x1, x2, x3
addi x1, x2, 4
slti x1, x2, 4
sltiu x1, x2, 4
xori x1, x2, 4
ori x1, x2, 4
andi x1, x2, 4
slli x1, x2, 4
srli x1, x2, 4
srai x1, x2, 4
lb x1, 4(x2)
lh x1, 4(x2)
lw x1, 4(x2)
ld x1, 4(x2)
lbu x1, 4(x2)
lhu x1, 4(x2)
lwu x1, 4(x2)
sb x3, 4(x2)
sh x3, 4(x2)
sw x3, 4(x2)
sd x3, 4(x2)
beq x2, x3, Lbeq
Lbeq:
bne x2, x3, Lbne
Lbne:
blt x2, x3, Lblt
Lblt:
bge x2, x3, Lbge
Lbge:
bltu x2, x3, Lbltu
Lbltu:
bgeu x2, x3, Lbgeu
Lbgeu:
jal x1, Ljal
Ljal:
jalr x1, 4(x2)
lui x1, 0x12345
auipc x1, 0x12345
"""

ROUNDTRIP_EXPECTED = [
    0x003100B3, 0x403100B3, 0x003110B3, 0x003120B3, 0x003130B3,
    0x003140B3, 0x003150B3, 0x403150B3, 0x003160B3, 0x003170B3,
    0x00410093, 0x00412093, 0x00413093, 0x00414093, 0x00416093,
    0x00417093, 0x00411093, 0x00415093, 0x40415093,
    0x00410083, 0x00411083, 0x00412083, 0x00413083, 0x00414083,
    0x00415083, 0x00416083,
    0x00310223, 0x00311223, 0x00312223, 0x00313223,
    0x00310263, 0x00311263, 0x00314263, 0x00315263, 0x00316263, 0x00317263,
    0x004000EF, 0x004100E7,
    0x123450B7, 0x12345097,
]


def selftest():
    words = struct.unpack("<9I", assemble(TEST1_SOURCE.splitlines()))
    assert list(words) == TEST1_EXPECTED, f"test1 mismatch: {[hex(w) for w in words]}"

    img = assemble(ROUNDTRIP_SOURCE.splitlines())
    n = len(ROUNDTRIP_EXPECTED)
    words = struct.unpack(f"<{n}I", img[:n * 4])
    for i, (got, want) in enumerate(zip(words, ROUNDTRIP_EXPECTED)):
        assert got == want, f"roundtrip insn {i}: got {got:#010x} want {want:#010x}"

    print("selftest OK")


def main():
    ap = argparse.ArgumentParser(description="RV64I mini-assembler")
    ap.add_argument("source", nargs="?", help=".s file to assemble")
    ap.add_argument("-o", "--output", help="output .bin file")
    ap.add_argument("--selftest", action="store_true", help="run built-in self-test and exit")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return

    if not args.source:
        ap.error("source file required unless --selftest")

    out_path = args.output or re.sub(r"\.s$", ".bin", args.source)
    with open(args.source) as f:
        lines = f.readlines()
    try:
        img = assemble(lines)
    except AsmError as e:
        print(f"{args.source}: {e}", file=sys.stderr)
        sys.exit(1)
    with open(out_path, "wb") as f:
        f.write(img)


if __name__ == "__main__":
    main()
