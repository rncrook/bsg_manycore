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
        , input all_remote_req_sent_i

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
        , input in_data_v_i
        , input [data_width_p-1:0] in_data_i
        , output logic in_data_yumi_o

    );

    enum logic [2:0] {IDLE = '0, BUSY, WAIT, DONE, PULL}  state, state_n;

    logic                          out_data_v_r,    out_data_v_n;
    logic                          out_data_w_r,    out_data_w_n;
    logic [dmem_addr_width_lp-1:0] out_data_addr_r, out_data_addr_n;
    logic [data_mask_width_lp-1:0] out_data_mask_r, out_data_mask_n;
    logic [data_width_p-1:0]       out_data_r,      out_data_n;

    logic all_local_req_sent_r;
    logic all_local_req_sent_d;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state <= IDLE;

            out_data_v_r    <= '0;
            out_data_w_r    <= '0;
            out_data_addr_r <= '0;
            out_data_mask_r <= '0;
            out_data_r      <= '0;

            all_local_req_sent_r <= '0;
        end else begin
            state <= state_n;

            out_data_v_r    <= out_data_v_n;
            out_data_w_r    <= out_data_w_n;
            out_data_addr_r <= out_data_addr_n;
            out_data_mask_r <= out_data_mask_n;
            out_data_r      <= out_data_n;

            all_local_req_sent_r <= all_local_req_sent_d;
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
        all_local_req_sent_d = all_local_req_sent_r;

        in_data_yumi_o = '0;


        case(state)
            IDLE: begin
                out_data_v_n     = '0;
                out_data_w_n     = '0;

                if (start_local_req_i) begin
                    if(push_not_pull_i) begin
                        state_n = BUSY;
                        incr_local_ptr_o = '1;
                        out_data_v_n     = '1;
                        out_data_w_n     = '0; //~push_not_pull_i;
                        out_data_addr_n  = (local_ptr_i >> 2);
                        out_data_mask_n  = '1; // for now, entire word is transferred. TODO: implement masking
                    end else begin
                        state_n = PULL;
                    end
                end
            end

            BUSY: begin
                if (out_data_yumi_i) begin
                    // if current request is yumi'd, update to next memory location
                    // otherwise, current request is held onto until a yumi
                    incr_local_ptr_o = '1; /// when yumi'd, get next pointer
                    out_data_v_n     = '1;
                    out_data_w_n     = '0; //~push_not_pull_i;
                    out_data_addr_n  = (local_ptr_i >> 2); // when yumi'd, load next address (current pointer) in
                    out_data_mask_n  = '1;
                end

                if (local_ptr_i - local_dmem_base_i >= num_bytes_i) begin
                    state_n              = WAIT;
                    out_data_w_n         = '0;
                    out_data_v_n         = '0;
                    all_local_req_sent_d = '1;
                end
            end

            PULL: begin
                if (out_data_yumi_i) begin
                    out_data_v_n = '0; // if current flop yumi'd, immediate invalidate next data on flops
                end

                // unless... if there is new data, write it to registers and validate it
                if (in_data_v_i) begin
                    incr_local_ptr_o = '1;
                    out_data_addr_n = (local_ptr_i >> 2);
                    out_data_w_n = '1;
                    out_data_v_n = '1;
                    out_data_n   = in_data_i;
                    out_data_mask_n = '1;
                    in_data_yumi_o = '1;
                end

                if (local_ptr_i - local_dmem_base_i >= num_bytes_i) begin
                    state_n              = DONE;
                    all_local_req_sent_d = '1;
                    out_data_v_n     = '1;
                    out_data_w_n     = '1;
                    out_data_addr_n  = wb_address_i >> 2;
                    out_data_n       = 32'h1;
                    out_data_mask_n  = '1;
                end
            end

            WAIT: begin
                // for a DMA push, this FSM should be placed into a wait-state
                // until the remote req fsm has issued all remote reqs. this is comm'd through
                // the dma_remote_req_gen_fsm's "all_remote_req_sent_o" signal, which should be an input
                // to this module
                if (all_remote_req_sent_i) begin
                    state_n = DONE;
                    out_data_v_n     = '1;
                    out_data_w_n     = '1;
                    out_data_addr_n  = wb_address_i >> 2;
                    out_data_n       = 32'h1;
                    out_data_mask_n  = '1;
                    all_local_req_sent_d = '0;
                end
            end

            DONE: begin
                if (out_data_yumi_i) begin
                    // after writeback gets consumed, clear state, and IDLE
                    state_n = IDLE;
                    out_data_v_n = '0;
                    out_data_w_n = '0;
                    all_local_req_sent_d = '0;
                end
            end
        endcase

    end



    assign out_data_v_o    = out_data_v_r;
    assign out_data_w_o    = out_data_w_r;
    assign out_data_addr_o = out_data_addr_r;
    assign out_data_mask_o = out_data_mask_r;
    assign out_data_o      = out_data_r;

    assign all_local_req_sent_o = all_local_req_sent_r;

    // synopsys translate_off
    always_ff @(negedge clk_i) begin
        if (out_data_yumi_i) begin
            $display("[DMA LOCAL REQUEST GENERATOR]: dma engine initiating %s request into local data memory: addr: %h, data: %h. time = %0t",
                     out_data_w_o ? "store" : "load", out_data_addr_o, out_data_o, $time);
        end
    end
    // synopsys translate_on



endmodule