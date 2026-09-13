// Binds decoder functional coverage onto every core instance without touching core.sv.
bind core decode_cov u_decode_cov (.clk(clk), .rst(rst), .instr(imem_rdata));
