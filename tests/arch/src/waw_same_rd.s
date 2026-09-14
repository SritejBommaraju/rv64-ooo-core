# waw_same_rd
lui x29, 8
ld x1, k0(x0)
ld x1, k1(x0)
addi x1, x0, 3
sd x1, 0(x29)
addi x2, x1, 1
sd x2, 8(x29)
ld x1, k2(x0)
ld x1, k3(x0)
addi x1, x0, 13
sd x1, 16(x29)
addi x2, x1, 1
sd x2, 24(x29)
ld x1, k4(x0)
ld x1, k5(x0)
addi x1, x0, 23
sd x1, 32(x29)
addi x2, x1, 1
sd x2, 40(x29)
ld x1, k6(x0)
ld x1, k7(x0)
addi x1, x0, 33
sd x1, 48(x29)
addi x2, x1, 1
sd x2, 56(x29)
ld x1, k8(x0)
ld x1, k9(x0)
addi x1, x0, 43
sd x1, 64(x29)
addi x2, x1, 1
sd x2, 72(x29)
ld x1, k10(x0)
ld x1, k11(x0)
addi x1, x0, 53
sd x1, 80(x29)
addi x2, x1, 1
sd x2, 88(x29)
ld x1, k12(x0)
ld x1, k13(x0)
addi x1, x0, 63
sd x1, 96(x29)
addi x2, x1, 1
sd x2, 104(x29)
ld x1, k14(x0)
ld x1, k15(x0)
addi x1, x0, 73
sd x1, 112(x29)
addi x2, x1, 1
sd x2, 120(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x1
k1: .dword 0x2
k2: .dword 0xb
k3: .dword 0xc
k4: .dword 0x15
k5: .dword 0x16
k6: .dword 0x1f
k7: .dword 0x20
k8: .dword 0x29
k9: .dword 0x2a
k10: .dword 0x33
k11: .dword 0x34
k12: .dword 0x3d
k13: .dword 0x3e
k14: .dword 0x47
k15: .dword 0x48
