////////////////////////////////////////////////////////////////////////////////
// 
// This file is part of ArmleoCPU.
// ArmleoCPU is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// ArmleoCPU is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with ArmleoCPU.  If not, see <https://www.gnu.org/licenses/>.
// 
// Copyright (C) 2016-2021, Arman Avetisyan, see COPYING file or LICENSE file
// SPDX-License-Identifier: GPL-3.0-or-later
// 

`define TIMEOUT 10000
`define SYNC_RST
`define CLK_HALF_PERIOD 5

`include "template.vh"


localparam ADDR_WIDTH = 16;
localparam ID_WIDTH = 4;
localparam DATA_WIDTH = 32;
localparam DATA_STROBES = DATA_WIDTH/8;
localparam HARTS = 3;

reg axi_awvalid;
wire axi_awready;
reg [ADDR_WIDTH-1:0] axi_awaddr;
wire [7:0] axi_awlen = 0;
wire [2:0] axi_awsize = 3'b010; // DATA_WIDTH == 64, will need to replace
wire [1:0] axi_awburst = 2'b01;
wire [ID_WIDTH-1:0] axi_awid = 0; // checked by formal

reg axi_wvalid;
wire axi_wready;
reg [DATA_WIDTH-1:0] axi_wdata;
reg [DATA_STROBES-1:0] axi_wstrb;
wire axi_wlast = 1; // checked by formal

wire axi_bvalid;
reg axi_bready;
wire [1:0] axi_bresp;
wire [ID_WIDTH-1:0] axi_bid; // checked by formal


reg axi_arvalid;
wire axi_arready;
reg [ADDR_WIDTH-1:0] axi_araddr;
wire [7:0] axi_arlen = 0;
wire [2:0] axi_arsize = 3'b010; // DATA_WIDTH == 64, will need to replace
wire [1:0] axi_arburst = 2'b01;
wire [ID_WIDTH-1:0] axi_arid = 0; // checked by formal

wire axi_rvalid;
reg axi_rready;
wire [1:0] axi_rresp;
wire [DATA_WIDTH-1:0] axi_rdata;
wire axi_rlast; // checked by formal
wire [ID_WIDTH-1:0] axi_rid; // checked by formal

reg mtime_increment;

reg [HARTS-1:0] hart_m_swi;
reg [HARTS-1:0] hart_s_swi;
reg [HARTS-1:0] hart_timeri;


`TOP #(
    .ID_WIDTH(ID_WIDTH),
    .HART_COUNT(HARTS)
) clint (
    .*
);

//-------------AW---------------
task aw_op;
input valid;
input [ADDR_WIDTH-1:0] addr;
begin
    axi_awvalid = valid;
    axi_awaddr = addr;
end endtask

task aw_expect;
input awready;
begin
    `assert_equal(axi_awready, awready);
end endtask

//-------------W---------------

task w_op;
input valid;
input [DATA_WIDTH-1:0] wdata;
input [DATA_STROBES-1:0] wstrb;
begin
    axi_wvalid = valid;
    axi_wdata = wdata;
    axi_wstrb = wstrb;
end endtask

task w_expect;
input wready;
begin
    `assert_equal(axi_wready, wready)
end endtask

//-------------B---------------
task b_op;
input ready;
begin
    axi_bready = ready;
end endtask

task b_expect;
input valid;
input [1:0] resp;
begin
    `assert_equal(axi_bvalid, valid)
    if(valid) begin
        `assert_equal(axi_bresp, resp)
    end
end endtask

//-------------AR---------------

task ar_op; 
input valid;
input [ADDR_WIDTH-1:0] addr;
begin
    axi_arvalid = valid;
    axi_araddr = addr;
end endtask

task ar_expect;
input ready;
begin
    `assert_equal(axi_arready, ready)
end endtask

//-------------R---------------
task r_op;
input ready;
begin
    axi_rready = ready;
end endtask

