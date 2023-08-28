/* reference:
 * page 20,
 * Introduction to Operating Systems
 * 6. Memory management
 * Manuel - Fall 2022
*/

`ifndef __LRU__
`define __LRU__

module LRU #(size = 1) (
    input clk,
    input reset,
    input [size - 1:0] usage, // each bit corresponds to an slot. 1 indicates being used.
    input update_usage, // input usage takes effect at rising edge of clk when update_usage is 1
    output [size - 1:0] lru // one-hot output: only the bit corresponding to the least recently used slot is 1
);
    logic [size - 1:0] matrix[size - 1:0];
    logic update_usage_valid;
    
    assign update_usage_valid = update_usage && usage != {size{1'b1}};
    genvar i;
    generate
        for(i = 0; i < size; i++) begin
            always_ff @(posedge clk) begin
                if(reset) begin
                    matrix[i] <= (i != 0)? {{(size - i){1'b0}}, {(i){1'b1}}}: {size{1'b0}};
                end
                else if(update_usage_valid) begin
                    matrix[i] <= (matrix[i] | {size{usage[i]}}) & ~usage;
                end
            end
            assign lru[i] = matrix[i] == {size{1'b0}};
        end
    endgenerate
endmodule

`endif