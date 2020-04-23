`timescale 1ns/1ns
module corevx_cache(
    input                   clk,
    input                   rst_n,

    //                      CACHE <-> EXECUTE/MEMORY
    
    output reg   [3:0]      c_response, // CACHE_RESPONSE_*
    output reg              c_reset_done,

    input  [3:0]            c_cmd, // CACHE_CMD_*
    input  [31:0]           c_address,
    input  [2:0]            c_load_type, // enum defined in corevx_defs LOAD_*
    output wire  [31:0]     c_load_data,
    input [1:0]             c_store_type, // enum defined in corevx_defs STORE_*
    input [31:0]            c_store_data,

    //                      CACHE <-> CSR
    //                      More in docs/
    //                      SATP from RISC-V privileged spec registered on FLUSH_ALL or SFENCE_VMA
    input                   csr_satp_mode, // Mode = 0 -> physical access,
                                           // 1 -> ppn valid
    input [21:0]            csr_satp_ppn,
    
    //                      MPRV from RISC-V privileged spec
    input                   csr_mstatus_mprv,
    //                      MXR from RISC-V privileged spec
    input                   csr_mstatus_mxr,
    //                      SUM from RISC-V privileged spec
    input                   csr_mstatus_sum,
    //                      MPP from RISC-V privileged spec
    input [1:0]             csr_mstatus_mpp,

    //                      MPRV from COREVX Extension
    input [1:0]             csr_mcurrent_privilege,


    
    //                      CACHE <-> MEMORY
    output reg              m_transaction,
    output reg   [2:0]      m_cmd,         // enum `ARMLEOBUS_CMD_*
    input                   m_transaction_done,
    input        [2:0]      m_transaction_response, // enum `ARMLEOBUS_RESPONSE_*
    output reg   [33:0]     m_address,
    output reg   [3:0]      m_burstcount,
    output reg   [31:0]     m_wdata,
    output reg   [3:0]      m_wbyte_enable,
    input        [31:0]     m_rdata
);

// |------------------------------------------------|
// |                                                |
// |              Parameters and includes           |
// |                                                |
// |------------------------------------------------|
//`define DEBUG_PTAG
//`define DEBUG_LANESTATE_WRITE
//`define DEBUG_LANESTATE_READ


`include "armleobus_defs.svh"
`include "corevx_privilege.svh"
`include "corevx_cache.svh"
`include "corevx_accesstag_defs.svh"
`include "st_type.svh"
`include "ld_type.svh"
`include "corevx_tlb_defs.svh"


parameter WAYS_W = 2;
localparam WAYS = 2**WAYS_W;

parameter TLB_ENTRIES_W = 4;
parameter TLB_WAYS_W = 2;
localparam TLB_ENTRIES = 2**TLB_ENTRIES_W;
// TODO:

localparam LANES_W = 6;
localparam LANES = 2**LANES_W;

localparam PHYS_W = 22;
localparam VIRT_W = 20;

// 4 = 16 words each 32 bit = 64 byte
localparam OFFSET_W = 4;
localparam WORDS_IN_LANE = 2**OFFSET_W;
// |------------------------------------------------|
// |                                                |
// |              Cache State                       |
// |                                                |
// |------------------------------------------------|

reg [3:0] state;
reg [3:0] return_state;
localparam 	STATE_RESET = 4'd0,
            STATE_ACTIVE = 4'd1,
            STATE_FLUSH = 4'd2,
            STATE_REFILL = 4'd3,
            STATE_FLUSH_ALL = 4'd4,
            STATE_PTW = 4'd5;
reg [LANES_W-1:0] reset_lane_counter;
reg  [TLB_ENTRIES_W-1:0] tlb_invalidate_set_index;
reg [OFFSET_W-1:0] os_word_counter;

// |------------------------------------------------|
// |                                                |
// |              Output stage                      |
// |                                                |
// |------------------------------------------------|
reg                         os_active;
reg                         os_error;
reg                         os_error_type;

//                          address decomposition
reg [VIRT_W-1:0]            os_address_vtag; // Used by PTW
reg [LANES_W-1:0]           os_address_lane;
reg [OFFSET_W-1:0]          os_address_offset;
reg [1:0]                   os_address_inword_offset;



reg [3:0]                   os_cmd;
reg [2:0]                   os_load_type;
reg [1:0]                   os_store_type;
`ifdef DEBUG
    reg [7*8-1:0] c_cmd_ascii;
    always @* begin
        if(c_cmd == `CACHE_CMD_LOAD) begin
            c_cmd_ascii = "LOAD";
        end else if(c_cmd == `CACHE_CMD_EXECUTE) begin
            c_cmd_ascii = "EXECUTE";
        end else if(c_cmd == `CACHE_CMD_STORE) begin
            c_cmd_ascii = "STORE";
        end else begin
            c_cmd_ascii = "UNKNOWN";
        end
    end

    reg [7*8-1:0] os_cmd_ascii;
    always @* begin
        if(os_cmd == `CACHE_CMD_LOAD) begin
            os_cmd_ascii = "LOAD";
        end else if(os_cmd == `CACHE_CMD_EXECUTE) begin
            os_cmd_ascii = "EXECUTE";
        end else if(os_cmd == `CACHE_CMD_STORE) begin
            os_cmd_ascii = "STORE";
        end else begin
            os_cmd_ascii = "UNKNOWN";
        end
    end
    reg [3*8-1:0] os_load_type_ascii;
    always @* begin
        case (os_load_type)
            LOAD_BYTE:
                os_load_type_ascii = "lb";
            LOAD_BYTE_UNSIGNED:
                os_load_type_ascii = "lbu";
            LOAD_HALF:
                os_load_type_ascii = "lh";
            LOAD_HALF_UNSIGNED:
                os_load_type_ascii = "lhu";
            LOAD_WORD:
                os_load_type_ascii = "lw";
            default:
                os_load_type_ascii = "???";
        endcase
    end
    
    reg [2*8-1:0] os_store_type_ascii;
    always @* begin
        case (os_store_type)
            STORE_BYTE:
                os_store_type_ascii = "sb";
            STORE_HALF:
                os_store_type_ascii = "sh";
            STORE_WORD:
                os_store_type_ascii = "sw";
            default:
                os_store_type_ascii = "??";
        endcase
    end

    reg[11*8-1:0] c_response_ascii;
    always @* begin
        case (c_response)
            `CACHE_RESPONSE_IDLE:        c_response_ascii = "IDLE";
            `CACHE_RESPONSE_DONE:        c_response_ascii = "DONE";
            `CACHE_RESPONSE_WAIT:        c_response_ascii = "WAIT";
            `CACHE_RESPONSE_MISSALIGNED: c_response_ascii = "MISSALIGNED";
            `CACHE_RESPONSE_PAGEFAULT:   c_response_ascii = "PAGEFAULT";
            `CACHE_RESPONSE_UNKNOWNTYPE: c_response_ascii = "UNKNOWNTYPE";
            `CACHE_RESPONSE_ACCESSFAULT: c_response_ascii = "ACCESSFAULT";
            default:
                os_store_type_ascii = "???????????";
        endcase
    end
`endif

