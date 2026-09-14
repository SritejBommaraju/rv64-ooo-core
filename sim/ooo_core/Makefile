TOP = ooo_top
RTL = ../../rtl/alu.sv ../../rtl/decode.sv \
      ../../rtl/rename/free_list.sv ../../rtl/rename/rename_map.sv ../../rtl/rename/rename.sv \
      ../../rtl/rename/prf.sv ../../rtl/ooo/rob.sv ../../rtl/lsq/lsq.sv \
      ../../rtl/ooo/ooo_mem.sv ../../rtl/ooo/ooo_core.sv ../../rtl/ooo/ooo_top.sv
BINS = alu_imm alu_reg branch jump load_store lui_auipc

.PHONY: build run run-all lint clean

build: obj_dir/V$(TOP)

# rename.sv/prf.sv/rob.sv/lsq.sv/decode.sv/alu.sv are unmodified: ooo_core.sv observes
# them only through their real ports (a shadow arch->phys map + prf's spare read ports),
# so no verilator public pragmas or --public-flat-rw are needed on the untouched files.
# (--public-flat-rw was tried first, but it forces verilator to honor decode.sv's
# "logic x = expr;" module-scope initializers as literal one-time inits instead of its
# normal as-if-continuous treatment, which silently freezes decode - left un-set here.)
obj_dir/V$(TOP): $(RTL) tb_ooo_core.cpp
	verilator --cc --exe --build -Wall -Wno-fatal \
		--top-module $(TOP) $(RTL) tb_ooo_core.cpp

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP) ../../sw/test1.bin

run-all: obj_dir/V$(TOP)
	@for b in $(BINS); do \
		echo "== $$b =="; \
		./obj_dir/V$(TOP) ../../sw/build/$$b.bin || exit 1; \
	done
	@echo "== test1 =="
	./obj_dir/V$(TOP) ../../sw/test1.bin
	@echo "== expect_fail (must NOT pass) =="
	./obj_dir/V$(TOP) ../../sw/build/expect_fail.bin && exit 1 || echo "expect_fail correctly did not PASS"

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir
