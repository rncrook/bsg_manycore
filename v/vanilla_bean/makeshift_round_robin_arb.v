
`include "bsg_manycore_defines.vh"

module makeshift_round_robin_arb
(
    input clk_i,
    input reset_i,

    input [1:0] reqs_i,
    input yumi_i,

    output logic [1:0] grants_o,
    output valid_o
);


    logic prev_sel, prev_sel_d;
    always_ff @(posedge clk_i) begin
        if (reset_i) prev_sel <= '0;
        else         prev_sel <= prev_sel_d;
    end

    always_comb begin
        prev_sel_d = prev_sel;
        grants_o = 2'b00;

        if (yumi_i) begin
            case (prev_sel)
                '0:
                    casez (reqs_i)
                        2'b1?: begin
                            grants_o  = 2'b10;
                            prev_sel_d = '1;
                        end
                        2'b01: begin
                            grants_o = 2'b01;
                            prev_sel_d = '0;
                        end
                    endcase
                '1:
                    casez (reqs_i)
                        2'b?1: begin
                            grants_o = 2'b01;
                            prev_sel_d = '0;
                        end
                        2'b10: begin
                            grants_o = 2'b10;
                            prev_sel_d = '1;
                        end
                    endcase
            endcase
        end

    end

    assign valid_o = | reqs_i;

endmodule