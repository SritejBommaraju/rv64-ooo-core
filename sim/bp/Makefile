RTL := ../../rtl/bp/bp_bimodal_btb.sv
TOP := bp_bimodal_btb

PHT_ENTRIES ?= 1024
BTB_ENTRIES ?= 64
TAG_BITS    ?= 20

MDIR        ?= obj_dir
GPARAMS := -GPHT_ENTRIES=$(PHT_ENTRIES) -GBTB_ENTRIES=$(BTB_ENTRIES) -GTAG_BITS=$(TAG_BITS)
CFLAGS  := -DPHT_ENTRIES=$(PHT_ENTRIES) -DBTB_ENTRIES=$(BTB_ENTRIES) -DTAG_BITS=$(TAG_BITS)

.PHONY: run run-small lint clean

run:
	verilator --cc --exe --build -Wall -Wno-fatal --Mdir $(MDIR) $(GPARAMS) \
		--top-module $(TOP) $(RTL) tb_bp.cpp -CFLAGS "$(CFLAGS)"
	./$(MDIR)/V$(TOP)

run-small:
	$(MAKE) run PHT_ENTRIES=16 BTB_ENTRIES=4 TAG_BITS=20 MDIR=obj_dir_small

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module $(TOP) $(RTL)

clean:
	rm -rf obj_dir obj_dir_small
