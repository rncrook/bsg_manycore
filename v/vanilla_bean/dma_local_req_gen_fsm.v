`include "bsg_manycore_defines.vh"

module dma_local_req_gen_fsm
    import bsg_manycore_pkg::*;
    import bsg_vanilla_pkg::*;
    #(

          `BSG_INV_PARAM(data_width_p)
        , `BSG_INV_PARAM(dmem_size_p)

        , localparam dmem_addr_width_lp = `BSG_SAFE_CLOG2(dmem_size_p)
        , data_mask_width_lp=(data_width_p>>3)
    ) (
          input reset_i
        , input clk_i


        // fsm control/status signals
        , input start_local_req_i
        , input push_not_pull_i
        , output logic all_local_req_sent_o
        , output logic incr_local_ptr_o

        , input [11:0] local_ptr_i
        , input [11:0] local_dmem_base_i
        , input [11:0] wb_address_i
        , input [11:0] num_bytes_i


        // data interfaces
        // ----------------

        // output data (yumi)
        , output out_data_v_o
        , output out_data_w_o
        , output logic [dmem_addr_width_lp-1:0] out_data_addr_o
        , output logic [data_mask_width_lp-1:0] out_data_mask_o
        , output logic [data_width_p-1:0] out_data_o
        , input out_data_yumi_i

        // input data - from tx response

    );


        assign all_local_req_sent = '0;
        //assign incr_local_ptr = '0;



        enum logic [1:0] {IDLE = '0, BUSY, DONE}  state, state_n;

        logic                          out_data_v_r,    out_data_v_n;
        logic                          out_data_w_r,    out_data_w_n;
        logic [dmem_addr_width_lp-1:0] out_data_addr_r, out_data_addr_n;
        logic [data_mask_width_lp-1:0] out_data_mask_r, out_data_mask_n;
        logic [data_width_p-1:0]       out_data_r,      out_data_n;

        always_ff @(posedge clk_i) begin
            if (reset_i) begin
                state <= IDLE;

                out_data_v_r    <= '0;
                out_data_w_r    <= '0;
                out_data_addr_r <= '0;
                out_data_mask_r <= '0;
                out_data_r      <= '0;
            end else begin
                state <= state_n;

                out_data_v_r    <= out_data_v_n;
                out_data_w_r    <= out_data_w_n;
                out_data_addr_r <= out_data_addr_n;
                out_data_mask_r <= out_data_mask_n;
                out_data_r      <= out_data_n;
            end
        end


        always_comb begin
            state_n         = state;

            out_data_v_n    = out_data_v_r;
            out_data_w_n    = out_data_w_r;
            out_data_addr_n = out_data_addr_r;
            out_data_mask_n = out_data_mask_r;
            out_data_n      = out_data_r;

            incr_local_ptr_o = '0;


            case(state)
                IDLE: begin
                    if (start_local_req_i) begin
                        state_n = BUSY;
                        incr_local_ptr_o = '1;
                        out_data_v_n     = '1;
                        out_data_w_n     = '0; //~push_not_pull_i;
                        out_data_addr_n  = (local_ptr_i >> 2);
                        out_data_mask_n  = '1; // for now, entire word is transferred. TODO: implement masking
                        //out_data_n = ~push_not_pull_i ? /* write into local */ /* use tx response data */
                        //                : /*otherwise, dont care ('0) */;
                    end
                end

                BUSY: begin
                    if (out_data_yumi_i) begin
                        incr_local_ptr_o = '1; /// when yumi'd, get next pointer
                        out_data_v_n     = '1;
                        out_data_w_n     = '0; //~push_not_pull_i;
                        out_data_addr_n  = (local_ptr_i >> 2); // when yumi'd, load next address (current pointer) in
                        out_data_mask_n  = '1;
                    end

                    if (local_ptr_i - local_dmem_base_i >= num_bytes_i) begin
                        state_n              = DONE;
                        out_data_w_n         = '0;
                        out_data_v_n         = '0;
                        all_local_req_sent_o = '1;
                    end
                end

                DONE: begin
                    state_n = DONE;
                end
            endcase

        end



        assign out_data_v_o    = out_data_v_r;
        assign out_data_w_o    = out_data_w_r;
        assign out_data_addr_o = out_data_addr_r;
        assign out_data_mask_o = out_data_mask_r;
        assign out_data_o      = out_data_r;



endmodule