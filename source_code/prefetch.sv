

// use this module for no prefetch
module FetchUnit #(block_size = 64, addr_size = `XLEN, mem_tag_size = `NUM_MEM_TAGS, mem_data_size = 64)(
    input clk,
    input reset,
    // output
    input [addr_size - 1:0] addr_in,
    input fetch_start,
    output [block_size - 1:0] block_out,
    output logic fetch_completed,
    // input
    output [addr_size - 1:0] addr_out,
    output [1:0] mem_command,
    input [$clog2(mem_tag_size):0] mem_response,
    input [mem_data_size - 1:0] mem_data_in,
    input [$clog2(mem_tag_size):0] mem_tag,
    // invalidate block if write back
    input [addr_size - 1:0] addr_invalidate,
    input invalidate
);
    localparam tag_size = addr_size - $clog2(block_size) + 3; // block_size is in bits while addr is byte addr
    localparam offset_size = $clog2(block_size) - $clog2(mem_data_size);
    localparam align_size = $clog2(mem_data_size) - 3;
    localparam offset_max = (offset_size != 0)? {offset_size{1'b1}}: 0;
    
    logic [tag_size - 1:0] tag_in;
    logic fetching;
    logic fetch_new;
    // request sender
    logic requesting;
    logic [tag_size - 1:0] request_tag;
    logic [offset_size - 1: 0] request_offset;
    // request manager
    logic [mem_tag_size:0] mem_tag_pending;
    logic [mem_tag_size:0] mem_tag_set;
    logic [mem_tag_size:0] mem_tag_clr;
    // data receiver
    logic [offset_size - 1:0] fetch_offset;
    logic [mem_data_size - 1:0] fetch_block[block_size / mem_data_size - 1: 0];
    // invaldation
    logic fetch_invalidate;
    logic [tag_size - 1:0] invalidate_tag;
    
    assign tag_in = addr_in[addr_size - 1:addr_size - tag_size];
    assign fetch_new = fetch_start && (!fetching || tag_in != request_tag);
    always_ff @(posedge clk) begin
        if(reset) begin
            fetching <= 1'b0;
        end
        else if(fetch_start) begin
            fetching <= 1'b1;
        end
    end
    
    // request sender
    if(offset_size != 0) begin
        if(align_size != 0) begin
            assign addr_out = {request_tag, request_offset, {align_size{1'b0}}};
        end
        else begin
            assign addr_out = {request_tag, request_offset};
        end
    end
    else begin
        if(align_size != 0) begin
            assign addr_out = {request_tag, {align_size{1'b0}}};
        end
        else begin
            assign addr_out = request_tag;
        end
    end
    assign mem_command = (requesting && !fetch_invalidate)? BUS_LOAD: BUS_NONE;
    always_ff @(posedge clk) begin
        if(reset) begin
            requesting <= 1'b0;
        end
        else if(fetch_new) begin
            requesting <= 1'b1;
            request_tag <= tag_in;
            request_offset <= {offset_size{1'b0}};
        end
        else if(fetch_invalidate) begin
            requesting <= 1'b1;
            request_offset <= {offset_size{1'b0}};
        end
        else if(requesting && mem_response != 0) begin
            request_offset <= request_offset + 1'b1;
            requesting <= request_offset != offset_max;
        end
    end
    
    // request manager
    assign mem_tag_set = requesting << mem_response;
    assign mem_tag_clr = 1 << mem_tag;
    always_ff @(posedge clk) begin
        if(reset) begin
            mem_tag_pending <= {(mem_tag_size + 1){1'b0}};
        end
        else if(fetch_new || fetch_invalidate) begin
            mem_tag_pending <= {(mem_tag_size + 1){1'b0}};
        end
        else begin
            mem_tag_pending <= mem_tag_pending | mem_tag_set & (~mem_tag_clr);
        end
    end
    
    // data receiver
    // assuming that data come in the order they are requested
    genvar i;
    generate
        for(i = 0; i < block_size / mem_data_size; i++) begin
            assign block_out[(i + 1) * mem_data_size - 1:i * mem_data_size] = fetch_block[i];
        end
    endgenerate
    always_ff @(posedge clk) begin
        if (reset) begin
            fetch_completed <= 1'b0;
        end
        else if(fetch_new || fetch_invalidate) begin
            fetch_completed <= 1'b0;
            fetch_offset <= {offset_size{1'b0}};
        end
        else if(mem_tag != 0 && (mem_tag_pending[mem_tag] || mem_tag == mem_response)) begin
            fetch_block[fetch_offset] <= mem_data_in;
            if(fetch_offset == offset_max) begin
                fetch_completed <= 1'b1; // Could save a cycle by forwarding the last datum but doing so causes a lot of mess
            end;
            fetch_offset <= fetch_offset + 1'b1;
        end
    end
    
    // invaldation
    assign invalidate_tag = addr_invalidate[addr_size - 1: addr_size - tag_size];
    assign fetch_invalidate = invalidate && invalidate_tag == request_tag;
endmodule

// one more than queue_size blocks can be hold by this module
module StreamBuffer #(way = 1, queue_size = 1, block_size = 64, addr_size = `XLEN, mem_tag_size = `NUM_MEM_TAGS, mem_data_size = 64)(
    input clk,
    input reset,
    // processor and L1
    input [addr_size - 1:0] addr_in, 
    input l1_miss, // if l1_miss causes prefetch miss, the same access to this device needs to be performed again after miss is resolved. (Simply just hold these two inputs until prefetch hit)
    output logic [block_size - 1:0] block_out,
    output logic prefetch_hit,
    // lower level memory
    output [addr_size - 1:0] addr_out,
    output [1:0] mem_command,
    input [$clog2(mem_tag_size):0] mem_response,
    input [mem_data_size - 1:0] mem_data_in,
    input [$clog2(mem_tag_size):0] mem_tag,
    // invalidate block if write back
    input [addr_size - 1:0] addr_invalidate,
    input invalidate
);
    localparam tag_size = addr_size - $clog2(block_size) + 3; // block_size is in bits while addr is byte addr
    localparam queue_entry_size = tag_size + block_size;
    
    // processor and L1
    logic [tag_size - 1:0] tag_in;
    // prefetch hit
    logic [tag_size - 1:0] queue_tag[way - 1:0];
    logic [block_size - 1:0] queue_block[way - 1:0];
    logic [block_size - 1:0] selected_block;
    logic [way - 1:0] queue_hit;
    logic any_hit;
    logic [way - 1:0] select_hit;
    logic [tag_size - 1:0] hit_tag;
    logic [way - 1:0] queue_not_empty;
    logic [way - 1:0] queue_pop;
    
    // prefetch miss
    logic [way - 1:0] lru;
    logic miss;
    logic responding_miss;
    logic [tag_size - 1:0] miss_tag;
    logic miss_reset;
    
    // prefetching interface
    logic [way - 1:0] prefetch_running;
    logic [tag_size - 1:0] prefetch_tag[way - 1:0];
    logic [way - 1:0] served_queue;
    logic [tag_size - 1:0] next_serve_tag;
    logic [way - 1:0] next_serve_queue;
    logic [block_size - 1:0] fetch_block;
    // prefetching control
    logic [way - 1:0] miss_queue_reset;
    logic [way - 1:0] queue_full;
    logic [tag_size - 1:0] fetch_tag;
    logic fetch_start;
    logic fetch_completed;
    logic fetch_pushed;
    logic [way - 1:0] queue_can_push;
    logic [way - 1:0] queue_push;
    // invaldation
    logic [tag_size - 1:0] invalidate_tag;
    logic [way - 1:0] invalidate_queue_reset;
    logic [way - 1:0] invalidate_push_reset;
    logic [tag_size - 1:0] resume_tag;
    
    genvar i;
    
    // processor and L1
    assign tag_in = addr_in[addr_size - 1:addr_size - tag_size];

    // prefetch hit
    generate
        for(i = 0; i < way; i++) begin
            assign queue_hit[i] = queue_not_empty[i] && tag_in == queue_tag[i] && !invalidate_queue_reset[i];
            if(i == 0) begin
                assign select_hit[i] = queue_hit[i];
            end
            else begin
                assign select_hit[i] = queue_hit[i] && queue_hit[i-1:0] == {i{1'b0}}; // avoid multiple hit
            end
            assign queue_pop[i] = l1_miss && select_hit[i] && (!prefetch_hit || tag_in != hit_tag);
        end
    endgenerate
    assign any_hit = queue_hit != {way{1'b0}};
    OneHotMux #(.mux_size(way), .data_width(block_size)) hitMux (
        .data_in(queue_block),
        .select(select_hit),
        .data_out(selected_block)
    );
    always_ff @(posedge clk) begin
        if(reset || (invalidate && invalidate_tag == hit_tag)) begin
            prefetch_hit <= 1'b0;
        end
        else if(l1_miss) begin
            prefetch_hit <= any_hit;
            if(any_hit) begin
                hit_tag <= tag_in;
                block_out <= selected_block;
            end
        end
    end
    LRU #(.size(way)) lruModule (
        .clk(clk),
        .reset(reset),
        .usage(queue_pop),
        .update_usage(queue_pop != {way{1'b0}}),
        .lru(lru)
    );
    
    // prefetch miss
    assign miss = l1_miss && (!prefetch_hit || tag_in != hit_tag) && !any_hit;
    assign miss_reset = miss && (!responding_miss || tag_in != miss_tag);
    always_ff @(posedge clk) begin
        responding_miss <= miss;
        miss_tag <= tag_in;
    end
    
    // prefetching interface
    OneHotMux #(.mux_size(way), .data_width(tag_size)) serveTagMux (
        .data_in(prefetch_tag),
        .select(next_serve_queue),
        .data_out(next_serve_tag)
    );
    OneHotMux #(.mux_size(way), .data_width(tag_size)) resumeTagMux (
        .data_in(queue_tag),
        .select(served_queue),
        .data_out(resume_tag)
    );
    always_ff @(posedge clk) begin
        if((invalidate_queue_reset & served_queue) != {way{1'b0}}) begin
            served_queue <= {way{1'b0}};
        end
        else if(miss_reset) begin
            served_queue <= lru;
        end
        else if(fetch_completed) begin
            served_queue <= next_serve_queue;
        end
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            next_serve_queue <= {way{1'b0}};
        end
        else if(miss_reset) begin
            next_serve_queue <= lru;
        end
        else if(any_hit) begin
            next_serve_queue <= select_hit; // MRU scheduling
        end
    end
    
    // prefetching control
    assign fetch_start = miss_reset || fetch_completed || (served_queue & invalidate_queue_reset) != {way{1'b0}};
    assign fetch_tag = miss_reset? tag_in: next_serve_tag;
    generate
        for(i = 0; i < way; i++) begin
            assign queue_can_push[i] = fetch_completed && served_queue[i] && !miss_queue_reset[i] && !queue_full[i] && !invalidate_push_reset[i];
            assign queue_push[i] = queue_can_push[i] && !fetch_pushed;
            assign miss_queue_reset[i] = miss_reset && lru[i];
            always_ff @(posedge clk) begin
                if(reset) begin
                    prefetch_running[i] = 1'b0;
                end
                if(miss_queue_reset[i]) begin
                    prefetch_running[i] = 1'b1;
                    prefetch_tag[i] <= tag_in;
                end
                else if(invalidate_queue_reset[i]) begin
                    prefetch_tag[i] <= queue_tag[i];
                end
                else if(queue_push[i]) begin
                    prefetch_tag[i] <= prefetch_tag[i] + 1'b1;
                end
            end
        end
    endgenerate
    always_ff @(posedge clk) begin
        if(reset || miss_reset || !fetch_completed) begin
            fetch_pushed <= 1'b0;
        end
        else if(queue_can_push != {way{1'b0}}) begin
            fetch_pushed <= 1'b1;
        end
    end
    
    FetchUnit #(
        .block_size(block_size),
        .addr_size(addr_size),
        .mem_tag_size(mem_tag_size),
        .mem_data_size(mem_data_size)
    ) fetchUnit(
        .clk(clk),
        .reset(reset),
        .addr_in({fetch_tag, {(addr_size - tag_size){1'b0}}}),
        .fetch_start(fetch_start),
        .block_out(fetch_block),
        .fetch_completed(fetch_completed),
        .addr_out(addr_out),
        .mem_command(mem_command),
        .mem_response(mem_response),
        .mem_data_in(mem_data_in),
        .mem_tag(mem_tag),
        .addr_invalidate(addr_invalidate),
        .invalidate(invalidate)
    );
    
    generate
        for(i = 0; i < way; i++) begin
            Queue #(.entry_size(queue_entry_size), .queue_size(queue_size))
                streamingBuffer(
                    .clk(clk),
                    .reset(reset || miss_queue_reset[i] || invalidate_queue_reset[i]),
                    .data_in({prefetch_tag[i], fetch_block}),
                    .push(queue_push[i]),
                    .data_out({queue_tag[i], queue_block[i]}),
                    .pop(queue_pop[i]),
                    .not_empty(queue_not_empty[i]),
                    .full(queue_full[i])
                );
        end
    endgenerate
    
    // invaldation
    assign invalidate_tag = addr_invalidate[addr_size - 1: addr_size - tag_size];
    generate
        for(i = 0; i < way; i++) begin
            assign invalidate_queue_reset[i] = invalidate && queue_not_empty[i] && invalidate_tag >= queue_tag[i] && invalidate_tag < prefetch_tag[i];
            assign invalidate_push_reset[i] = invalidate && prefetch_running[i] && invalidate_tag == prefetch_tag[i];
        end
    endgenerate
endmodule