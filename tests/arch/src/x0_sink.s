# x0_sink
lui x29, 8
addi x0, x0, 5
sd x0, 0(x29)
addi x0, x0, -5
sd x0, 8(x29)
addi x0, x0, 0
sd x0, 16(x29)
addi x0, x0, 2047
sd x0, 24(x29)
addi x0, x0, -2048
sd x0, 32(x29)
addi x0, x0, 1
sd x0, 40(x29)
addi x0, x0, -1
sd x0, 48(x29)
addi x0, x0, 999
sd x0, 56(x29)
addi x0, x0, -999
sd x0, 64(x29)
addi x0, x0, 8
sd x0, 72(x29)
lui x0, 0x12345
sd x0, 80(x29)
auipc x0, 0x111
sd x0, 88(x29)
ld x0, k0(x0)
sd x0, 96(x29)
lui x0, 0x12345
sd x0, 104(x29)
auipc x0, 0x111
sd x0, 112(x29)
ld x0, k0(x0)
sd x0, 120(x29)
lui x0, 0x12345
sd x0, 128(x29)
auipc x0, 0x111
sd x0, 136(x29)
ld x0, k0(x0)
sd x0, 144(x29)
ld x1, k0(x0)
add x0, x1, x1
sd x0, 152(x29)
.word 0x02108033
sd x0, 160(x29)
.word 0x0010803b
sd x0, 168(x29)
.word 0x0030801b
sd x0, 176(x29)
add x0, x1, x1
sd x0, 184(x29)
.word 0x02108033
sd x0, 192(x29)
.word 0x0010803b
sd x0, 200(x29)
.word 0x0030801b
sd x0, 208(x29)
add x0, x1, x1
sd x0, 216(x29)
.word 0x02108033
sd x0, 224(x29)
.word 0x0010803b
sd x0, 232(x29)
.word 0x0030801b
sd x0, 240(x29)
jal x0, jx01
addi x9, x0, -1
jx01: addi x9, x0, 1
sd x0, 248(x29)
auipc x3, 0
jalr x0, 8(x3)
sd x0, 256(x29)
sd x9, 264(x29)
addi x31, x0, 1
halt2: jal x0, halt2
k0: .dword 0x42
