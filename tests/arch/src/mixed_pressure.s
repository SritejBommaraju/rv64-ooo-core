# mixed_pressure
lui x29, 8
ld x1, k0(x0)
ld x2, k1(x0)
ld x3, k2(x0)
ld x4, k3(x0)
ld x5, k4(x0)
ld x6, k5(x0)
ld x7, k6(x0)
ld x8, k7(x0)
ld x9, k8(x0)
ld x10, k9(x0)
ld x11, k10(x0)
ld x12, k11(x0)
ld x13, k12(x0)
ld x14, k13(x0)
ld x15, k14(x0)
ld x16, k15(x0)
ld x17, k16(x0)
ld x18, k17(x0)
ld x19, k18(x0)
ld x20, k19(x0)
ld x21, k20(x0)
ld x22, k21(x0)
ld x23, k22(x0)
ld x24, k23(x0)
ld x25, k24(x0)
ld x26, k25(x0)
ld x27, k26(x0)
ld x28, k27(x0)
ld x30, k28(x0)
ld x31, k29(x0)
addi x1, x1, 1
addi x2, x2, 2
addi x3, x3, 3
addi x4, x4, 4
addi x5, x5, 5
addi x6, x6, 6
addi x7, x7, 7
addi x8, x8, 8
addi x9, x9, 9
addi x10, x10, 10
addi x11, x11, 11
addi x12, x12, 12
addi x13, x13, 13
addi x14, x14, 14
addi x15, x15, 15
addi x16, x16, 16
addi x17, x17, 17
addi x18, x18, 18
addi x19, x19, 19
addi x20, x20, 20
addi x21, x21, 21
addi x22, x22, 22
addi x23, x23, 23
addi x24, x24, 24
addi x25, x25, 25
addi x26, x26, 26
addi x27, x27, 27
addi x28, x28, 28
addi x30, x30, 30
addi x31, x31, 31
sd x1, 0(x29)
sd x2, 8(x29)
sd x3, 16(x29)
sd x4, 24(x29)
sd x5, 32(x29)
sd x6, 40(x29)
sd x7, 48(x29)
sd x8, 56(x29)
sd x9, 64(x29)
sd x10, 72(x29)
sd x11, 80(x29)
sd x12, 88(x29)
sd x13, 96(x29)
sd x14, 104(x29)
sd x15, 112(x29)
sd x16, 120(x29)
sd x17, 128(x29)
sd x18, 136(x29)
sd x19, 144(x29)
sd x20, 152(x29)
sd x21, 160(x29)
sd x22, 168(x29)
sd x23, 176(x29)
sd x24, 184(x29)
sd x25, 192(x29)
sd x26, 200(x29)
sd x27, 208(x29)
sd x28, 216(x29)
sd x30, 224(x29)
sd x31, 232(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x1001
k1: .dword 0x2002
k2: .dword 0x3003
k3: .dword 0x4004
k4: .dword 0x5005
k5: .dword 0x6006
k6: .dword 0x7007
k7: .dword 0x8008
k8: .dword 0x9009
k9: .dword 0xa00a
k10: .dword 0xb00b
k11: .dword 0xc00c
k12: .dword 0xd00d
k13: .dword 0xe00e
k14: .dword 0xf00f
k15: .dword 0x10010
k16: .dword 0x11011
k17: .dword 0x12012
k18: .dword 0x13013
k19: .dword 0x14014
k20: .dword 0x15015
k21: .dword 0x16016
k22: .dword 0x17017
k23: .dword 0x18018
k24: .dword 0x19019
k25: .dword 0x1a01a
k26: .dword 0x1b01b
k27: .dword 0x1c01c
k28: .dword 0x1e01e
k29: .dword 0x1f01f
