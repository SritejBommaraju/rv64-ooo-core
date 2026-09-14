# bp_loops: nested counted loops (50 outer x 40 inner -> 2000 dynamic backward
# branches), a strictly-alternating taken/not-taken branch, a forward branch
# taken on only the last outer iteration, and a jalr through a register.

li s0, 0     # alternator bit
li t3, 0     # outer counter
outer:
li t1, 0     # inner counter
inner:
addi t1, t1, 1
addi t4, t1, -40
bne t4, x0, inner        # backward, taken 39/40 times per outer iter

xori s0, s0, 1
beq s0, x0, alt_skip     # strictly alternating taken/not-taken
addi s1, s1, 1
alt_skip:

addi t5, t3, -49
beq t5, x0, rare_taken   # forward, taken only on the last outer iteration
jal x0, rare_skip
rare_taken:
addi s2, s2, 1
rare_skip:

addi t3, t3, 1
addi t6, t3, -50
bne t6, x0, outer        # backward, taken 49/50 times

jal ra, sub_fn
jal x0, after_sub
sub_fn:
jalr x0, 0(ra)           # jalr through a register
after_sub:

addi x31, x0, 1
done: jal x0, done
