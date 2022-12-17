#include "bsg_manycore.h"
#include "bsg_manycore_arch.h"
#include "bsg_set_tile_x_y.h"


//code runs on processor 0
void proc0(void){
}

//code runs on processor 1
void proc1(void){


    // initialize core 1's data memory
    for (int* i = 0; i < 1024; i++) {
        *i = (int)i;
    }


    // define the dma operation
    int* dma_reg_ptr = 0x1000;

    int *remote_ptr  = (int *)bsg_remote_ptr(0,0,0x0);
    int num_bytes     = 128;
    int wb_address    = 0xABC;
    int push_not_pull = 0x1;
    int match_id_rd   = 0xA;
    int go_n          = 0x1;
    int misc_ctrl_reg_val =  (wb_address << 16)   | (match_id_rd << 4)
                          |  (push_not_pull << 2) | go_n;

    // clear this for sim. purposes. reading unitialized memory is not good for the sim.
    *(int *)wb_address = 0;

    // write to the dma register
    *(dma_reg_ptr    ) = 0x0; // local address
    *(dma_reg_ptr + 1) = remote_ptr; // remote pointer (tile)
    *(dma_reg_ptr + 2) = num_bytes; // number of bytes to transfer
    *(dma_reg_ptr + 3) = misc_ctrl_reg_val; // misc control register incantation


    while (*(volatile int*)wb_address != 1);


    bsg_finish();

}


////////////////////////////////////////////////////////////////////
int main()
{
  bsg_set_tile_x_y();

  int id = bsg_x_y_to_id(bsg_x,bsg_y);


  if (id == 0)          proc0();
  else if( id == 1 )    proc1();
  else                  bsg_wait_while(1);

  bsg_wait_while(1);
}

