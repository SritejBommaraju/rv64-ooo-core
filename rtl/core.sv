// Single-issue, single-cycle RV64I seed core. No pipelining, no OOO yet.
module core (
    input  logic        clk,
    input  logic        rst,
    output logic [63:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic [63:0] dmem_addr,
    output logic [63:0] dmem_wdata,
    output logic        dmem_wen,
    output logic [2:0]  dmem_funct3,
    input  logic [63:0] dmem_rdata
);
    logic [63:0] pc, pc_next;
    assign imem_addr = pc;

    logic [4:0]  rs1, rs2, rd;
    logic [63:0] imm;
    logic [3:0]  alu_op;
    logic        alu_src_imm, reg_write, is_load, is_store, is_branch, is_jal, is_jalr, is_lui, is_auipc;
    logic [2:0]  funct3;
    logic        is_word, is_muldiv;
    logic [2:0]  muldiv_op;

    decode u_decode (
        .instr(imem_rdata), .rs1(rs1), .rs2(rs2), .rd(rd), .imm(imm),
        .alu_op(alu_op), .alu_src_imm(alu_src_imm), .reg_write(reg_write),
        .is_load(is_load), .is_store(is_store), .is_branch(is_branch),
        .is_jal(is_jal), .is_jalr(is_jalr), .is_lui(is_lui), .is_auipc(is_auipc),
        .funct3(funct3), .is_word(is_word), .is_muldiv(is_muldiv), .muldiv_op(muldiv_op)
    );

    logic [63:0] rdata1, rdata2, wdata;
    logic [63:0] alu_a, alu_b, alu_y, muldiv_y;

    assign alu_a = is_auipc ? pc : rdata1;
    assign alu_b = alu_src_imm ? imm : rdata2;

    alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .is_word(is_word), .y(alu_y));
    muldiv u_muldiv (.a(rdata1), .b(rdata2), .op(muldiv_op), .is_word(is_word), .y(muldiv_y));

    // branch condition
    logic branch_taken;
    always_comb begin
        unique case (funct3)
            3'h0: branch_taken = (rdata1 == rdata2);                       // BEQ
            3'h1: branch_taken = (rdata1 != rdata2);                       // BNE
            3'h4: branch_taken = ($signed(rdata1) <  $signed(rdata2));     // BLT
            3'h5: branch_taken = ($signed(rdata1) >= $signed(rdata2));     // BGE
            3'h6: branch_taken = (rdata1 <  rdata2);                       // BLTU
            3'h7: branch_taken = (rdata1 >= rdata2);                       // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    assign dmem_addr   = rdata1 + imm;
    assign dmem_wdata  = rdata2;
    assign dmem_wen    = is_store;
    assign dmem_funct3 = funct3;

    // load sign/zero extension
    logic [63:0] load_data;
    always_comb begin
        unique case (funct3)
            3'h0: load_data = {{56{dmem_rdata[7]}},  dmem_rdata[7:0]};   // LB
            3'h1: load_data = {{48{dmem_rdata[15]}}, dmem_rdata[15:0]};  // LH
            3'h2: load_data = {{32{dmem_rdata[31]}}, dmem_rdata[31:0]};  // LW
            3'h3: load_data = dmem_rdata;                                // LD
            3'h4: load_data = {56'd0, dmem_rdata[7:0]};                  // LBU
            3'h5: load_data = {48'd0, dmem_rdata[15:0]};                 // LHU
            3'h6: load_data = {32'd0, dmem_rdata[31:0]};                 // LWU
            default: load_data = dmem_rdata;
        endcase
    end

    assign wdata = is_load   ? load_data :
                   is_lui    ? imm :
                   is_jal    ? pc + 64'd4 :
                   is_jalr   ? pc + 64'd4 :
                   is_muldiv ? muldiv_y :
                   alu_y;

    regfile u_regfile (
        .clk(clk), .rs1(rs1), .rs2(rs2), .rd(rd),
        .wdata(wdata), .wen(reg_write), .rdata1(rdata1), .rdata2(rdata2)
    );

    always_comb begin
        if (is_jal)               pc_next = pc + imm;
        else if (is_jalr)         pc_next = (rdata1 + imm) & ~64'd1;
        else if (is_branch && branch_taken) pc_next = pc + imm;
        else                      pc_next = pc + 64'd4;
    end

    always_ff @(posedge clk) begin
        if (rst) pc <= 64'd0;
        else     pc <= pc_next;
    end
endmodule
