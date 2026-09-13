RTL := ../../rtl/lsq/lsq.sv
TOP := lsq

MDIR ?= obj_dir

.PHONY: run lint clean

run:
	verilator --cc --exe --build -Wall -Wno-fatal --Mdir $(MDIR) \
		--top-module $(TOP) $(RTL) tb_lsq.cpp
	./$(MDIR)/V$(TOP)

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
