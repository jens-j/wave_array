module qflexpress_wrapper(
    i_clk, 
    i_reset,
    i_wb_cyc,
    i_wb_stb,
    i_cfg_stb,
    i_wb_we,
    i_wb_addr,
    i_wb_data,
    o_wb_stall,
    o_wb_ack,
    o_wb_data,
    o_qspi_sck,
    o_qspi_cs_n,
    o_qspi_mod,
    o_qspi_dat,
    i_qspi_dat
);

input i_clk; // clock input 
input i_reset;
input i_wb_cyc;
input i_wb_stb;
input i_cfg_stb;
input i_wb_we;
input [22:0] i_wb_addr;
input [31:0] i_wb_data;
output o_wb_stall;
output o_wb_ack;
output [31:0] o_wb_data;
output o_qspi_sck;
output o_qspi_cs_n;
output [1:0] o_qspi_mod;
output [3:0] o_qspi_dat;
input  [3:0] i_qspi_dat;

// qflexpress #( .LGFLASHSZ(25) ) qflexpress_inst (
qflexpress #() qflexpress_inst (
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_wb_cyc(i_wb_cyc),
    .i_wb_stb(i_wb_stb),
    .i_cfg_stb(i_cfg_stb),
    .i_wb_we(i_wb_we),
    .i_wb_addr(i_wb_addr[21:0]),
    .i_wb_data(i_wb_data),
    .o_wb_stall(o_wb_stall),
    .o_wb_ack(o_wb_ack),
    .o_wb_data(o_wb_data),
    .o_qspi_sck(o_qspi_sck),
    .o_qspi_cs_n(o_qspi_cs_n),
    .o_qspi_mod(o_qspi_mod),
    .o_qspi_dat(o_qspi_dat),
    .i_qspi_dat(i_qspi_dat)
);

endmodule 