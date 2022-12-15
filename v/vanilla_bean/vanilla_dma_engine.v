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

        // incoming request interface to vanilla core
        // ---------------------------------------
        , output logic remote_dmem_core_v_o
        , output logic remote_dmem_core_w_o
        , output logic [dmem_addr_width_lp-1:0] remote_dmem_core_addr_o
        , output logic [data_mask_width_lp-1:0] remote_dmem_core_mask_o
        , output logic [data_width_p-1:0] remote_dmem_core_data_o
        , input remote_dmem_core_yumi_i
        //, input [data_width_p-1:0] remote_dmem_core_data_i

        // network TX interface (reqeuest/response)
        // ---------------------------------------
        , output logic remote_req_tx_v_o



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

    always_comb begin
        vcore_to_dma_req_v = 1'b0;
        remote_req_tx_v_o  = 1'b0;

        if (remote_req_core_v_i) begin
            if (remote_req_core_i.addr ==? 32'b0000_0000_0000_00??_????_????_????_????)
                vcore_to_dma_req_v = 1'b1;
            else
                remote_req_tx_v_o = 1'b1;
        end
    end

    // map incoming requests to registers

    // 0x0000
    logic [11:0] local_dmem_addr_r, local_dmem_addr_n;

    // 0x0004
    logic [11:0] remote_dmem_addr_r, remote_dmem_addr_n;

    // 0x00
    logic [5:0]  remote_tile_X_r,   remote_tile_X_n;
    logic [5:0]  remote_tile_Y_r,   remote_tile_Y_n;


    logic        go_r,              go_n;
    logic        push_not_pull_r,   push_not_pull_n;
    logic [4:0]  match_rd_id_r,     match_rd_id_n;
    logic [11:0] wb_addr_r,         wb_addr_n;
    logic [11:0] num_bytes_r,       num_bytes_n;


    // control register block
    // TODO: maybe replace this block with bsg_dff_reset
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            local_dmem_addr_r  <= '0;
            remote_dmem_addr_r <= '0;
            remote_tile_X_r    <= '0;
            remote_tile_Y_r    <= '0;
            go_r               <= '0;
            push_not_pull_r    <= '0;
            match_rd_id_r      <= '0;
            wb_addr_r          <= '0;
            wb_addr_r          <= '0;
            num_bytes_r        <= '0;
        end else begin
            local_dmem_addr_r  <= local_dmem_addr_n;
            remote_dmem_addr_r <= remote_dmem_addr_n;
            remote_tile_X_r    <= remote_tile_X_n;
            remote_tile_Y_r    <= remote_tile_Y_n;
            go_r               <=  go_n;
            push_not_pull_r    <=  push_not_pull_n;
            match_rd_id_r      <=  match_rd_id_n;
            wb_addr_r          <=  wb_addr_n;
            num_bytes_r        <=  num_bytes_n;
        end
    end


    logic load_local_ptr;


    // register address decode and update logic
    always_comb begin
        local_dmem_addr_n  = local_dmem_addr_r;
        remote_dmem_addr_n = remote_dmem_addr_r;
        remote_tile_X_n    = remote_tile_X_r;
        remote_tile_Y_n    = remote_tile_Y_r;
        go_n               = go_r;
        push_not_pull_n    = push_not_pull_r;
        match_rd_id_n      = match_rd_id_r;
        wb_addr_n          = wb_addr_r;
        num_bytes_n        = num_bytes_r;
        load_local_ptr     = '0;


        if (vcore_to_dma_req_v) begin
            // decoding byte-addresses
            // writing to each 4-byte space requires an individual store instructions
            case (remote_req_core_i.addr[3:0])
                'h0: begin
                    local_dmem_addr_n  = remote_req_core_i.data[11:0];
                    load_local_ptr = '1;
                end

                'h4: begin
                    remote_dmem_addr_n  = remote_req_core_i.data[11:0];
                    remote_tile_X_n     = remote_req_core_i.data[21:16];
                    remote_tile_Y_n     = remote_req_core_i.data[29:24];
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
    end


    // Vanilla Core incoming request interface logic
    // --------------------------------------------------


    logic all_local_req_sent_lo;
    //logic start_local_req_li;

    logic [11:0] local_dmem_ptr_r, local_dmem_ptr_n;
    logic incr_local_ptr_lo;

    assign local_dmem_ptr_n = load_local_ptr    ? remote_req_core_i.data[11:0] :
                              incr_local_ptr_lo ? local_dmem_ptr_r + 'h4 :
                                                  local_dmem_ptr_r;

    bsg_dff_reset #(.width_p(12)) local_dmem_ptr (
          .clk_i (clk_i)
        , .reset_i (reset_i)
        , .data_i (local_dmem_ptr_n)
        , .data_o (local_dmem_ptr_r)
    );


    ///assign start_local_req_li = go_r;

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

        , .local_ptr_i (local_dmem_ptr_r) // byte-addr
        , .local_dmem_base_i (local_dmem_addr_r) // byte-addr
        , .wb_address_i  ('0)
        , .num_bytes_i   ('d64)


        // output data interface

        , .out_data_v_o(local_req_gen_v_lo)
        , .out_data_w_o(local_req_gen_w_lo)
        , .out_data_addr_o(local_req_gen_addr_lo)
        , .out_data_mask_o(local_req_gen_mask_lo)
        , .out_data_o(local_req_gen_data_lo)
        , .out_data_yumi_i(local_req_gen_yumi_li)

    );




    // Request to vcore arbitration

    //bsg_arb_round_robin #(
    //    .width_p(2) // number of incoming requests to arbitrate
    //) local_req_arb_inst (
    //    .clk_i(clk_i)
    //    ,.reset_i(reset_i)

    //    , .reqs_i   ({local_req_gen_v_lo, remote_dmem_rx_v_i})
    //    , .grants_o ({local_req_gen_yumi_li, remote_dmem_rx_yumi_o})
    //    , .yumi_i   (remote_dmem_core_yumi_i)
    //);
    makeshift_round_robin_arb local_req_arb_inst (
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
          .data_i({
                        {
                         local_req_gen_w_lo
                        , local_req_gen_addr_lo
                        , local_req_gen_mask_lo
                        , local_req_gen_data_lo},

                         {
                         remote_dmem_rx_w_i
                        , remote_dmem_rx_addr_i
                        , remote_dmem_rx_mask_i
                        , remote_dmem_rx_data_i}
                  })
        , .sel_one_hot_i({local_req_gen_yumi_li, remote_dmem_rx_yumi_o})
        , .data_o({
                  remote_dmem_core_w_o
                 , remote_dmem_core_addr_o
                 , remote_dmem_core_mask_o
                 , remote_dmem_core_data_o})
    );


































    // synopsys translate_off
    int idx;
    always_ff @(negedge clk_i) begin
        //if (reset_i)  idx = 0;
        if (vcore_to_dma_req_v) begin
            //idx++;
            $display("[VCORE DMA]: dma engine has received a packet: addr: %h, data: %h",
                     remote_req_core_i.addr, remote_req_core_i.data);
            //if (idx == 3) $finish;
        end
    end
    // synopsys translate_on


endmodule