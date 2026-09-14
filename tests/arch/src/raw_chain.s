# raw_chain
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
addi x1, x1, 55
sd x1, 96(x29)
addi x1, x1, -55
sd x1, 104(x29)
addi x1, x1, 123
sd x1, 112(x29)
addi x1, x1, -123
sd x1, 120(x29)
addi x1, x1, 8
sd x1, 128(x29)
addi x1, x1, -8
sd x1, 136(x29)
addi x1, x1, 256
sd x1, 144(x29)
addi x1, x1, -256
sd x1, 152(x29)
addi x1, x1, 17
sd x1, 160(x29)
addi x1, x1, -17
sd x1, 168(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x1
