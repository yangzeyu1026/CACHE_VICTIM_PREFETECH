`ifndef __D_CACHE__
`define __D_CACHE__

`include "sys_defs.svh"

module d_cache (
    input         reset,            // cache reset
	input         clk,              // cache clock

    // CPU I/O
	input  logic [`XLEN-1:0] cpu2cache_addr,                 // address for current command
	input  logic [`XLEN-1:0] cpu2cache_data,                 // STORE data
	input  MEM_SIZE          cpu2cache_size,                 // BYTE, HALF, WORD or DOUBLE
	input  logic [1:0]       cpu2cache_command,              // `BUS_NONE `BUS_LOAD or `BUS_STORE
	output logic [`XLEN-1:0] cache2cpu_data,                 // LOAD data
    output logic             cpu_req_ready,

    // memory I/O
    input  [3:0]                    mem2cache_response,      // which bank handle the req 
                                                             // 0 means mem not ready
    input  [3:0]                    mem2cache_tag,           // which bank has finished req
    input  logic [`DATA_LENGTH-1:0] mem2cache_data,          // data from mem
    output logic [`XLEN-1:0]        cache2mem_address,       // request address
    output logic [`DATA_LENGTH-1:0] cache2mem_data,          // request data
    output logic [1:0]             cache2mem_command,        // `BUS_NONE `BUS_LOAD or `BUS_STORE
    output integer hit_counter,
    output integer miss_counter

    ,output logic [2:0] state_test
    ,output  logic [3:0] mem_bank_test
    ,output logic [1:0] allocate_stage_test
    // ,output logic hit_test
    ,output logic [2:0] cpu_req_index_test
    ,output logic [63:0] cache_data_test
    ,output logic [1:0] chosen_line_test
    ,output logic request_test
    ,output logic victim_hit_test
    ,output logic hit_test
    ,output logic [`XLEN-1:0] address_test
  );
  

  typedef enum logic [2:0] { IDLE, COMPARE_TAG, VICTIM, WRITE_BACK, PREFETCH, ALLOCATE } STATE;

  STATE currentState, nextState;

  CACHE_LINE cache_lines [0:`CACHE_LINE_NUM-1];

  logic [`CACHE_LENTH-1:0] cpu_req_index;
  logic [`BLOCK_LENGTH-1:0] cpu_req_offset;
  logic [`TAG_LENGTH-1:0] cpu_req_tag; 
  logic hit;
  logic cache_dirty;
  logic allocate_mem_ready;
  logic [1:0] allocate_stage;
  logic [3:0] mem_bank; // which bank handles the req

  logic victim_request;
  logic victim_response;
  logic victim_hit;
  logic victim_wb_req;
  logic cache2victim_dirty;
  logic [`DATA_LENGTH-1:0] cache2victim_data;
  logic [`XLEN-1:0] cache2victim_evict_addr;
  logic [`XLEN-1:0] cache2victim_req_addr;
  logic victim2cache_dirty;
  logic [`DATA_LENGTH-1:0] victim2cache_data;
  logic [`DATA_LENGTH-1:0] victim2mem_data;
  logic [`XLEN-1:0] victim2mem_addr;

  assign cpu_req_index = cpu2cache_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH];
  assign cpu_req_offset = cpu2cache_addr[`BLOCK_LENGTH-1:0];
  assign cpu_req_tag = cpu2cache_addr[`XLEN-1:`BLOCK_LENGTH+`CACHE_LENTH];
  assign hit = cache_lines[cpu_req_index].valid && (cache_lines[cpu_req_index].tag == cpu_req_tag);
  assign cache_dirty = cache_lines[cpu_req_index].dirty;

  // assign hit_test = stream_l1_miss;
  assign state_test = currentState;
  assign mem_bank_test = mem_bank;
  assign allocate_stage_test = allocate_stage;
  assign cpu_req_index_test = {cpu_req_offset[`BLOCK_LENGTH-1:2],2'b0};
  assign cache_data_test = cache_lines[2].data;
  // assign addresss_test = stream2mem_addr;

  always_ff @( posedge clk ) begin // STATE CHANGE
    if (reset) begin
        currentState <= IDLE;
        allocate_stage <= 2'b00;
        mem_bank <= 4'b0000;
        for (int i = 0; i < `CACHE_LINE_NUM; i = i+1) begin
            cache_lines[i].valid <= 1'b0;
        end
    end
    else begin
        currentState <= nextState;
    end
  end // STATE CHANGE

  always_ff @( negedge clk ) begin
    if (currentState == COMPARE_TAG && !hit && cache_lines[cpu_req_index].valid) begin
        victim_request <= #1 1'b1;
        cache2victim_dirty <= #1 cache_lines[cpu_req_index].dirty;
        cache2victim_data <= #1 cache_lines[cpu_req_index].data;
        cache2victim_evict_addr <= #1 {cache_lines[cpu_req_index].tag,cpu_req_index,3'b000};
        cache2victim_req_addr <= #1 cpu2cache_addr;
    end
    else begin
        victim_request <= #1 1'b0;
        cache2victim_dirty <= #1 1'b0;
        cache2victim_data <= #1 0;
        cache2victim_evict_addr <= #1 0;
        cache2victim_req_addr <= #1 0;
    end
  end

  victim_buffer #(.VICTIM_SIZE(4),.VICTIM_LEN(2)) vb (
    .clk(clk),
    .rst(reset),
    .request(victim_request),
    .cache2victim_dirty(cache2victim_dirty),
    .cache2victim_data(cache2victim_data),
    .cache2victim_evict_addr(cache2victim_evict_addr),
    .cache2victim_req_addr(cache2victim_req_addr),
    .victim2cache_dirty(victim2cache_dirty),
    .victim2cache_data(victim2cache_data),
    .victim2mem_addr(victim2mem_addr),
    .victim2mem_data(victim2mem_data),
    .response(victim_response),
    .hit(victim_hit),
    .wb_req(victim_wb_req)
    ,.chosen_line_test(chosen_line_test)
    ,.is_full_test(request_test)
  );

  assign victim_hit_test = allocate_mem_ready;

 always_comb begin // STATE TRANSACTION LOGIC
    case (currentState)
        IDLE: begin
            nextState = (cpu2cache_command==BUS_LOAD||cpu2cache_command==BUS_STORE) ? COMPARE_TAG : IDLE;
        end
        COMPARE_TAG: begin
            if (hit) begin
                nextState = IDLE;
            end
            else if (!hit && !cache_lines[cpu_req_index].valid) begin
                nextState = ALLOCATE;
            end
            else if (!hit && cache_lines[cpu_req_index].valid) begin
                nextState = VICTIM;
            end
            else begin
                nextState = COMPARE_TAG;
            end
        end
        VICTIM: begin
            if (victim_response && victim_hit) begin
                nextState = COMPARE_TAG;
            end
            else if (victim_response && !victim_hit && victim_wb_req) begin
                nextState = WRITE_BACK;
            end
            else if (victim_response && !victim_hit /*victim_wb_req=x|0*/) begin
                nextState = ALLOCATE;
            end
            else begin
                nextState = VICTIM;
            end
        end
        WRITE_BACK: begin
            nextState = ALLOCATE;
        end
        ALLOCATE: begin
            if (allocate_mem_ready) begin
                nextState = COMPARE_TAG;
            end
            else begin
                nextState = ALLOCATE;
            end
        end
        default: begin
            nextState = IDLE;
        end
    endcase
 end // STATE TRANSACTIOIN LOGIC

// cpu_req_ready_signal
 always_ff @( negedge clk ) begin
    if (currentState==COMPARE_TAG && hit) begin
        cpu_req_ready <= 1'b1;
    end
    else begin
        cpu_req_ready <= 1'b0;
    end
 end

 always_ff @(negedge clk) begin // THINGS @ COMPARE TAG
    if (currentState==COMPARE_TAG && hit) begin
        if (cpu2cache_command==BUS_LOAD) begin
            if (cpu2cache_size==BYTE) begin
                cache2cpu_data <= {24'b0, cache_lines[cpu_req_index].data[cpu_req_offset*8+7-:8]};
                // cpu_req_ready <= 1'b1;
            end else if (cpu2cache_size==HALF) begin
                cache2cpu_data <= {16'b0, cache_lines[cpu_req_index].data[cpu_req_offset[`BLOCK_LENGTH-1:1]*16+15-:16]};
                // cpu_req_ready <= 1'b1;
            end else if (cpu2cache_size==WORD) begin
                cache2cpu_data <= cache_lines[cpu_req_index].data[cpu_req_offset[`BLOCK_LENGTH-1:2]*32+31-:32];
                // cpu_req_ready <= 1'b1;
            end else begin // DOUBLE, which is never required from riscv32
                // cache2cpu_data <= cache_lines[cpu_req_index].data[cpu_req_offset];
                // cpu_req_ready <= 1'b0;
            end
        end
        else if (cpu2cache_command==BUS_STORE) begin
            cache_lines[cpu_req_index].dirty <= 1'b1;
            if (cpu2cache_size==BYTE) begin
                cache_lines[cpu_req_index].data[cpu_req_offset*8+7-:8] <= cpu2cache_data[7:0];
                // cpu_req_ready <= 1'b1;
            end else if (cpu2cache_size==HALF) begin
                cache_lines[cpu_req_index].data[cpu_req_offset[`BLOCK_LENGTH-1:1]*16+15-:16] <= cpu2cache_data[15:0];
                // cpu_req_ready <= 1'b1;
            end else if (cpu2cache_size==WORD) begin
                cache_lines[cpu_req_index].data[cpu_req_offset[`BLOCK_LENGTH-1:2]*32+31-:32] <= cpu2cache_data[31:0];
                // cpu_req_ready <= 1'b1;
            end else begin // DOUBLE, which is never required from riscv32
                // cache_lines[cpu_req_index].data[cpu_req_offset] <= cpu2cache_data;
                // cpu_req_ready <= 0;
            end
        end
        else begin
            // cpu_req_ready <= 1'b0;
        end
    end else begin
        // cpu_req_ready <= 1'b0;
    end
 end // THINGS @ COMPARE TAG

 always_ff @( posedge clk ) begin
    if (currentState==VICTIM&&victim_hit) begin
        cache_lines[cpu_req_index].tag <= cpu_req_tag;
        cache_lines[cpu_req_index].data <= victim2cache_data;
        cache_lines[cpu_req_index].dirty <= victim2cache_dirty;
        cache_lines[cpu_req_index].valid <= 1'b1;
    end
    else begin
        
    end
 end

 logic stream_invalidate;
 logic [`XLEN-1:0] stream_invalidate_addr;
 always_ff @( posedge clk ) begin
    if (currentState==WRITE_BACK) begin
        stream_invalidate <= 1'b1;
        stream_invalidate_addr <= victim2mem_addr; // ?
    end
    else begin
        stream_invalidate <=1'b0;
    end
 end
 logic stream_l1_miss;
 logic [`XLEN-1:0] stream_address_in;
 always_ff @( posedge clk ) begin
    if ((currentState==ALLOCATE) && !allocate_mem_ready) begin
        stream_l1_miss <= 1'b1;
        stream_address_in <= cpu2cache_addr;
    end
    else begin
        stream_l1_miss <= 1'b0;
    end
 end
 logic [`XLEN-1:0] stream2mem_addr;
 logic [1:0] stream2mem_command;
 logic [`DATA_LENGTH-1:0] stream2cache_data;
 StreamBuffer #(.way(2),.queue_size(3),.block_size(64),.addr_size(32),.mem_tag_size(8),.mem_data_size(64)) sb (
    .clk(clk),                                 // input
    .reset(reset),                             // input
    .addr_in(stream_address_in),               // input
    .l1_miss(stream_l1_miss),                  // input
    .block_out(stream2cache_data),             // output
    .prefetch_hit(allocate_mem_ready),         // output
    .addr_out(stream2mem_addr),                // output
    .mem_command(stream2mem_command),          // output
    .mem_response(mem2cache_response),         // input
    .mem_data_in(mem2cache_data),              // input
    .mem_tag(mem2cache_tag),                   // input
    .addr_invalidate(stream_invalidate_addr),  // input
    .invalidate(stream_invalidate)                // input
 );

 assign cache2mem_address = (currentState==WRITE_BACK) ? victim2mem_addr :
 // (currentState==ALLOCATE) ? stream2mem_addr : {(`XLEN){1'b0}};
 stream2mem_addr;
 assign cache2mem_command = (currentState==WRITE_BACK) ? BUS_STORE :
 // (currentState==ALLOCATE) ? stream2mem_command : BUS_NONE;
 stream2mem_command;
 assign cache2mem_data = (currentState==WRITE_BACK) ? victim2mem_data : {(`XLEN){1'b0}};

 always_ff @( posedge clk ) begin
    if (currentState==ALLOCATE&&allocate_mem_ready) begin
        cache_lines[cpu_req_index].data <= stream2cache_data;
        cache_lines[cpu_req_index].dirty<= 1'b0;
        cache_lines[cpu_req_index].valid<= 1'b1;
        cache_lines[cpu_req_index].tag  <= cpu_req_tag;
    end
    else begin /*keep the cache lines as it was*/ end
 end

 logic [10:0] allocate_stage_counter;
 always_ff @( negedge clk ) begin
    if (reset) begin
        allocate_stage_counter <= 0;
    end
    else if (currentState!=ALLOCATE) begin
        allocate_stage_counter <= 0;
    end
    else begin
        allocate_stage_counter <= allocate_stage_counter + 1;
    end
 end

 integer cache_hit_counter;
 integer victim_hit_counter;
 integer stream_hit_counter;
 assign hit_counter = cache_hit_counter + victim_hit_counter + stream_hit_counter;
 always_ff @( posedge clk ) begin
    if (reset) begin
        cache_hit_counter<=0;
        victim_hit_counter<=0;
        stream_hit_counter<=0;
        miss_counter<=0;
    end
    else begin
        if (currentState==COMPARE_TAG&&hit) begin
            cache_hit_counter <= cache_hit_counter+1;
        end
        else if (currentState==VICTIM&&victim_hit) begin
            victim_hit_counter <= victim_hit_counter + 1;
            cache_hit_counter <= cache_hit_counter - 1;
        end
        else if (currentState==ALLOCATE&&(allocate_stage_counter<`DMEM_LATENCY_IN_CYCLES)&&allocate_mem_ready) begin
            stream_hit_counter <= stream_hit_counter+1;
            cache_hit_counter <= cache_hit_counter-1;
        end
        else if (currentState==ALLOCATE&&(allocate_stage_counter>`DMEM_LATENCY_IN_CYCLES)&&allocate_mem_ready) begin
            miss_counter<=miss_counter+1;
            cache_hit_counter<=cache_hit_counter-1;
        end
    end
 end
 assign hit_test = stream_l1_miss;
 assign address_test = stream_address_in;

endmodule
`endif