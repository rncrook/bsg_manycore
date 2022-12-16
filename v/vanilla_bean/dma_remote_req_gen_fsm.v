
`include "bsg_manycore_defines.vh"

module dma_remote_req_gen_fsm
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
        , input start_remote_req_i
        , input push_not_pull_i
        , output logic all_remote_req_sent_o // to local_req_gen_fsm

        , input [31:0] remote_ptr_i
        , output logic incr_remote_ptr_o
        , input [11:0] num_bytes_i

        , input local_req_gen_yumi_i



        // // output request interface
        , output logic dma_remote_req_v_o
        , output remote_req_s dma_remote_req_o
        , input dma_remote_req_ready_i

        // vcore dmem data, input data interface
        , input [31:0] dmem_fifo_data_i // take this a cycle after local_req_gen_yumi is asserted
        , input dmem_fifo_v_i
        , output logic dmem_fifo_yumi_o


        , input [4:0] match_rd_id


    );


    enum logic [1:0] {IDLE = '0, PULL, PUSH, DONE}  state_r, state_n;
    logic [31:0] last_remote_addr_r, last_remote_addr_n;


    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_r <= IDLE;
            last_remote_addr_r <= '0;

        end else begin
            state_r <= state_n;
            last_remote_addr_r <= last_remote_addr_n;
        end
    end

    always_comb begin
        state_n = state_r;
        last_remote_addr_n = last_remote_addr_r;
        dmem_fifo_yumi_o = '0;
        incr_remote_ptr_o = '0;
        all_remote_req_sent_o = '0;

        dma_remote_req_v_o = '0;
        dma_remote_req_o = '0;

        case(state_r)
            IDLE: begin
                if (start_remote_req_i) begin
                    last_remote_addr_n = remote_ptr_i + num_bytes_i;

                    case(push_not_pull_i)
                        1'b0: state_n = PULL;
                        1'b1: state_n = PUSH;
                    endcase
                end
            end
            PUSH: begin
                // in a push state, the remote request generator is reading out local dmem data
                // from its input fifo and formatting it into a remote store request at address
                // pointed to by the global remote pointer
                if (last_remote_addr_r == remote_ptr_i) begin
                    all_remote_req_sent_o = '1;
                    state_n = IDLE;
                end else if (dmem_fifo_v_i & dma_remote_req_ready_i) begin
                    // dmem fifo picked up a word

                    dma_remote_req_o = '{ // lots of hardcoded widths here, maybe think about this more
                        write_not_read : 1'b1, // we're PUSHing
                        is_amo_op      : 1'b0, // not amo
                        amo_type       : 2'h0,
                        mask           : 4'hF, // for now, pass all bytes
                        load_info      : 7'h0,
                        reg_id         : match_rd_id, // match id reg.... in PUSH, does this matter?
                        data           : dmem_fifo_data_i,
                        addr           : remote_ptr_i
                    };

                    dmem_fifo_yumi_o = '1;
                    dma_remote_req_v_o = '1;
                    incr_remote_ptr_o = '1;
                end

            end
            PULL: begin
                // in a pull state, the remote request generator issues load requests to
                // the global remote pointer => there is no dependency on local dmem data here

                if (last_remote_addr_r == remote_ptr_i) begin
                    all_remote_req_sent_o = '1;
                    state_n = IDLE;
                end else if (dma_remote_req_ready_i) begin
                    dma_remote_req_o = '{ // lots of hardcoded widths here, maybe think about this more
                        write_not_read : 1'b0, // we're PULLing
                        is_amo_op      : 1'b0, // not amo
                        amo_type       : 2'h0,
                        mask           : 4'hF, // for now, pass all bytes
                        load_info      : 7'h0,
                        reg_id         : match_rd_id, // match id reg.... in PUSH, does this matter?
                        data           : dmem_fifo_data_i,
                        addr           : remote_ptr_i
                    };

                    incr_remote_ptr_o = '1;
                    dma_remote_req_v_o = '1;
                end
            end
            DONE: begin

            end
        endcase
    end

    // synopsys translate_off
    always_ff @(negedge clk_i) begin
        if (dma_remote_req_v_o & dma_remote_req_ready_i) begin
            $display("[DMA REMOTE REQUEST GENERATOR]: dma engine initiating remote %s request : addr: %h, data: %h. time = %0t",
                     dma_remote_req_o.write_not_read ? "store" : "load", dma_remote_req_o.addr, dma_remote_req_o.data, $time);
        end
    end
    // synopsys translate_on

endmodule