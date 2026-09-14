TOP = muldiv
RTL = ../../rtl/muldiv.sv

.PHONY: run lint clean

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP)

obj_dir/V$(TOP): $(RTL) tb_muldiv.cpp ../../model/iss.cpp ../../model/iss.h
	verilator --cc --exe --build -Wall -Wno-fatal --top-module $(TOP) $(RTL) tb_muldiv.cpp ../../model/iss.cpp

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
