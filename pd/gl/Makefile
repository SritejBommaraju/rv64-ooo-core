# Verilator build for the gate-level sanity check: pd/out/core_syn_gl.v (synthesized core, regfile
# kept as RTL) + real regfile.sv + unmodified mem.sv/top.sv + sg13g2 cell/UDP models.
PDK ?= $(HOME)/pdk/IHP-Open-PDK
CELLS := $(PDK)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_udp.v \
         $(PDK)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v

TOP = top
RTL = ../out/core_syn_gl.v ../../rtl/regfile.sv ../../rtl/mem.sv ../../rtl/top.sv $(CELLS)

.PHONY: run clean

# alu_imm.bin passes on the in-order RTL (see sw/run_tests.py), unlike sw/test1.bin, so this is
# a meaningful PASS/FAIL against the synthesized netlist.
run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../../sw/build/alu_imm.bin

obj_dir/V$(TOP): $(RTL) tb_gl.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --timing --top-module $(TOP) $(RTL) tb_gl.cpp

clean:
	rm -rf obj_dir
