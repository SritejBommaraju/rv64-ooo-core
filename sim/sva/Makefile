RTL = ../../rtl/alu.sv ../../rtl/regfile.sv ../../rtl/decode.sv ../../rtl/core.sv ../../rtl/mem.sv ../../rtl/top.sv $(wildcard ../../rtl/muldiv.sv)
SVA = ../../rtl/sva/regfile_sva.sv ../../rtl/sva/core_sva.sv ../../rtl/sva/mem_sva.sv ../../rtl/sva/bind_all.sv

.PHONY: run lint neg clean

run: obj_dir/Vtop
	./obj_dir/Vtop ../../sw/test1.bin

obj_dir/Vtop: $(RTL) $(SVA) tb_sva.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --assert --Mdir obj_dir --top-module top $(RTL) $(SVA) tb_sva.cpp

lint:
	verilator --lint-only --assert -Wall -Wno-fatal --top-module top $(RTL) $(SVA)

neg: obj_dir_neg/Vtop
	./obj_dir_neg/Vtop ../../sw/test1.bin

obj_dir_neg/Vtop: $(RTL) $(SVA) neg_sva.sv tb_sva.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --assert --Mdir obj_dir_neg --top-module top $(RTL) $(SVA) neg_sva.sv tb_sva.cpp

clean:
	rm -rf obj_dir obj_dir_neg
