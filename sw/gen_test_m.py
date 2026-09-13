import struct

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

def tdiv(a, b):  # truncate toward zero, python semantics
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q

def trem(a, b):
    return a - tdiv(a, b) * b

# ---- RV64M expected-value model (spec corner cases) ----
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

def exp_mulw(a, b):   return u64(s32(u32(a) * u32(b)))
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

# ---- instruction encoders ----
def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def i_type(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def b_type(imm, rs2, rs1, funct3, opcode):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | opcode

def j_type(imm, rd, opcode):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 12) & 0xFF) << 12) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 1) & 0x3FF) << 21) | (rd << 7) | opcode

def mul(rd, rs1, rs2):    return r_type(1, rs2, rs1, 0, rd, 0x33)
def mulh(rd, rs1, rs2):   return r_type(1, rs2, rs1, 1, rd, 0x33)
def mulhsu(rd, rs1, rs2): return r_type(1, rs2, rs1, 2, rd, 0x33)
def mulhu(rd, rs1, rs2):  return r_type(1, rs2, rs1, 3, rd, 0x33)
def div(rd, rs1, rs2):    return r_type(1, rs2, rs1, 4, rd, 0x33)
def divu(rd, rs1, rs2):   return r_type(1, rs2, rs1, 5, rd, 0x33)
def rem(rd, rs1, rs2):    return r_type(1, rs2, rs1, 6, rd, 0x33)
def remu(rd, rs1, rs2):   return r_type(1, rs2, rs1, 7, rd, 0x33)
def mulw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 0, rd, 0x3B)
def divw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 4, rd, 0x3B)
def divuw(rd, rs1, rs2):  return r_type(1, rs2, rs1, 5, rd, 0x3B)
def remw(rd, rs1, rs2):   return r_type(1, rs2, rs1, 6, rd, 0x3B)
def remuw(rd, rs1, rs2):  return r_type(1, rs2, rs1, 7, rd, 0x3B)
def ld(rd, rs1, imm):     return i_type(imm, rs1, 3, rd, 0x03)
def bne(rs1, rs2, imm):   return b_type(imm, rs2, rs1, 1, 0x63)
def addi(rd, rs1, imm):   return i_type(imm, rs1, 0, rd, 0x13)
def jal(rd, imm):         return j_type(imm, rd, 0x6F)

# ---- tiny two-pass assembler ----
ops = []
data = []

def emit(w): ops.append(('word', w))
def emit_ld(rd, val):
    data.append(u64(val))
    ops.append(('ld', rd, len(data) - 1))
def emit_bne_fail(rs1, rs2): ops.append(('bne_fail', rs1, rs2))
def label(name): ops.append(('label', name))

def check(op_fn, exp_fn, a, b):
    emit_ld(1, a)
    emit_ld(2, b)
    emit(op_fn(10, 1, 2))
    emit_ld(11, exp_fn(a, b))
    emit_bne_fail(10, 11)

# MUL: normal large, and both-negative
check(mul, exp_mul, 1_000_000, 1_000_000)
check(mul, exp_mul, -5, -7)

# MULH: both-negative (large magnitude so high bits are nonzero), and positive edge
check(mulh, exp_mulh, -(1 << 40), -(1 << 40))
check(mulh, exp_mulh, 1 << 62, 2)

# MULHSU: negative signed operand, and positive signed operand, both with large unsigned operand
check(mulhsu, exp_mulhsu, -(1 << 40), (1 << 64) - 1)
check(mulhsu, exp_mulhsu, 1 << 40, (1 << 63) + 5)

# MULHU: near-max unsigned operands, and large-but-distinct operands
check(mulhu, exp_mulhu, (1 << 64) - 1, (1 << 64) - 1)
check(mulhu, exp_mulhu, 1 << 40, 1 << 40)

# DIV: divide by zero, and signed-overflow (-2^63 / -1)
check(div, exp_div, 42, 0)
check(div, exp_div, -(1 << 63), -1)

# DIVU: divide by zero, and normal large unsigned divide
check(divu, exp_divu, 42, 0)
check(divu, exp_divu, (1 << 64) - 1, 3)

# REM: divide by zero, and negative truncated remainder
check(rem, exp_rem, 42, 0)
check(rem, exp_rem, -7, 2)

# REMU: divide by zero, and normal unsigned remainder
check(remu, exp_remu, 42, 0)
check(remu, exp_remu, (1 << 64) - 1, 3)

# MULW: 32-bit overflow wrap, and both-negative 32-bit
check(mulw, exp_mulw, 0x7FFFFFFF, 2)
check(mulw, exp_mulw, -5, -7)

# DIVW: divide by zero, and signed-overflow (-2^31 / -1)
check(divw, exp_divw, 42, 0)
check(divw, exp_divw, -(1 << 31), -1)

# DIVUW: divide by zero, and normal unsigned divide
check(divuw, exp_divuw, 42, 0)
check(divuw, exp_divuw, 0xFFFFFFFF, 3)

# REMW: negative truncated remainder (required edge case), and divide by zero
check(remw, exp_remw, -7, 2)
check(remw, exp_remw, 42, 0)

# REMUW: divide by zero, and normal unsigned remainder
check(remuw, exp_remuw, 42, 0)
check(remuw, exp_remuw, 0xFFFFFFFF, 3)

label('pass')
emit(addi(31, 0, 1))
emit(jal(0, 0))
label('fail')
emit(addi(31, 0, 0))
emit(jal(0, 0))

# pass 1: instruction addresses and label addresses
addr = 0
label_addr = {}
for kind, *rest in ops:
    if kind == 'label':
        label_addr[rest[0]] = addr
    else:
        addr += 4
num_instrs = addr // 4
data_base = num_instrs * 4

# pass 2: encode
words = []
addr = 0
for entry in ops:
    kind = entry[0]
    if kind == 'label':
        continue
    elif kind == 'word':
        words.append(entry[1])
    elif kind == 'ld':
        _, rd, didx = entry
        words.append(ld(rd, 0, data_base + didx * 8))
    elif kind == 'bne_fail':
        _, rs1, rs2 = entry
        words.append(bne(rs1, rs2, label_addr['fail'] - addr))
    addr += 4

assert data_base < 2048, "data offsets must fit in 12-bit ld immediate"

with open("test_m.bin", "wb") as f:
    for w in words:
        f.write(struct.pack("<I", w))
    for d in data:
        f.write(struct.pack("<Q", d))
