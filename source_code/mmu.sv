`ifndef __MMU__
`define __MMU__

module mmu (
    input clk,
    input rst,
    input imem_rst,

    input logic [`XLEN-1:0] cpu2imem_addr,
    output logic [`DATA_LENGTH-1:0] imem2cpu_data,

    input logic [`XLEN-1:0] cpu2cache_addr,
    input logic [`XLEN-1:0] cpu2cache_data,
    input  MEM_SIZE cpu2cache_size,
    input logic [1:0]  cpu2cache_command,
    output logic  [`XLEN-1:0] cache2cpu_data,
    output logic cpu_req_ready,
    
    output integer hit_counter,
    output integer miss_counter

    // ,output logic hit_test
    // ,output logic [2:0] state_test
    // ,output logic [`XLEN-1:0] address_test
);

imem Imem (
    .clk(clk),
    .rst(imem_rst),
    .proc2mem_data({(64){1'b0}}),
    .proc2mem_size(DOUBLE),
    .proc2mem_command(BUS_LOAD),
    .proc2mem_addr(cpu2imem_addr),
    .mem2proc_data(imem2cpu_data)
);

logic [3:0]              mem2cache_response;      // which bank handle the                                                   // 0 means mem not ready
logic [3:0]              mem2cache_tag;           // which bank has finished req
logic [`DATA_LENGTH-1:0] mem2cache_data;          // data from mem
logic [`XLEN-1:0]        cache2mem_address;       // request address
logic [`DATA_LENGTH-1:0] cache2mem_data;          // request data
logic [1:0]             cache2mem_command;

d_cache data_cache(
    .clk(clk),
    .reset(rst),
    .cpu2cache_addr(cpu2cache_addr),
    .cpu2cache_data(cpu2cache_data),
    .cpu2cache_size(cpu2cache_size),
    .cpu2cache_command(cpu2cache_command),
    .cache2cpu_data(cache2cpu_data),
    .cpu_req_ready(cpu_req_ready),
    .mem2cache_response(mem2cache_response),
    .mem2cache_tag(mem2cache_tag),
    .mem2cache_data(mem2cache_data),
    .cache2mem_address(cache2mem_address),
    .cache2mem_data(cache2mem_data),
    .cache2mem_command(cache2mem_command),
    .hit_counter(hit_counter),
    .miss_counter(miss_counter)
    // ,.allocate_stage_test(state_test)
    // ,.hit_test(hit_test)
    // ,.state_test(state_test)
    // ,.address_test(address_test)
);

dmem Dmem (
    .clk(clk),
    .rst(rst),
    .proc2mem_data(cache2mem_data),
    .proc2mem_addr(cache2mem_address),
    .proc2mem_command(cache2mem_command),
    .mem2proc_response(mem2cache_response),
    .mem2proc_data(mem2cache_data),
    .mem2proc_tag(mem2cache_tag)
);
    
endmodule

`endif