task r_expect;
input valid;
input [1:0] resp;
input [DATA_WIDTH-1:0] data;
begin
    `assert_equal(axi_rvalid, valid)
    if(valid) begin
        `assert_equal(axi_rresp, resp)
        if(resp <= 2'b01)
            `assert_equal(axi_rdata, data)
    end
end endtask

//-------------Others---------------
task poke_all;
input aw;
input w;
input b;

input ar;
input r;
begin
    if(aw === 1)
        aw_op(0, 0);
    if(w === 1)
        w_op(0, 0, 0);
    if(b === 1)
        b_op(0);
    if(ar === 1)
        ar_op(0, 0);
    if(r === 1)
        r_op(0);
end endtask

task expect_all;
input aw;
input w;
input b;

input ar;
input r;begin
    if(aw === 1)
        aw_expect(0);
    if(w === 1)
        w_expect(0);
    if(b === 1)
        b_expect(0, 2'bZZ);
    if(ar === 1)
        ar_expect(0);
    if(r === 1)
        r_expect(0, 2'bZZ, {DATA_WIDTH{1'bZ}});
end endtask

function [0:0] is_addr_in_range;
input [ADDR_WIDTH-1:0] addr;
begin
    is_addr_in_range = 0;
    if(addr[15:12] == 0 && (addr[11:2] < HARTS))
        is_addr_in_range = 1;
    else if(addr[15:12] == 4 && (addr[11:3] < HARTS))
        is_addr_in_range = 1;
    else if(addr[15:12] == 'hC && (addr[11:2] < HARTS)) // S SWI
        is_addr_in_range = 1;
    else if(addr == 16'hBFF8 || addr == 16'hBFF8 + 4)
        is_addr_in_range = 1;
end
endfunction

task test_write;
input [ADDR_WIDTH-1:0] addr;
input [DATA_STROBES-1:0] strb;
input [DATA_WIDTH-1:0] data;
begin
    reg [1:0] expected_resp;
    aw_op(1, addr);
    expect_all(1,1,1, 1,1);
    @(negedge clk)

    
    w_op(1, data, strb);
    
    
    if(is_addr_in_range(addr))
        expected_resp = 2'b00;
    else
        expected_resp = 2'b10;
    
    #2
    expect_all(0,0,1, 1,1);
    aw_expect(1);
    w_expect(1);

    // Stalled B cycle

    @(negedge clk)

    aw_op(0, 0);
    w_op(0, 0, 0);

    b_op(0);

    expect_all(1,1, 0, 1,1);
    b_expect(1, expected_resp);

    @(negedge clk)
    b_op(1);

    #2
    expect_all(1,1, 0, 1,1);
    b_expect(1, expected_resp);
    @(negedge clk);
    poke_all(1,1,1, 1,1);
end
endtask

task test_read;
input [ADDR_WIDTH-1:0] addr;
input [DATA_WIDTH-1:0] data;
begin
    reg [1:0] expected_resp;
    
    if(is_addr_in_range(addr))
        expected_resp = 2'b00;
    else
        expected_resp = 2'b10;
    
    ar_op(1, addr);

    #2

    expect_all(1,1,1, 0,1);
    @(negedge clk);

    ar_op(0, 0);
    r_op(0);
    #2
    r_expect(1, expected_resp, data);
    expect_all(1,1,1, 1,0);
    @(negedge clk);


    ar_op(0, 0);
    r_op(1);
    #2
    r_expect(1, expected_resp, data);
    expect_all(1,1,1, 1,0);
    @(negedge clk);
    poke_all(1,1,1, 1,1);
end
endtask


initial begin
    
    @(posedge rst_n)
    mtime_increment = 0;
    poke_all(1,1,1, 1,1);
    expect_all(1,1,1, 1,1);


    $display("Testing M SWI", $time);
    test_write(16'h0000, 4'hF, 1); // write to msip[0]
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 0)
    `assert_equal(hart_m_swi[2], 0)

    test_write(16'h0004, 4'hF, 1); // write to msip[1]
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 1)
    `assert_equal(hart_m_swi[2], 0)

    test_write(16'h0008, 4'hF, 1); // write to msip[1]
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 1)
    `assert_equal(hart_m_swi[2], 1)

    test_write(16'h0000, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 1)
    `assert_equal(hart_m_swi[2], 1)

    test_write(16'h0004, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 1)
    `assert_equal(hart_m_swi[2], 1)

    test_write(16'h0008, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_m_swi[0], 1)
    `assert_equal(hart_m_swi[1], 1)
    `assert_equal(hart_m_swi[2], 1)

    test_read(16'h0000, 1);
    test_read(16'h0004, 1);
    test_read(16'h0008, 1);
    test_write(16'h0008, 4'hF, 32'hFFFFFFFF);
    test_read(16'h0008, 1);
    



    $display("Testing S SWI", $time);
    test_write(16'hC000, 4'hF, 1); // write to msip[0]
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 0)
    `assert_equal(hart_s_swi[2], 0)

    test_write(16'hC004, 4'hF, 1); // write to msip[1]
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 1)
    `assert_equal(hart_s_swi[2], 0)

    test_write(16'hC008, 4'hF, 1); // write to msip[1]
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 1)
    `assert_equal(hart_s_swi[2], 1)

    test_write(16'hC000, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 1)
    `assert_equal(hart_s_swi[2], 1)

    test_write(16'hC004, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 1)
    `assert_equal(hart_s_swi[2], 1)

    test_write(16'hC008, 4'h0, 0); // write to msip[0] with byte disabled
    `assert_equal(hart_s_swi[0], 1)
    `assert_equal(hart_s_swi[1], 1)
    `assert_equal(hart_s_swi[2], 1)

    test_read(16'hC000, 1);
    test_read(16'hC004, 1);
    test_read(16'hC008, 1);

    test_write(16'hC008, 4'hF, 32'hFFFFFFFF);
    test_read(16'hC008, 1);


    $display("Testing MTIME", $time);
    mtime_increment = 1;
    @(negedge clk)
    mtime_increment = 0;
    test_read(16'hBFF8, 1);

    test_read(16'hBFF8 + 4, 0);

    $display("Testbench: MTIME writing", $time);
    test_write(16'hBFF8, 4'hF, 32'hFFFFFFFF);
    test_write(16'hBFF8 + 4, 4'hF, 32'hFFFFFFFF);

    test_read(16'hBFF8, 32'hFFFFFFFF);
    test_read(16'hBFF8 + 4, 32'hFFFFFFFF);

    // Revert to original value for other tests
    test_write(16'hBFF8, 4'hF, 1);
    test_write(16'hBFF8 + 4, 4'hF, 0);

    
    $display("Testbench: Timer interrupts", $time);

    test_write(16'h4000, 4'hF, 1);
    test_write(16'h4004, 4'hF, 0);
    `assert_equal(hart_timeri, 3'b001)

    test_write(16'h4008, 4'hF, 1);
    test_write(16'h400C, 4'hF, 0);
    `assert_equal(hart_timeri, 3'b011)

    test_write(16'h4010, 4'hF, 1);
    test_write(16'h4014, 4'hF, 0);
    `assert_equal(hart_timeri, 3'b111)

    test_read(16'h4000, 1);
    test_read(16'h4004, 0);
    test_read(16'h4008, 1);
    test_read(16'h400C, 0);
    test_read(16'h4010, 1);
    test_read(16'h4014, 0);
    

    $display("Testbench: access to unknown locations returns error", $time);

    test_read(16'h000C, 0);
    test_read(16'h000C, 0);

    test_read(16'h4018, 0);
    
    test_read(16'hD000, 0);

    @(negedge clk)
    
    @(negedge clk)
    @(negedge clk)
    @(negedge clk)
    $finish;
end

endmodule