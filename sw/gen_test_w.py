import struct

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1

def to_u64(x):
    return x & MASK64

def sext32(x):
    x &= MASK32
    return x - (1 << 32) if x & 0x80000000 else x

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

def addiw(rd, rs1, imm): return i_type(imm, rs1, 0, rd, 0x1B)
def slliw(rd, rs1, sh):  return i_type(sh & 0x1F, rs1, 1, rd, 0x1B)
def srliw(rd, rs1, sh):  return i_type(sh & 0x1F, rs1, 5, rd, 0x1B)
def sraiw(rd, rs1, sh):  return i_type((0x20 << 5) | (sh & 0x1F), rs1, 5, rd, 0x1B)
def addw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0, rd, 0x3B)
def subw(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 0, rd, 0x3B)
def sllw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 1, rd, 0x3B)
def srlw(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 5, rd, 0x3B)
def sraw(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 5, rd, 0x3B)
def ld(rd, rs1, imm):    return i_type(imm, rs1, 3, rd, 0x03)
def bne(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 1, 0x63)
def addi(rd, rs1, imm):  return i_type(imm, rs1, 0, rd, 0x13)
def jal(rd, imm):        return j_type(imm, rd, 0x6F)

# ---- tiny two-pass assembler: ops are ('word', w) / ('ld', rd, data_idx) / ('bne_fail', rs1, rs2) / ('label', name)
ops = []
data = []

def emit(w): ops.append(('word', w))
def emit_ld(rd, val):
    data.append(to_u64(val))
    ops.append(('ld', rd, len(data) - 1))
def emit_bne_fail(rs1, rs2): ops.append(('bne_fail', rs1, rs2))
def label(name): ops.append(('label', name))

# x1 = a, x2 = b (when needed), x10 = actual result, x11 = expected result
def check_i(op_fn, a, shamt_or_imm, expected):
    emit_ld(1, a)
    emit(op_fn(10, 1, shamt_or_imm))
    emit_ld(11, expected)
    emit_bne_fail(10, 11)

def check_r(op_fn, a, b, expected):
    emit_ld(1, a)
    emit_ld(2, b)
    emit(op_fn(10, 1, 2))
    emit_ld(11, expected)
    emit_bne_fail(10, 11)

# ADDIW: overflow wrap, and negative operand
check_i(addiw, 0x7FFFFFFF, 1, sext32(0x80000000))
check_i(addiw, -5, -10, -15)

# SLLIW: shift by 31 edge, and negative operand
check_i(slliw, 1, 31, sext32(1 << 31))
check_i(slliw, -1, 4, sext32(0xFFFFFFF0))

# SRLIW: shift by 31 edge (logical), and negative-as-32bit operand
check_i(srliw, -1, 31, 1)
check_i(srliw, 0x80000000, 4, 0x08000000)

# SRAIW: shift by 31 edge (arithmetic), and negative operand
check_i(sraiw, 0x80000000, 31, -1)
check_i(sraiw, -16, 2, -4)

# ADDW: overflow wrap, and both-negative
check_r(addw, 0x7FFFFFFF, 1, sext32(0x80000000))
check_r(addw, -100, -200, -300)

# SUBW: underflow wrap, and normal
check_r(subw, -2147483648, 1, sext32(0x7FFFFFFF))
check_r(subw, 5, 10, -5)

# SLLW: shift amount from register, by 31 edge, and negative operand
check_r(sllw, 1, 31, sext32(1 << 31))
check_r(sllw, -1, 4, sext32(0xFFFFFFF0))

# SRLW: shift by 31 edge, and negative-as-32bit operand
check_r(srlw, -1, 31, 1)
check_r(srlw, 0x80000000, 4, 0x08000000)

# SRAW: shift by 31 edge, and negative operand
check_r(sraw, 0x80000000, 31, -1)
check_r(sraw, -16, 2, -4)

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

with open("test_w.bin", "wb") as f:
    for w in words:
        f.write(struct.pack("<I", w))
    for d in data:
        f.write(struct.pack("<Q", d))
