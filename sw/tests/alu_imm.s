# I-type ALU ops: addi slti sltiu xori ori andi slli srli srai
# (negative immediates, and srai of a negative operand).

li t0, 5
addi t1, t0, 10
li t2, 15
bne t1, t2, fail

li t0, 5
addi t1, t0, -10
li t2, -5
bne t1, t2, fail

li t0, 3
slti t1, t0, 5
li t2, 1
bne t1, t2, fail

li t0, -5
slti t1, t0, 0
li t2, 1
bne t1, t2, fail

li t0, 3
sltiu t1, t0, 5
li t2, 1
bne t1, t2, fail

li t0, -1
sltiu t1, t0, 5
li t2, 0
bne t1, t2, fail

li t0, 0x0F0
xori t1, t0, 0x0FF
li t2, 0x00F
bne t1, t2, fail

li t0, -1
xori t1, t0, 5
li t2, -6
bne t1, t2, fail

li t0, 0x0F0
ori t1, t0, 0x00F
li t2, 0x0FF
bne t1, t2, fail

li t0, -8
ori t1, t0, 1
li t2, -7
bne t1, t2, fail

li t0, 0x0FF
andi t1, t0, 0x0F0
li t2, 0x0F0
bne t1, t2, fail

li t0, -1
andi t1, t0, 0x055
li t2, 0x055
bne t1, t2, fail

li t0, 1
slli t1, t0, 4
li t2, 16
bne t1, t2, fail

li t0, 1
slli t1, t0, 63
ld t2, MSB(x0)
bne t1, t2, fail

li t0, 8
srli t1, t0, 2
li t2, 2
bne t1, t2, fail

li t0, -1
srli t1, t0, 60
li t2, 15
bne t1, t2, fail

li t0, -8
srai t1, t0, 2
li t2, -2
bne t1, t2, fail

li t0, -1
srai t1, t0, 63
li t2, -1
bne t1, t2, fail

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin

.org 0x400
MSB: .dword 0x8000000000000000
