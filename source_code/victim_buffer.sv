`ifndef __VICTIM_BUFFER__
`define __VICTIM_BUFFER__

module victim_buffer #(VICTIM_SIZE = 4, VICTIM_LEN = 2) (
    input logic clk,     // buffer clock, update output at negedge
    input logic rst,     // buffer reset, effectively set valid to 0
    input logic request, // request from L1 cache

    /* BEGIN: effective when request */
    // the following is what the cache evicted
    input logic                    cache2victim_dirty,
    input logic [`DATA_LENGTH-1:0] cache2victim_data,
    input logic [`XLEN-1:0]        cache2victim_evict_addr,
    // the following is what the cache request
    input logic [`XLEN-1:0]        cache2victim_req_addr,
    // NOTICE: the two addressed should have the same index
    // ASSUME: we don't request victim buffer if the corresponding
    // index in the cache is invalid
    /* END:   effective when request */

    /* BEGIN: data to cache */
    // the following is effective when response && hit
    output logic                    victim2cache_dirty,
    output logic [`DATA_LENGTH-1:0] victim2cache_data,
    /* END:   data to cache */

    /* BEGIN: data to memory unit */
    // the following is effective when response && !hit && wb_req
    output logic [`DATA_LENGTH-1:0] victim2mem_data,
    output logic [`XLEN-1:0]        victim2mem_addr,
    /* END:   data to memory unit*/

    output logic response, // when buffer is ready
    output logic hit,      // when buffer hit
    output logic wb_req    // when the evicted block from buffer
                           // need to be write back
    ,output logic [1:0] chosen_line_test
    ,output logic is_full_test
    ,output logic [2:0] three_bit_test
    ,output logic [`TAG_LENGTH-1:0] tag_length_bit
    ,output logic [2:0] another_three_bit_test
    ,output logic [1:0] two_bit_test
    ,output logic [3:0] four_bit_test
    ,output logic [3:0] another_four_bit_test
);

    // break input into useful parts
    // ensure that all the input signals are valid during one clock cycle
    logic [`TAG_LENGTH-1:0] req_tag;
    logic [`TAG_LENGTH-1:0] evict_tag;
    logic [`CACHE_LENTH-1:0] req_index;
    logic [`CACHE_LENTH-1:0] evict_index;
    logic evict_dirty;
    logic [`DATA_LENGTH-1:0] evict_data;
    always_ff @( posedge clk ) begin
        if (request) begin
            req_tag <= cache2victim_req_addr[`XLEN-1:`BLOCK_LENGTH+`CACHE_LENTH];
            evict_tag <= cache2victim_evict_addr[`XLEN-1:`BLOCK_LENGTH+`CACHE_LENTH];
            req_index <= cache2victim_req_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH];
            evict_index <= cache2victim_evict_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH];
            evict_dirty <= cache2victim_dirty;
            evict_data <= cache2victim_data;
        end else begin
            req_tag <= 0;
            evict_tag <= 0;
            req_index <= 0;
            evict_index <= 0;
            evict_dirty <= 0;
            evict_data <= 0;  
        end
    end

    // iteration index
    integer i,j;

    // victim data, I assume it is updated only at posedge clk
    CACHE_LINE victim_lines [0:VICTIM_SIZE-1];
    logic [`CACHE_LENTH-1:0] index_lines [0:VICTIM_SIZE-1];

    // pseudo random number signal
    // logic [VICTIM_LEN-1:0] random_num;
    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         random_num <= 0;
    //     end
    //     else begin
    //         random_num <= random_num + 1;
    //     end
    // end

    // lru_bit update
    logic [VICTIM_SIZE-1:0] usage;
    logic update_usage;
    logic [VICTIM_SIZE-1:0] lru_bit;
    LRU #(.size(VICTIM_SIZE)) lru_calculation (
        .clk(clk),
        .reset(rst),
        .usage(usage),
        .update_usage(update_usage),
        .lru(lru_bit)
    );
    always_ff @( negedge clk ) begin
        if (request) begin
            update_usage<=1'b1;
        end
        else begin
            update_usage<=1'b0;
        end
    end
    logic [VICTIM_LEN-1:0] least_recent_used_num;
    logic [VICTIM_LEN-1:0] replace_line_num;
    // my_encoder lru_encoder (
    //     .input_signal(lru_bit),
    //     .output_signal(least_recent_used_num)
    // );
    assign least_recent_used_num = $clog2(lru_bit);
    my_power #(.length(VICTIM_SIZE)) usage_decoder(
        .input_signal(replace_line_num),
        .output_signal(usage)
    );

    // update chosen number line
    // if hit, choose the hit one
    // if not, choose a random one
    // this calculation should take some time
    logic hit_in; // updated at posedge after some calculation
    logic [VICTIM_LEN-1:0] chosen_line_num;
    always_ff @ (posedge clk) begin
        if (rst) begin
            for (i = 0; i < VICTIM_SIZE; i = i+1 ) begin
                victim_lines[i].valid <= 1'b0;
                index_lines[i] <= 0;
                hit_in  <= 1'b0;
            end
        end
        else begin
            if (request) begin
                hit_in = 1'b0;
                for (i = 0; i < VICTIM_SIZE ; i = i+1) begin
                    if (
                        victim_lines[i].valid
                     && victim_lines[i].tag == cache2victim_req_addr[`XLEN-1:`BLOCK_LENGTH+`CACHE_LENTH]
                     && index_lines[i] == cache2victim_req_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH]
                    ) begin
                        chosen_line_num = i;
                        hit_in = 1'b1;
                        break;
                    end
                    else begin
                        // hit_in = 1'b0;
                    end
                end
            end
            else begin
                // hit_in = 1'b0;
            end
        end
    end

    // empty line logic
    // calculate is_full | empty line
    // this calculation should take some time
    logic is_full;
    logic [VICTIM_LEN-1:0] first_empty_line;
    always_ff @( posedge clk ) begin
        if (rst) begin
            is_full <= 1'b0;
            first_empty_line <= 0;
        end
        else begin
            is_full = 1'b1;
            for (j = 0; j<VICTIM_SIZE ; j = j+1) begin
                if (!victim_lines[j].valid) begin
                    is_full = 1'b0;
                    first_empty_line = j;
                    // $display("empty_line: %d", j);
                    break;
                end
                else begin
                    // $display("empty_line: %d", victim_lines[j].valid);
                end
            end
        end
    end

    logic need_to_wb;
    // only need to write back if the victim block is dirty
    assign need_to_wb = (is_full&&victim_lines[replace_line_num].dirty) ? 1'b1 : 1'b0;

    // update output signal
    // assume there is a delay of request at negedge
    always_ff @( negedge clk ) begin
        if (request) begin
            response <= 1'b1;
            if (hit_in) begin
                hit <= 1'b1;
                victim2cache_data <= victim_lines[chosen_line_num].data;
                victim2cache_dirty <= victim_lines[chosen_line_num].dirty;
            end else begin
                hit <= 1'b0;
                if (is_full) begin // only evict when the buffer is full when not hit
                    wb_req <= need_to_wb;
                    victim2mem_data <= victim_lines[least_recent_used_num].data;
                    victim2mem_addr <= {victim_lines[least_recent_used_num].tag,index_lines[least_recent_used_num],{(`BLOCK_LENGTH){1'b0}}};
                end
                else begin
                    wb_req <= 1'b0;
                end
            end
        end
        else begin
            // do nothing, since there is no request
            response <= 1'b0;
        end
    end

    // update buffer
    // logic [VICTIM_LEN-1:0] replace_line_num;
    assign replace_line_num = hit_in ? chosen_line_num :
     is_full ? least_recent_used_num : first_empty_line;
    always_ff @( posedge clk ) begin
        if (response) begin
            victim_lines[replace_line_num].valid <= 1'b1;
            victim_lines[replace_line_num].dirty <= evict_dirty;
            victim_lines[replace_line_num].tag <= evict_tag;
            victim_lines[replace_line_num].data <= evict_data;
            index_lines[replace_line_num] <= evict_index;
        end
        else begin
            
        end
    end


    assign chosen_line_test = replace_line_num;
    assign is_full_test = request;
    assign three_bit_test = index_lines[1];
    assign another_three_bit_test = cache2victim_req_addr[`CACHE_LENTH+`BLOCK_LENGTH-1:`BLOCK_LENGTH];
    assign tag_length_bit = victim_lines[0].tag;
    assign two_bit_test = least_recent_used_num;
    assign four_bit_test = lru_bit;
    assign another_four_bit_test = usage;
endmodule

`endif