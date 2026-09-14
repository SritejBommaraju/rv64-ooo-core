# Per-block RTL file lists for pd/Makefile's synth/sta loops. TOP module name == block name for
# every entry except core (top = core) and muldiv/alu (top = block name, single-file).
# Add a new block by adding a FILES_<block> line and appending <block> to ALL_BLOCKS.

FILES_core    := ../rtl/alu.sv ../rtl/muldiv.sv ../rtl/regfile.sv ../rtl/decode.sv ../rtl/core.sv
FILES_muldiv  := ../rtl/muldiv.sv
FILES_alu     := ../rtl/alu.sv
FILES_rob     := ../rtl/ooo/rob.sv
FILES_rename  := ../rtl/rename/free_list.sv ../rtl/rename/rename_map.sv ../rtl/rename/rename.sv
FILES_prf     := ../rtl/rename/prf.sv
FILES_lsq     := ../rtl/lsq/lsq.sv
FILES_l1d     := ../rtl/cache/mshr.sv ../rtl/cache/l1d.sv
FILES_bp_bimodal_btb := ../rtl/bp/bp_bimodal_btb.sv

# TOP module per block, where it differs from the block name.
TOP_core   := core
TOP_muldiv := muldiv
TOP_alu    := alu
TOP_rob    := rob
TOP_rename := rename
TOP_prf    := prf
TOP_lsq    := lsq
TOP_l1d    := l1d
TOP_bp_bimodal_btb := bp_bimodal_btb

ALL_BLOCKS := core muldiv alu rob rename prf lsq l1d bp_bimodal_btb

# Classic yosys `read_verilog -sv` cannot parse ANSI-style unpacked-array ports at all
# (e.g. `input logic alloc_valid [WIDTH]`) regardless of -sv. rob and lsq's top-level ports use
# that style, so they need yosys's bundled slang frontend instead (-m slang / read_slang), with
# --allow-use-before-declare since lsq (and l1d's mshr) also forward-reference module-scope
# `logic` signals across assign statements, which slang treats as an error by default even though
# ordering doesn't matter for non-automatic variables. rename/prf/l1d/bp_bimodal_btb's unpacked
# arrays are internal signals or otherwise fine, not ANSI ports, so the classic frontend handles
# them.
SLANG_BLOCKS := rob lsq

# Drop-in slot: once rtl/ooo/ooo_core.sv exists (wiring rob+rename+prf+lsq+l1d+bp+alu+muldiv),
# uncomment these two lines and add ooo_core to ALL_BLOCKS above -- no other Makefile/synth.ys
# changes are needed, since the loop below is generic over ALL_BLOCKS.
# FILES_ooo_core := ../rtl/ooo/rob.sv ../rtl/rename/free_list.sv ../rtl/rename/rename_map.sv \
#   ../rtl/rename/rename.sv ../rtl/rename/prf.sv ../rtl/lsq/lsq.sv ../rtl/cache/mshr.sv \
#   ../rtl/cache/l1d.sv ../rtl/bp/bp_bimodal_btb.sv ../rtl/alu.sv ../rtl/muldiv.sv ../rtl/ooo/ooo_core.sv
# TOP_ooo_core := ooo_core
