# div
lui x29, 8
ld x1, k0(x0)
ld x2, k1(x0)
.word 0x0220c533
sd x10, 0(x29)
ld x1, k2(x0)
ld x2, k3(x0)
.word 0x0220c533
sd x10, 8(x29)
ld x1, k4(x0)
ld x2, k5(x0)
.word 0x0220d533
sd x10, 16(x29)
ld x1, k6(x0)
ld x2, k7(x0)
.word 0x0220d533
sd x10, 24(x29)
ld x1, k8(x0)
ld x2, k9(x0)
.word 0x0220e533
sd x10, 32(x29)
ld x1, k10(x0)
ld x2, k11(x0)
.word 0x0220e533
sd x10, 40(x29)
ld x1, k12(x0)
ld x2, k13(x0)
.word 0x0220f533
sd x10, 48(x29)
ld x1, k14(x0)
ld x2, k15(x0)
.word 0x0220f533
sd x10, 56(x29)
ld x1, k16(x0)
ld x2, k17(x0)
.word 0x0220c53b
sd x10, 64(x29)
ld x1, k18(x0)
ld x2, k19(x0)
.word 0x0220c53b
sd x10, 72(x29)
ld x1, k20(x0)
ld x2, k21(x0)
.word 0x0220d53b
sd x10, 80(x29)
ld x1, k22(x0)
ld x2, k23(x0)
.word 0x0220d53b
sd x10, 88(x29)
ld x1, k24(x0)
ld x2, k25(x0)
.word 0x0220e53b
sd x10, 96(x29)
ld x1, k26(x0)
ld x2, k27(x0)
.word 0x0220e53b
sd x10, 104(x29)
ld x1, k28(x0)
ld x2, k29(x0)
.word 0x0220f53b
sd x10, 112(x29)
ld x1, k30(x0)
ld x2, k31(x0)
.word 0x0220f53b
sd x10, 120(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x2a
k1: .dword 0x0
k2: .dword 0x8000000000000000
k3: .dword 0xffffffffffffffff
k4: .dword 0x2a
k5: .dword 0x0
k6: .dword 0xffffffffffffffff
k7: .dword 0x3
k8: .dword 0x2a
k9: .dword 0x0
k10: .dword 0xfffffffffffffff9
k11: .dword 0x2
k12: .dword 0x2a
k13: .dword 0x0
k14: .dword 0xffffffffffffffff
k15: .dword 0x3
k16: .dword 0x2a
k17: .dword 0x0
k18: .dword 0xffffffff80000000
k19: .dword 0xffffffffffffffff
k20: .dword 0x2a
k21: .dword 0x0
k22: .dword 0xffffffff
k23: .dword 0x3
k24: .dword 0xfffffffffffffff9
k25: .dword 0x2
k26: .dword 0x2a
k27: .dword 0x0
k28: .dword 0x2a
k29: .dword 0x0
k30: .dword 0xffffffff
k31: .dword 0x3
