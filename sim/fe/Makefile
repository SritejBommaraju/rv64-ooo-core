# frontend + branch_tbl + rob + rename + lsq, verilated as five independent top modules
# (none instantiate each other) and wired together by tb_fe.cpp, which also links in the
# ISS as the execute stage.
RTL_FE  := ../../rtl/fe/frontend.sv ../../rtl/bp/bp_bimodal_btb.sv
RTL_BT  := ../../rtl/ooo/branch_tbl.sv
RTL_ROB := ../../rtl/ooo/rob.sv
RTL_RN  := ../../rtl/rename/free_list.sv ../../rtl/rename/rename_map.sv ../../rtl/rename/rename.sv
RTL_LSQ := ../../rtl/lsq/lsq.sv

MDIR := obj_dir
VROOT := $(shell verilator --getenv VERILATOR_ROOT)
VINC := -I$(VROOT)/include -I$(VROOT)/include/vltstd

.PHONY: run progs lint clean

progs:
	python3 ../../sw/asm.py ../../sw/tests/bp_loops.s -o ../../sw/build/bp_loops.bin
	python3 ../../sw/asm.py ../../sw/tests/branch.s -o ../../sw/build/branch.bin
	python3 ../../sw/asm.py ../../tests/arch/src/branches.s -o ../../sw/build/branches_arch.bin

run: progs
	mkdir -p $(MDIR)/fe $(MDIR)/bt $(MDIR)/rob $(MDIR)/rn $(MDIR)/lsq
	verilator --cc -Wall -Wno-fatal --Mdir $(MDIR)/fe  --top-module frontend    $(RTL_FE)
	verilator --cc -Wall -Wno-fatal --Mdir $(MDIR)/bt  --top-module branch_tbl $(RTL_BT)
	verilator --cc -Wall -Wno-fatal --Mdir $(MDIR)/rob --top-module rob        $(RTL_ROB)
	verilator --cc -Wall -Wno-fatal -CFLAGS "-std=c++17" --Mdir $(MDIR)/rn --top-module rename $(RTL_RN)
	verilator --cc -Wall -Wno-fatal --Mdir $(MDIR)/lsq --top-module lsq       $(RTL_LSQ)
	g++ -std=c++17 -Wall -O2 \
	  -I$(MDIR)/fe -I$(MDIR)/bt -I$(MDIR)/rob -I$(MDIR)/rn -I$(MDIR)/lsq $(VINC) \
	  tb_fe.cpp ../../model/iss.cpp \
	  $(MDIR)/fe/*.cpp $(MDIR)/bt/*.cpp $(MDIR)/rob/*.cpp $(MDIR)/rn/*.cpp $(MDIR)/lsq/*.cpp \
	  $(VROOT)/include/verilated.cpp $(VROOT)/include/verilated_threads.cpp \
	  -o $(MDIR)/tb_fe
	./$(MDIR)/tb_fe

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module frontend $(RTL_FE)
	verilator --lint-only -Wall -Wno-fatal --top-module branch_tbl $(RTL_BT)

clean:
	rm -rf obj_dir
