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
`define CLK_HALF_PERIOD 1

`include "template.vh"

reg axi_arready;
wire axi_arvalid;
wire [33:0] axi_araddr;

reg axi_rvalid;
wire axi_rready;
reg [1:0] axi_rresp;
reg axi_rlast;
reg [31:0] axi_rdata;

reg resolve_request = 1'b0;
reg [31:0] resolve_virtual_address;

wire [19:0] virtual_address = resolve_virtual_address[31:12];

wire resolve_done, resolve_pagefault, resolve_accessfault;

wire [7:0] resolve_metadata;
wire [21:0] resolve_physical_address;

wire [21:0] satp_ppn = 0;

armleocpu_ptw ptw(
	.*
);

reg cycle = 0;

reg [8191:0] pma_error = 0;
reg [31:0] mem [8191:0];
always @(posedge clk) begin
	axi_arready <= 0;
	if(axi_rvalid && axi_rready) begin
		axi_rvalid <= 1'b0;
	end else if(axi_arvalid && !cycle) begin
		cycle <= 1;
		axi_arready <= 1;
	end else if(axi_arvalid && cycle) begin
		axi_rvalid <= 1'b1;
		axi_rlast <= 1'b1;
		axi_rresp <= pma_error[axi_araddr >> 2];
		axi_rdata <= mem[axi_araddr >> 2];
		cycle <= 0;
	end
end


// Test cases:
// Megapage PMA Error mem[1]
// Leaf PMA Error mem[2] mem[1024]
// valid Megapage and page w/
//               w/ rwx mem[3] || mem[8], mem[1025]
//               w/ rw mem[4]  || mem[9], mem[1026]
//               w/ rx mem[5]  || mem[10], mem[1027]
//               w/ r mem[6]   || mem[11], mem[1028]
//               w/ x mem[7]   || mem[12], mem[1029]
// Test for missaligned megapage mem[13]
// Test for invalid megapage leaf
//                        w/ i mem[14]
//                        w/ w mem[15]
//                        w/ xw mem[16]
// Test for invalid leaf
//                        w/ i mem[17], mem[1030]
//                        w/ w mem[18], mem[1031]
//                        w/ xw mem[19], mem[1032]

