`timescale 1ns/1ns
module cache_testbench;

`include "../sync_clk_gen_template.svh"

`include "../../src/corevx_defs.sv"


initial begin
    //#100000
    //$finish;
end


logic [31:0] c_address;
logic c_wait, c_pagefault, c_accessfault, c_done;

logic c_execute;

logic c_load;
logic [2:0] c_load_type;
logic [31:0] c_load_data;
logic c_load_unknowntype, c_load_missaligned;


logic c_store;
logic [1:0] c_store_type;
logic [31:0] c_store_data;
logic c_store_unknowntype, c_store_missaligned;

logic c_flush;
logic c_flushing, c_flush_done, c_miss;

logic csr_matp_mode;
logic [21:0] csr_matp_ppn;

logic [33:0] m_address;
logic [4:0] m_burstcount;

logic m_waitrequest;
logic [1:0] m_response;

logic m_read, m_write, m_readdatavalid;
logic [31:0] m_readdata, m_writedata;
logic [3:0] m_byteenable;


corevx_cache cache(
    .*
);

// 1st 4KB is not used
// 2nd 4KB is megapage table
// 3rd 4KB is page table
// 4th 4KB is data page 0
// 5th 4KB is data page 1
// 6th 4KB is data page 2
// 7th 4KB is data page 3
// Remember: mem addressing is word based


reg [31:0] mem [1024*1024-1:0];
reg [1024*1024-1:0] pma_error = 0;

initial begin
    m_response = 2'b11;

    m_readdata = 0;
    m_readdatavalid = 0;
    
end



wire [31:0] m = ((m_address & ~{2'b0, 1'b1, 31'h0}) >> 2) ;
wire bypassing = |(m_address & {2'b0, 1'b1, 31'h0});
wire k = pma_error[m];

always @(posedge clk) begin
    if(m_read && m_waitrequest) begin
        m_readdata <= mem[m];
        m_readdatavalid <= 1;
        m_waitrequest <= 0;
        if(pma_error[m] === 1) begin
            m_response <= 2'b11;
        end else begin
            m_response <= 2'b00;
        end
    end else if(m_write && m_waitrequest) begin
        if(pma_error[m] === 1) begin
            m_response <= 2'b11;
        end else begin
            m_response <= 2'b00;
        end
        if(m_byteenable[3])
            mem[m][31:24] <= m_writedata[31:24];
        if(m_byteenable[2])
            mem[m][23:16] <= m_writedata[23:16];
        if(m_byteenable[1])
            mem[m][15:8 ] <= m_writedata[15:8];
        if(m_byteenable[0])
            mem[m][7 :0 ]<= m_writedata[7:0];
        
        m_waitrequest <= 0;
        m_readdatavalid <= 0;
    end else begin
        m_waitrequest <= 1;
        m_readdatavalid <= 0;
        m_response <= 2'b11;
    end
end


task cache_readreq;
input [31:0] address;
begin
    c_load = 1;
    c_address = address;
    do begin
        @(negedge clk);
    end while(!c_done);
    c_load = 0;
end
endtask

task cache_checkread;
input [31:0] readdata;
begin
    @(posedge clk);
    `assert(c_done, 1);
    `assert(c_load_data, readdata);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(negedge clk);
end
endtask

task cache_writereq;
input [31:0] address;
input [31:0] store_data;
begin
    c_store = 1;
    c_address = address;
    c_store_data = store_data;
    do begin
        @(posedge clk);
    end while(!c_done);
    ///@(negedge clk);
    c_store = 0;
    @(negedge clk);
end
endtask
    

reg [31:0] lfsr_state = 32'h13ea9c83;
reg [31:0] saved_state;
reg [31:0] saved_address[1023:0];
reg [31:0] saved_data[1023:0];

integer seed = 32'h13ea9c83;

integer temp;

reg [31:0] addr, data;

initial begin
    /*$urandom(seed);

    repeat(10) begin
        $display("%d", $urandom);
    end
    $display("\n\n");

    seed = 32'h13ea9c83;
    $urandom(seed);
    
    repeat(10) begin
        $display("%d", $urandom);
    end*/

    c_address = 0;
    c_execute = 0;

    c_load = 0;
    c_load_type = LOAD_WORD;
    
    c_store = 0;
    c_store_type = STORE_WORD;
    c_store_data = 0;
    
    c_flush = 0;

    csr_matp_mode = 0;
    csr_matp_ppn = 1;

    @(posedge rst_n)
    @(posedge clk)
    /*
    mem[0] = 32'hBEAFDEAD;
    c_load <= 1;
    //     VTAG/PTAG, LANE, OFFSET, INWORD_OFSET
    c_address <= {20'h80000, 6'h0, 4'h0, 2'h0};
    @(posedge clk)
    @(posedge clk)
    c_load <= 0;
    @(posedge clk)
    `assert(c_done, 1);
    `assert(c_load_data, 32'hBEAFDEAD);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(posedge clk)
    $display("Bypassed Physical Load Done 32'hBEAFDEAD");





    c_store <= 1;
    c_store_data <= 32'hFFCC2211;
    c_address <= {20'h80000, 6'h0, 4'h0, 2'h0};
    @(posedge clk)
    @(posedge clk)
    c_store = 0;
    @(posedge clk)
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    `assert(c_done, 1);
    @(posedge clk)
    `assert(mem[((c_address & ~{2'b0, 1'b1, 31'h0}) >> 2)], 32'hFFCC2211);
    $display("Bypassed Physical Store Done");



    
    mem[{1'b1, 6'h1, 4'h1}] = 32'hAF728D27;
    c_load <= 1;
    //     VTAG/PTAG, LANE, OFFSET, INWORD_OFSET
    c_address <= {20'h80001, 6'h1, 4'h1, 2'h0};
    @(posedge clk)
    @(posedge clk)
    c_load <= 0;
    @(posedge clk)
    `assert(c_load_data, 32'hAF728D27);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(posedge clk)
    $display("Bypassed Physical Load Done AF728D27");
    


    mem[1] = 32'hAFBEADDE;
    c_load <= 1;
    //     VTAG/PTAG, LANE, OFFSET, INWORD_OFSET
    c_address <= {20'h80000, 6'h0, 4'h1, 2'h0};
    @(posedge clk)
    @(posedge clk)
    c_load <= 0;
    @(posedge clk)
    `assert(c_load_data, 32'hAFBEADDE);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(posedge clk)
    $display("Bypassed Physical Load Done AFBEADDE");




    @(posedge clk)
    c_load <= 1;
    c_address <= {20'h00000, 6'h0, 4'h1, 2'h0};
    @(posedge clk)
    @(posedge clk)
    @(posedge clk)
    @(posedge clk)


    repeat(32) begin
        @(posedge clk);
        `assert(c_done, 0);
    end

    c_load <= 0;
    @(posedge clk);
    `assert(c_done, 1);
    `assert(c_load_data, 32'hAFBEADDE);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(posedge clk);
    $display("First Cached load done (miss)");




    mem[{6'h1, 4'h1}] = 32'hAE101080;

    c_load <= 1;
    c_address <= {20'h00000, 6'h1, 4'h1, 2'h0};


    @(posedge clk)
    @(posedge clk)
    @(posedge clk)
    @(posedge clk)


    repeat(32) begin
        @(posedge clk);
        `assert(c_done, 0);
    end

    c_load <= 0;
    @(posedge clk);
    `assert(c_done, 1);
    `assert(c_load_data, 32'hAE101080);
    `assert(c_load_missaligned, 0);
    `assert(c_load_unknowntype, 0);
    `assert(c_store_missaligned, 0);
    `assert(c_store_unknowntype, 0);
    @(posedge clk);
    $display("Second Cached load done (miss)");

    */
    
    @(negedge clk)
    //cache_flush();
    cache_writereq({20'h00000, 6'h4, 4'h1, 2'h0}, 32'd0);
    //@(negedge clk)
    cache_writereq({20'h00001, 6'h4, 4'h1, 2'h0}, 32'd1);
    //@(negedge clk)
    cache_writereq({20'h00002, 6'h4, 4'h1, 2'h0}, 32'd2);
    //@(negedge clk)
    cache_writereq({20'h00003, 6'h4, 4'h1, 2'h0}, 32'd3);
    //@(negedge clk)
    cache_writereq({20'h00004, 6'h4, 4'h1, 2'h0}, 32'd4);
    //@(negedge clk)
    cache_writereq({20'h00005, 6'h4, 4'h1, 2'h0}, 32'd5);
    //@(negedge clk)

    cache_readreq({20'h00000, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd0);
    //@(negedge clk)
    cache_readreq({20'h00001, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd1);
    //@(negedge clk)
    cache_readreq({20'h00002, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd2);
    //@(negedge clk)
    cache_readreq({20'h00003, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd3);
    //@(negedge clk)
    cache_readreq({20'h00004, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd4);
    //@(negedge clk)
    cache_readreq({20'h00005, 6'h4, 4'h1, 2'h0});
    cache_checkread(32'd5);
    //@(negedge clk)
    
    $display("[t=%d][TB] Known ordered accesses done", $time);
    
    seed = 32'h13ea9c84;
    temp = $urandom(seed);
    addr = 0;
    //addr = ;
    //data = ;
    repeat(1000) begin
        addr = addr + 1;
        data = $urandom;
        cache_writereq((addr) << 5, data);
    end
    
    $display("[t=%d][TB] RNG Write done", $time);
    seed = 32'h13ea9c84;
    temp = $urandom(seed);
    addr = 0;
    repeat(1000) begin
        addr = addr + 1;
        data = $urandom;
        cache_readreq((addr) << 5);
        cache_checkread(data);
    end
        
    $display("[t=%d][TB] RNG Read done", $time);
    repeat(10) begin
        @(posedge clk);
    end
    $finish;
/*
            
            
            ISSUE_PHYS_LOAD_1: begin
                if(c_done && !c_wait) begin
                    state <= ISSUE_PHYS_STORE;
                    `assert(c_load_data, 32'hBEAFDEAD);
                    `assert(c_load_missaligned, 0);
                    `assert(c_load_unknowntype, 0);
                    `assert(c_store_missaligned, 0);
                    `assert(c_store_unknowntype, 0);
                end
            end
            ISSUE_PHYS_STORE: begin
                if(c_done && !c_wait) begin
                    state <= state + 1;
                end
            end
            ISSUE_PHYS_LOAD_2: begin

            end
            ISSUE_FLUSH: begin
                if(c_flush_done)
                    state <= state + 1;
            end
            ISSUE_PHYS_LOAD_3: begin

            end
            @(posedge clk)
            @(posedge clk)
            $finish;
        endcase
    end*/
end



/*

PTW Megapage Access fault
PTW Page access fault
Cache memory access fault

PTW Megapage pagefault
PTW Page pagefault
Cache memory pagefault for each case (read, write, execute, access, dirty, user)

For two independent lanes
    For each csr_satp_mode = 0 and csr_satp_mode = 1
        For address[33:32] = 0 and address[33:32] != 0
            For each load type and store type combination
                Bypassed load
                Bypassed load after load
                Bypassed store
                Bypassed load after store
                Bypassed store after store

                Cached load
                Cached load after load
                Cached store
                Cached load after store
                Cached store after store
        For each unknown type for load
            Bypassed load
            Cached load
        For each unknown type for store
            Bypassed store
            Cached store
        For each missaligned address for each store case
            Bypassed store
            Cached store
        For each missaligned address for each load case
            Bypassed load
            Cached load
    Flush

Generate random access pattern using GLFSR, check for validity
*/


endmodule
