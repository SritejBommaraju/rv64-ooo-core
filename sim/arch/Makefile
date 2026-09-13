TOP = top
RTL = ../../rtl/alu.sv ../../rtl/muldiv.sv ../../rtl/regfile.sv ../../rtl/decode.sv ../../rtl/core.sv ../../rtl/mem.sv ../../rtl/top.sv

.PHONY: build run lint clean

build: obj_dir/V$(TOP)

# ARGS carries "<prog.bin> --sig-begin <hex> --sig-end <hex> --sig-out <path>"
run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) $(ARGS)

obj_dir/V$(TOP): $(RTL) tb_arch.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --top-module $(TOP) $(RTL) tb_arch.cpp

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
