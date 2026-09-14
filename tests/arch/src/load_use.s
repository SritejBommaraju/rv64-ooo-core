# load_use
lui x29, 8
ld x1, k0(x0)
addi x2, x1, 5
sd x2, 0(x29)
ld x3, k1(x0)
ld x4, k0(x0)
add x5, x3, x4
sd x5, 8(x29)
ld x1, k2(x0)
addi x2, x1, 5
sd x2, 16(x29)
ld x3, k3(x0)
ld x4, k2(x0)
add x5, x3, x4
sd x5, 24(x29)
ld x1, k4(x0)
addi x2, x1, 5
sd x2, 32(x29)
ld x3, k5(x0)
ld x4, k4(x0)
add x5, x3, x4
sd x5, 40(x29)
ld x1, k6(x0)
addi x2, x1, 5
sd x2, 48(x29)
ld x3, k7(x0)
ld x4, k6(x0)
add x5, x3, x4
sd x5, 56(x29)
ld x1, k8(x0)
addi x2, x1, 5
sd x2, 64(x29)
ld x3, k9(x0)
ld x4, k8(x0)
add x5, x3, x4
sd x5, 72(x29)
ld x1, k10(x0)
addi x2, x1, 5
sd x2, 80(x29)
ld x3, k11(x0)
ld x4, k10(x0)
add x5, x3, x4
sd x5, 88(x29)
ld x1, k12(x0)
addi x2, x1, 5
sd x2, 96(x29)
ld x3, k13(x0)
ld x4, k12(x0)
add x5, x3, x4
sd x5, 104(x29)
ld x1, k14(x0)
addi x2, x1, 5
sd x2, 112(x29)
ld x3, k15(x0)
ld x4, k14(x0)
add x5, x3, x4
sd x5, 120(x29)
ld x1, k16(x0)
addi x2, x1, 5
sd x2, 128(x29)
ld x3, k17(x0)
ld x4, k16(x0)
add x5, x3, x4
sd x5, 136(x29)
ld x1, k18(x0)
addi x2, x1, 5
sd x2, 144(x29)
ld x3, k19(x0)
ld x4, k18(x0)
add x5, x3, x4
sd x5, 152(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x1
k1: .dword 0x2
k2: .dword 0x8
k3: .dword 0x9
k4: .dword 0xf
k5: .dword 0x10
k6: .dword 0x16
k7: .dword 0x17
k8: .dword 0x1d
k9: .dword 0x1e
k10: .dword 0x24
k11: .dword 0x25
k12: .dword 0x2b
k13: .dword 0x2c
k14: .dword 0x32
k15: .dword 0x33
k16: .dword 0x39
k17: .dword 0x3a
k18: .dword 0x40
k19: .dword 0x41
