# loop_wrap
lui x29, 8
ld x1, k0(x0)
addi x1, x1, 3
sd x1, 0(x29)
addi x1, x1, -5
sd x1, 8(x29)
addi x1, x1, 100
sd x1, 16(x29)
addi x1, x1, -2048
sd x1, 24(x29)
addi x1, x1, 2047
sd x1, 32(x29)
addi x1, x1, 7
sd x1, 40(x29)
addi x1, x1, -1
sd x1, 48(x29)
addi x1, x1, 42
sd x1, 56(x29)
addi x1, x1, 1000
sd x1, 64(x29)
addi x1, x1, -333
sd x1, 72(x29)
addi x1, x1, 9
sd x1, 80(x29)
addi x1, x1, -9
sd x1, 88(x29)
ld x5, k4(x0)
addi x6, x0, 0
loopw1: addi x0, x0, 0
sd x5, k1(x0)
sd x6, k2(x0)
add x7, x5, x6
sd x7, k3(x0)
ld x8, k1(x0)
ld x9, k2(x0)
ld x10, k3(x0)
add x6, x9, x10
addi x5, x5, -1
bne x5, x0, loopw1
sd x5, 96(x29)
sd x6, 104(x29)
ld x11, k1(x0)
sd x11, 112(x29)
ld x12, k2(x0)
sd x12, 120(x29)
ld x13, k3(x0)
sd x13, 128(x29)
addi x31, x0, 1
halt2: jal x0, halt2
k0: .dword 0x1
k1: .dword 0x0
k2: .dword 0x0
k3: .dword 0x0
k4: .dword 0x30
