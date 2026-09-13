TOP = top
BIN ?= ../../sw/test1.bin
RTL = ../../rtl/alu.sv ../../rtl/regfile.sv ../../rtl/decode.sv ../../rtl/core.sv ../../rtl/mem.sv ../../rtl/top.sv \
      $(wildcard ../../rtl/muldiv.sv) ../../rtl/cov/decode_cov.sv ../../rtl/cov/bind_cov.sv

.PHONY: run lint clean

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) $(BIN)
	python3 report.py coverage.dat

obj_dir/V$(TOP): $(RTL) tb_cov.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --assert --coverage-user --Mdir obj_dir --top-module $(TOP) $(RTL) tb_cov.cpp

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir coverage.dat
