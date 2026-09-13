TOP = top
RTL = ../rtl/alu.sv ../rtl/muldiv.sv ../rtl/regfile.sv ../rtl/decode.sv ../rtl/core.sv ../rtl/mem.sv ../rtl/top.sv

.PHONY: run run-w run-m run-all lint clean

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../sw/test1.bin

run-w: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../sw/test_w.bin

run-m: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../sw/test_m.bin

run-all: run run-w run-m

obj_dir/V$(TOP): $(RTL) tb_main.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --top-module $(TOP) $(RTL) tb_main.cpp

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
