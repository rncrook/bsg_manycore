`include "bsg_manycore_defines.vh"

module vanilla_dma_engine
    import bsg_manycore_pkg::*;
    import bsg_vanilla_pkg::*;
    #(
          `BSG_INV_PARAM(data_width_p)
        , `BSG_INV_PARAM(dmem_size_p)

        , localparam dmem_addr_width_lp = `BSG_SAFE_CLOG2(dmem_size_p)
        , data_mask_width_lp=(data_width_p>>3)
    ) (
          input clk_i
        , input reset_i


        // outgoing request interface from vanilla core
        // ---------------------------------------
        , input remote_req_s remote_req_core_i
        , input remote_req_core_v_i
        , output logic give_credit_back_o

        // incoming request interface to vanilla core
        // ---------------------------------------
        , output logic remote_dmem_core_v_o
        , output logic remote_dmem_core_w_o
        , output logic [dmem_addr_width_lp-1:0] remote_dmem_core_addr_o
        , output logic [data_mask_width_lp-1:0] remote_dmem_core_mask_o
        , output logic [data_width_p-1:0] remote_dmem_core_data_o
        , input remote_dmem_core_yumi_i
        , input [data_width_p-1:0] remote_dmem_core_data_i

        // network TX interface (reqeuest/response)
        // ---------------------------------------
        , output logic remote_req_tx_v_o
        , remote_req_s remote_req_tx_o

        // tx response
        , input int_remote_load_resp_tx_v_i
        , output logic int_remote_load_resp_core_v_o
        , input [4:0] int_remote_load_resp_rd_i
        , input [data_width_p-1:0] int_remote_load_resp_data_i
        , output logic int_remote_load_resp_yumi_o


        // network RX interface
        // --------------------
        , input remote_dmem_rx_v_i
        , input remote_dmem_rx_w_i
        , input [dmem_addr_width_lp-1:0] remote_dmem_rx_addr_i
        , input [data_mask_width_lp-1:0] remote_dmem_rx_mask_i
        , input [data_width_p-1:0] remote_dmem_rx_data_i
        //, output logic [data_width_p-1:0] remote_dmem_rx_data_o
        , output logic remote_dmem_rx_yumi_o
    );




    // remote_req from vanilla core to:
    //      -> network_tx (non-tile addresses)
    //      -> dma engine (local-tile addresses)

    //wire [31:0] vcore_to_dma_req_v = remote_req_core_v_i &
    //                      (remote_req_core_i.addr ==? 32'b0000_0000_0000_00??_????_????_????_????);
    logic vcore_to_dma_req_v;
    logic remote_req_tx_to_fifo_v;

    always_comb begin
        vcore_to_dma_req_v = 1'b0;
        remote_req_tx_to_fifo_v  = 1'b0;

        if (remote_req_core_v_i) begin
            if (remote_req_core_i.addr ==? 32'b0000_0000_0000_00??_????_????_????_????)
                vcore_to_dma_req_v = 1'b1;
            else
                remote_req_tx_to_fifo_v = 1'b1;
        end
    end

    // map incoming requests to registers

    // 0x0000
    logic [11:0] local_dmem_addr_r, local_dmem_addr_n;

    // 0x0004
    //logic [11:0] remote_dmem_addr_r, remote_dmem_addr_n;
    //logic [5:0]  remote_tile_X_r,   remote_tile_X_n;
    //logic [5:0]  remote_tile_Y_r,   remote_tile_Y_n;
    logic [31:0] remote_global_addr_r, remote_global_addr_n; // todo: likely can remove this


    logic        go_r,              go_n;
    logic        push_not_pull_r,   push_not_pull_n;
    logic [4:0]  match_rd_id_r,     match_rd_id_n;
    logic [11:0] wb_addr_r,         wb_addr_n;
    logic [11:0] num_bytes_r,       num_bytes_n;


    // control register block
    // TODO: maybe replace this block with bsg_dff_reset
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            local_dmem_addr_r    <= '0;
            remote_global_addr_r <= '0;
            go_r                 <= '0;
            push_not_pull_r      <= '0;
            match_rd_id_r        <= '0;
            wb_addr_r            <= '0;
            num_bytes_r          <= '0;
        end else begin
            local_dmem_addr_r    <=  local_dmem_addr_n;
            remote_global_addr_r <=  remote_global_addr_n;
            go_r                 <=  go_n;
            push_not_pull_r      <=  push_not_pull_n;
            match_rd_id_r        <=  match_rd_id_n;
            wb_addr_r            <=  wb_addr_n;
            num_bytes_r          <=  num_bytes_n;
        end
    end


    logic load_local_ptr;

    logic load_global_remote_ptr;

    // register address decode and update logic
    always_comb begin
        local_dmem_addr_n  = local_dmem_addr_r;
        //remote_dmem_addr_n = remote_dmem_addr_r;
        //remote_tile_X_n    = remote_tile_X_r;
        //remote_tile_Y_n    = remote_tile_Y_r;
        go_n               = go_r;
        push_not_pull_n    = push_not_pull_r;
        match_rd_id_n      = match_rd_id_r;
        wb_addr_n          = wb_addr_r;
        num_bytes_n        = num_bytes_r;
        remote_global_addr_n = remote_global_addr_r;
        load_local_ptr     = '0;
        load_global_remote_ptr = '0;

        give_credit_back_o = '0;


        if (vcore_to_dma_req_v) begin
            give_credit_back_o = '1;
            // decoding byte-addresses
            // writing to each 4-byte space requires an individual store instructions
            case (remote_req_core_i.addr[4:0])
                'h0: begin
                    local_dmem_addr_n  = remote_req_core_i.data[11:0];
                    load_local_ptr = '1;
                end

                'h4: begin
                    //remote_dmem_addr_n  = remote_req_core_i.data[11:0];  // remove
                    //remote_tile_X_n     = remote_req_core_i.data[21:16]; // remove
                    //remote_tile_Y_n     = remote_req_core_i.data[29:24]; // remove

                    // just pass around the 32-bit address, dont care about tile details
                    remote_global_addr_n = remote_req_core_i.data; // todo: likely can remove this
                    load_global_remote_ptr = '1;
                end

                'h8: begin
                    num_bytes_n = remote_req_core_i.data[11:0];
                end

                'hC: begin
                    go_n = remote_req_core_i.data[0];
                    push_not_pull_n = remote_req_core_i.data[2];
                    match_rd_id_n = remote_req_core_i.data[9:4];
                    wb_addr_n = remote_req_core_i.data[27:16]; // 12 or 10 bits?
                end
            endcase

        end

        if (go_r) go_n = '0;
    end

    // Network TX response decode
    logic tx_response_v;
    always_comb begin
        tx_response_v                 = '0;
        int_remote_load_resp_core_v_o = '0;

        if (int_remote_load_resp_tx_v_i) begin
            int_remote_load_resp_core_v_o = '1;
            if (~push_not_pull_r & int_remote_load_resp_rd_i == match_rd_id_r) begin
                int_remote_load_resp_core_v_o = '0;
                tx_response_v = '1;
            end
        end
    end



    logic all_local_req_sent_lo;
    //logic start_local_req_li;

    logic [11:0] local_dmem_ptr_r, local_dmem_ptr_n;
    logic incr_local_ptr_lo;

    assign local_dmem_ptr_n = load_local_ptr    ? remote_req_core_i.data[11:0] :
                              incr_local_ptr_lo ? local_dmem_ptr_r + 'h4 :
                                                  local_dmem_ptr_r;

    bsg_dff_reset #(.width_p(12)) local_dmem_ptr_reg (
          .clk_i (clk_i)
        , .reset_i (reset_i)
        , .data_i (local_dmem_ptr_n)
        , .data_o (local_dmem_ptr_r)
    );


    // global_remote_ptr
    //      - the DMA engine should be able to initiate requests to anything sitting
    //      within the entire addressable space provided (the VCORE Endpoint Virtual Address Space)
    //      - it would be nice if this dma engine could address the entire
    logic [31:0] global_remote_ptr_r, global_remote_ptr_n;
    logic incr_global_remote_ptr_lo;

    assign global_remote_ptr_n = load_global_remote_ptr    ? remote_req_core_i.data[31:0] :
                                 incr_global_remote_ptr_lo ? global_remote_ptr_r + 'h4    :
                                                             global_remote_ptr_r;

    bsg_dff_reset #(.width_p(32)) global_remote_ptr_reg (
          .clk_i   (clk_i)
        , .reset_i (reset_i)
        , .data_i  (global_remote_ptr_n)
        , .data_o  (global_remote_ptr_r)
    );


    // Local request generator

    logic local_req_gen_v_lo;
    logic local_req_gen_w_lo;
    logic [dmem_addr_width_lp-1:0] local_req_gen_addr_lo;
    logic [data_mask_width_lp-1:0] local_req_gen_mask_lo;
    logic [data_width_p-1:0] local_req_gen_data_lo;
    logic local_req_gen_yumi_li;

    dma_local_req_gen_fsm # (
        .data_width_p(data_width_p)
        ,.dmem_size_p(dmem_size_p)
    ) local_req_fsm_inst (
        .clk_i(clk_i)
        , .reset_i(reset_i)

        // fsm / control status signals

        , .start_local_req_i (go_r)
        , .push_not_pull_i (push_not_pull_r)
        , .all_local_req_sent_o (all_local_req_sent_lo)
        , .incr_local_ptr_o(incr_local_ptr_lo)
        , .all_remote_req_sent_i(all_remote_req_sent_lo)

        , .local_ptr_i (local_dmem_ptr_r) // byte-addr
        , .local_dmem_base_i (local_dmem_addr_r) // byte-addr
        , .wb_address_i  (wb_addr_r)
        , .num_bytes_i   (num_bytes_r)


        // output data interface
        , .out_data_v_o(local_req_gen_v_lo)
        , .out_data_w_o(local_req_gen_w_lo)
        , .out_data_addr_o(local_req_gen_addr_lo)
        , .out_data_mask_o(local_req_gen_mask_lo)
        , .out_data_o(local_req_gen_data_lo)
        , .out_data_yumi_i(local_req_gen_yumi_li)

        // tx response data interface (for dma pulls)
        , .in_data_v_i(tx_response_v)
        , .in_data_i(int_remote_load_resp_data_i)
        , .in_data_yumi_o(int_remote_load_resp_yumi_o)

    );




    // Local request arbitration (to vanilla core)

    makeshift_round_robin_arb local_req_arb_inst ( // hand-coded for arbitrating two requests
          .clk_i(clk_i)
        , .reset_i(reset_i)

        , .reqs_i   ({local_req_gen_v_lo, remote_dmem_rx_v_i})
        , .grants_o ({local_req_gen_yumi_li, remote_dmem_rx_yumi_o})

        , .yumi_i   (remote_dmem_core_yumi_i)
        , .valid_o  (remote_dmem_core_v_o)
    );

    bsg_mux_one_hot #(
        .width_p(1 + dmem_addr_width_lp +
                 data_mask_width_lp + data_width_p ), // width of request
        .els_p(2)   // number of requests
    ) local_req_mux_inst (
          .data_i({ {  local_req_gen_w_lo
                     , local_req_gen_addr_lo
                     , local_req_gen_mask_lo
                     , local_req_gen_data_lo}

                    ,{ remote_dmem_rx_w_i
                     , remote_dmem_rx_addr_i
                     , remote_dmem_rx_mask_i
                     , remote_dmem_rx_data_i}})
        , .sel_one_hot_i({local_req_gen_yumi_li, remote_dmem_rx_yumi_o})
        , .data_o({
                  remote_dmem_core_w_o
                 , remote_dmem_core_addr_o
                 , remote_dmem_core_mask_o
                 , remote_dmem_core_data_o})
    );




    // REMOTE REQUEST GENERATOR

    // dmem data fifo

    logic valid_dmem_dma_data; // qualifies dmem data coming from core
    bsg_dff_reset #(.width_p(1)) local_yumi_buffer (
          .clk_i (clk_i)
        , .reset_i (reset_i)
        // dmem queue is not used during pulls
        , .data_i (local_req_gen_yumi_li & ~all_local_req_sent_lo & push_not_pull_r)
        , .data_o (valid_dmem_dma_data)
    );



    logic dmem_fifo_v_lo;
    logic dmem_fifo_yumi_lo;
    logic [31:0] dmem_fifo_data_lo;


    bsg_fifo_1r1w_small #(
          .width_p  (32) // 32-wide
        , .els_p    (3) // 2-depth FIFO
        , .ready_THEN_valid_p(1)  // r->v
    ) local_dmem_data_queue (
         .clk_i (clk_i)
        , .reset_i(reset_i)

        // previous cycle's local req yumi validates new dmem data
        , .v_i(valid_dmem_dma_data)
        , .ready_o() // for now, this shouldnt matter
        , .data_i(remote_dmem_core_data_i)

        , .v_o   (dmem_fifo_v_lo)
        , .data_o(dmem_fifo_data_lo)
        , .yumi_i(dmem_fifo_yumi_lo)
    );


    // remote request generator fsm

    logic all_remote_req_sent_lo;

    remote_req_s dma_remote_req_lo;
    logic dma_remote_req_v_lo;

    logic tx_req_fifo_ready_lo [2];

    dma_remote_req_gen_fsm #(
        .data_width_p(data_width_p)
        ,.dmem_size_p(dmem_size_p)
    ) remote_req_fsm_inst (
         .reset_i (reset_i)
        , .clk_i (clk_i)

        , .start_remote_req_i(go_r)
        , .push_not_pull_i(push_not_pull_r) // for now,  always PUSH
        , .all_remote_req_sent_o(all_remote_req_sent_lo)

        , .remote_ptr_i(global_remote_ptr_r)
        , .incr_remote_ptr_o(incr_global_remote_ptr_lo)
        , .num_bytes_i(num_bytes_r) // for now, just 16 words

        , .local_req_gen_yumi_i(local_req_gen_yumi_li)


        , .dma_remote_req_v_o (dma_remote_req_v_lo)
        , .dma_remote_req_o (dma_remote_req_lo)
        , .dma_remote_req_ready_i (tx_req_fifo_ready_lo[0])



        , .dmem_fifo_data_i(dmem_fifo_data_lo)
        , .dmem_fifo_v_i(dmem_fifo_v_lo)
        , .dmem_fifo_yumi_o(dmem_fifo_yumi_lo)

        , .match_rd_id('d10) // for now, hardcode register 10
    );



    // Network TX outgoing request interface



    remote_req_s tx_req_fifo_li [2];
    logic tx_req_fifo_v_li [2];

    remote_req_s tx_req_fifo_lo [2];
    logic tx_req_fifo_v_lo [2];

    logic [1:0] tx_req_fifo_yumi_lo;


    assign tx_req_fifo_v_li = {dma_remote_req_v_lo, remote_req_tx_to_fifo_v};
    assign tx_req_fifo_li   = {dma_remote_req_lo, remote_req_core_i};

    genvar i;
    generate
        for(i = 0; i < 2; i++) begin : tx_req_fifo

            bsg_fifo_1r1w_small #(
                  .width_p  ($bits(remote_req_s))
                , .els_p    (3) // 2-depth FIFO
                , .ready_THEN_valid_p(1)  // r->v
            ) dma_tx_req_queue (
                  .clk_i (clk_i)
                , .reset_i(reset_i)

                , .v_i(tx_req_fifo_v_li[i])
                , .ready_o(tx_req_fifo_ready_lo[i]) // unused for core requests, when valid is asserted, the core expects the data to be sunk
                , .data_i(tx_req_fifo_li[i])

                , .v_o   (tx_req_fifo_v_lo[i])
                , .data_o(tx_req_fifo_lo[i])
                , .yumi_i(tx_req_fifo_yumi_lo[i])
            );

        end
    endgenerate



    bsg_round_robin_n_to_1 #(
          .width_p($bits(remote_req_s))
        , .num_in_p(2)
        , .strict_p(0)
    ) tx_req_fifo_merger (
          .clk_i   (clk_i)
        , .reset_i (reset_i)

        // to fifos
        , .data_i({tx_req_fifo_lo[1], tx_req_fifo_lo[0]})
        , .v_i({tx_req_fifo_v_lo[1], tx_req_fifo_v_lo[0]})
        , .yumi_o(tx_req_fifo_yumi_lo)

        // to downstream
        , .v_o      (remote_req_tx_v_o)
        , .data_o   (remote_req_tx_o)
        , .tag_o    ()
        , .yumi_i   (remote_req_tx_v_o) // maybe this should be also be a function of
                                        // something downstream (available credit signal?)
    );






    // synopsys translate_off
    always_ff @(negedge clk_i) begin
        if (vcore_to_dma_req_v) begin
            $display("[VCORE DMA]: dma engine has received a packet: addr: %h, data: %h. time = %0t",
                     remote_req_core_i.addr, remote_req_core_i.data, $time);
        end
        if (valid_dmem_dma_data) begin
            $display("[VCORE DMA]: core data memory returned: %h. time = %0t", remote_dmem_core_data_i, $time);
        end
        if (all_local_req_sent_lo & all_remote_req_sent_lo) begin
            $display("[VCORE DMA]: all local and remote requests have been sent. time = %0t", $time);
        end
    end
    // synopsys translate_on


endmodule