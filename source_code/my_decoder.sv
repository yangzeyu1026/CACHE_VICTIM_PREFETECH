`ifndef __MY_DECODER__
`define __MY_DECODER__

module my_power #(length=4) (
    input logic [$clog2(length)-1:0] input_signal,
    output logic [length-1:0] output_signal
);
    genvar i;
    generate
        for (i = length-1; i>=0 ; i=i-1) begin
            assign output_signal[i] = (i==input_signal) ? 1'b1 : 1'b0;
        end
    endgenerate
endmodule
`endif