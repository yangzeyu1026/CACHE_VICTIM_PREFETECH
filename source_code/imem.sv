`ifndef __IMEM__
`define __IMEM__

module imem (
	input         clk,              // Memory clock
	input         rst,              // Memory reset
	input  [`XLEN-1:0] proc2mem_addr,    // address for current command
	//support for memory model with byte level addressing
	input  [63:0] proc2mem_data,    // address for current command
    input  MEM_SIZE proc2mem_size, //BYTE, HALF, WORD or DOUBLE
	input  logic [1:0]   proc2mem_command, // `BUS_NONE `BUS_LOAD or `BUS_STORE
	
	output logic  [3:0] mem2proc_response,// 0 = can't accept, other=tag of transaction
	output logic [63:0] mem2proc_data,    // data resulting from a load
	output logic  [3:0] mem2proc_tag     // 0 = no value, other=tag of transaction
  );

  	logic [63:0] next_mem2proc_data;
	logic  [3:0] next_mem2proc_response, next_mem2proc_tag;
	
	logic [63:0]                    unified_memory  [`MEM_64BIT_LINES - 1:0];
	logic [63:0]                    loaded_data     [`NUM_MEM_TAGS:1];
	logic [`NUM_MEM_TAGS:1]  [15:0] cycles_left;
	logic [`NUM_MEM_TAGS:1]         waiting_for_bus;
	
	logic acquire_tag;
	logic bus_filled;
	
always @ (negedge clk) begin
	if (rst) begin
		for(int i=0; i<`MEM_64BIT_LINES; i=i+1) begin
			unified_memory[i] <= 64'h0;
		end
		mem2proc_data<=64'bx;
		mem2proc_tag<=4'd0;
		mem2proc_response<=4'd0;
		for(int i=1;i<=`NUM_MEM_TAGS;i=i+1) begin
			loaded_data[i]<=64'bx;
			cycles_left[i]<=16'd0;
			waiting_for_bus[i]<=1'b0;
		end
	end
	else begin
		
	end
end

	    wire valid_address = (proc2mem_addr<`MEM_SIZE_IN_BYTES);
	EXAMPLE_CACHE_BLOCK c;
    // temporary wires for byte level selection because verilog does not support variable range selection
	always @(negedge clk) begin
		next_mem2proc_tag      = 4'b0;
		next_mem2proc_response = 4'b0;
		next_mem2proc_data     = 64'bx;
		bus_filled             = 1'b0;
		acquire_tag            = ((proc2mem_command == BUS_LOAD) ||
		                          (proc2mem_command == BUS_STORE)) && valid_address;
		
		for(int i=1;i<=`NUM_MEM_TAGS;i=i+1) begin
			if(cycles_left[i]>16'd0) begin
				cycles_left[i] = cycles_left[i]-16'd1;
			
			end else if(acquire_tag && !waiting_for_bus[i]) begin
				next_mem2proc_response = i;
				acquire_tag            = 1'b0;
				cycles_left[i]         = `IMEM_LATENCY_IN_CYCLES; 
				                          // must add support for random lantencies
				                          // though this could be done via a non-number
				                          // definition for this macro
				//filling up these temp variables
				c.byte_level = unified_memory[proc2mem_addr[`XLEN-1:3]];
				c.half_level = unified_memory[proc2mem_addr[`XLEN-1:3]];
				c.word_level = unified_memory[proc2mem_addr[`XLEN-1:3]];

				if(proc2mem_command == BUS_LOAD) begin
					waiting_for_bus[i] = 1'b1;
					loaded_data[i]     = unified_memory[proc2mem_addr[`XLEN-1:3]];
                	case (proc2mem_size) 
                        BYTE: begin
							loaded_data[i] = {56'b0, c.byte_level[proc2mem_addr[2:0]]};
                        end
                        HALF: begin
							assert(proc2mem_addr[0] == 0);
							loaded_data[i] = {48'b0, c.half_level[proc2mem_addr[2:1]]};
                        end
                        WORD: begin
							assert(proc2mem_addr[1:0] == 0);
							loaded_data[i] = {32'b0, c.word_level[proc2mem_addr[2]]};
                        end
						DOUBLE:
							loaded_data[i] = unified_memory[proc2mem_addr[`XLEN-1:3]];
					endcase

				end else begin
					case (proc2mem_size) 
                        BYTE: begin
							c.byte_level[proc2mem_addr[2:0]] = proc2mem_data[7:0];
                            unified_memory[proc2mem_addr[`XLEN-1:3]] = c.byte_level;
                        end
                        HALF: begin
							assert(proc2mem_addr[0] == 0);
							c.half_level[proc2mem_addr[2:1]] = proc2mem_data[15:0];
                            unified_memory[proc2mem_addr[`XLEN-1:3]] = c.half_level;
                        end
                        WORD: begin
							assert(proc2mem_addr[1:0] == 0);
							c.word_level[proc2mem_addr[2]] = proc2mem_data[31:0];
                            unified_memory[proc2mem_addr[`XLEN-1:3]] = c.word_level;
                        end
                        default: begin
							assert(proc2mem_addr[1:0] == 0);
							c.byte_level[proc2mem_addr[2]] = proc2mem_data[31:0];
                            unified_memory[proc2mem_addr[`XLEN-1:3]] = c.word_level;
                        end
					endcase
				end
			end
			
			if((cycles_left[i]==16'd0) && waiting_for_bus[i] && !bus_filled) begin
					bus_filled         = 1'b1;
					next_mem2proc_tag  = i;
					next_mem2proc_data = loaded_data[i];
					waiting_for_bus[i] = 1'b0;
			end
		end
		mem2proc_response <= `SD next_mem2proc_response;
		mem2proc_data     <= `SD next_mem2proc_data;
		mem2proc_tag      <= `SD next_mem2proc_tag;
	end
    endmodule
`endif