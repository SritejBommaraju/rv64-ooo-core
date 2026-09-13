RTL := ../../../rtl/cache/mshr.sv ../../../rtl/cache/l1d.sv
TOP := l1d

N_MSHR ?= 4

MDIR    ?= obj_dir
GPARAMS := -GN_MSHR=$(N_MSHR)

.PHONY: run lint clean

run:
	verilator --cc --exe --build -Wall -Wno-fatal --Mdir $(MDIR) $(GPARAMS) \
		--top-module $(TOP) $(RTL) tb_l1d.cpp -CFLAGS "-I."
	./$(MDIR)/V$(TOP)

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
