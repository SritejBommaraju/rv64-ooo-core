// Binds the SVA checker modules into the RTL under test without touching rtl/ itself.
bind regfile regfile_sva u_regfile_sva (.*);
bind core     core_sva    u_core_sva    (.*);
bind mem      mem_sva     u_mem_sva     (.*);