reg [31:0]                  os_store_data;


reg [WAYS_W-1:0]            victim_way;
reg                         csr_satp_mode_r;
reg [21:0]                  csr_satp_ppn_r;

// TODO: Register this
reg [1:0]                   os_csr_mcurrent_privilege;
reg                         os_csr_mstatus_mprv;
reg                         os_csr_mstatus_mxr;
reg                         os_csr_mstatus_sum;
reg [1:0]                   os_csr_mstatus_mpp;


// |------------------------------------------------|
// |                                                |
// |              Signals                           |
// |                                                |
// |------------------------------------------------|


// TODO: correctly handle vm_enabled csr_satp_mode_r
wire [1:0] vm_privilege = ((os_csr_mcurrent_privilege == `COREVX_PRIVILEGE_MACHINE) && os_csr_mstatus_mprv) ? os_csr_mstatus_mpp : os_csr_mcurrent_privilege;
wire vm_enabled = (vm_privilege == `COREVX_PRIVILEGE_SUPERVISOR || vm_privilege == `COREVX_PRIVILEGE_USER) && csr_satp_mode_r;

wire access_request =   (c_cmd == `CACHE_CMD_EXECUTE) ||
                        (c_cmd == `CACHE_CMD_LOAD) ||
                        (c_cmd == `CACHE_CMD_STORE);

wire [VIRT_W-1:0] 	        c_address_vtag          = c_address[31:32-VIRT_W]; // Goes to TLB/PTW only
wire [LANES_W-1:0]	        c_address_lane          = c_address[2+OFFSET_W+LANES_W-1:2+OFFSET_W];
wire [OFFSET_W-1:0]			c_address_offset        = c_address[2+OFFSET_W-1:2];
wire [1:0]			        c_address_inword_offset = c_address[1:0];


reg                         stall; // Output stage stalls input stage
wire                        pagefault;
reg                         unknowntype;
reg                         missaligned;

wire [PHYS_W-1:0]           ptag;

// reset state
reg                         tlb_invalidate_done;
reg                         reset_valid_reset_done;

wire [WAYS-1:0]             os_valid_per_way = lanestate_readdata[0];
wire [WAYS-1:0]             os_dirty_per_way = lanestate_readdata[1];
wire                        os_victim_valid = os_valid_per_way[victim_way];
wire                        os_victim_dirty = os_dirty_per_way[victim_way] && os_valid_per_way[victim_way];

reg  [WAYS-1:0]             way_hit;
reg  [WAYS_W-1:0]           os_cache_hit_way;
reg                         os_cache_hit;
reg  [31:0]                 os_readdata;




// Lane tag storage
// Valid and Dirty bits = Lanestate
// PTAG is read when idle or flush_all
// Valid and dirty is read when idle or flush_all
// PTAG is written when in refill
// Valid and dirty is written when idle, refill, or flush

//                      PTAG Read port
reg                     ptag_read           [WAYS-1:0];
reg  [LANES_W-1:0]      ptag_readlane       [WAYS-1:0];
wire [PHYS_W-1:0]       ptag_readdata       [WAYS-1:0];

//                      PTAG Write port
reg                     ptag_write          [WAYS-1:0];
reg  [LANES_W-1:0]      ptag_writelane;
reg  [PHYS_W-1:0]       ptag_writedata;

//                      lanestate read port
reg                     lanestate_read           [WAYS-1:0];
reg  [LANES_W-1:0]      lanestate_readlane       [WAYS-1:0];
wire [WAYS-1:0]         lanestate_readdata       [1:0];
//                      lanestate write port
reg  [WAYS-1:0]         lanestate_write;
reg  [LANES_W-1:0]      lanestate_writelane;
reg  [1:0]              lanestate_writedata;
`ifdef DEBUG
    `ifdef DEBUG_LANESTATE_WRITE
        genvar lanestate_write_counter;
        generate
        for(lanestate_write_counter = 0; lanestate_write_counter < WAYS; lanestate_write_counter = lanestate_write_counter + 1) begin : lanestate_write_debug_for
            always @(posedge clk)
                if(lanestate_write[lanestate_write_counter]) begin
                    $display("[%d] lanestate_write way = 0x%X, lane = 0x%X, data = 0x%X",
                            $time, lanestate_write_counter, lanestate_writelane, lanestate_writedata);
                end
        end
        endgenerate
    `endif
`endif

//                      Storage read port vars
reg  [WAYS-1:0]         storage_read;
reg  [LANES_W-1:0]      storage_readlane    [WAYS-1:0];
reg  [OFFSET_W-1:0]     storage_readoffset  [WAYS-1:0];
wire [31:0]             storage_readdata    [WAYS-1:0];
//                      Storage write port vars
reg  [WAYS-1:0]         storage_write;
reg  [3:0]              storage_byteenable;
reg  [31:0]             storage_writedata;
reg  [LANES_W-1:0]      storage_writelane;
reg  [OFFSET_W-1:0]     storage_writeoffset;


// PTW request signals
reg                     ptw_resolve_request;
reg  [19:0]             ptw_resolve_vtag;
// PTW result signals
wire                    ptw_resolve_done;
wire                    ptw_pagefault;
wire                    ptw_accessfault;

wire [7:0]              ptw_resolve_access_bits;
wire [PHYS_W-1:0]       ptw_resolve_phystag;

// PTW m_* signals
wire                    ptw_m_transaction;
wire [2:0]              ptw_m_cmd;
wire [33:0]             ptw_m_address;


// Store gen signals
wire [31:0]             storegen_dataout;
wire [3:0]              storegen_mask;
wire                    storegen_missaligned;
wire                    storegen_unknowntype;
// Load gen signals
reg [31:0]              loadgen_datain;
wire                    loadgen_missaligned;
wire                    loadgen_unknowntype;

reg  [1:0]              tlb_command;

// read port
reg  [19:0]             tlb_resolve_virtual_address;
wire                    tlb_hit;
wire [7:0]              tlb_read_accesstag;
wire [PHYS_W-1:0]       tlb_read_ptag;

// write port
reg  [19:0]             tlb_write_vtag;
reg  [7:0]              tlb_write_accesstag;
reg  [PHYS_W-1:0]       tlb_write_ptag;


genvar way_num;
genvar byte_offset;
generate
for(way_num = 0; way_num < WAYS; way_num = way_num + 1) begin : mem_generate_for
    mem_1w1r #(
        .ELEMENTS_W(LANES_W),
        .WIDTH(PHYS_W)
    ) ptag_storage (
        .clk(clk),
        
        .read(ptag_read[way_num]),
        .readaddress(ptag_readlane[way_num]),
        .readdata(ptag_readdata[way_num]),
        
        .write(ptag_write[way_num]),
        .writeaddress(ptag_writelane),
        .writedata(ptag_writedata)
    );
    
    mem_1w1r #(
        .ELEMENTS_W(LANES_W),
        .WIDTH(2)
    ) lanestatestorage (
        .clk(clk),
        
        .read(lanestate_read[way_num]),
        .readaddress(lanestate_readlane[way_num]),
        .readdata({lanestate_readdata[1][way_num], lanestate_readdata[0][way_num]}),

        .write(lanestate_write[way_num]),
        .writeaddress(lanestate_writelane),
        .writedata(lanestate_writedata)
    );

    for(byte_offset = 0; byte_offset < 32; byte_offset = byte_offset + 8) begin : storage_generate_for
        mem_1w1r #(
            .ELEMENTS_W(LANES_W+OFFSET_W),
            .WIDTH(8)
        ) datastorage (
            .clk(clk),

            .read(storage_read[way_num]),
            .readaddress({storage_readlane[way_num], storage_readoffset[way_num]}),
            .readdata(storage_readdata[way_num][byte_offset+7:byte_offset]),

            .write(storage_write[way_num] && storage_byteenable[byte_offset/8]),
            .writeaddress({storage_writelane, storage_writeoffset}),
            .writedata(storage_writedata[byte_offset+7:byte_offset])
        );
    end
