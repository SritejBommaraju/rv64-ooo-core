import struct

# addi x1,x0,5 ; addi x2,x0,7 ; add x3,x1,x2 ; addi x4,x0,12
# beq x3,x4,pass ; addi x31,x0,0 ; jal x0,0 (fail spin)
# pass: addi x31,x0,1 ; jal x0,0 (pass spin)
words = [
    0x00500093,
    0x00700113,
    0x002081B3,
    0x00C00213,
    0x00418663,
    0x00000F93,
    0x0000006F,
    0x00100F93,
    0x0000006F,
]

with open("test1.bin", "wb") as f:
    for w in words:
        f.write(struct.pack("<I", w))
