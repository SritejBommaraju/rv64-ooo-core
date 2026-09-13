# All six branches: taken/not-taken, forward/backward, and signed vs unsigned
# discrimination on 0x8000000000000000 (very negative signed, huge unsigned).

li t0, 3
li t1, 5
beq t0, t1, bad_beq
j ok_beq1
bad_beq: j fail
ok_beq1:
li t0, 5
li t1, 5
beq t0, t1, ok_beq2
j fail
ok_beq2:

li t0, 5
li t1, 5
bne t0, t1, bad_bne
j ok_bne1
bad_bne: j fail
ok_bne1:
li t0, 3
li t1, 5
bne t0, t1, ok_bne2
j fail
ok_bne2:

li t0, 5
li t1, 3
blt t0, t1, bad_blt
j ok_blt1
bad_blt: j fail
ok_blt1:
li t0, -5
li t1, 3
blt t0, t1, ok_blt2
j fail
ok_blt2:

li t0, -5
li t1, 3
bge t0, t1, bad_bge
j ok_bge1
bad_bge: j fail
ok_bge1:
li t0, 5
li t1, 3
bge t0, t1, ok_bge2
j fail
ok_bge2:

li t0, 5
li t1, 3
bltu t0, t1, bad_bltu
j ok_bltu1
bad_bltu: j fail
ok_bltu1:
li t0, 3
li t1, 5
bltu t0, t1, ok_bltu2
j fail
ok_bltu2:

li t0, 3
li t1, 5
bgeu t0, t1, bad_bgeu
j ok_bgeu1
bad_bgeu: j fail
ok_bgeu1:
li t0, 5
li t1, 3
bgeu t0, t1, ok_bgeu2
j fail
ok_bgeu2:

# backward branch: bne loop, decrements 3 times
li t0, 3
li t2, 0
back_loop:
addi t2, t2, 1
addi t0, t0, -1
bne t0, x0, back_loop
li t3, 3
bne t2, t3, fail

# signed vs unsigned discrimination on the MSB
ld t0, MSB(x0)
li t1, 1
blt t0, t1, sd_ok1
j fail
sd_ok1:
bltu t0, t1, fail
j sd_ok2
sd_ok2:
bge t1, t0, sd_ok3
j fail
sd_ok3:
bgeu t1, t0, fail
j sd_ok4
sd_ok4:

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin

.org 0x400
MSB: .dword 0x8000000000000000
