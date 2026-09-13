RTL := ../../rtl/rename/free_list.sv ../../rtl/rename/rename_map.sv ../../rtl/rename/rename.sv
TOP := rename

MDIR ?= obj_dir

.PHONY: run lint clean

run:
	verilator --cc --exe --build -Wall -Wno-fatal -CFLAGS "-std=c++17" --Mdir $(MDIR) \
		--top-module $(TOP) $(RTL) tb_rename.cpp
	./$(MDIR)/V$(TOP)

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)
	verilator --lint-only -Wall -Wno-fatal --top-module prf ../../rtl/rename/prf.sv

clean:
	rm -rf obj_dir
