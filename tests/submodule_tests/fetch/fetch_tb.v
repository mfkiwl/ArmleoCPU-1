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
////////////////////////////////////////////////////////////////////////////////

`define TIMEOUT 1000
`define SYNC_RST
`define CLK_HALF_PERIOD 5

`define MAXIMUM_ERRORS 1

`include "template.vh"


reg [31:0] reset_vector;
reg c_done;
reg [3:0] c_response;

wire [3:0] c_cmd;
wire [31:0] c_address;

reg [31:0] c_load_data;

reg interrupt_pending;
reg dbg_mode;
wire dbg_pipeline_busy;

wire f2d_valid;
wire [`F2E_TYPE_WIDTH-1:0] f2d_type;
wire [31:0] f2d_instr;
wire [31:0] f2d_pc;

reg d2f_ready;
reg [`ARMLEOCPU_D2F_CMD_WIDTH-1:0] d2f_cmd;
reg [31:0] d2f_branchtarget;

reg dbg_cmd_valid;
reg [`DEBUG_CMD_WIDTH-1:0] dbg_cmd;
reg [31:0] dbg_arg0, dbg_arg1, dbg_arg2;

wire dbg_cmd_ready;

armleocpu_fetch u0 (
    .*
);

initial begin
    
    reset_vector = 32'h100;
    c_done = 0;
    c_response = `CACHE_RESPONSE_SUCCESS;
    c_load_data = 0;

    interrupt_pending = 0;

    dbg_mode = 0;
    dbg_cmd_valid = 0;
    dbg_cmd = `DEBUG_CMD_NONE;

    d2f_ready = 0;
    d2f_cmd = `ARMLEOCPU_D2F_CMD_NONE;
    d2f_branchtarget = 0;



    @(posedge rst_n)

    $display("Testbench: Starting fetch testing");
    
    @(negedge clk);

    $display("Testbench: Test case, start of fetch should start from reset_vector");

    c_done = 1;
    c_load_data = 88;
    d2f_ready = 1;

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h100);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    $display("Testbench: After one fetch and no d2f/dbg_mode next fetch should start");
    

    d2f_ready = 1;

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h104);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 88);
    `assert_equal(f2d_pc, 32'h100);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    $display("Testbench: Fetch should handle cache response stalled 1 cycle");
    

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h104);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 1;
    c_load_data = 99;

    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h108);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 99);
    `assert_equal(f2d_pc, 32'h104);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    $display("Testbench: Fetch should handle cache response stalled 2 cycle");

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h108);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h108);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 1;
    c_load_data = 101;

    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h10C);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 101);
    `assert_equal(f2d_pc, 32'h108);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);


    @(negedge clk);

    $display("Testbench: Fetch should handle cache response stalled 2 cycle, with decode stalling 1 cycle and then branching");


    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h10C);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h10C);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 1;
    c_load_data = 104;

    d2f_ready = 0;

    #1

    `assert_equal(c_cmd, `CACHE_CMD_NONE);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 104);
    `assert_equal(f2d_pc, 32'h10C);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);


    @(negedge clk);
    
    c_done = 0;
    d2f_ready = 1;
    d2f_branchtarget = 32'h200;
    d2f_cmd = `ARMLEOCPU_D2F_CMD_START_BRANCH;

    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h200);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 104);
    `assert_equal(f2d_pc, 32'h10C);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);


    @(negedge clk);

    $display("Testbench: Fetch should handle cache response stalled 2 cycle, with decode stalling 1 cycle and then flushing");

    d2f_cmd = `ARMLEOCPU_D2F_CMD_NONE;

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h200);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 0;
    #1

    `assert_equal(c_cmd, `CACHE_CMD_EXECUTE);
    `assert_equal(c_address, 32'h200);
    `assert_equal(f2d_valid, 0);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);

    @(negedge clk);

    c_done = 1;
    c_load_data = 205;

    d2f_ready = 0;

    #1
    
    `assert_equal(c_cmd, `CACHE_CMD_NONE);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 205);
    `assert_equal(f2d_pc, 32'h200);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);


    @(negedge clk);
    
    c_done = 0;
    d2f_ready = 1;
    d2f_cmd = `ARMLEOCPU_D2F_CMD_FLUSH;

    #1

    `assert_equal(c_cmd, `CACHE_CMD_FLUSH_ALL);
    `assert_equal(f2d_valid, 1);
    `assert_equal(f2d_type, `F2E_TYPE_INSTR);
    `assert_equal(f2d_instr, 205);
    `assert_equal(f2d_pc, 32'h200);
    `assert_equal(dbg_pipeline_busy, 1);
    `assert_equal(dbg_cmd_ready, 0);


    @(negedge clk);
    

    // TODO: Test cases: 
    // Any combination of:
    // d2f stalled 1 cycle, d2f stalled 2 cycles, d2f not stalled
    // Then branch OR flush OR interrupt begin
    // Possibly set dbg_mode
    
    
    // interrupt begin
    // Interrupt begin with debug set
    // Interrupt set after branch


    $display("Testbench: Tests passed");
    $finish;
end


endmodule
