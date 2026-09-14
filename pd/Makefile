# IHP sg13g2 synth + STA flow, per-block. Run from WSL: cd pd && make synth sta summary
CADSUITE  ?= $(HOME)/oss-cad-suite
YOSYS     ?= $(CADSUITE)/bin/yosys
STA       ?= $(HOME)/OpenSTA/build/docs-sta/sta
PDK       ?= $(HOME)/pdk/IHP-Open-PDK
LIBERTY   ?= $(PDK)/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
RTL_DIR   ?= ..
TIMEOUT_S ?= 1800

include blocks.mk

OUT := out
BLOCKS ?= $(ALL_BLOCKS)

.PHONY: install-check synth sta summary all clean synth-gl gl _synth_one _sta_one

install-check:
	@test -x $(YOSYS) || (echo "missing yosys at $(YOSYS)"; exit 1)
	@test -x $(STA) || (echo "missing OpenSTA at $(STA)"; exit 1)
	@test -f $(LIBERTY) || (echo "missing liberty at $(LIBERTY)"; exit 1)
	@$(YOSYS) -V
	@$(STA) -version
	@echo install-check OK

$(OUT):
	mkdir -p $(OUT)

# Synthesize each block in BLOCKS (default: every block in blocks.mk). Plain yosys script syntax
# has no env-var substitution, so we sed the @FILES@/@TOP@/@OUT@/@LIBERTY@ placeholders in
# synth.ys into a generated per-block script. Each run is wrapped in `timeout` so a block that
# blows up (lsq/l1d are the suspects) is recorded as TIMEOUT in the summary, not left hanging.
synth: install-check | $(OUT)
	@for top in $(BLOCKS); do \
		$(MAKE) --no-print-directory _synth_one B=$$top || exit 1; \
	done
	@rm -f $(OUT)/stat.txt; \
	for top in $(BLOCKS); do \
		echo "--- $$top ---" >> $(OUT)/stat.txt; \
		grep -A200 "Printing statistics" $(OUT)/$${top}_synth.log >> $(OUT)/stat.txt 2>/dev/null || echo "(no stats -- see status)" >> $(OUT)/stat.txt; \
	done

# One block: B is a make variable here (passed via command line from the loop above), so
# $(FILES_$(B))/$(TOP_$(B)) resolve directly at make-expansion time -- no shell indirection needed.
_synth_one:
	@echo "=== synth $(B) ==="
	@if [ -n "$(filter $(B),$(SLANG_BLOCKS))" ]; then \
		filelines="read_slang --allow-use-before-declare $(FILES_$(B)) --top $(TOP_$(B))"; \
	else \
		filelines=$$(for f in $(FILES_$(B)); do echo "read_verilog -sv $$f"; done); \
	fi; \
	awk -v r="$$filelines" '{gsub(/@FILES@/,r)}1' synth.ys \
		| sed -e "s#@TOP@#$(TOP_$(B))#g" -e "s#@OUT@#$(OUT)/$(B)_syn#g" -e "s#@LIBERTY@#$(LIBERTY)#g" \
		> $(OUT)/$(B)_synth.ys
	@yosys_bin="$(YOSYS)"; [ -n "$(filter $(B),$(SLANG_BLOCKS))" ] && yosys_bin="$(YOSYS) -m slang"; \
	start=$$(date +%s); \
	if timeout $(TIMEOUT_S) $$yosys_bin -s $(OUT)/$(B)_synth.ys -l $(OUT)/$(B)_synth.log; then \
		echo OK > $(OUT)/$(B)_synth.status; \
	elif [ $$? -eq 124 ]; then \
		echo TIMEOUT > $(OUT)/$(B)_synth.status; \
	else \
		echo ERROR > $(OUT)/$(B)_synth.status; \
	fi; \
	end=$$(date +%s); \
	echo $$((end - start)) > $(OUT)/$(B)_synth.time
	@[ -f $(OUT)/$(B)_syn.v ] && sed -i 's/wire signed/wire/' $(OUT)/$(B)_syn.v || true

# STA for each block that actually produced a netlist. Timeouts/errors are skipped (summarize.py
# records them from the .status file, not from a missing _sta.txt).
sta: | $(OUT)
	@for top in $(BLOCKS); do \
		$(MAKE) --no-print-directory _sta_one B=$$top; \
	done

_sta_one:
	@if [ -f $(OUT)/$(B)_syn.v ]; then \
		echo "=== sta $(B) ==="; \
		NETLIST=$(OUT)/$(B)_syn.v TOP=$(TOP_$(B)) LIBERTY=$(LIBERTY) \
			$(STA) -exit sta.tcl > $(OUT)/$(B)_sta.txt 2>&1 || true; \
	else \
		echo "=== skip sta $(B) (no netlist) ==="; \
	fi

summary: | $(OUT)
	python3 summarize.py $(OUT) "$(BLOCKS)"
	@cat $(OUT)/summary.txt

# Gate-level functional sanity check: separate netlist with regfile left unsynthesized (see
# synth_gl.ys), so pd/gl/tb_gl.cpp can keep the existing hierarchical x31==1 halt convention.
synth-gl: install-check | $(OUT)
	sed -e "s#@OUT@#$(OUT)/core_syn_gl#g" -e "s#@LIBERTY@#$(LIBERTY)#g" \
		synth_gl.ys > $(OUT)/core_synth_gl.ys
	$(YOSYS) -s $(OUT)/core_synth_gl.ys -l $(OUT)/core_synth_gl.log

gl: synth-gl
	$(MAKE) -C gl run

all: synth sta summary

clean:
	rm -rf $(OUT)
	$(MAKE) -C gl clean