reg [9:0] t = 0;
reg [9:0] r;
reg [9:0] w;
reg [9:0] x;
reg [31:0] resolve_physical_address_expected;
reg dummy = 0;
initial begin
	r = 10'b000000_0010;
	w = 10'b000000_0100;
	x = 10'b000000_1000;

	$display("-------------- PMA Tests ----------- BEGIN ------");
	// Megapage PMA Error mem[1]
	pma_error[1] = 1;
	mem[1] = 0;
	@(posedge rst_n)
	resolve_request = 1;
	resolve_virtual_address = {10'h1, 10'h0, 12'h001};
	@(negedge clk);
	@(negedge clk);
	@(negedge clk);
	@(negedge clk);
	@(negedge clk);
	`assert_equal(resolve_done, 1'b1);
	`assert_equal(resolve_accessfault, 1'b1);
	`assert_equal(resolve_pagefault, 1'b0);


	// Leaf PMA Error mem[2] mem[1024]
	pma_error[2] = 0;
	mem[2] = {12'h0, 10'h01, 10'h01};
	pma_error[1024] = 1;


	
	resolve_request = 1;
	resolve_virtual_address = {10'h2, 10'h0, 12'h001};
	@(negedge clk);
	while(!resolve_done) begin
		@(negedge clk);
	end
	`assert_equal(resolve_done, 1'b1);
	`assert_equal(resolve_accessfault, 1'b1);
	`assert_equal(resolve_pagefault, 1'b0);
	// IDLE cycles
	resolve_request = 0;
	@(posedge clk)
	
	$display("------------- PMA Tests done ----------- END ------\n\n");





	$display("------------- Megapage valid leaf Tests ----------- BEGIN ------");
	mem[3] = {12'h1, 10'h00, 10'h01} | r | w | x;
	mem[4] = {12'h1, 10'h00, 10'h01} | r | w;
	mem[5] = {12'h1, 10'h00, 10'h01} | r | x;
	mem[6] = {12'h1, 10'h00, 10'h01} | r;
	mem[7] = {12'h1, 10'h00, 10'h01} | x;




	mem[1025] = mem[3];
	mem[1026] = mem[4];
	mem[1027] = mem[5];
	mem[1028] = mem[6];
	mem[1029] = mem[7];


	t = 3;
	repeat(5) begin
		resolve_request = 0;
		resolve_virtual_address = {t, 10'h0, 12'h001};
		@(posedge clk)
		// Idle cycles

		// Request
		@(negedge clk)
		resolve_request = 1;
		@(negedge clk);
		while(!resolve_done) begin
			@(negedge clk);
		end
		resolve_request = 0;
		`assert_equal(resolve_done, 1'b1);
		`assert_equal(resolve_pagefault, 1'b0);
		`assert_equal(resolve_accessfault, 1'b0);
		`assert_equal(resolve_metadata, axi_rdata[9:0]);
		resolve_physical_address_expected = {axi_rdata[31:20], 10'h0};
		`assert_equal(resolve_physical_address, resolve_physical_address_expected);
		$display("------------- Megapage valid leaf for case N = %d/5 done\n", t - 2);
		t = t + 1;
	end
	@(negedge clk)
	resolve_request = 0;
	resolve_virtual_address = {10'd13, 10'h0, 12'h001};
	@(posedge clk)
	$display("------------- Megapage valid leaf Tests done ----------- END ------\n\n");

	resolve_request = 0;
	resolve_virtual_address = {10'd13, 10'h0, 12'h001};
	@(posedge clk)
	@(posedge clk)
	



	// missaligned megapage
	$display("------------- Missaligned Megapage Tests ----------- BEGIN ------\n\n");
	@(negedge clk)
	mem[13] = {12'h1, 10'h01, 10'h01} | r | w | x;

	resolve_request = 1;
	resolve_virtual_address = {10'd13, 10'h0, 12'h001};
	@(negedge clk);
	while(!resolve_done) begin
		@(negedge clk);
	end
	`assert_equal(resolve_done, 1'b1);
	`assert_equal(resolve_pagefault, 1'b1);
	`assert_equal(resolve_accessfault, 1'b0);
	@(posedge clk)
	@(posedge clk)
	dummy = dummy;
	$display("------------- Missaligned Megapage Tests ----------- DONE ------\n\n");

	$display("------------- Invalid Megapage Tests ----------- BEGIN ------\n\n");
	// Test for invalid megapage leaf
	//                        w/ i mem[14]
	//                        w/ w mem[15]
	//                        w/ xw mem[16]
	mem[14] = {22'h0, 10'h0};
	mem[15] = {22'h0, 10'h1} | w;
	mem[16] = {22'h0, 10'h1} | x | w;


	for(t = 0; t < 3; t = t + 1) begin
		@(negedge clk)

		resolve_request = 1;
		resolve_virtual_address = {10'd14 + t, 10'h0, 12'h001};
		@(negedge clk);
		while(!resolve_done) begin
			@(negedge clk);
		end
		`assert_equal(resolve_done, 1'b1);
		`assert_equal(resolve_pagefault, 1'b1);
		`assert_equal(resolve_accessfault, 1'b0);
		dummy = dummy;
	end
	resolve_request = 0;
	@(posedge clk)
	@(posedge clk)
	@(posedge clk)
	$display("------------- Invalid Megapage Tests ----------- DONE ------\n\n");
	dummy = dummy;


	// Test for invalid leaf
	//                        w/ i mem[17], mem[1030]
	//                        w/ w mem[18], mem[1031]
	//                        w/ xw mem[19], mem[1032]
	$display("------------- Invalid leaf page Tests ----------- BEGIN ------\n\n");
	

	mem[17] = {22'h1, 10'h1};
	mem[18] = {22'h1, 10'h1};
	mem[19] = {22'h1, 10'h1};
	mem[1030] = {22'h0, 10'h0};
	mem[1031] = {22'h0, 10'h1} | w;
	mem[1032] = {22'h0, 10'h1} | x | w;


	for(t = 0; t < 3; t = t + 1) begin
		@(negedge clk)

		resolve_request = 1;
		resolve_virtual_address = {10'd17 + t, 10'h6 + t, 12'h001};
		@(negedge clk);		
		while(!resolve_done) begin
			@(negedge clk);
		end
		`assert_equal(resolve_done, 1'b1);
		`assert_equal(resolve_pagefault, 1'b1);
		`assert_equal(resolve_accessfault, 1'b0);
		dummy = dummy;
	end
	resolve_request = 0;
	@(posedge clk)
	@(posedge clk)
	@(posedge clk)
	$display("------------- Invalid leaf page Tests ----------- DONE ------\n\n");
	dummy = dummy;

	$finish;
end


endmodule