end
endgenerate


// |------------------------------------------------|
// |                   LoadGen                      |
// |------------------------------------------------|

corevx_loadgen loadgen(
    .inwordOffset       (os_address_inword_offset),
    .loadType           (os_load_type),

    .LoadGenDataIn      (loadgen_datain),

    .LoadGenDataOut     (c_load_data),
    .LoadMissaligned    (loadgen_missaligned),
    .LoadUnknownType    (loadgen_unknowntype)
);

// |------------------------------------------------|
// |                 StoreGen                       |
// |------------------------------------------------|


corevx_storegen storegen(
    .inwordOffset           (os_address_inword_offset),
    .storegenType           (os_store_type),

    .storegenDataIn         (os_store_data),

    .storegenDataOut        (storegen_dataout),
    .storegenDataMask       (storegen_mask),
    .storegenMissAligned    (storegen_missaligned),
    .storegenUnknownType    (storegen_unknowntype)
);


// Page table walker instance
corevx_ptw ptw(
    .clk                    (clk),
    .rst_n                  (rst_n),

    .m_transaction          (ptw_m_transaction),
    .m_cmd                  (ptw_m_cmd),
    .m_address              (ptw_m_address),
    .m_transaction_done     (m_transaction_done),
    .m_transaction_response (m_transaction_response),
    .m_rdata                (m_rdata),
    
    .resolve_request        (ptw_resolve_request),
    /*verilator lint_off PINCONNECTEMPTY*/
    .resolve_ack            (),
    /*verilator lint_on PINCONNECTEMPTY*/
    .virtual_address        (ptw_resolve_vtag/*os_address_vtag*/),

    .resolve_done           (ptw_resolve_done),
    .resolve_pagefault      (ptw_pagefault),
    .resolve_accessfault    (ptw_accessfault),

    .resolve_access_bits    (ptw_resolve_access_bits),
    .resolve_physical_address(ptw_resolve_phystag),

    .satp_mode              (csr_satp_mode_r),
    .satp_ppn               (csr_satp_ppn_r)
);

