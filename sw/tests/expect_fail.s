# EXPECT: FAIL
# Never sets x31=1, to prove run_tests.py detects a failing test.
li t0, 1
li t1, 2
bne t0, t1, spin
addi x31, x0, 1
spin: j spin
