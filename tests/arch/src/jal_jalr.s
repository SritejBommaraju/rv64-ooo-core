# jal_jalr
lui x29, 8
jal x10, j1
addi x20, x0, -1
jal x0, after2
j1: addi x20, x0, 100
after2: addi x0, x0, 0
sd x10, 0(x29)
sd x20, 8(x29)
jal x11, j3
addi x20, x0, -1
jal x0, after4
j3: addi x20, x0, 101
after4: addi x0, x0, 0
sd x11, 16(x29)
sd x20, 24(x29)
jal x12, j5
addi x20, x0, -1
jal x0, after6
j5: addi x20, x0, 102
after6: addi x0, x0, 0
sd x12, 32(x29)
sd x20, 40(x29)
jal x13, j7
addi x20, x0, -1
jal x0, after8
j7: addi x20, x0, 103
after8: addi x0, x0, 0
sd x13, 48(x29)
sd x20, 56(x29)
auipc x1, 0
jalr x14, 8(x1)
addi x21, x0, 200
sd x14, 64(x29)
sd x21, 72(x29)
auipc x1, 0
jalr x14, 16(x1)
addi x0, x0, 0
addi x0, x0, 0
addi x21, x0, 201
sd x14, 80(x29)
sd x21, 88(x29)
auipc x1, 0
jalr x14, 12(x1)
addi x0, x0, 0
addi x21, x0, 202
sd x14, 96(x29)
sd x21, 104(x29)
auipc x1, 0
jalr x14, 20(x1)
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x21, x0, 203
sd x14, 112(x29)
sd x21, 120(x29)
auipc x1, 0
jalr x14, 24(x1)
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x21, x0, 204
sd x14, 128(x29)
sd x21, 136(x29)
addi x31, x0, 1
halt9: jal x0, halt9
