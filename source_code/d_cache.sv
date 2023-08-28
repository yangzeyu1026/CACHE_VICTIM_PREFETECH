`ifndef __D_CACHE__
`define __D_CACHE__

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
    output logic [1:0]              cache2mem_command,       // `BUS_NONE `BUS_LOAD or `BUS_STORE

    output int hit_counter,
    output int miss_counter

    ,output logic [2:0] state_test
    ,output  logic [3:0] mem_bank_test
    ,output logic [1:0] allocate_stage_test
    ,output logic hit_test
    ,output logic [2:0] cpu_req_index_test
    ,output logic [63:0] cache_data_test
  );
  

  typedef enum logic [2:0] { IDLE, COMPARE_TAG, WRITE_BACK, ALLOCATE, VICTIM } STATE;

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
  assign allocate_mem_ready = (mem_bank==mem2cache_tag) && (mem_bank!=4'b0000);
  assign cpu_req_index = cpu2cache_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH];
  assign cpu_req_offset = cpu2cache_addr[`BLOCK_LENGTH-1:0];
  assign cpu_req_tag = cpu2cache_addr[`XLEN-1:`BLOCK_LENGTH+`CACHE_LENTH];
  assign hit = cache_lines[cpu_req_index].valid && (cache_lines[cpu_req_index].tag == cpu_req_tag);
  assign cache_dirty = cache_lines[cpu_req_index].dirty;

  assign hit_test = (mem_bank==mem2cache_tag) && (mem_bank!=4'b0000);
  assign state_test = currentState;
  assign mem_bank_test = mem_bank;
  assign allocate_stage_test = allocate_stage;
  assign cpu_req_index_test = {cpu_req_offset[`BLOCK_LENGTH-1:2],2'b0};
  assign cache_data_test = cache_lines[2].data;

  always_ff @( posedge clk ) begin // STATE CHANGE
    if (reset) begin
        currentState <= IDLE;
        allocate_stage <= 2'b00;
        mem_bank <= 4'b0000;
        for (int i = 0; i < `CACHE_LINE_NUM; i = i+1) begin
            cache_lines[i].valid <= 1'b0;
        end
        hit_counter <= 0;
        miss_counter <= 0;
    end
    else begin
        currentState <= nextState;
    end
  end // STATE CHANGE

always_ff @( posedge clk ) begin
    if (currentState==COMPARE_TAG&&hit) begin
        hit_counter <= hit_counter + 1;
    end
    else if (currentState==ALLOCATE&&allocate_mem_ready) begin
        miss_counter <= miss_counter + 1;
        hit_counter <= hit_counter - 1;
    end
end

 always_comb begin // STATE TRANSACTION LOGIC
    case (currentState)
        IDLE: begin
            nextState = (cpu2cache_command==BUS_LOAD||cpu2cache_command==BUS_STORE) ? COMPARE_TAG : IDLE;
        end
        COMPARE_TAG: begin
            if (hit) begin
                nextState = IDLE;
            end
            else if (cache_lines[cpu_req_index].valid && cache_lines[cpu_req_index].dirty) begin
                // allocated & valid & not hit
                nextState = WRITE_BACK;
            end
            else begin
                // not hit && clean
                nextState = ALLOCATE;
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

 always_ff @(posedge clk) begin // THINGS @ ALLOCATE && WRITE BACK
    if (currentState==WRITE_BACK) begin
        // if (!mem_ready) begin
            cache2mem_address <= {cache_lines[cpu_req_index].tag,cpu_req_index,3'b000};
            cache2mem_command <= BUS_STORE;
            cache2mem_data    <= cache_lines[cpu_req_index].data;
        // end
        // else begin
        //     cache2mem_command <= BUS_NONE;
        // end
    end 
    else if (currentState==ALLOCATE) begin
        if (allocate_stage==2'b00) begin
            cache2mem_address <= {cpu_req_tag,cpu_req_index,3'b000};
            cache2mem_command <= BUS_LOAD;
            // mem_bank          <= 
            allocate_stage    <= allocate_stage+1;
        end
        else if (allocate_stage==2'b01) begin
            cache2mem_address <= 32'b0;
            cache2mem_command <= BUS_NONE;
            mem_bank          <= mem2cache_response;
            allocate_stage    <= allocate_stage+1;
        end else begin
            
        end


        if (allocate_mem_ready) begin
            cache_lines[cpu_req_index].data <= mem2cache_data;
            cache_lines[cpu_req_index].dirty<= 1'b0;
            cache_lines[cpu_req_index].valid<= 1'b1;
            cache_lines[cpu_req_index].tag  <= cpu_req_tag;
            allocate_stage                  <= `SD 2'b00;
            mem_bank                        <= `SD 4'b0000;
        end  
        else begin
        end     
    end
    else begin
        cache2mem_command <= BUS_NONE;
    end
 end // THINGS
endmodule
`endif