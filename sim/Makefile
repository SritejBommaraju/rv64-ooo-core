TOP = top
RTL = ../rtl/alu.sv ../rtl/regfile.sv ../rtl/decode.sv ../rtl/core.sv ../rtl/mem.sv ../rtl/top.sv

.PHONY: run lint clean

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../sw/test1.bin

obj_dir/V$(TOP): $(RTL) tb_main.cpp
	verilator --cc --exe --build -Wall --top-module $(TOP) $(RTL) tb_main.cpp

lint:
	verilator --lint-only -Wall --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
