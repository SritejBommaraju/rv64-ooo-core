# OpenSTA script. Reads LIBERTY and NETLIST/TOP from the environment (set by the Makefile).
read_liberty $::env(LIBERTY)
read_verilog $::env(NETLIST)
link_design $::env(TOP)

create_clock -name clk -period 10 [get_ports clk]

report_checks -path_delay max
report_tns
report_wns
