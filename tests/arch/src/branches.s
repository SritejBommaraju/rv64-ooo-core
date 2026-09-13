# branches
lui x29, 8
ld x1, k0(x0)
ld x2, k1(x0)
beq x1, x2, bt1
addi x10, x0, 0
jal x0, bd2
bt1: addi x10, x0, 1
bd2: addi x0, x0, 0
sd x10, 0(x29)
ld x1, k2(x0)
ld x2, k3(x0)
beq x1, x2, bt3
addi x10, x0, 0
jal x0, bd4
bt3: addi x10, x0, 1
bd4: addi x0, x0, 0
sd x10, 8(x29)
ld x1, k4(x0)
ld x2, k5(x0)
beq x1, x2, bt5
addi x10, x0, 0
jal x0, bd6
bt5: addi x10, x0, 1
bd6: addi x0, x0, 0
sd x10, 16(x29)
ld x1, k6(x0)
ld x2, k7(x0)
bne x1, x2, bt7
addi x10, x0, 0
jal x0, bd8
bt7: addi x10, x0, 1
bd8: addi x0, x0, 0
sd x10, 24(x29)
ld x1, k8(x0)
ld x2, k9(x0)
bne x1, x2, bt9
addi x10, x0, 0
jal x0, bd10
bt9: addi x10, x0, 1
bd10: addi x0, x0, 0
sd x10, 32(x29)
ld x1, k10(x0)
ld x2, k11(x0)
bne x1, x2, bt11
addi x10, x0, 0
jal x0, bd12
bt11: addi x10, x0, 1
bd12: addi x0, x0, 0
sd x10, 40(x29)
ld x1, k12(x0)
ld x2, k13(x0)
blt x1, x2, bt13
addi x10, x0, 0
jal x0, bd14
bt13: addi x10, x0, 1
bd14: addi x0, x0, 0
sd x10, 48(x29)
ld x1, k14(x0)
ld x2, k15(x0)
blt x1, x2, bt15
addi x10, x0, 0
jal x0, bd16
bt15: addi x10, x0, 1
bd16: addi x0, x0, 0
sd x10, 56(x29)
ld x1, k16(x0)
ld x2, k17(x0)
blt x1, x2, bt17
addi x10, x0, 0
jal x0, bd18
bt17: addi x10, x0, 1
bd18: addi x0, x0, 0
sd x10, 64(x29)
ld x1, k18(x0)
ld x2, k19(x0)
bge x1, x2, bt19
addi x10, x0, 0
jal x0, bd20
bt19: addi x10, x0, 1
bd20: addi x0, x0, 0
sd x10, 72(x29)
ld x1, k20(x0)
ld x2, k21(x0)
bge x1, x2, bt21
addi x10, x0, 0
jal x0, bd22
bt21: addi x10, x0, 1
bd22: addi x0, x0, 0
sd x10, 80(x29)
ld x1, k22(x0)
ld x2, k23(x0)
bge x1, x2, bt23
addi x10, x0, 0
jal x0, bd24
bt23: addi x10, x0, 1
bd24: addi x0, x0, 0
sd x10, 88(x29)
ld x1, k24(x0)
ld x2, k25(x0)
bltu x1, x2, bt25
addi x10, x0, 0
jal x0, bd26
bt25: addi x10, x0, 1
bd26: addi x0, x0, 0
sd x10, 96(x29)
ld x1, k26(x0)
ld x2, k27(x0)
bltu x1, x2, bt27
addi x10, x0, 0
jal x0, bd28
bt27: addi x10, x0, 1
bd28: addi x0, x0, 0
sd x10, 104(x29)
ld x1, k28(x0)
ld x2, k29(x0)
bltu x1, x2, bt29
addi x10, x0, 0
jal x0, bd30
bt29: addi x10, x0, 1
bd30: addi x0, x0, 0
sd x10, 112(x29)
ld x1, k30(x0)
ld x2, k31(x0)
bgeu x1, x2, bt31
addi x10, x0, 0
jal x0, bd32
bt31: addi x10, x0, 1
bd32: addi x0, x0, 0
sd x10, 120(x29)
ld x1, k32(x0)
ld x2, k33(x0)
bgeu x1, x2, bt33
addi x10, x0, 0
jal x0, bd34
bt33: addi x10, x0, 1
bd34: addi x0, x0, 0
sd x10, 128(x29)
ld x1, k34(x0)
ld x2, k35(x0)
bgeu x1, x2, bt35
addi x10, x0, 0
jal x0, bd36
bt35: addi x10, x0, 1
bd36: addi x0, x0, 0
sd x10, 136(x29)
addi x31, x0, 1
halt37: jal x0, halt37
k0: .dword 0x1
k1: .dword 0x1
k2: .dword 0x1
k3: .dword 0x2
k4: .dword 0xffffffffffffffff
k5: .dword 0x1
k6: .dword 0x1
k7: .dword 0x1
k8: .dword 0x1
k9: .dword 0x2
k10: .dword 0xffffffffffffffff
k11: .dword 0x1
k12: .dword 0x1
k13: .dword 0x1
k14: .dword 0x1
k15: .dword 0x2
k16: .dword 0xffffffffffffffff
k17: .dword 0x1
k18: .dword 0x1
k19: .dword 0x1
k20: .dword 0x1
k21: .dword 0x2
k22: .dword 0xffffffffffffffff
k23: .dword 0x1
k24: .dword 0x1
k25: .dword 0x1
k26: .dword 0x1
k27: .dword 0x2
k28: .dword 0xffffffffffffffff
k29: .dword 0x1
k30: .dword 0x1
k31: .dword 0x1
k32: .dword 0x1
k33: .dword 0x2
k34: .dword 0xffffffffffffffff
k35: .dword 0x1
