module Queue #(entry_size, queue_size) (
    input clk,
    input reset,
    // input and controls
    // if push is high on posedge, data_in is added to queue
    input [entry_size - 1: 0] data_in,
    input push,
    // output and controls
    // data_out is always the first entry
    output [entry_size - 1: 0] data_out,
    // if pop is high posedge, the first entry is removed from queue
    input pop,
    // query
    output not_empty,
    output full
);
    logic [entry_size - 1: 0] data[queue_size: 0];
    logic data_valid[queue_size: -1];
    logic pop_not_empty;
    
    assign data[queue_size] = {entry_size{1'bX}};
    assign data_valid[-1] = 1'b1;
    assign data_valid[queue_size] = 1'b0;
    assign pop_not_empty = pop && not_empty;
    genvar i;
    generate
        for(i = 0; i < queue_size; i++) begin
            always_ff @(posedge clk) begin
                if(reset) begin
                    data_valid[i] <= 1'b0;
                end
                else if(pop_not_empty) begin
                    if(push && data_valid[i] && !data_valid[i+1]) begin
                        data[i] <= data_in;
                    end
                    else begin
                        data[i] <= data[i+1];
                        data_valid[i] <= data_valid[i+1];
                    end
                end
                else if(push) begin
                    if(!data_valid[i] && data_valid[i-1]) begin
                        data[i] <= data_in;
                        data_valid[i] <= 1'b1;
                    end
                end
            end
        end
    endgenerate
    
    assign data_out = data[0];
    assign not_empty = data_valid[0];
    assign full = data_valid[queue_size - 1];
endmodule

module OneHotMux #(mux_size = 1, data_width = 1) (
    input [data_width - 1:0] data_in[mux_size - 1:0],
    input [mux_size - 1:0] select,
    output [data_width - 1:0] data_out
);
    genvar i;
    generate
        for(i = 0; i < mux_size; i++) begin
            assign data_out = select[i]? data_in[i]: {data_width{1'bZ}};
        end
    endgenerate
endmodule