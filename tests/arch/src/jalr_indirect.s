# jalr_indirect
lui x29, 8
auipc x5, 0
addi x5, x5, 4
jalr x6, 12(x5)
addi x20, x0, -1
addi x21, x0, 300
sd x6, 0(x29)
sd x21, 8(x29)
auipc x5, 0
addi x5, x5, 5
jalr x6, 11(x5)
addi x20, x0, -1
addi x21, x0, 301
sd x6, 16(x29)
sd x21, 24(x29)
auipc x5, 0
addi x5, x5, 6
jalr x6, 10(x5)
addi x20, x0, -1
addi x21, x0, 302
sd x6, 32(x29)
sd x21, 40(x29)
auipc x5, 0
addi x5, x5, 7
jalr x6, 9(x5)
addi x20, x0, -1
addi x21, x0, 303
sd x6, 48(x29)
sd x21, 56(x29)
auipc x5, 0
addi x5, x5, 8
jalr x6, 8(x5)
addi x20, x0, -1
addi x21, x0, 304
sd x6, 64(x29)
sd x21, 72(x29)
auipc x5, 0
addi x5, x5, 9
jalr x6, 7(x5)
addi x20, x0, -1
addi x21, x0, 305
sd x6, 80(x29)
sd x21, 88(x29)
auipc x5, 0
addi x5, x5, 10
jalr x6, 6(x5)
addi x20, x0, -1
addi x21, x0, 306
sd x6, 96(x29)
sd x21, 104(x29)
auipc x5, 0
addi x5, x5, 11
jalr x6, 5(x5)
addi x20, x0, -1
addi x21, x0, 307
sd x6, 112(x29)
sd x21, 120(x29)
addi x31, x0, 1
halt1: jal x0, halt1
