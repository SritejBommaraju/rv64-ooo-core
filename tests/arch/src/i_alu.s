# i_alu
lui x29, 8
ld x1, k0(x0)
addi x10, x1, 0
sd x10, 0(x29)
ld x1, k1(x0)
addi x10, x1, 1
sd x10, 8(x29)
ld x1, k2(x0)
addi x10, x1, -1
sd x10, 16(x29)
ld x1, k3(x0)
addi x10, x1, -2048
sd x10, 24(x29)
ld x1, k4(x0)
addi x10, x1, 2047
sd x10, 32(x29)
ld x1, k5(x0)
addi x10, x1, 3
sd x10, 40(x29)
ld x1, k6(x0)
slti x10, x1, 0
sd x10, 48(x29)
ld x1, k7(x0)
slti x10, x1, 1
sd x10, 56(x29)
ld x1, k8(x0)
slti x10, x1, -1
sd x10, 64(x29)
ld x1, k9(x0)
slti x10, x1, -2048
sd x10, 72(x29)
ld x1, k10(x0)
slti x10, x1, 2047
sd x10, 80(x29)
ld x1, k11(x0)
slti x10, x1, 3
sd x10, 88(x29)
ld x1, k12(x0)
sltiu x10, x1, 0
sd x10, 96(x29)
ld x1, k13(x0)
sltiu x10, x1, 1
sd x10, 104(x29)
ld x1, k14(x0)
sltiu x10, x1, -1
sd x10, 112(x29)
ld x1, k15(x0)
sltiu x10, x1, -2048
sd x10, 120(x29)
ld x1, k16(x0)
sltiu x10, x1, 2047
sd x10, 128(x29)
ld x1, k17(x0)
sltiu x10, x1, 3
sd x10, 136(x29)
ld x1, k18(x0)
xori x10, x1, 0
sd x10, 144(x29)
ld x1, k19(x0)
xori x10, x1, 1
sd x10, 152(x29)
ld x1, k20(x0)
xori x10, x1, -1
sd x10, 160(x29)
ld x1, k21(x0)
xori x10, x1, -2048
sd x10, 168(x29)
ld x1, k22(x0)
xori x10, x1, 2047
sd x10, 176(x29)
ld x1, k23(x0)
xori x10, x1, 3
sd x10, 184(x29)
ld x1, k24(x0)
ori x10, x1, 0
sd x10, 192(x29)
ld x1, k25(x0)
ori x10, x1, 1
sd x10, 200(x29)
ld x1, k26(x0)
ori x10, x1, -1
sd x10, 208(x29)
ld x1, k27(x0)
ori x10, x1, -2048
sd x10, 216(x29)
ld x1, k28(x0)
ori x10, x1, 2047
sd x10, 224(x29)
ld x1, k29(x0)
ori x10, x1, 3
sd x10, 232(x29)
ld x1, k30(x0)
andi x10, x1, 0
sd x10, 240(x29)
ld x1, k31(x0)
andi x10, x1, 1
sd x10, 248(x29)
ld x1, k32(x0)
andi x10, x1, -1
sd x10, 256(x29)
ld x1, k33(x0)
andi x10, x1, -2048
sd x10, 264(x29)
ld x1, k34(x0)
andi x10, x1, 2047
sd x10, 272(x29)
ld x1, k35(x0)
andi x10, x1, 3
sd x10, 280(x29)
ld x1, k36(x0)
slli x10, x1, 0
sd x10, 288(x29)
ld x1, k37(x0)
slli x10, x1, 1
sd x10, 296(x29)
ld x1, k38(x0)
slli x10, x1, 63
sd x10, 304(x29)
ld x1, k39(x0)
slli x10, x1, 0
sd x10, 312(x29)
ld x1, k40(x0)
slli x10, x1, 1
sd x10, 320(x29)
ld x1, k41(x0)
slli x10, x1, 63
sd x10, 328(x29)
ld x1, k42(x0)
slli x10, x1, 0
sd x10, 336(x29)
ld x1, k43(x0)
slli x10, x1, 1
sd x10, 344(x29)
ld x1, k44(x0)
slli x10, x1, 63
sd x10, 352(x29)
ld x1, k45(x0)
srli x10, x1, 0
sd x10, 360(x29)
ld x1, k46(x0)
srli x10, x1, 1
sd x10, 368(x29)
ld x1, k47(x0)
srli x10, x1, 63
sd x10, 376(x29)
ld x1, k48(x0)
srli x10, x1, 0
sd x10, 384(x29)
ld x1, k49(x0)
srli x10, x1, 1
sd x10, 392(x29)
ld x1, k50(x0)
srli x10, x1, 63
sd x10, 400(x29)
ld x1, k51(x0)
srli x10, x1, 0
sd x10, 408(x29)
ld x1, k52(x0)
srli x10, x1, 1
sd x10, 416(x29)
ld x1, k53(x0)
srli x10, x1, 63
sd x10, 424(x29)
ld x1, k54(x0)
srai x10, x1, 0
sd x10, 432(x29)
ld x1, k55(x0)
srai x10, x1, 1
sd x10, 440(x29)
ld x1, k56(x0)
srai x10, x1, 63
sd x10, 448(x29)
ld x1, k57(x0)
srai x10, x1, 0
sd x10, 456(x29)
ld x1, k58(x0)
srai x10, x1, 1
sd x10, 464(x29)
ld x1, k59(x0)
srai x10, x1, 63
sd x10, 472(x29)
ld x1, k60(x0)
srai x10, x1, 0
sd x10, 480(x29)
ld x1, k61(x0)
srai x10, x1, 1
sd x10, 488(x29)
ld x1, k62(x0)
srai x10, x1, 63
sd x10, 496(x29)
addi x31, x0, 1
halt1: jal x0, halt1
k0: .dword 0x0
k1: .dword 0x1
k2: .dword 0xffffffffffffffff
k3: .dword 0x8000000000000000
k4: .dword 0x7fffffffffffffff
k5: .dword 0xfffffffffffffffb
k6: .dword 0x0
k7: .dword 0x1
k8: .dword 0xffffffffffffffff
k9: .dword 0x8000000000000000
k10: .dword 0x7fffffffffffffff
k11: .dword 0xfffffffffffffffb
k12: .dword 0x0
k13: .dword 0x1
k14: .dword 0xffffffffffffffff
k15: .dword 0x8000000000000000
k16: .dword 0x7fffffffffffffff
k17: .dword 0xfffffffffffffffb
k18: .dword 0x0
k19: .dword 0x1
k20: .dword 0xffffffffffffffff
k21: .dword 0x8000000000000000
k22: .dword 0x7fffffffffffffff
k23: .dword 0xfffffffffffffffb
k24: .dword 0x0
k25: .dword 0x1
k26: .dword 0xffffffffffffffff
k27: .dword 0x8000000000000000
k28: .dword 0x7fffffffffffffff
k29: .dword 0xfffffffffffffffb
k30: .dword 0x0
k31: .dword 0x1
k32: .dword 0xffffffffffffffff
k33: .dword 0x8000000000000000
k34: .dword 0x7fffffffffffffff
k35: .dword 0xfffffffffffffffb
k36: .dword 0xffffffffffffffff
k37: .dword 0xffffffffffffffff
k38: .dword 0xffffffffffffffff
k39: .dword 0x4000000000000000
k40: .dword 0x4000000000000000
k41: .dword 0x4000000000000000
k42: .dword 0x8000000000000001
k43: .dword 0x8000000000000001
k44: .dword 0x8000000000000001
k45: .dword 0xffffffffffffffff
k46: .dword 0xffffffffffffffff
k47: .dword 0xffffffffffffffff
k48: .dword 0x4000000000000000
k49: .dword 0x4000000000000000
k50: .dword 0x4000000000000000
k51: .dword 0x8000000000000001
k52: .dword 0x8000000000000001
k53: .dword 0x8000000000000001
k54: .dword 0xffffffffffffffff
k55: .dword 0xffffffffffffffff
k56: .dword 0xffffffffffffffff
k57: .dword 0x4000000000000000
k58: .dword 0x4000000000000000
k59: .dword 0x4000000000000000
k60: .dword 0x8000000000000001
k61: .dword 0x8000000000000001
k62: .dword 0x8000000000000001
