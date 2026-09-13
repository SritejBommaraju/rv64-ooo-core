# sb/sh/sw/sd then lb/lbu/lh/lhu/lw/lwu/ld from the addresses each was stored
# to: sign/zero extension and little-endian byte order.

ld t0, PATTERN(x0)   # 0x0123456789ABCDEF

sb t0, BUF_B(x0)
lb t1, BUF_B(x0)
li t2, -17            # 0xEF as a signed byte
bne t1, t2, fail
lbu t1, BUF_B(x0)
li t2, 0xEF
bne t1, t2, fail

sh t0, BUF_H(x0)
lh t1, BUF_H(x0)
ld t2, EXP_LH(x0)
bne t1, t2, fail
lhu t1, BUF_H(x0)
ld t2, EXP_LHU(x0)
bne t1, t2, fail

sw t0, BUF_W(x0)
lw t1, BUF_W(x0)
ld t2, EXP_LW(x0)
bne t1, t2, fail
lwu t1, BUF_W(x0)
ld t2, EXP_LWU(x0)
bne t1, t2, fail

sd t0, BUF_D(x0)
ld t1, BUF_D(x0)
bne t1, t0, fail

# little-endian byte order, checked via the word buffer: EF CD AB 89
lb t1, BUF_W(x0)
li t2, -17
bne t1, t2, fail
lbu t1, BUF_W+1(x0)
li t2, 0xCD
bne t1, t2, fail
lbu t1, BUF_W+2(x0)
li t2, 0xAB
bne t1, t2, fail
lb t1, BUF_W+3(x0)
li t2, -119            # 0x89 as a signed byte
bne t1, t2, fail

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin

.org 0x400
PATTERN: .dword 0x0123456789ABCDEF
EXP_LH:  .dword 0xFFFFFFFFFFFFCDEF
EXP_LHU: .dword 0x000000000000CDEF
EXP_LW:  .dword 0xFFFFFFFF89ABCDEF
EXP_LWU: .dword 0x0000000089ABCDEF
BUF_B:   .dword 0
BUF_H:   .dword 0
BUF_W:   .dword 0
BUF_D:   .dword 0