corevx_tlb #(TLB_ENTRIES_W, TLB_WAYS_W) tlb(
    .rst_n                  (rst_n),
    .clk                    (clk),
    
    .command                (tlb_command),

    // read port
    .virtual_address        (tlb_resolve_virtual_address),
    .hit                    (tlb_hit),
    .accesstag_r            (tlb_read_accesstag),
    .phys_r                 (tlb_read_ptag),
    
    // write for for entry virt
    .virtual_address_w      (tlb_write_vtag),
    .accesstag_w            (tlb_write_accesstag),
    .phys_w                 (tlb_write_ptag),

    .invalidate_set_index   (tlb_invalidate_set_index)
);

corevx_cache_pagefault pagefault_generator(
    .csr_satp_mode_r            (csr_satp_mode_r),

    .os_csr_mcurrent_privilege  (os_csr_mcurrent_privilege),
    .os_csr_mstatus_mprv        (os_csr_mstatus_mprv),
    .os_csr_mstatus_mxr         (os_csr_mstatus_mxr),
    .os_csr_mstatus_sum         (os_csr_mstatus_sum),
    .os_csr_mstatus_mpp         (os_csr_mstatus_mpp),

    .os_cmd                     (os_cmd),
    .tlb_read_accesstag         (tlb_read_accesstag),

    .pagefault                  (pagefault)
);



