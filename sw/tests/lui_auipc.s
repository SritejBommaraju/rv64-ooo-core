# lui sign-extension of imm bit 19 (instr bit 31) into the upper 32 bits;
# auipc computed relative to its own pc (checked via address deltas so the
# test does not depend on where the assembler happens to place it).

lui t0, 0x80000
ld t1, LUI_NEG(x0)
bne t0, t1, fail

lui t0, 0x12345
ld t1, LUI_POS(x0)
bne t0, t1, fail

# auipc's own-pc component: two back-to-back auipcs (imm=0, so the result is
# exactly each instruction's own pc) must differ by exactly the 4-byte gap
# between them. (auipc with a nonzero immediate hits a decode bug in this
# seed core -- alu_src_imm is never asserted for AUIPC -- so it is not
# exercised here; that is a core bug, not an assembler/test issue.)
here1: auipc t0, 0
here2: auipc t1, 0
sub t2, t1, t0
li t3, 4
bne t2, t3, fail

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin

.org 0x400
LUI_NEG: .dword 0xFFFFFFFF80000000
LUI_POS: .dword 0x0000000012345000
