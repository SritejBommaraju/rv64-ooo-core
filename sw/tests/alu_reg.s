# R-type ALU ops: add sub sll slt sltu xor srl sra or and, 2+ cases each
# (positive, negative operands, shift-by-63, sltu with the MSB set).

li t0, 5
li t1, 3
add t2, t0, t1
li t3, 8
bne t2, t3, fail

li t0, -5
li t1, 3
add t2, t0, t1
li t3, -2
bne t2, t3, fail

li t0, 5
li t1, 8
sub t2, t0, t1
li t3, -3
bne t2, t3, fail

li t0, -5
li t1, -8
sub t2, t0, t1
li t3, 3
bne t2, t3, fail

li t0, 1
li t1, 4
sll t2, t0, t1
li t3, 16
bne t2, t3, fail

li t0, 1
li t1, 63
sll t2, t0, t1
ld t3, MSB(x0)
bne t2, t3, fail

li t0, 3
li t1, 5
slt t2, t0, t1
li t3, 1
bne t2, t3, fail

li t0, -5
li t1, 3
slt t2, t0, t1
li t3, 1
bne t2, t3, fail

li t0, 3
li t1, 5
sltu t2, t0, t1
li t3, 1
bne t2, t3, fail

ld t0, MSB(x0)
li t1, 1
sltu t2, t0, t1
li t3, 0
bne t2, t3, fail

li t0, 0x0F0
li t1, 0x0FF
xor t2, t0, t1
li t3, 0x00F
bne t2, t3, fail

li t0, -1
li t1, 5
xor t2, t0, t1
li t3, -6
bne t2, t3, fail

li t0, 8
li t1, 2
srl t2, t0, t1
li t3, 2
bne t2, t3, fail

li t0, -1
li t1, 60
srl t2, t0, t1
li t3, 15
bne t2, t3, fail

li t0, -8
li t1, 2
sra t2, t0, t1
li t3, -2
bne t2, t3, fail

li t0, -1
li t1, 63
sra t2, t0, t1
li t3, -1
bne t2, t3, fail

li t0, 0x0F0
li t1, 0x00F
or t2, t0, t1
li t3, 0x0FF
bne t2, t3, fail

li t0, -1
li t1, 5
or t2, t0, t1
li t3, -1
bne t2, t3, fail

li t0, 0x0FF
li t1, 0x0F0
and t2, t0, t1
li t3, 0x0F0
bne t2, t3, fail

li t0, -1
li t1, 0x055
and t2, t0, t1
li t3, 0x055
bne t2, t3, fail

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin

.org 0x400
MSB: .dword 0x8000000000000000