// |------------------------------------------------|
// |         Output stage data multiplexer          |
// |------------------------------------------------|
always @* begin
    integer way_idx;
    os_cache_hit = 1'b0;
    os_readdata = 32'h0;
    os_cache_hit_way = {WAYS_W{1'b0}};
    for(way_idx = WAYS-1; way_idx >= 0; way_idx = way_idx - 1) begin
        way_hit[way_idx] = os_valid_per_way[way_idx] && ptag_readdata[way_idx] == tlb_read_ptag;
        if(way_hit[way_idx]) begin
            /*verilator lint_off WIDTH*/
            os_cache_hit_way = way_idx;
            /*verilator lint_on WIDTH*/
            os_readdata = storage_readdata[way_idx];
            os_cache_hit = 1'b1;
        end
    end
end

always @* begin
    if(os_cmd == `CACHE_CMD_LOAD) begin
        unknowntype = loadgen_unknowntype;
        missaligned = loadgen_missaligned;
    end else begin
        unknowntype = storegen_unknowntype;
        missaligned = storegen_missaligned;
    end
end

assign ptag = vm_enabled ? tlb_read_ptag : {2'b00, os_address_vtag};

integer i;

always @* begin
    tlb_command = `TLB_CMD_NONE;
    stall = 1;
    c_response = `CACHE_RESPONSE_IDLE;

    m_transaction = 0;
    m_cmd = `ARMLEOBUS_CMD_NONE;
    m_address = {ptag, os_address_lane, os_address_offset, 2'b00};
    m_burstcount = 1;
    m_wdata = storegen_dataout;
    m_wbyte_enable = storegen_mask;

    for(i = 0; i < WAYS; i = i + 1) begin
        ptag_read[i] = 1'b0;
        ptag_readlane[i] = c_address_lane;
        ptag_write[i] = 1'b0;

        lanestate_read[i] = 1'b0;
        lanestate_readlane[i] = c_address_lane;
        lanestate_write[i] = 1'b0;

        storage_read[i] = 1'b0;
        storage_readlane[i] = {LANES_W{1'b0}};
        storage_readoffset[i] = {OFFSET_W{1'b0}};
        storage_write[i] = 1'b0;
    end
    storage_writedata = storegen_dataout;
    storage_writelane = os_address_lane;
    storage_writeoffset = os_address_offset;
    storage_byteenable = storegen_mask;

    lanestate_writelane = {LANES_W{1'b0}};
    lanestate_writedata = 2'b11; // valid and dirty

    ptag_writedata = ptag;
    ptag_writelane = os_address_lane;
    ptw_resolve_request = 1'b0;
    ptw_resolve_vtag = os_address_vtag;
    loadgen_datain = os_readdata;
    tlb_resolve_virtual_address = c_address_vtag;
    tlb_write_vtag = os_address_vtag;
    tlb_write_accesstag = ptw_resolve_access_bits;
    tlb_write_ptag = ptw_resolve_phystag;
    c_reset_done = 1'b1;
    if(tlb_invalidate_set_index == TLB_ENTRIES-1) begin
        tlb_invalidate_done = 1'b1;
    end else begin
        tlb_invalidate_done = 1'b0;
    end
    // used by state reset
    if(reset_lane_counter == LANES-1) begin
        reset_valid_reset_done = 1'b1;
    end else begin
        reset_valid_reset_done = 1'b0;
    end
    case(state)
        STATE_RESET: begin
            c_reset_done = 1'b0;
            
            for(i = 0; i < WAYS; i = i + 1)
                lanestate_write[i] = 1'b1;
            lanestate_writedata = 2'b00;
            lanestate_writelane = reset_lane_counter;

            tlb_command = `TLB_CMD_INVALIDATE;
            
            c_response = `CACHE_RESPONSE_WAIT;
            stall = 1;
        end
        STATE_ACTIVE: begin
            
            stall = 0;
            if(os_active) begin
                if(os_error) begin
                    // Returned from refill or flush and error happened
                    stall = 0;
                    if(os_error_type == `CACHE_ERROR_ACCESSFAULT)
                        c_response = `CACHE_RESPONSE_ACCESSFAULT;
                    else if(os_error_type == `CACHE_ERROR_PAGEFAULT)
                        c_response = `CACHE_RESPONSE_PAGEFAULT;
                end else if(unknowntype) begin
                    c_response = `CACHE_RESPONSE_UNKNOWNTYPE;
                end else if(missaligned) begin
                    c_response = `CACHE_RESPONSE_MISSALIGNED;
                end else if(vm_enabled && !tlb_hit) begin
                    // TLB Miss
                    stall = 1;
                    c_response = `CACHE_RESPONSE_WAIT;
                end else if(vm_enabled && pagefault) begin
                    // pagefault
                    c_response = `CACHE_RESPONSE_PAGEFAULT;
                end else begin
                    
                    // TLB Hit
                    if(ptag[19]) begin
                        // bypass
                        loadgen_datain = m_rdata;
                        //m_wdata = storegen_dataout;
                        //m_wbyte_enable = storegen_mask;
                        if((os_cmd == `CACHE_CMD_LOAD) || (os_cmd == `CACHE_CMD_EXECUTE)) begin
                            m_cmd = `ARMLEOBUS_CMD_READ;
                        end else if(os_cmd == `CACHE_CMD_STORE) begin
                            m_cmd = `ARMLEOBUS_CMD_WRITE;
                        end
                        m_transaction = 1'b1;
                        c_response = `CACHE_RESPONSE_WAIT;
                        stall = 1'b1;
                        if(m_transaction_done) begin
                            stall = 1'b0;
                            if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS)
                                c_response = `CACHE_RESPONSE_DONE;
                            else
                                c_response = `CACHE_RESPONSE_ACCESSFAULT;
                        end
                    end else begin
                        // cache access (no bypass)
                        loadgen_datain = os_readdata;
                        storage_byteenable = storegen_mask;
                        storage_writedata = storegen_dataout;
                        lanestate_writedata = 2'b11;
                        if(os_cache_hit) begin
                            // Cache hit
                            c_response = `CACHE_RESPONSE_DONE;
                            if(os_cmd == `CACHE_CMD_STORE) begin
                                lanestate_writelane = os_address_lane;
                                storage_write[os_cache_hit_way] = 1'b1;
                                lanestate_write[os_cache_hit_way] = 1'b1;
                                c_response = `CACHE_RESPONSE_DONE;
                            end
                        end else begin
                            // Cache miss
                            stall = 1;
                            c_response = `CACHE_RESPONSE_WAIT;
                        end // cache miss end
                    end // bypass/cache end
                end // no error end
            end // os active end
        end
        STATE_REFILL: begin
            m_cmd = `ARMLEOBUS_CMD_READ;
            m_transaction = 1'b1;
            storage_writelane = os_address_lane;
            storage_writeoffset = os_word_counter;
            storage_writedata = m_rdata;
            storage_byteenable = 4'hF;
            lanestate_writelane = os_address_lane;
            lanestate_writedata = 2'b01;
            
            ptag_writelane = os_address_lane;
            ptag_writedata = ptag;

            if(m_transaction_done) begin
                if(m_transaction_response != `ARMLEOBUS_RESPONSE_SUCCESS) begin
                    
                end else begin
                    storage_write[victim_way] = 1'b1;
                    
                    if(os_word_counter == WORDS_IN_LANE - 1) begin
                        lanestate_write[victim_way] = 1'b1;
                        lanestate_read[victim_way] = 1'b1;
                        storage_read[victim_way] = 1'b1;
                        storage_readlane[victim_way] = os_address_lane;
                        storage_readoffset[victim_way] = os_address_offset;
                        ptag_write[victim_way] = 1'b1;
                        ptag_read[victim_way] = 1'b1;
                    end
                end
            end
            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;
        end
        STATE_FLUSH: begin
            // TODO: Read first word
            // For each word complete read next word
            // For each word read write it to backmemory
            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;
        end
        STATE_PTW: begin
            m_transaction = ptw_m_transaction;
            m_cmd = ptw_m_cmd;
            m_address = ptw_m_address;
            m_burstcount = 1;
            // TODO: check for pagefault/accessfault
            // TODO: tlb_command = `TLB_CMD_WRITE;
            stall = 1;
            c_response = `CACHE_RESPONSE_WAIT;
        end
        STATE_FLUSH_ALL: begin
            tlb_command = `TLB_CMD_INVALIDATE;
        end
        default: begin
            c_response = `CACHE_RESPONSE_WAIT;
            stall = 1;
        end
    endcase
    if(!stall) begin
        if(access_request) begin
            for(i = 0; i < WAYS; i = i + 1) begin
                storage_read[i]         = 1'b1;
                storage_readlane[i]     = c_address_lane;
                storage_readoffset[i]   = c_address_offset;
                storage_byteenable      = storegen_mask;
                lanestate_read[i]       = 1'b1;
                lanestate_readlane [i]  = c_address_lane;

                ptag_read[i]            = 1'b1;
                ptag_readlane[i]        = c_address_lane;
            end
            tlb_command = `TLB_CMD_RESOLVE;
        end
    end
end

always @(posedge clk) begin
    if(!rst_n) begin
        state <= STATE_RESET;
        reset_lane_counter <= {LANES_W{1'b0}};
        tlb_invalidate_set_index <= {TLB_ENTRIES_W{1'b0}};
    end else begin
        case(state)
            STATE_RESET: begin
                os_active <= 1'b0;
                os_address_lane <= {LANES_W{1'b0}};
                os_word_counter <= {OFFSET_W{1'b0}};
                
                victim_way <= {WAYS_W{1'b0}};
                os_error <= 1'b0;
                if(!reset_valid_reset_done)
                    reset_lane_counter <= reset_lane_counter + 1;
                if(!tlb_invalidate_done)
                    tlb_invalidate_set_index <= tlb_invalidate_set_index + 1;

                if(tlb_invalidate_done && reset_valid_reset_done) begin
                    state <= STATE_ACTIVE;
                    reset_lane_counter <= 0;
                    tlb_invalidate_set_index <= 0;
                    `ifdef DEBUG
                        $display("[%d] [Cacbe] Reset done", $time);
                    `endif
                    csr_satp_mode_r <= csr_satp_mode;
                    csr_satp_ppn_r <= csr_satp_ppn;
                end
            end
            STATE_ACTIVE: begin
                if(os_active) begin
                    if(os_error) begin
                        // Returned from refill/flush with error
                        // Empty because no need to do anything
                        os_active <= 0;
                        os_error <= 0;
                        `ifdef DEBUG
                        $display("[%d][Cache:Output Stage] Error from prev cycle", $time);
                        `endif
                    end else if(unknowntype) begin
                        `ifdef DEBUG
                        $display("[%d][Cache:Output Stage] %s, unknowntype", $time, os_cmd_ascii);
                        `endif
                        os_active <= 0;
                    end else if(missaligned) begin
                        `ifdef DEBUG
                        $display("[%d][Cache:Output Stage] %s, unknowntype", $time, os_cmd_ascii);
                        `endif
                        os_active <= 0;
                    end else if(vm_enabled && !tlb_hit) begin
                        // TLB Miss
                        `ifdef DEBUG
                        $display("[%d][Cache:Output Stage] TLB Miss", $time);
                        `endif
                        state <= STATE_PTW;
                    end else if(vm_enabled && pagefault) begin
                        // pagefault
                        `ifdef DEBUG
                        $display("[%d][Cache:Output Stage] %s, tlb hit, pagefault", $time, os_cmd_ascii);
                        `endif
                        os_active <= 0;
                    end else begin
                        // tlb hit
                        if(ptag[19]) begin
                            // bypass
                            if(m_transaction_done) begin
                                if(m_transaction_response == `ARMLEOBUS_RESPONSE_SUCCESS) begin
                                    `ifdef DEBUG
                                        if(m_cmd == `ARMLEOBUS_CMD_READ) begin
                                            $display("[%d][Cache:Output Stage] %s, bypass done m_address = 0x%X, m_rdata = 0x%X, load_type = %s",
                                                    $time, os_cmd_ascii, m_address, m_rdata, os_load_type_ascii);
                                        end else begin
                                            $display("[%d][Cache:Output Stage] %s, bypass done m_address = 0x%X, m_wdata = 0x%X, os_store_data=0x%X, store_type = %s",
                                                    $time, os_cmd_ascii, m_address, m_wdata, os_store_data, os_store_type_ascii);
                                        end
                                    `endif
                                end
                                os_active <= 1'b0;
                            end
                        end else begin
                            // Cached access
                            if(os_cache_hit) begin
                                // Cache hit
                                os_active <= 1'b0;
                                // TODO: log
                                `ifdef DEBUG
                                    $display("[%d][Cache:Output Stage] %s, Cache hit", $time, os_cmd_ascii);
                                `endif
                            end else begin // no cache hit
                                // Cache miss
                                if(os_victim_valid && os_victim_dirty) begin
                                    `ifdef DEBUG
                                        $display("[%d][Cache:Output Stage] Cache miss, victim dirty", $time);
                                    `endif
                                    state <= STATE_FLUSH;
                                    return_state <= STATE_REFILL;
                                end else begin
                                    `ifdef DEBUG
                                        $display("[%d][Cache:Output Stage] Cache miss, victim clean", $time);
                                    `endif
                                    state <= STATE_REFILL;
                                end
                            end // cache hit/miss
                        end // tlb_ptag_read[19]
                    end
                end // os_active
            end // CASE
            STATE_REFILL: begin
                //TODO: Handle PMA Errors by returning to idle with error
                if(m_transaction_done) begin
                    if(m_transaction_response != `ARMLEOBUS_RESPONSE_SUCCESS) begin
                        state <= STATE_ACTIVE;
                        os_error <= 1;
                        os_error_type <= `CACHE_ERROR_ACCESSFAULT;
                        os_word_counter <= 0;
                    end else begin
                        os_word_counter <= os_word_counter + 1;
                        if(os_word_counter == WORDS_IN_LANE - 1) begin
                            os_word_counter <= 0;
                            state <= STATE_ACTIVE;
                            victim_way <= victim_way + 1'b1;
                        end
                    end
                end
            end
            STATE_FLUSH: begin
                //
            end
            STATE_FLUSH_ALL: begin
                // os_active <= 1'b1;
                // os_error <= 1'b1;
                csr_satp_mode_r <= csr_satp_mode;
                csr_satp_ppn_r  <= csr_satp_ppn;
            end
            default: begin
                `ifdef DEBUG
                    $display("[%d][Cache] Unknown state", $time);
                `endif
            end
        endcase
        if(!stall) begin
            if(access_request) begin
                `ifdef DEBUG
                    $display("[%d][Cache] Access request", $time);
                `endif
                os_active                   <= 1'b1;

                os_address_vtag             <= c_address_vtag;
                os_address_lane             <= c_address_lane;
                os_address_offset           <= c_address_offset;
                os_address_inword_offset    <= c_address_inword_offset;

                os_cmd                      <= c_cmd;
                os_load_type                <= c_load_type;
                os_store_type               <= c_store_type;
                os_store_data               <= c_store_data;

                os_csr_mcurrent_privilege   <= csr_mcurrent_privilege;
                os_csr_mstatus_mprv         <= csr_mstatus_mprv;
                os_csr_mstatus_mxr          <= csr_mstatus_mxr;
                os_csr_mstatus_sum          <= csr_mstatus_sum;
                os_csr_mstatus_mpp          <= csr_mstatus_mpp;
            end
            if(c_cmd == `CACHE_CMD_FLUSH_ALL) begin
                `ifdef DEBUG
                $display("[%d][Cache] IDLE -> FLUSH_ALL", $time);
                `endif
                state <= STATE_FLUSH_ALL;
            end
        end
    end
end


// Debug outputs
`ifdef DEBUG
reg [(9*8)-1:0] state_ascii;
always @* begin case(state)
    STATE_ACTIVE:         state_ascii = "IDLE";
    STATE_FLUSH:        state_ascii = "FLUSH";
    STATE_REFILL:       state_ascii = "REFILL";
    STATE_FLUSH_ALL:    state_ascii = "FLUSH_ALL";
    STATE_PTW:          state_ascii = "PTW";
    STATE_RESET:        state_ascii = "RESET";
    endcase
end

reg [(9*8)-1:0] return_state_ascii;
always @* begin case(return_state)
    STATE_ACTIVE:         return_state_ascii = "IDLE";
    STATE_FLUSH:        return_state_ascii = "FLUSH";
    STATE_REFILL:       return_state_ascii = "REFILL";
    STATE_FLUSH_ALL:    return_state_ascii = "FLUSH_ALL";
    STATE_PTW:          return_state_ascii = "PTW";
    endcase
end
`endif


/*
// Used by flush to wait for storage to read first word before writing it to memory;
reg flush_initial_done;
// Used by flush_all
reg flush_all_initial_done;


    if(state == STATE_FLUSH) begin
        storage_read[current_way] = flush_storage_read;
        storage_readlane[current_way] = os_address_lane;
        storage_readoffset[current_way] = os_word_counter_next;
    end
end
always @* begin
    ptag_read[way_num] = 
        ((state == STATE_ACTIVE) && !stall && access_request) ||
        ((state == STATE_FLUSH_ALL));// TODO: Fix
    ptag_readlane[way_num] = (state == STATE_ACTIVE) ? c_address_lane : os_address_lane;
end


always @* begin
    ptag_write[way_num] = 0;
    if(way_num == victim_way) begin
        ptag_write[way_num] = ptw_complete || (state == STATE_REFILL && !refill_initial_done);
    end
end

`ifdef DEBUG
integer p;
always @(posedge clk) begin
    for(p = 0; p < WAYS; p = p + 1) begin
        if(storage_write[p])
            $display("[t=%d][Cache] storage_write = 1, storage_writedata[p = 0x%X, lane = 0x%X, offset = 0x%X] = 0x%X",
            $time,                                    p[WAYS_W-1:0], os_address_lane, state == STATE_REFILL ? os_word_counter : os_address_offset, storage_writedata[p]);
    end
end
`endif
always @* begin
    for(o = 0; o < WAYS; o = o + 1) begin
        ptag_readlane[o]                = c_address_lane;
        ptag_read[o]                    = access;
    end
    if(state == STATE_FLUSH) begin
        ptag_readlane[current_way]  = os_address_lane;
        ptag_read[current_way]      = !flush_initial_done;
    end
end



// Memory mux
// Flush (write port)
// Refill (read port)
// PTW (read port)
// Bypass (read and write port)

always @* begin
    // TODO:
    m_address = {ptag_readdata[current_way], os_address_lane, os_word_counter, 2'b00}; // default: flush write address
    m_burstcount = 16;
    m_read = 0;

    m_write = 0;
    m_writedata = storage_readdata[current_way];// flush write data
    m_byteenable = 4'b1111;

    case(state)
        STATE_ACTIVE: begin
            m_address = {tlb_read_ptag, os_address_lane, os_address_offset, 2'b00};
            m_burstcount = 1;

            m_read = s_bypass && os_load && !bypass_load_handshaked;
            
            m_write = s_bypass && os_store;
            m_writedata = storegen_dataout;
            m_byteenable = storegen_mask;
        end

        STATE_FLUSH: begin
            m_write = flush_initial_done;
            m_writedata = storage_readdata[current_way];
        end
        STATE_REFILL: begin
            m_address = {tlb_read_ptag, os_address_lane, os_word_counter, 2'b00};// TODO: Same as flush write address

            m_read = refill_initial_done && !refill_waitrequest_handshaked; // TODO

            m_write = 0;
        end
        STATE_PTW: begin
            m_address = ptw_avl_address;
            m_burstcount = 1;

            m_read = ptw_avl_read;
        end
    endcase
end


// |------------------------------------------------|
// |                                                |
// |             always_comb                        |
// |                                                |
// |------------------------------------------------|



always @* begin
    // Core
    c_wait = 0;
    c_done = 0;
    c_pagefault = 0;
    c_accessfault = 0;
    //c_flushing = 0;
    c_flush_done = 0;
    

    `ifdef DEBUG
    c_miss = 0;
    `endif

    s_bypass = 0;
    current_way_next = current_way;
    os_address_lane_next = os_address_lane + 1;

    case(state)
        STATE_ACTIVE: begin
            if(os_active) begin
                if(!tlb_miss) begin
                    if(tlb_read_ptag[19]) begin
                        s_bypass = 1;
                        c_wait = 1;
                        
                        if(os_store) begin
                            if(!m_waitrequest) begin
                                c_wait = 0;
                                c_done = 1;
                            end
                        end else if(os_load) begin
                            if(!m_waitrequest) begin

                            end
                            if(!m_waitrequest && m_readdatavalid) begin
                                c_wait = 0;
                                c_done = 1;
                            end
                        end
                        c_accessfault = c_done && m_response != 2'b00;
                    end else begin
                        if(os_cache_hit_any) begin
                            if(os_load) begin

                            end else if(os_store) begin

                            end
                            c_done = 1;
                            // Cache hit
                        end else begin
                            // Cache miss
                            c_wait = 1;
                            if(os_current_way_valid && os_current_way_dirty) begin
                                
                            end else begin
                                
                            end
                        end
                    end
                end else if(tlb_miss) begin
                    c_wait = 1;
                end
                if(c_flush && !c_wait) begin

                end else if(access) begin
                    
                end
            end
        end
        
        STATE_FLUSH_ALL: begin
            
            c_wait = 1;
            {current_way_next, os_address_lane_next} = {current_way, os_address_lane} + 1;
            if(os_address_lane == 2**LANES_W-1) begin
                if(current_way == WAYS-1) begin
                    c_flush_done = flush_all_initial_done;
                end
            end
            if(valid[os_address_lane_next][current_way_next] && dirty[os_address_lane_next][current_way_next]) begin
                // Goto state_flush
                
            end else if(valid[os_address_lane_next][current_way_next]) begin
                // invalidate
                if(current_way_next == WAYS-1 && os_address_lane_next == LANES-1) begin
                    c_flush_done = flush_all_initial_done;
                end
            end else begin
                // Nothing to do
                if(current_way_next == WAYS-1 && os_address_lane_next == LANES-1) begin
                    c_flush_done = flush_all_initial_done;
                end
            end
            // Go to state flush for each way and lane that is dirty, then return to state idle after all ways and sets are flushed
        end
        STATE_FLUSH: begin
            c_wait = 1;
        end
        STATE_PTW: begin
            c_wait = 1;
            ptw_resolve_request = 1;
        end
        STATE_REFILL: begin
            c_wait = 1;
        end
        default: begin
            c_wait = 1;
        end
    endcase
    
end

// |------------------------------------------------|
// |                                                |
// |             always_ff                          |
// |                                                |
// |------------------------------------------------|
`ifdef DEBUG
task debug_print_request;
begin
    $display("[t=%d][Cache] %s request", $time, c_load ? "load" : "store");
    $display("[t=%d][Cache] c_address_vtag = 0x%X, c_address_lane = 0x%X, c_address_offset = 0x%X", $time, c_address_vtag, c_address_lane, c_address_offset);
    $display("[t=%d][Cache] c_address_inword_offset = 0x%X, type = %s", $time, c_address_inword_offset, 
        c_load && c_load_type == LOAD_BYTE          ? "LOAD_BYTE" : (
        c_load && c_load_type == LOAD_BYTE_UNSIGNED ? "LOAD_BYTE_UNSIGNED" : (
        c_load && c_load_type == LOAD_HALF          ? "LOAD_HALF" : (
        c_load && c_load_type == LOAD_HALF_UNSIGNED ? "LOAD_HALF_UNSIGNED" : (
        c_load && c_load_type == LOAD_WORD          ? "LOAD_WORD" : (
        c_load                                      ? "unknown load" : (
        c_store && c_store_type == STORE_BYTE ? "STORE_BYTE": (
        c_store && c_store_type == STORE_HALF ? "STORE_HALF": (
        c_store && c_store_type == STORE_WORD ? "STORE_WORD": (
        c_store ? "unknown store": (
            "unknown"
        )))))))))));
    //$display("[t=%d][Cache] TLB Request", $time);// TODO:
    //$display("[t=%d][Cache] access read request", $time);// TODO:
    
end
endtask


task debug_print_way_selector;
begin
    integer way_idx;
    $display("[t=%d][Cache/OS] way_selector_debug: os_cache_hit_any = 0x%X, os_cache_hit_way = 0x%X, os_readdata = 0x%X, tlb_read_ptag = 0x%X",
               $time,          os_cache_hit_any,        os_cache_hit_way,        os_readdata,        tlb_read_ptag);
    for(way_idx = WAYS-1; way_idx >= 0; way_idx = way_idx - 1) begin
        $display("[t=%d][Cache/OS] way_idx = 0x%X, os_valid[way_idx] = 0x%X, ptag_readdata[way_idx] = 0x%X, os_cache_hit[way_idx] = 0x%X",
                   $time,          way_idx,        os_valid[way_idx],        ptag_readdata[way_idx],        os_cache_hit[way_idx]);
    end
end
endtask
`endif

*/
endmodule
