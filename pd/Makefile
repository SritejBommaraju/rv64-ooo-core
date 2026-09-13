# IHP sg13g2 synth + STA flow. Run from WSL: cd pd && make all
CADSUITE  ?= $(HOME)/oss-cad-suite
YOSYS     ?= $(CADSUITE)/bin/yosys
STA       ?= $(HOME)/OpenSTA/build/docs-sta/sta
PDK       ?= $(HOME)/pdk/IHP-Open-PDK
LIBERTY   ?= $(PDK)/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
RTL_DIR   ?= ..

OUT := out
BLOCKS := core muldiv alu

.PHONY: install-check synth sta all clean

install-check:
	@test -x $(YOSYS) || (echo "missing yosys at $(YOSYS)"; exit 1)
	@test -x $(STA) || (echo "missing OpenSTA at $(STA)"; exit 1)
	@test -f $(LIBERTY) || (echo "missing liberty at $(LIBERTY)"; exit 1)
	@$(YOSYS) -V
	@$(STA) -version
	@echo install-check OK

$(OUT):
	mkdir -p $(OUT)

# Synthesize each block (core = full core, plus muldiv/alu standalone for per-block numbers).
# Plain yosys script syntax has no env-var substitution, so we sed the @TOP@/@OUT@/@LIBERTY@
# placeholders in synth.ys into a generated per-block script.
synth: install-check | $(OUT)
	@for top in $(BLOCKS); do \
		echo "=== synth $$top ==="; \
		sed -e "s#@TOP@#$$top#g" -e "s#@OUT@#$(OUT)/$${top}_syn#g" -e "s#@LIBERTY@#$(LIBERTY)#g" \
			synth.ys > $(OUT)/$${top}_synth.ys; \
		$(YOSYS) -s $(OUT)/$${top}_synth.ys -l $(OUT)/$${top}_synth.log || exit 1; \
		sed -i 's/wire signed/wire/' $(OUT)/$${top}_syn.v; \
	done
	@echo "--- core ---"  > $(OUT)/stat.txt
	@grep -A200 "Printing statistics" $(OUT)/core_synth.log  >> $(OUT)/stat.txt
	@echo "--- muldiv ---" >> $(OUT)/stat.txt
	@grep -A200 "Printing statistics" $(OUT)/muldiv_synth.log >> $(OUT)/stat.txt
	@echo "--- alu ---" >> $(OUT)/stat.txt
	@grep -A200 "Printing statistics" $(OUT)/alu_synth.log >> $(OUT)/stat.txt

sta: | $(OUT)
	@NETLIST=$(OUT)/core_syn.v TOP=core LIBERTY=$(LIBERTY) \
		$(STA) -exit sta.tcl | tee $(OUT)/sta.txt

# Gate-level functional sanity check: separate netlist with regfile left unsynthesized (see
# synth_gl.ys), so pd/gl/tb_gl.cpp can keep the existing hierarchical x31==1 halt convention.
synth-gl: install-check | $(OUT)
	sed -e "s#@OUT@#$(OUT)/core_syn_gl#g" -e "s#@LIBERTY@#$(LIBERTY)#g" \
		synth_gl.ys > $(OUT)/core_synth_gl.ys
	$(YOSYS) -s $(OUT)/core_synth_gl.ys -l $(OUT)/core_synth_gl.log

gl: synth-gl
	$(MAKE) -C gl run

all: synth sta

clean:
	rm -rf $(OUT)
	$(MAKE) -C gl clean
