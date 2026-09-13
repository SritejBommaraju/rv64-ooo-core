# jal/jalr link value (pc+4), jalr target computed from base+offset with bit 0
# cleared, and jalr with a negative offset. Uses auipc to read known pcs so
# the checks don't depend on absolute assembled addresses.

here1:
auipc t0, 0
jal ra, target1
j fail
target1:
sub t2, ra, t0
li t3, 8
bne t2, t3, fail

here2:
auipc t0, 0
addi t1, t0, 16
jalr ra, 0(t1)
j fail
target2:
sub t2, ra, t0
li t3, 12
bne t2, t3, fail

# odd target: base+17 is odd, jalr must clear bit 0 and land on base+16
here3:
auipc t0, 0
addi t1, t0, 17
jalr ra, 0(t1)
j fail
odd_target:
sub t2, ra, t0
li t3, 12
bne t2, t3, fail

# negative offset: base = here4+40, offset -20 -> target = here4+20
here4:
auipc t0, 0
addi t1, t0, 40
jalr ra, -20(t1)
j fail
nop
neg_target:
sub t2, ra, t0
li t3, 12
bne t2, t3, fail

addi x31, x0, 1
done: j done
fail: addi x31, x0, 0
fspin: j fspin
